terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      # ACM 証明書 (us-east-1) を扱うため、呼び出し側から
      # aws.us_east_1 alias provider を渡してもらう前提。
      configuration_aliases = [aws.us_east_1]
    }
  }
}
