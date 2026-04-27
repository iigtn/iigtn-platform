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

  domain_name          = var.domain_name
  additional_san_names = var.additional_san_names

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

  domain_name        = var.domain_name
  additional_aliases = var.additional_aliases
  certificate_arn    = module.network_dns.certificate_arn
  bucket_name        = local.web_bucket_name

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
# Module: observability
# ------------------------------------------------------------------------------
# CloudWatch Alarms + SNS + AWS Budgets
# ==============================================================================
module "observability" {
  source = "../../modules/observability"

  name_prefix                = "iigtn-lab-prod"
  alarm_email                = var.alarm_email
  lambda_function_name       = module.backend_api.lambda_function_name
  api_id                     = module.backend_api.api_id
  cloudfront_distribution_id = module.frontend_cdn.distribution_id
  monthly_budget_usd         = var.monthly_budget_usd
}

# ==============================================================================
# CloudFront アラームは us-east-1 専用なので envs root で provider 明示
# (モジュールへの provider alias 渡しが効かないケースがあるための退避策)
# ==============================================================================
# CloudFront アラームは us-east-1 必須。alarm_actions に指定する SNS トピックも
# 同一 region に置く必要があるため、us-east-1 用の SNS トピックも別途作成する。
resource "aws_sns_topic" "alarms_us_east_1" {
  provider = aws.us_east_1
  name     = "iigtn-lab-prod-alarms-use1"
}

resource "aws_sns_topic_subscription" "alarms_us_east_1_email" {
  count    = var.alarm_email == "" ? 0 : 1
  provider = aws.us_east_1

  topic_arn = aws_sns_topic.alarms_us_east_1.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "cf_4xx_rate" {
  provider = aws.us_east_1

  alarm_name          = "iigtn-lab-prod-cf-4xx-rate"
  alarm_description   = "CloudFront 4xx rate > 5% over 10 min"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  period              = 300
  statistic           = "Average"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = module.frontend_cdn.distribution_id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.alarms_us_east_1.arn]
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
