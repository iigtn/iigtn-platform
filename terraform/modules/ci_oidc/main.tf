# ==============================================================================
# Section 1: GitHub OIDC Provider
# ------------------------------------------------------------------------------
# AWS アカウントに「GitHub を IdP として信頼する」登録を 1 個だけ作る。
# 同じアカウントに複数モジュールから OIDC Provider を作ろうとすると衝突する
# ため、`ci_oidc` 1 箇所で集約管理するのがセオリー。
#
# - url               : GitHub Actions の OIDC token 発行 URL（固定値）
# - client_id_list    : audience として使う識別子（AWS STS で固定）
# - thumbprint_list   : GitHub IdP の TLS 証明書サムプリント。AWS が
#                       内部で自動検証するので空配列でも動くが、明示する
#                       方が安全（GitHub が証明書ローテートしたら更新必要）
# ------------------------------------------------------------------------------
# 参考: https://docs.github.com/ja/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
# ==============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

# ==============================================================================
# Section 2: Trust Policy — 誰がこの Role を AssumeRole できるか
# ------------------------------------------------------------------------------
# - Federated Principal: 上で作った OIDC Provider
# - Action: AssumeRoleWithWebIdentity（OIDC 経由の AssumeRole 専用 API）
# - Conditions:
#   1. aud (audience) が sts.amazonaws.com（GitHub Actions が AWS 向けに発行
#      したトークンであることを保証）
#   2. sub (subject) が `repo:<owner>/<repo>:ref:refs/heads/<branch>`
#      のいずれかにマッチ（リポジトリ＋ブランチで限定）
# ==============================================================================
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # 条件 1: audience は AWS STS でなければならない
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # 条件 2: 指定 owner/repo の指定ブランチからのみ
    # sub の形式: "repo:<owner>/<repo>:ref:refs/heads/<branch>"
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for branch in var.allowed_branches :
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${branch}"
      ]
    }
  }
}

# ==============================================================================
# Section 3: Permissions Policy — Role になった結果、何ができるか
# ------------------------------------------------------------------------------
# 最小権限の原則。フロントエンドデプロイに必要な API のみ許可:
#   - S3 (バケット内のファイル CRUD)
#   - CloudFront キャッシュ無効化
# それ以外（IAM 操作・他バケット・他 Distribution）は一切できない。
# ==============================================================================
data "aws_iam_policy_document" "deploy" {
  # ── S3: バケット自身に対する操作 ──────────────────────────────────────
  statement {
    sid       = "S3ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.deploy_bucket_arn]
  }

  # ── S3: バケット内オブジェクト操作 ────────────────────────────────────
  statement {
    sid    = "S3ObjectRW"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${var.deploy_bucket_arn}/*"]
  }

  # ── CloudFront: 特定 Distribution のキャッシュ無効化 ──────────────────
  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations"
    ]
    resources = [var.cloudfront_distribution_arn]
  }
}

# ==============================================================================
# Section 4: IAM Role 本体
# ------------------------------------------------------------------------------
# Trust Policy を assume_role_policy に、Permissions Policy をインライン
# で紐付ける。インラインにするのは「この Role 専用の権限」を Role と
# 同じ寿命で管理するため（外出ししないことで destroy 時に残骸が出ない）。
# ==============================================================================
resource "aws_iam_role" "deploy" {
  name = var.role_name
  # IAM Role description は ASCII / Latin-1 のみ許容のため英語で書く
  description        = "GitHub Actions OIDC deploy role for ${var.github_owner}/${var.github_repo}"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = var.tags
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
