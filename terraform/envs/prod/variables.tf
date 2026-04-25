variable "region" {
  description = "メインリージョン（CloudFront/ACM の us-east-1 はモジュール内で固定）"
  type        = string
  default     = "ap-northeast-1"
}

variable "domain_name" {
  description = "AWS で立てるサブドメイン。例: lab.iigtn.com"
  type        = string
}

# ─── GitHub Actions OIDC 用 ──────────────────────────────────────────────────
variable "github_owner" {
  description = "GitHub の個人/組織名。Trust Policy の sub claim 検証に使う"
  type        = string
}

variable "github_repo" {
  description = "GitHub のリポジトリ名"
  type        = string
  default     = "iigtn-platform"
}

variable "github_allowed_branches" {
  description = "デプロイ用 Role の AssumeRole を許可するブランチ"
  type        = list(string)
  default     = ["main"]
}
