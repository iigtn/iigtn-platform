# Module: `backend_api`

API Gateway HTTP API + Lambda + DynamoDB + SES で問い合わせフォームを処理するモジュール。

---

## 作成リソース

| リソース | 用途 |
|---|---|
| `aws_dynamodb_table` | 問い合わせ保存（PK = UUID） |
| `aws_lambda_function` | フォーム処理（バリデーション → DDB Put → SES 送信） |
| `archive_file` (data) | Lambda コードの zip パッケージング |
| `aws_cloudwatch_log_group` | Lambda ログ（14 日 retention） |
| `aws_iam_role` + `aws_iam_role_policy` | Lambda 実行ロール（最小権限） |
| `aws_apigatewayv2_api` | HTTP API |
| `aws_apigatewayv2_stage` | `$default` ステージ + throttling |
| `aws_apigatewayv2_integration` | API GW → Lambda の Proxy 統合 |
| `aws_apigatewayv2_route` × 2 | `POST /api/contact` + `OPTIONS /api/contact` |
| `aws_lambda_permission` | API GW から Lambda 呼び出し許可 |

---

## 入力

| 名前 | 必須 | 説明 |
|---|---|---|
| `name_prefix` | ✓ | リソース命名のプレフィクス（例 `iigtn-lab-prod`） |
| `lambda_source_dir` | ✓ | Lambda コードのディレクトリパス |
| `allowed_origin` | ✓ | CORS Allow-Origin（例 `https://lab.iigtn.com`） |
| `ses_from` |  | 送信元アドレス（空なら SES 連携無効） |
| `ses_to` |  | 送信先アドレス（空なら SES 連携無効） |
| `log_retention_days` |  | デフォルト 14 |
| `tags` |  | 共通タグ |

## 出力

| 名前 | 用途 |
|---|---|
| `api_endpoint` | API GW のフル URL |
| `api_endpoint_host` | ホスト名のみ（CloudFront origin に直で使える） |
| `api_id` | API GW ID |
| `lambda_function_name` | ログ確認・呼び出し用 |
| `lambda_function_arn` | IAM 等で参照 |
| `table_name` | DDB テーブル名 |
| `table_arn` | DDB テーブル ARN |
| `log_group_name` | ログ確認用 |

---

## 設計判断

| 項目 | 値 | 理由 |
|---|---|---|
| API GW タイプ | HTTP API | REST より約 1/3 の価格、低レイテンシ |
| Lambda runtime | Node.js 20 | LTS、AWS SDK v3 同梱 |
| Lambda architecture | arm64 | 約 20% 安、性能ほぼ同等 |
| Lambda memory | 256 MB | DDB+SES 程度なら十分速い |
| Lambda timeout | 10s | フォーム用途で長く待つ意味なし |
| DDB billing | On-demand | アクセス薄なら最安 |
| DDB PK | `id` (UUID) | PII を PK にしない |
| DDB PITR | 有効 | 35 日連続バックアップ、誤削除対策 |
| Logs Retention | 14 日 | コスト最適化、長期保管したい時は env で延長 |
| SES Permissions | `Resource: *` | 後で verified identity ARN で絞る予定 |
| Throttling | Burst 100 / Rate 50 rps | 個人サイトでは十分余裕 |

---

## SES サンドボックスの扱い

新規 AWS アカウントの SES は **サンドボックス** モード:
- 送信元 / 送信先 の **両方が verified** なメアドのみ送信可
- 1 日 200 通・1 秒 1 通の上限

verify する手順 (AWS コンソール):
1. SES → Identities → Create identity
2. Identity type: Email address
3. Email address: `aws-dev@iigtn.com` 等
4. Create → 当該アドレスに確認メールが届く → リンククリック

本番化 (production access) は AWS に申請:
1. SES → Account dashboard → Request production access
2. 用途・送信量・バウンス対応を記入
3. 1〜2 営業日で解除

---

## ローカルでテストするコマンド例

apply 後、API GW URL を取得してテスト:

```bash
# 直接 API GW を叩く
curl -X POST https://<api_id>.execute-api.ap-northeast-1.amazonaws.com/api/contact \
  -H 'Content-Type: application/json' \
  -d '{"name":"Tester","email":"test@example.com","message":"Hello there from CLI"}'

# CloudFront 経由 (本番経路)
curl -X POST https://lab.iigtn.com/api/contact \
  -H 'Content-Type: application/json' \
  -d '{"name":"Tester","email":"test@example.com","message":"Hello there from CLI"}'

# DDB に入っているか確認
aws dynamodb scan --table-name iigtn-lab-prod-contacts --max-items 5

# Lambda ログ確認
aws logs tail /aws/lambda/iigtn-lab-prod-contact --since 5m
```
