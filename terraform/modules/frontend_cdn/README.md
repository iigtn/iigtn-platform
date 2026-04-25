# Module: `frontend_cdn`

S3 (private) + CloudFront (with OAC) + ACM 証明書アタッチ で静的サイト配信基盤を作るモジュール。

---

## 作成リソース

| リソース | 用途 |
|---|---|
| `aws_s3_bucket` | 静的サイトファイル保管 |
| `aws_s3_bucket_public_access_block` | 公開ブロック 4 種 |
| `aws_s3_bucket_versioning` | 誤デプロイのロールバック用 |
| `aws_s3_bucket_server_side_encryption_configuration` | SSE-S3 (AES256) |
| `aws_cloudfront_origin_access_control` | CloudFront → S3 の認証手段 (OAC) |
| `aws_cloudfront_distribution` | CDN + TLS 終端 |
| `aws_s3_bucket_policy` | CloudFront だけに s3:GetObject を許可 |

---

## 入力

| 名前 | 必須 | 説明 |
|---|---|---|
| `domain_name` | ✓ | カスタムドメイン (例 `lab.iigtn.com`) |
| `certificate_arn` | ✓ | us-east-1 の ACM 証明書 ARN |
| `bucket_name` | ✓ | グローバル一意な S3 バケット名 |
| `tags` |  | 共通タグ |

## 出力

| 名前 | 用途 |
|---|---|
| `distribution_domain_name` | **Squarespace に CNAME で登録する宛先** |
| `distribution_id` | CloudFront 無効化コマンドで使う |
| `bucket_name` | デプロイ (`aws s3 sync`) の宛先 |

---

## 採用した設計

| 項目 | 値 | 理由 |
|---|---|---|
| OAC | 有効（OAI ではない） | 新規構築は OAC 推奨、KMS 対応 |
| Public Access Block | 4 種すべて true | 構造的 public 化防止 |
| Bucket Policy | CloudFront のこの Distribution からのみ許可 | aws:SourceArn 条件で限定 |
| TLS minimum | TLSv1.2_2021 | 古いクライアント切り捨ての方が安全 |
| HTTP→HTTPS | redirect-to-https | 平文を許可しない |
| Cache Policy | AWS マネージド `CachingOptimized` | まず標準で運用、必要なら自作に切替 |
| Response Headers | AWS マネージド `SecurityHeadersPolicy` | X-Frame-Options 等を自動付与 |
| 圧縮 | 自動（gzip/brotli） | 帯域削減 |
| Price Class | 200 | 北米欧州アジア。日本訪問者向けに最適 |
| HTTP/3 | 有効 | 新しいクライアントの体感速度向上 |
| Geo Restriction | なし | 個人サイト |
| WAF | なし（将来追加） | 攻撃を観測してから |
| SPA error fallback | 403/404 → /index.html (200) | クライアントサイドルーティング対応 |

---

## 使い方（envs/prod/main.tf）

```hcl
module "frontend_cdn" {
  source          = "../../modules/frontend_cdn"
  domain_name     = "lab.iigtn.com"
  certificate_arn = module.network_dns.certificate_arn
  bucket_name     = "iigtn-lab-web-prod-${data.aws_caller_identity.current.account_id}"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

## デプロイの仕方

apply 後の S3 へファイルを置けばすぐ配信される（最初は `index.html` だけでも OK）:

```bash
echo '<h1>Hello from CloudFront</h1>' > /tmp/index.html
aws s3 cp /tmp/index.html s3://<bucket_name>/index.html
```

CloudFront のキャッシュは 24h なので、即時反映したい時は invalidation:

```bash
aws cloudfront create-invalidation \
  --distribution-id <distribution_id> \
  --paths "/index.html"
```
