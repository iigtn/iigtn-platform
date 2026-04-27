# ==============================================================================
# ACM Certificate (us-east-1) — for CloudFront
# ------------------------------------------------------------------------------
# 設計上の判断:
#   親ドメイン (iigtn.com) の DNS は Squarespace に置かれており、サブドメイン
#   委譲 (NS) を Squarespace の UI が拒否する。Workspace バンドルドメインで
#   よくある制約。よって Route53 hosted zone は作らない方針に変更。
#   DNS レコード（ACM 検証用 + 後の CloudFront 用）は Squarespace 側で手動管理。
#
# このモジュールが扱う範囲:
#   - ACM 証明書 (us-east-1) の発行
#   - DNS 検証完了の待機
#   - Squarespace に登録すべき CNAME を outputs として表示
# ==============================================================================
resource "aws_acm_certificate" "this" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = concat(["*.${var.domain_name}"], var.additional_san_names)
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# ==============================================================================
# ACM Certificate Validation — 検証完了をブロック
# ------------------------------------------------------------------------------
# Squarespace に CNAME を手動投入した後、ACM が検証 CNAME を引いて成功する。
# 75 分待つので、apply 後すぐに Squarespace で CNAME を登録すること。
#
# Squarespace に登録すべき CNAME は output "validation_records" を参照。
# ==============================================================================
resource "aws_acm_certificate_validation" "this" {
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.this.arn

  # validation_record_fqdns には ACM が要求する FQDN を渡す。
  # Route53 で record を作っていないので Squarespace 側に同じ FQDN/値の
  # CNAME が登録されることを前提にしている。
  validation_record_fqdns = [
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.resource_record_name
  ]

  timeouts {
    create = "75m"
  }
}
