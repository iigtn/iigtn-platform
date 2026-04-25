# Runbook & Incident Logs — 障害対応手順 + 実障害ログ

このドキュメントは 2 部構成：

- **Part 1: Runbook** — 想定される障害への手順書（事前定義）
- **Part 2: Incident Logs** — 実際に発生した / 学習目的で意図的に再現した事象の記録

> 実測メトリクス（MTTD / MTTR / アラート発火件数）は [metrics.md](./metrics.md) に集計します。

---

## Part 1: Runbook

### 1-1. よくあるトラブル一覧

| # | 症状 | 原因の典型 | 対応 |
|---|---|---|---|
| 1 | **CloudFront 403 (AccessDenied)** | OAC 設定漏れ / Bucket Policy が古い / オブジェクトキー不一致 | ① Bucket Policy に Distribution ARN<br>② Origin に OAC アタッチ<br>③ CloudFront Functions でリライト |
| 2 | **CloudFront 403 (Forbidden)** | WAF でブロック / 署名付き URL 期限切れ | WAF Sampled requests でブロック理由特定 |
| 3 | **ACM 証明書が反映されない** | DNS 検証レコード未投入 / NS が Route53 になっていない | ① `dig NS iigtn.com`<br>② 検証 CNAME 引けるか<br>③ 24h 待ってから再作成 |
| 4 | **CloudFront に ACM 証明書が出ない** | 証明書が us-east-1 以外で発行 | us-east-1 で再発行 |
| 5 | **SES サンドボックス制限** | 検証済アドレスにしか送信できない | Production access 申請 |
| 6 | **SES バウンス率上昇** | 無効アドレス送信、フィードバックループ未設定 | バウンス・苦情を SNS で通知 → サプレッションリスト |
| 7 | **Lambda Timeout** | 外部 API 待ち / コールドスタート | Timeout 拡大、SES クライアントをハンドラ外で初期化 |
| 8 | **API Gateway CORS エラー** | OPTIONS 未許可 / Origin 不一致 | HTTP API CORS で `iigtn.com` 許可、`POST` 含める |
| 9 | **DynamoDB Throttle** | バースト時スロットル | On-demand 切替 or Auto Scaling |
| 10 | **Terraform State Lock 解除されない** | apply 異常終了 | `terraform force-unlock <ID>` |
| 11 | **GitHub Actions が AssumeRole できない** | Trust Policy `sub` 不一致 | `repo:owner/repo:ref:refs/heads/main` 表記 |
| 12 | **CloudFront 配信が古い** | キャッシュ TTL 長い | `aws cloudfront create-invalidation --paths "/index.html"` |

### 1-2. 障害発生時の調査順序（外側 → 内側）

```
[ 1. 一次切り分け ]
    ├─ AWS Health Dashboard で東京リージョン障害無いか
    ├─ status.iigtn.com（将来）で過去事象を確認
    └─ 影響範囲（全体か特定ページか）

[ 2. 配信層 ]
    ├─ Route53 ヘルスチェック・DNS 解決
    ├─ CloudFront Status / 4xx・5xx メトリクス
    └─ ACM 証明書の有効期限

[ 3. アプリ層 ]
    ├─ S3 Bucket Policy / オブジェクト存在
    ├─ API Gateway 5xx・レイテンシ
    ├─ Lambda エラー率・Concurrency・Throttle
    └─ DynamoDB Throttle / ConditionalCheckFailed

[ 4. 周辺 ]
    ├─ SES 送信成功率・バウンス率
    ├─ CloudWatch Alarm 履歴
    └─ AWS Budgets で異常コスト

[ 5. 復旧 → 記録 ]
    ├─ 一次対応
    ├─ Runbook 追記
    └─ Post-mortem を docs/postmortem/ に残す
```

### 1-3. Post-mortem テンプレ

`docs/postmortem/YYYY-MM-DD-<title>.md`：

```markdown
# Incident YYYY-MM-DD <タイトル>

## Summary
- 影響範囲 / 影響時間 / 影響ユーザ数

## Timeline (JST)
- HH:MM 検知方法 (SNS/メール/外部報告/翌朝確認)
- HH:MM 一次対応
- HH:MM 復旧

## MTTD / MTTR
- 検知まで X 分 / 復旧まで Y 分
- 着手まで Z 分（深夜事象なら正直に書く）

## Root Cause
- なぜ起きたか（5 Whys）

## What worked / What didn't
- 監視で検知できたか / 通知が届いたか / 見逃したか

## Action items
- [ ] Runbook 追記
- [ ] アラート閾値見直し
- [ ] テスト追加
```

---

## Part 2: Incident Logs

> ⚠️ ここはテンプレ的な Runbook と違い、**実際に起きた / 意図的に再現した事象** だけを記録します。
> ポートフォリオの差別化要因になる章。サイト運用とともに育てます。
>
> 📝 各 Case はテンプレートなので、実体験で埋めてください。**意図的再現の場合はその旨を明記** すること（捏造に見えないため）。

### Case 1: CloudFront 403 (AccessDenied) — OAC 設定漏れ

| 項目 | 内容 |
|---|---|
| 発生日 | _[編集]_ YYYY-MM-DD |
| 種別 | _[編集]_ ☐ 本番事故  / ☐ 学習目的での意図的再現 |
| 症状 | iigtn.com 全ページが `AccessDenied` を返す |
| 発見経路 | Synthetics Canary が 200 → 403 を検知 → SNS → メール |
| 検知から復旧 | _[編集]_ XX 分 |
| 直接原因 | Terraform で OAC は作成したが、S3 Bucket Policy の `aws:SourceArn` condition 値が古い Distribution ARN だった |
| 一次対応 | Bucket Policy の `aws:SourceArn` を修正、`terraform apply` |
| 再発防止 | tfsec カスタムルールで OAC ↔ Bucket Policy ARN の整合性検証 |
| 学び | OAC は「両側設定」が必要。片側だけだと **黙って 403** が返る |

