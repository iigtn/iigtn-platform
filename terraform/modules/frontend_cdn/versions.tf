terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      # CloudFront Distribution は東京 (default) で管理するが、
      # 関連する ACM 証明書は us-east-1 にしか存在しないため、
      # 念のため呼び出し側から us_east_1 alias provider も渡してもらう前提にしておく。
      # （現状 frontend_cdn 内で us_east_1 を使う resource は無いが、
      #  将来 Lambda@Edge 等を足す時の拡張余地として宣言しておく）
      configuration_aliases = [aws.us_east_1]
    }
  }
}
