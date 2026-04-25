# ==============================================================================
# Data Sources — 既存情報を読むだけ（リソース作成なし）
# ------------------------------------------------------------------------------
# - aws_caller_identity: 今 Terraform を実行している IAM の身分情報を取得。
#   → account_id (`211374268447`) を S3 バケット名に埋め込んでグローバル一意性を確保。
# ==============================================================================
data "aws_caller_identity" "current" {}

# ==============================================================================
# Locals — 中間計算値（DRY のため）
# ------------------------------------------------------------------------------
# 同じ値を複数モジュールで使うなら locals に集約しておくと、変更が 1 箇所で済む。
# ==============================================================================
locals {
  # S3 バケット名。AWS 全体で一意でないといけないため、アカウント ID を末尾に付ける慣行。
  # `iigtn-lab-web-prod-211374268447` の形になる。
  web_bucket_name = "iigtn-lab-web-prod-${data.aws_caller_identity.current.account_id}"
}

# ==============================================================================
# Module: network_dns
# ------------------------------------------------------------------------------
# ACM 証明書 (us-east-1) を発行し、DNS 検証完了を待つ。
# DNS 検証用 CNAME は Squarespace 側で手動投入済 (Step 4 で登録)。
# 出力: certificate_arn を frontend_cdn に渡す。
# ==============================================================================
module "network_dns" {
  source = "../../modules/network_dns"

  domain_name = var.domain_name

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

# ==============================================================================
# Module: frontend_cdn
# ------------------------------------------------------------------------------
# S3 (private) + CloudFront (with OAC) で静的サイト配信基盤を作る。
# certificate_arn は network_dns モジュールから受け取る。
# ==============================================================================
module "frontend_cdn" {
  source = "../../modules/frontend_cdn"

  domain_name     = var.domain_name
  certificate_arn = module.network_dns.certificate_arn
  bucket_name     = local.web_bucket_name

  # /api/* を API Gateway に向けるための origin 情報を渡す
  api_origin_domain_name = module.backend_api.api_endpoint_host

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

# ==============================================================================
# Module: backend_api
# ------------------------------------------------------------------------------
# 問い合わせフォーム機能 (API Gateway + Lambda + DynamoDB + SES)。
# Lambda コード本体は ../../../backend/functions/contact/ にある。
# ==============================================================================
module "backend_api" {
  source = "../../modules/backend_api"

  name_prefix       = "iigtn-lab-prod"
  lambda_source_dir = "${path.root}/../../../backend/functions/contact"
  allowed_origin    = "https://${var.domain_name}"

  # SES 連携 (sandbox 中なので、検証済みのアドレスのみ送信可)
  ses_from = var.ses_from
  ses_to   = var.ses_to
}

# ==============================================================================
# Module: ci_oidc
# ------------------------------------------------------------------------------
# GitHub Actions が静的キーなしで AWS にデプロイできるようにする。
# OIDC Provider + IAM Role + 最小権限 Permissions Policy を作成。
# - frontend_cdn が作った S3 バケット ARN と Distribution ARN を依存として渡す
#   ことで、デプロイできる範囲を物理的に絞っている（最小権限）
# ==============================================================================
module "ci_oidc" {
  source = "../../modules/ci_oidc"

  github_owner     = var.github_owner
  github_repo      = var.github_repo
  allowed_branches = var.github_allowed_branches

  deploy_bucket_arn           = module.frontend_cdn.bucket_arn
  cloudfront_distribution_arn = module.frontend_cdn.distribution_arn
}
