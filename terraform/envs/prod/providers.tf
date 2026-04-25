# ==============================================================================
# AWS Provider — 2 つ用意
# ------------------------------------------------------------------------------
# 1. default      : ap-northeast-1 (東京) — 大半のリソース
# 2. us_east_1    : us-east-1 (バージニア) — CloudFront 用 ACM 証明書専用
#
# default_tags ですべてのタグを自動付与（個別 resource に書かなくて良くなる）。
# ==============================================================================
provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = "iigtn"
    Environment = "prod"
    ManagedBy   = "Terraform"
    Repo        = "iigtn-platform"
  }
}
