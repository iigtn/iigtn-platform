output "distribution_id" {
  description = <<-EOT
    CloudFront Distribution の ID（`E1234ABCDEF` 形式）。
    キャッシュ無効化（`aws cloudfront create-invalidation`）等で使う。
  EOT
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_domain_name" {
  description = <<-EOT
    CloudFront が払い出した `*.cloudfront.net` ドメイン。
    親 DNS (Squarespace) でこのドメインに向けて CNAME を作ると、
    https://lab.iigtn.com/ がこの Distribution に紐付く。
  EOT
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_arn" {
  description = "Distribution ARN（IAM ポリシー等で参照）"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_hosted_zone_id" {
  description = <<-EOT
    CloudFront 用の固定 Hosted Zone ID（`Z2FDTNDATAQYW2`）。
    Route53 を使う場合の Alias レコードで使う。Squarespace 経由なら不要。
  EOT
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "bucket_name" {
  description = "静的サイトを置く S3 バケット名（デプロイ時に sync する宛先）"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 バケット ARN（GitHub Actions 用 IAM ポリシー等で参照）"
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "S3 のリージョナルドメイン（`<bucket>.s3.<region>.amazonaws.com`）。CloudFront origin として使われている値"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "oac_id" {
  description = "Origin Access Control ID（追加 Distribution で使い回す場合に参照）"
  value       = aws_cloudfront_origin_access_control.this.id
}
