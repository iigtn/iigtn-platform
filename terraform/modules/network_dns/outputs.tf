output "certificate_arn" {
  description = "Validated ACM certificate ARN (us-east-1) — CloudFront にアタッチする"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "certificate_domain_name" {
  description = "発行された証明書のプライマリドメイン"
  value       = aws_acm_certificate.this.domain_name
}

output "validation_records" {
  description = <<-EOT
    Squarespace の DNS に追加する必要がある CNAME レコード一覧。
    apply 後に表示される。各エントリは 1 個の CNAME に対応する。

    Squarespace UI での入力例:
      Host:  <name (FQDN から iigtn.com を除いた部分)>
      Type:  CNAME
      Data:  <value>
      TTL:   5 min
  EOT
  value = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
