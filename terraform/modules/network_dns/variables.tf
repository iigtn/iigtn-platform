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

variable "additional_san_names" {
  description = <<-EOT
    ACM 証明書の SAN に追加するドメイン名のリスト。例: ["iigtn.com"]
    apex ドメインを SAN 追加して CloudFront alias で apex 配信するときに使う。
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "全リソースに付ける共通タグ"
  type        = map(string)
  default     = {}
}
