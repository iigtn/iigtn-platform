# Metrics — 実運用メトリクス

> 月次更新。**「実際に動いている」ことの最も強い証拠** になるドキュメント。
> 計測値は **Cost Explorer / CloudWatch / Search Console / RUM** から自動取得する想定。
>
> ⚠️ launch 直後は値が無いため、**「未測定 / 計測予定」** と明記。後付けで嘘を書かないこと。

---

## サマリ（最新月: YYYY-MM）

| カテゴリ | 指標 | 値 | 前月比 |
|---|---|---:|---:|
| Performance | LCP (p75) | _未測定_ | — |
| Performance | INP (p75) | _未測定_ | — |
| Performance | TTFB (p75) | _未測定_ | — |
| Reliability | Uptime | _未測定_ | — |
| Reliability | Lambda エラー率 | _未測定_ | — |
| Reliability | アラート発火回数 | _未測定_ | — |
| Traffic | 月間 PV | _未測定_ | — |
| Traffic | UU | _未測定_ | — |
| Traffic | Bot 比率 | _未測定_ | — |
| Cost | 月次合計 | _未測定_ | — |
| Cost | 想定との乖離 | _未測定_ | — |
| CVR | フォーム送信率 | _未測定_ | — |

---

## 計測対象とソース

### Performance（CrUX / RUM / CloudFront）
| 指標 | 目標 | 取得元 |
|---|---|---|
| LCP (p75) | < 2.5 s | Search Console / CrUX |
| INP (p75) | < 200 ms | web-vitals.js → DynamoDB |
| CLS (p75) | < 0.1 | 同上 |
| TTFB (p75) | < 600 ms | CloudFront `x-cache`, RUM |
| CloudFront キャッシュヒット率 | > 90% | CloudFront Reports |
| Lambda Duration p95 | < 500 ms | CloudWatch Metrics |
| API Gateway latency p95 | < 800 ms | CloudWatch Metrics |

### Reliability
| 指標 | 目標 | 取得元 |
|---|---|---|
| Uptime（月次） | > 99.9% | Synthetics Canary |
| Lambda エラー率 | < 1% | CloudWatch |
| API Gateway 5xx 率 | < 0.5% | CloudWatch |
| アラート発火件数 | — | SNS topic 履歴 |
| MTTD（検知までの中央値） | — | Post-mortem 集計 |
| MTTR（復旧までの中央値） | — | Post-mortem 集計 |

### Traffic
| 指標 | 取得元 |
|---|---|
| 日次/月次 PV | GA4 / CloudFront access log |
| ユニーク IP | CloudFront access log |
| Bot 比率 | UA 分類 |
| 流入元 | GA4 |

### Cost
| 指標 | 取得元 |
|---|---|
| 月次合計 | Cost Explorer |
| サービス別内訳 | Cost Explorer |
| 想定 (cost.md) との乖離 | 手計算 |

### CVR / Engagement
| 指標 | 取得元 |
|---|---|
| 問い合わせフォーム到達 → 送信完了率 | RUM + DynamoDB |
| 直帰率 | GA4 |
| 平均ページ滞在時間 | GA4 |

---

## 月次レポート（公開 Template）

毎月初に以下のフォーマットで `blog/metrics-YYYY-MM.md` にコミット → 自動公開：

```markdown
# Metrics Report YYYY-MM

## Summary
- 一行サマリ（前月比でうまくいったこと / 課題 1 件）

## Performance
- LCP / INP / TTFB / Hit rate

## Reliability
- Uptime / アラート発火 / 障害サマリ

## Traffic
- PV / UU / 流入元 Top 5

## Cost
- 月次合計 / サービス別 / 想定との乖離

## What I changed this month
- 具体的に変えた設定・コード

## Open questions
- 来月までに判断したいこと
```

---

## 過去のアラート発火履歴（実ログサマリ）

> Post-mortem の集計指標。月次で集計を更新。

| 月 | 件数 | 内訳 | MTTD | MTTR |
|---|---:|---|---:|---:|
| _未集計_ | — | — | — | — |

例（launch 後の想定フォーマット）:

```
2026-MM-DD 03:42 JST  Lambda Errors > 1%
  - 検知: SNS → メール (3 分後に確認 / 朝起きて気付いた)
  - 原因: SES throttle by sandbox
  - 復旧: production access 申請
  - MTTD: 3 分（検知）/ 8 時間（着手まで）
  - MTTR: 18 時間
  - 学び: メール通知だけでは深夜事象に弱い → Slack 連携検討
```

---

## メトリクスの公開原則

- **悪い数字も隠さない**。「Uptime 98.5%（先月 99.7% から悪化）」のような後退も書く
- **ベンチマークを混ぜない**。「業界平均より良い」みたいな相対化はしない
- **改善に時間がかかる項目は素直に放置中と書く**。たとえば「TTFB は 800ms で目標未達。優先度低のため放置中」
- **数値の根拠**（取得日時 / 期間 / サンプル数）を必ず添える
