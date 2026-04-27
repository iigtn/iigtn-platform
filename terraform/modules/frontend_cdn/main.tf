# ==============================================================================
# Section 1: S3 Bucket — 静的サイトファイルの保管場所
# ------------------------------------------------------------------------------
# - 「バケット」は S3 のファイル置き場の単位
# - バケット名は AWS 全体でグローバル一意（重複を取れない）
# - このモジュールでは「非公開」バケットを作る。世界に直接公開するのは
#   CloudFront だけ、というのが最近のベストプラクティス。
# ==============================================================================
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

# ==============================================================================
# Section 2: S3 Safety Configs — 安全装置 3 種
# ------------------------------------------------------------------------------
# AWS では、バケット作成と「公開ブロック・暗号化・バージョニング」は
# 別リソース で個別に設定する作りになっている（昔は bucket リソース内に
# 書けたが、5.x で分離された）。理由: 設定変更時の影響範囲を局所化するため。
# ==============================================================================

# ─── (2-1) Public Access Block ────────────────────────────────────────────────
# 4 つの真偽値を全部 true にすることで、「うっかり public にしてしまう」を
# 構造的に不可能にする。Bucket Policy で public 化を試みても効かなくなる。
# 採用評価で「最小権限」を語るなら、最初に必ずこれをやる。
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true # ACL の public 設定をブロック
  ignore_public_acls      = true # 既存の public ACL を無視
  block_public_policy     = true # public な Bucket Policy をブロック
  restrict_public_buckets = true # public Bucket Policy を持つバケットを完全制限
}

# ─── (2-2) Versioning ─────────────────────────────────────────────────────────
# 同じキーに上書き / 削除しても旧バージョンが消えずに残る。
# - 誤デプロイのロールバックが効く
# - 完全削除には一手間かかる（destroy 時に注意：force_destroy=false がデフォルト）
# - ストレージは少し増えるが、サイト規模なら無視できるコスト
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ─── (2-3) Server-Side Encryption (SSE-S3 / AES256) ───────────────────────────
# AWS 管理の鍵で自動的に保存時暗号化される。アプリ側は透過。
# 法定要件があれば SSE-KMS (CMK) に上げるが、個人ポートフォリオは SSE-S3 で十分。
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ==============================================================================
# Section 3: CloudFront Origin Access Control (OAC)
# ------------------------------------------------------------------------------
# 「CloudFront だけ S3 を読める」を実現する仕組み。
#   - signing_protocol "sigv4": リクエストに AWS SigV4 署名を付与
#   - signing_behavior "always": 常に署名を付ける（"never" や "no-override" もある）
#   - origin_access_control_origin_type "s3": S3 を origin にする時の指定
# OAC の ID はこの後 Distribution の origin に紐付ける。
# 旧 OAI との違い: KMS 暗号化バケットや S3 以外の origin (Lambda 関数 URL 等) にも対応。
# ==============================================================================
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.bucket_name}-oac"
  description                       = "OAC for ${var.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ==============================================================================
# Section 3.5: CloudFront Function — ディレクトリ末尾スラッシュを index.html に
# ------------------------------------------------------------------------------
# OAC + S3 構成では、/blog/ のような末尾スラッシュの URL に対して、S3 が「キー
# blog/」を返さないため 404 となり、SPA フォールバックでトップに飛ぶ。
# CloudFront Function (viewer-request) でリクエスト URI を /blog/index.html に
# 書き換えて、ディレクトリインデックス相当の挙動を実現する。
# ==============================================================================
resource "aws_cloudfront_function" "rewrite_index" {
  name    = "${var.bucket_name}-rewrite-index"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite /xxx/ to /xxx/index.html (directory index emulation for OAC + S3)"
  publish = true
  code    = file("${path.module}/functions/rewrite-index.js")
}

