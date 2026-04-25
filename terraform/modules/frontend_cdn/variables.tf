variable "domain_name" {
  description = <<-EOT
    CloudFront にアタッチするドメイン名。例: "lab.iigtn.com"
    aliases (CNAME) として CloudFront Distribution に登録される。
    DNS は別途 (Squarespace 等) でこのドメインを Distribution の cloudfront.net 名に向ける。
  EOT
  type        = string
}

variable "certificate_arn" {
  description = <<-EOT
    CloudFront にアタッチする ACM 証明書 ARN。**us-east-1 リージョン** のもの限定。
    network_dns モジュールの output.certificate_arn から渡す想定。
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:", var.certificate_arn))
    error_message = "certificate_arn は us-east-1 の ACM 証明書である必要があります（CloudFront の仕様）。"
  }
}

variable "bucket_name" {
  description = <<-EOT
    静的サイトを置く S3 バケット名。AWS 全体で一意である必要がある（小文字、ハイフン可、ドット可）。
    例: "iigtn-lab-web-prod-211374268447"
  EOT
  type        = string
}

variable "tags" {
  description = "全リソースに付ける共通タグ"
  type        = map(string)
  default     = {}
}
