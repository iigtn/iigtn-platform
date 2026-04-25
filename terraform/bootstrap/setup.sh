#!/usr/bin/env bash
# ==============================================================================
# Terraform State Bootstrap (manual one-time setup)
#
# Creates:
#   - S3 bucket   : iigtn-tfstate-<account_id>  (versioned, encrypted, blocked)
#   - DynamoDB    : iigtn-tflock                (PK=LockID, on-demand)
#
# Idempotent: safe to re-run. Existing resources are not touched.
#
# Prereqs:
#   - aws CLI v2
#   - aws configure (or sso) with admin permissions
#   - region = ap-northeast-1
# ==============================================================================
set -euo pipefail

REGION="${REGION:-ap-northeast-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="iigtn-tfstate-${ACCOUNT_ID}"
TABLE="iigtn-tflock"

echo "==> Account : $ACCOUNT_ID"
echo "==> Region  : $REGION"
echo "==> Bucket  : $BUCKET"
echo "==> Table   : $TABLE"
echo

# ------------------------------------------------------------------------------
# 1. S3 bucket
# ------------------------------------------------------------------------------
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "[skip]   S3 bucket $BUCKET already exists"
else
  echo "[create] S3 bucket $BUCKET"
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
fi

echo "[apply]  versioning"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "[apply]  encryption (AES256)"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }
    }]
  }'

echo "[apply]  public access block"
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ------------------------------------------------------------------------------
# 2. DynamoDB lock table
# ------------------------------------------------------------------------------
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "[skip]   DynamoDB $TABLE already exists"
else
  echo "[create] DynamoDB $TABLE"
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" >/dev/null
  echo "[wait]   table to be active"
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
fi

# ------------------------------------------------------------------------------
# 3. Verify
# ------------------------------------------------------------------------------
echo
echo "=== Verification ==="
aws s3api get-bucket-versioning --bucket "$BUCKET"
aws dynamodb describe-table \
  --table-name "$TABLE" --region "$REGION" \
  --query 'Table.{Name:TableName,Status:TableStatus,Billing:BillingModeSummary.BillingMode}'

echo
echo "Done. Use this backend config in terraform/envs/<env>/backend.tf:"
cat <<EOF

terraform {
  backend "s3" {
    bucket         = "$BUCKET"
    key            = "envs/<dev|prod>/terraform.tfstate"
    region         = "$REGION"
    dynamodb_table = "$TABLE"
    encrypt        = true
  }
}
EOF