# ==============================================================================
# Section 4: CloudFront Distribution — CDN 本体
# ------------------------------------------------------------------------------
# CloudFront Distribution は CDN の設定 1 セット。世界中の Edge に展開され、
# 訪問者は最寄りの Edge から配信を受ける。
# - aliases: Distribution に紐付くカスタムドメイン名（CNAME に登録する側の名前）
# - origin: 元データの取得先（S3）
# - default_cache_behavior: マッチパターン無指定時のルーティング & キャッシュ
# - viewer_certificate: HTTPS で使う証明書（ACM の us-east-1）
# ==============================================================================
resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "iigtn ${var.domain_name} static site"
  http_version    = "http2and3" # HTTP/3 (QUIC) を有効化。新しいブラウザで体感速度が上がる

  # --- 訪問者がアクセスする URL のドメイン名 ---
  # ここに登録した名前で SSL 証明書も使う必要がある（後述）
  aliases = concat([var.domain_name], var.additional_aliases)

  # --- 配信できる Edge 範囲 ---
  # PriceClass_100: 北米・欧州のみ（最安）
  # PriceClass_200: 上 + アジア・中東・アフリカ ← 日本にちゃんと配信したいならこれ
  # PriceClass_All: 全世界（最高だが日本訪問者には差ほぼなし）
  price_class = "PriceClass_200"

  # --- ルートに何も付けないアクセスでの既定ファイル ---
  default_root_object = "index.html"

  # --- Origin (1): S3 バケット ---
  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "s3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # --- Origin (2): API Gateway (api_origin_domain_name が空でない時だけ追加) ---
  # dynamic ブロックで条件付き定義する Terraform のイディオム。
  # for_each に空リストを渡せば 0 個、1 要素を渡せば 1 個生成される。
  dynamic "origin" {
    for_each = var.api_origin_domain_name == "" ? [] : [1]
    content {
      domain_name = var.api_origin_domain_name
      origin_id   = "apigw-origin"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only" # API GW は HTTPS のみ
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # --- デフォルトキャッシュ動作 ---
  # CloudFront が「マッチする behavior が無い」時に使う規則。
  default_cache_behavior {
    target_origin_id       = "s3-${var.bucket_name}"
    viewer_protocol_policy = "redirect-to-https" # HTTP で来たら HTTPS にリダイレクト
    allowed_methods        = ["GET", "HEAD"]     # 静的サイトなので読み取りのみ
    cached_methods         = ["GET", "HEAD"]
    compress               = true # gzip/brotli 自動圧縮（帯域 50% 削減 typically）

    # AWS マネージドキャッシュポリシー "CachingOptimized" を使う。
    # ID は AWS 側で固定値。自分で書くより、まずマネージド利用で運用開始 → 必要に応じて自作に切替。
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized

    # AWS マネージド Response Headers Policy "SecurityHeadersPolicy"
    # X-Frame-Options / X-Content-Type-Options / Referrer-Policy 等を自動で付ける
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # SecurityHeadersPolicy

    # ディレクトリインデックス書き換え (/blog/ → /blog/index.html)
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_index.arn
    }
  }

  # --- /api/* Behavior: API Gateway へ転送 ---
  # default_cache_behavior が S3 用なので、API は別 behavior で扱う。
  # dynamic は origin と同様に api_origin_domain_name の有無で生成切替。
  dynamic "ordered_cache_behavior" {
    for_each = var.api_origin_domain_name == "" ? [] : [1]
    content {
      path_pattern           = var.api_path_pattern
      target_origin_id       = "apigw-origin"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      # API レスポンスはキャッシュしない (CachingDisabled マネージドポリシー)
      cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      # Host 以外のヘッダ・クエリ・cookie をオリジンに転送 (AllViewerExceptHostHeader)
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
  }

  # --- カスタムエラーレスポンス ---
  # SPA でクライアントサイドルーティングを使うと、`/about` 等は S3 に存在せず 403/404 を返す。
  # それを 200 + index.html に書き換えると、JavaScript ルーティングが動く。
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  # --- 地理制限 ---
  # 個人サイトなので制限なし。クライアント案件で「日本国内のみ」等の要件が来たら whitelist。
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # --- TLS 証明書設定 ---
  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"     # SNI で複数ドメイン同居を許可（IP ごとに 1 証明書なら "vip"、$600/月）
    minimum_protocol_version = "TLSv1.2_2021" # TLS 1.2 以上を必須に。古いクライアント切り捨て
  }

  tags = var.tags

  # --- ライフサイクル ---
  # Distribution の作り直しは時間かかる（30 分級）ので、誤って destroy しないよう保護する選択肢もある。
  # 今は dev 環境的な使い方なので付けない。本番運用ノリになったら追加検討。
  # lifecycle { prevent_destroy = true }
}

# ==============================================================================
# Section 5: S3 Bucket Policy — CloudFront からの読み取りだけを許可
# ------------------------------------------------------------------------------
# OAC を作っただけでは S3 側で「お前を許可してない」と弾かれる（403）。
# Bucket Policy で「この Distribution からの GetObject だけ許可」を明示する。
# - Principal: CloudFront のサービス
# - Condition の aws:SourceArn: 特定の Distribution からのリクエストだけに絞る
# ==============================================================================
data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "AllowCloudFrontReadViaOAC"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  # public_access_block より後に作る必要がある（順序保証のための明示依存）
  depends_on = [aws_s3_bucket_public_access_block.this]
}
