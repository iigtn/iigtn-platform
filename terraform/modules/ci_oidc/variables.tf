variable "github_owner" {
  description = <<-EOT
    GitHub リポジトリの所有者（個人ユーザー名 or 組織名）。
    Trust Policy の sub claim 検証に使う。
    例: "gatani" / "iigtn-org"
  EOT
  type        = string
}

variable "github_repo" {
  description = <<-EOT
    GitHub リポジトリ名。
    例: "iigtn-platform"
  EOT
  type        = string
}

variable "allowed_branches" {
  description = <<-EOT
    AssumeRole を許可するブランチのリスト。
    通常は main / production のみ。Pull Request からは AssumeRole させない設計。
  EOT
  type        = list(string)
  default     = ["main"]
}

variable "role_name" {
  description = "GitHub Actions が AssumeRole する IAM Role の名前"
  type        = string
  default     = "iigtn-github-actions-deploy"
}

variable "deploy_bucket_arn" {
  description = "デプロイ先 S3 バケットの ARN（権限付与に使う）"
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "キャッシュ無効化対象 CloudFront Distribution の ARN"
  type        = string
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
