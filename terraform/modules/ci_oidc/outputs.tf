output "oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN（他モジュールで参照する場合用）"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "deploy_role_arn" {
  description = <<-EOT
    GitHub Actions ワークフローで AssumeRole する IAM Role の ARN。
    .github/workflows/*.yml で `role-to-assume:` にこの値を貼る。
  EOT
  value       = aws_iam_role.deploy.arn
}

output "deploy_role_name" {
  description = "Role 名（コンソールで探す時に便利）"
  value       = aws_iam_role.deploy.name
}
