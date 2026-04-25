# ==============================================================================
# S3 Backend — Terraform state を AWS 上で集中管理
# ------------------------------------------------------------------------------
# bootstrap で作った S3 バケットと DynamoDB ロックテーブルを参照する。
# backend ブロックには変数を使えないため、値は直接書く（仕様）。
# ==============================================================================
terraform {
  backend "s3" {
    bucket         = "iigtn-tfstate-211374268447"
    key            = "envs/prod/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "iigtn-tflock"
    encrypt        = true
  }
}
