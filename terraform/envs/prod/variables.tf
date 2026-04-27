variable "region" {
  description = "メインリージョン（CloudFront/ACM の us-east-1 はモジュール内で固定）"
  type        = string
  default     = "ap-northeast-1"
}

variable "domain_name" {
  description = "AWS で立てるサブドメイン。例: lab.iigtn.com"
  type        = string
}

variable "additional_san_names" {
  description = "ACM 証明書の SAN に追加するドメイン名 (apex 用)。例: [\"iigtn.com\"]"
  type        = list(string)
  default     = []
}

variable "additional_aliases" {
  description = "CloudFront に追加で紐付けるドメイン (apex 配信用)。例: [\"iigtn.com\"]"
  type        = list(string)
  default     = []
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

# ─── SES ─────────────────────────────────────────────────────────────────────
# 注意: sandbox では from/to 両方が AWS で verify 済みである必要がある。
# 空にすれば SES 連携を無効化（DDB だけに保存される）
variable "ses_from" {
  description = "SES 送信元アドレス (検証済必須)。例: noreply@iigtn.com / 空なら無効"
  type        = string
  default     = ""
}

variable "ses_to" {
  description = "SES 送信先アドレス (sandbox では検証済必須)。例: aws-dev@iigtn.com / 空なら無効"
  type        = string
  default     = ""
}

# ─── Observability ───────────────────────────────────────────────────────────
variable "alarm_email" {
  description = "CloudWatch アラート + AWS Budgets 通知先メアド"
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "月額予算 (USD)"
  type        = number
  default     = 10
}
