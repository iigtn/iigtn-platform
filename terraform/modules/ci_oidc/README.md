# Module: `ci_oidc`

GitHub Actions が AWS に **静的キーなしで** デプロイするための OIDC + IAM Role を作るモジュール。

---

## 作成リソース

| リソース | 用途 |
|---|---|
| `aws_iam_openid_connect_provider` | GitHub を AWS の IdP として登録（アカウント全体で 1 個） |
| `aws_iam_role` (deploy) | GitHub Actions が AssumeRole する役割 |
| `aws_iam_role_policy` (deploy) | フロントデプロイに必要な最小権限のインラインポリシー |

---

## 入力

| 名前 | 必須 | 説明 |
|---|---|---|
| `github_owner` | ✓ | GitHub の個人/組織名 |
| `github_repo` | ✓ | リポジトリ名 |
| `allowed_branches` |  | デプロイ許可ブランチ（デフォルト `["main"]`） |
| `role_name` |  | Role 名（デフォルト `iigtn-github-actions-deploy`） |
| `deploy_bucket_arn` | ✓ | デプロイ先 S3 バケット ARN |
| `cloudfront_distribution_arn` | ✓ | キャッシュ無効化対象の Distribution ARN |
| `tags` |  | 共通タグ |

## 出力

| 名前 | 用途 |
|---|---|
| `oidc_provider_arn` | 他モジュールで OIDC Provider 参照する時 |
| `deploy_role_arn` | **GitHub Actions ワークフローで `role-to-assume` に貼る** |
| `deploy_role_name` | コンソール検索用 |

---

## Trust Policy の設計

Role を AssumeRole できるのは以下の **すべて** を満たすトークンのみ:

1. GitHub OIDC Provider が発行
2. `aud (audience)` claim が `sts.amazonaws.com`
3. `sub (subject)` claim が `repo:<owner>/<repo>:ref:refs/heads/<branch>` のいずれかにマッチ

これにより:
- 他人のリポジトリは AssumeRole 不可
- 自リポジトリの **PR / 他ブランチ** からも AssumeRole 不可（明示的に許可したブランチのみ）
- fork 先からも AssumeRole 不可

---

## Permissions Policy の設計（最小権限）

| API | 対象 |
|---|---|
| `s3:ListBucket`, `s3:GetBucketLocation` | デプロイ先バケット 1 個のみ |
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:PutObjectAcl` | バケット内オブジェクト |
| `cloudfront:CreateInvalidation`, `cloudfront:GetInvalidation`, `cloudfront:ListInvalidations` | 特定 Distribution のみ |

それ以外（IAM・他バケット・他 Distribution）は **何もできない**。

---

## GitHub Actions 側のワークフロー例

```yaml
name: frontend-deploy
on:
  push:
    branches: [main]
    paths: ['frontend/**', '.github/workflows/frontend-deploy.yml']

permissions:
  id-token: write   # ← OIDC token を発行するために必須
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: <terraform output deploy_role_arn>
          aws-region: ap-northeast-1

      - name: Build
        # ...

      - name: Deploy to S3
        run: aws s3 sync ./frontend/dist s3://<bucket>/ --delete

      - name: Invalidate CloudFront
        run: aws cloudfront create-invalidation --distribution-id <id> --paths "/index.html" "/sitemap.xml"
```
