variable "domain_name" {
  description = <<-EOT
    Hosted zone のドメイン名。例: "lab.iigtn.com"
    証明書はこのドメインと "*.<domain_name>" のワイルドカードを SAN として
    一括カバーする。
  EOT
  type        = string

  validation {
    condition     = length(var.domain_name) > 0 && !can(regex("\\.$", var.domain_name))
    error_message = "domain_name は空でなく、末尾のドット (.) を含まないこと。"
  }
}

variable "tags" {
  description = "全リソースに付ける共通タグ"
  type        = map(string)
  default     = {}
}
