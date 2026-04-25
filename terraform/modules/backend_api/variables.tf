variable "name_prefix" {
  description = "リソース名のプレフィクス（例: iigtn-lab-prod）。テーブル名・関数名・API 名等に使う"
  type        = string
}

variable "lambda_source_dir" {
  description = "Lambda コードのあるローカルディレクトリ（例: ../../../backend/functions/contact）"
  type        = string
}

variable "ses_from" {
  description = "SES 送信元アドレス（検証済必須）。空なら SES 連携は無効化"
  type        = string
  default     = ""
}

variable "ses_to" {
  description = "SES 送信先アドレス（sandbox では検証済必須）。空なら SES 連携は無効化"
  type        = string
  default     = ""
}

variable "allowed_origin" {
  description = "CORS Allow-Origin の値。例: https://lab.iigtn.com"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs の保持日数"
  type        = number
  default     = 14
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
