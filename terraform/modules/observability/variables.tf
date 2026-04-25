variable "name_prefix" {
  description = "リソース命名プレフィクス"
  type        = string
}

variable "alarm_email" {
  description = "アラート通知先メアド。空ならメール購読を作らない"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "監視対象 Lambda 関数名"
  type        = string
}

variable "api_id" {
  description = "監視対象 API Gateway HTTP API ID"
  type        = string
}

variable "cloudfront_distribution_id" {
  description = "監視対象 CloudFront Distribution ID"
  type        = string
}

variable "monthly_budget_usd" {
  description = "月間予算（USD）。超過時にアラートメール"
  type        = number
  default     = 10
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
