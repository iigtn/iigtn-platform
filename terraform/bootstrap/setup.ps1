# ==============================================================================
# Terraform State Bootstrap (manual one-time setup) — PowerShell version
#
# Creates:
#   - S3 bucket   : iigtn-tfstate-<account_id>  (versioned, encrypted, blocked)
#   - DynamoDB    : iigtn-tflock                (PK=LockID, on-demand)
#
# Idempotent: safe to re-run.
#
# Usage:
#   pwsh ./setup.ps1
#   # or
#   powershell -ExecutionPolicy Bypass -File ./setup.ps1
# ==============================================================================
$ErrorActionPreference = "Stop"

$Region    = if ($env:REGION) { $env:REGION } else { "ap-northeast-1" }
$AccountId = (aws sts get-caller-identity --query Account --output text)
$Bucket    = "iigtn-tfstate-$AccountId"
$Table     = "iigtn-tflock"

Write-Host "==> Account : $AccountId"
Write-Host "==> Region  : $Region"
Write-Host "==> Bucket  : $Bucket"
Write-Host "==> Table   : $Table"
Write-Host ""

# -----------------------------------------------------------------------------
# 1. S3 bucket
# -----------------------------------------------------------------------------
$bucketExists = $true
try { aws s3api head-bucket --bucket $Bucket 2>$null | Out-Null }
catch { $bucketExists = $false }

if ($bucketExists) {
    Write-Host "[skip]   S3 bucket $Bucket already exists"
} else {
    Write-Host "[create] S3 bucket $Bucket"
    aws s3api create-bucket `
        --bucket $Bucket `
        --region $Region `
        --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
}

Write-Host "[apply]  versioning"
aws s3api put-bucket-versioning `
    --bucket $Bucket `
    --versioning-configuration Status=Enabled

Write-Host "[apply]  encryption (AES256)"
$encConfig = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-encryption `
    --bucket $Bucket `
    --server-side-encryption-configuration $encConfig

Write-Host "[apply]  public access block"
aws s3api put-public-access-block `
    --bucket $Bucket `
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# -----------------------------------------------------------------------------
# 2. DynamoDB lock table
# -----------------------------------------------------------------------------
$tableExists = $true
try { aws dynamodb describe-table --table-name $Table --region $Region 2>$null | Out-Null }
catch { $tableExists = $false }

if ($tableExists) {
    Write-Host "[skip]   DynamoDB $Table already exists"
} else {
    Write-Host "[create] DynamoDB $Table"
    aws dynamodb create-table `
        --table-name $Table `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region | Out-Null
    Write-Host "[wait]   table to be active"
    aws dynamodb wait table-exists --table-name $Table --region $Region
}

# -----------------------------------------------------------------------------
# 3. Verify
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Verification ==="
aws s3api get-bucket-versioning --bucket $Bucket
aws dynamodb describe-table `
    --table-name $Table --region $Region `
    --query "Table.{Name:TableName,Status:TableStatus,Billing:BillingModeSummary.BillingMode}"

Write-Host ""
Write-Host "Done. Use this backend config in terraform/envs/<env>/backend.tf:"
@"

terraform {
  backend "s3" {
    bucket         = "$Bucket"
    key            = "envs/<dev|prod>/terraform.tfstate"
    region         = "$Region"
    dynamodb_table = "$Table"
    encrypt        = true
  }
}
"@
