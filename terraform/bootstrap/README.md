# Terraform Bootstrap

> ⚠️ **このディレクトリの中身は手動で 1 回だけ実行する初期設定です。**
> Terraform 管理対象外（鶏卵問題のため）。実行後は二度と触りません。

---

## 何をするのか

Terraform の **state（現状記録ファイル）の置き場** を AWS 上に作ります。

- **S3 バケット**: `iigtn-tfstate-<account_id>` — state ファイル本体を保管
- **DynamoDB テーブル**: `iigtn-tflock` — 同時 apply を防ぐロック

これらは Terraform で作りたくても作れません。state を置く場所自体が無いと Terraform が動かないからです。

---

## 前提

- AWS アカウント作成済
- ルートユーザに MFA 設定済
- IAM Identity Center で開発用ユーザを作成済（または管理者 IAM ユーザ）
- ローカルに AWS CLI v2 インストール済
- `aws configure sso` または `aws configure` で認証設定済
- リージョンは **ap-northeast-1（東京）** を使う前提

---

## 1 回だけの実行手順

### Step 1. AWS アカウント ID を取得

```bash
aws sts get-caller-identity --query Account --output text
```

例: `123456789012` が返ってくるので控える。

### Step 2. S3 バケットを作る

> バケット名はグローバル一意。`<account_id>` を上で取ったものに置き換える。

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-1
BUCKET="iigtn-tfstate-${ACCOUNT_ID}"

# バケット作成（東京リージョン）
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# バージョニング ON（state 履歴を残してロールバック可能に）
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# 暗号化（SSE-S3, AES256）
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }
    }]
  }'

# Public Block 全 ON（誤公開を構造的に防ぐ）
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 確認
aws s3api get-bucket-versioning --bucket "$BUCKET"
aws s3api get-bucket-encryption --bucket "$BUCKET"
aws s3api get-public-access-block --bucket "$BUCKET"
```

### Step 3. DynamoDB ロックテーブルを作る

```bash
aws dynamodb create-table \
  --table-name iigtn-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

# 作成完了まで待つ（30 秒程度）
aws dynamodb wait table-exists \
  --table-name iigtn-tflock \
  --region "$REGION"

# 確認
aws dynamodb describe-table \
  --table-name iigtn-tflock \
  --region "$REGION" \
  --query 'Table.{Name:TableName,Status:TableStatus,Billing:BillingModeSummary.BillingMode}'
```

---

## なぜこの設定なのか

| 設定 | 理由 |
|---|---|
| **S3 バージョニング ON** | 誤った state を上書きしてもロールバック可能。プロジェクト最重要ファイルのため必須 |
| **SSE-S3 (AES256)** | state ファイルには IAM Role ARN や接続情報が含まれる。最低限の暗号化 |
| **Public Block 全 ON** | state ファイルが公開バケット経由で漏洩する事故を構造的に防ぐ |
| **DynamoDB PK=LockID** | Terraform の S3 backend は LockID という属性でロックを取る仕様 |
| **PAY_PER_REQUEST** | apply 中の数秒しかロックされない。プロビジョン課金より圧倒的に安い |

---

## 完了確認

両方が以下のように作られていれば OK:

```bash
# S3
aws s3 ls | grep iigtn-tfstate
# 例: 2026-04-25 12:00:00 iigtn-tfstate-123456789012

# DynamoDB
aws dynamodb list-tables --region ap-northeast-1 --query 'TableNames'
# 例: ["iigtn-tflock"]
```

---

## 次のステップ

- bootstrap が終わったら、**`terraform/envs/dev/`** で `terraform init` を実行
- backend 設定はそこで以下のように書く:

```hcl
terraform {
  backend "s3" {
    bucket         = "iigtn-tfstate-<ACCOUNT_ID>"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "iigtn-tflock"
    encrypt        = true
  }
}
```

---

## 万が一の操作

### 全部やり直したい場合（state を捨てる覚悟がある時のみ）

```bash
# テーブル削除
aws dynamodb delete-table --table-name iigtn-tflock --region ap-northeast-1

# バケット中身を削除（バージョン付きなので注意）
aws s3 rm "s3://iigtn-tfstate-${ACCOUNT_ID}" --recursive
aws s3api delete-objects --bucket "iigtn-tfstate-${ACCOUNT_ID}" \
  --delete "$(aws s3api list-object-versions --bucket "iigtn-tfstate-${ACCOUNT_ID}" \
    --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}')"

# バケット削除
aws s3api delete-bucket --bucket "iigtn-tfstate-${ACCOUNT_ID}"
```

⚠️ **これを実行すると Terraform 管理下の全リソースの追跡情報を失う**。本番運用後は絶対にやらないこと。
