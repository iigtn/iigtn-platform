# ==============================================================================
# Outputs — apply 後にユーザに見せる値
# ==============================================================================

# ─── network_dns モジュール由来 ─────────────────────────────────────────────
output "certificate_arn" {
  description = "ACM 証明書 ARN (us-east-1)。CloudFront にアタッチ済"
  value       = module.network_dns.certificate_arn
}

output "certificate_domain_name" {
  description = "証明書のプライマリドメイン"
  value       = module.network_dns.certificate_domain_name
}

output "validation_records" {
  description = "ACM 検証用 CNAME（Squarespace に登録済のレコード参考値）"
  value       = module.network_dns.validation_records
}

# ─── frontend_cdn モジュール由来 ────────────────────────────────────────────
output "distribution_id" {
  description = "CloudFront Distribution ID（無効化コマンド等で使う）"
  value       = module.frontend_cdn.distribution_id
}

output "distribution_domain_name" {
  description = <<-EOT
    CloudFront の `*.cloudfront.net` ドメイン。
    Squarespace で `lab` の CNAME としてこの値を登録すると、
    https://lab.iigtn.com/ がこの Distribution に紐付く。
  EOT
  value       = module.frontend_cdn.distribution_domain_name
}

output "bucket_name" {
  description = "静的サイトを置く S3 バケット名"
  value       = module.frontend_cdn.bucket_name
}

# ─── ci_oidc モジュール由来 ─────────────────────────────────────────────────
output "deploy_role_arn" {
  description = <<-EOT
    GitHub Actions ワークフローで `role-to-assume` に貼る IAM Role ARN。
    このロールに対し OIDC 経由で AssumeRole するため、静的アクセスキー不要。
  EOT
  value       = module.ci_oidc.deploy_role_arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN"
  value       = module.ci_oidc.oidc_provider_arn
}

# ─── backend_api モジュール由来 ─────────────────────────────────────────────
output "api_endpoint" {
  description = "API Gateway HTTP API のデフォルトエンドポイント（CloudFront 経由なので通常使わない）"
  value       = module.backend_api.api_endpoint
}

output "api_endpoint_host" {
  description = "API Gateway のホスト名のみ"
  value       = module.backend_api.api_endpoint_host
}

output "lambda_function_name" {
  description = "Contact form Lambda 関数名（CloudWatch Logs 確認等に使う）"
  value       = module.backend_api.lambda_function_name
}

output "table_name" {
  description = "問い合わせ保存用 DynamoDB テーブル名"
  value       = module.backend_api.table_name
}
