# ==============================================================================
# Section 1: DynamoDB Table — 問い合わせ保存
# ------------------------------------------------------------------------------
# - PK: id (UUID v4) — エンティティ一意識別
# - PII (email) は **PK にしない**。設計書 lessons.md D 項参照
# - On-demand: アクセスが薄い間は最安。月数百回程度ならほぼ 0 円
# - サーバ側暗号化はデフォルトで AES256 / AWS 管理キー
# - point_in_time_recovery: 最大 35 日の連続バックアップ。誤削除対策の砦
# ==============================================================================
resource "aws_dynamodb_table" "contacts" {
  name         = "${var.name_prefix}-contacts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

# ==============================================================================
# Section 2: Lambda パッケージング
# ------------------------------------------------------------------------------
# archive_file データソースは apply 時にディレクトリを zip にする。
# 中身が変わると hash も変わり、Lambda の更新が自動でトリガーされる。
# ==============================================================================
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/.build/contact_lambda.zip"
}

# ==============================================================================
# Section 3: CloudWatch Logs + IAM Role
# ------------------------------------------------------------------------------
# Lambda は CloudWatch Logs に書く。ログループは Lambda が自動作成するが、
# Retention（保持日数）を明示するために事前に作っておく。
# 自動作成だと無期限保持になり、コストが地味に増える事故が起きやすい。
# ==============================================================================
resource "aws_cloudwatch_log_group" "contact" {
  name              = "/aws/lambda/${var.name_prefix}-contact"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ── Lambda 実行ロール (Trust Policy) ────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-contact-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  description        = "Execution role for contact form Lambda"
  tags               = var.tags
}

# ── Lambda 用最小権限ポリシー ──────────────────────────────────────────
data "aws_iam_policy_document" "lambda_policy" {
  # CloudWatch Logs (この関数のログストリームのみ)
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.contact.arn}:*"]
  }

  # DynamoDB (この contacts テーブルのみ。Put のみ)
  statement {
    sid       = "DDBPut"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.contacts.arn]
  }

  # SES (任意のドメインで SendEmail 可。本番化時に Identity ARN で絞ると更に安全)
  statement {
    sid    = "SESSend"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    # SES の identity ARN は account/identity 単位なのでバケット同様に絞れる。
    # 今は全許可、将来 verified identity の ARN で絞る。
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name_prefix}-contact-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# ==============================================================================
# Section 4: Lambda 関数
# ------------------------------------------------------------------------------
# - arm64: Graviton で約 20% 安、性能ほぼ同等
# - timeout 10s: SES 呼び出し含めても十分。フォーム用途で長く待つ理由なし
# - memory 256MB: 小さめでも DDB+SES 程度なら速い。コスト最適
# ==============================================================================
resource "aws_lambda_function" "contact" {
  function_name    = "${var.name_prefix}-contact"
  description      = "Contact form handler (validates -> DDB Put -> SES send)"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  architectures    = ["arm64"]
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      DDB_TABLE      = aws_dynamodb_table.contacts.name
      SES_FROM       = var.ses_from
      SES_TO         = var.ses_to
      ALLOWED_ORIGIN = var.allowed_origin
    }
  }

  # CloudWatch Logs グループより後に作る（log group が無いと Lambda が
  # デフォルトで無期限の log group を勝手に作ってしまうのを防ぐ）
  depends_on = [aws_cloudwatch_log_group.contact]

  tags = var.tags
}

# ==============================================================================
# Section 5: API Gateway HTTP API
# ------------------------------------------------------------------------------
# REST API より約 1/3 の価格。フォーム規模なら HTTP API で十分。
# - protocol_type "HTTP": HTTP API を意味する。"REST" だと REST API
# - $default ステージ: 自動デプロイ・追加 stage 名なし
# ==============================================================================
resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "iigtn ${var.name_prefix} HTTP API"

  cors_configuration {
    allow_origins = [var.allowed_origin]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }

  tags = var.tags
}

# ── Stage: $default は AutoDeploy 可能 ─────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 100
    throttling_rate_limit    = 50
  }

  tags = var.tags
}

# ── Integration: API GW → Lambda の接続 ───────────────────────────────
# AWS_PROXY: payload を Lambda にそのまま渡す方式 (Lambda Proxy Integration)
# payload_format_version "2.0": HTTP API 用の新フォーマット (event.requestContext.http 構造)
resource "aws_apigatewayv2_integration" "contact" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# ── Routes: パス + メソッドの定義 ─────────────────────────────────────
resource "aws_apigatewayv2_route" "contact_post" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /api/contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact.id}"
}

# preflight (CORS OPTIONS) を Lambda に流すかは設計次第。
# API GW の cors_configuration が自動応答してくれるが、Lambda 側でも返せる
# ようにしてあるので、両方設定しておく（API GW が先に処理する）。
resource "aws_apigatewayv2_route" "contact_options" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "OPTIONS /api/contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact.id}"
}

# ==============================================================================
# Section 6: Lambda Permission — API GW からの呼び出しを許可
# ------------------------------------------------------------------------------
# Lambda は IAM Role で「他から呼べる」ようにはなっていない。
# 「特定の API GW からの InvokeFunction」を明示的に許可する resource policy が必要。
# source_arn の `*/*/*/*` は (stage)/(method)/(path-segments...) のワイルドカード。
# ==============================================================================
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