### Case 2: SES Production Access の申請却下と再申請

| 項目 | 内容 |
|---|---|
| 発生日 | _[編集]_ YYYY-MM-DD |
| 症状 | サンドボックス解除申請が初回却下 |
| 却下理由（推定） | _[編集]_ ユースケース説明不足 / 想定送信量未記載 |
| 改善した申請内容 | _[編集]_ 月 100 通以下、バウンス時はサプレッションリスト追加と明記 |
| 学び | SES 申請は AWS 担当者が「後で運用責任を取れるか」を見ている |

### Case 3: Lambda コールドスタート 1.2s 問題（意図的再現）

| 項目 | 内容 |
|---|---|
| 種別 | 学習目的で意図的に再現 |
| 症状 | 問い合わせフォーム送信時、初回だけ 1.2s 待たされる |
| 原因 | Container Image 形式 + x86_64 + 同期初期化処理 |
| 対応 | ZIP 形式 + arm64 + ハンドラ外で SES クライアント初期化 + bundle 削減 |
| Before / After | 1.2s → 約 280ms |

### Case 4: Terraform で prod 環境を一部破壊しかけた

| 項目 | 内容 |
|---|---|
| 発生日 | _[編集]_ YYYY-MM-DD |
| 症状 | _[編集]_ 例：`terraform apply` で prod の DynamoDB テーブルが Replace 扱いに |
| 原因 | _[編集]_ 例：tfvars の環境スイッチを忘れて dev のつもりで prod ステートに apply |
| 阻止できた理由 | _[編集]_ 例：`prevent_destroy` が発火 / Plan を読み返した |
| 学び | プランを読まずに apply しないこと。**`prevent_destroy` は最後の砦** |

### Case 5: DNS 切り替えで一時ダウン

| 項目 | 内容 |
|---|---|
| 発生日 | _[編集]_ YYYY-MM-DD |
| 症状 | _[編集]_ 旧 NS の TTL が長く、一部ユーザに数時間古い IP が返った |
| 一次対応 | _[編集]_ 待機。途中で何もできない |
| 学び | DNS は **ロールバック不可** な領域がある |

### Case 6: CloudFront Invalidation 課金の見落とし

| 項目 | 内容 |
|---|---|
| 種別 | _[編集]_ 設定見直しによる予防（実際の超過なし） |
| 気付いた経緯 | リリース毎に `--paths "/*"` を打つ workflow を見直した際、**月 1,000 paths 無料・超過分は path あたり ~$0.005** という料金体系を再確認 |
| 学び | AWS の課金単位は **doc を精読しないと誤解する** |

### Case 7: アラートを見逃して翌朝対応した（人間的失敗）

> 📝 **「気付くのが遅れた」系はリアルな運用の証拠** になる。隠さず書く方が信用される。

| 項目 | 内容 |
|---|---|
| 発生日 | _[編集]_ YYYY-MM-DD（深夜帯） |
| 症状 | _[編集]_ 例：03:42 JST に Lambda Errors > 1% で SNS → メール発火。スマホ通知 OFF だったため気付かず、翌朝 8:30 に確認 |
| 影響 | _[編集]_ 例：問い合わせフォーム経由のメール送信が約 5 時間停止（実害は問い合わせ 0 件のため軽微） |
| 着手まで | 検知 3 分（メール）/ **着手 約 5 時間後**（朝起きて気付いた） |
| 直接原因 | SES サンドボックスのバウンスで Lambda が連続失敗 |
| 反省 | 通知チャネルがメールのみで、深夜事象に弱い |
| 改善 | _[編集]_ 例：CRITICAL アラートだけは Slack + LINE Notify に分岐、深夜は LINE で起こすルール化 |
| 学び | 「アラートが届いた = 気付ける」ではない。**通知チャネルと自分の生活リズム** をセットで設計する必要がある |

### Case 8: GitHub Secrets を誤って Issue 本文に貼った（やらかし）

> 📝 これも「やらかし系」テンプレ。

| 項目 | 内容 |
|---|---|
| 発生日 | _[編集]_ YYYY-MM-DD |
| 症状 | _[編集]_ 例：デバッグログを Issue にペーストしたら AWS_ACCESS_KEY_ID が含まれていた |
| 気付いた経緯 | _[編集]_ 例：GitHub の Secret Scanning Push Protection アラート / Slack 通知 |
| 一次対応 | ① Issue を即削除（git history は残るので注意）<br>② IAM Access Key を即削除 → 新規発行<br>③ CloudTrail で不正アクセスの有無を確認 |
| 再発防止 | リポジトリで `git-secrets` / `gitleaks` を pre-commit に登録、CI でも実行 |
| 学び | **「Secret は人間が触れる場所に置かない」** が原則。OIDC 移行を急ぐきっかけになった |

---

## アラート発火履歴サマリ（実ログから集計）

> [metrics.md](./metrics.md) に月次集計を載せ、**個別の post-mortem は `docs/postmortem/` に分離** しています。

| 月 | 件数 | 内訳 | MTTD（中央値） | MTTR（中央値） |
|---|---:|---|---:|---:|
| _未集計_ | — | — | — | — |
