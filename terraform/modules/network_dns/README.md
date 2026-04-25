# Module: `network_dns`

ACM 証明書 (us-east-1) を発行し、DNS 検証完了まで待機するモジュール。
**DNS そのものは管理しない**（Squarespace 等の外部 DNS が前提）。

> ⚠️ 過去バージョンでは Route53 hosted zone も作成していたが、Squarespace 親ドメインへの NS 委譲が DNS プロバイダ側 UI で拒否されたため、ホストゾーン作成は廃止した。詳細は本モジュールヘッダコメント参照。

---

## 作成リソース

| リソース | リージョン | 内容 |
|---|---|---|
| `aws_acm_certificate` | **us-east-1** | `<domain_name>` + `*.<domain_name>` の TLS 証明書 |
| `aws_acm_certificate_validation` | us-east-1 | DNS 検証完了待ち（最大 75 分） |

> ACM は CloudFront 連携のため必ず us-east-1 で発行する必要がある。

---

## 入力

| 名前 | 型 | 必須 | 説明 |
|---|---|---|---|
| `domain_name` | `string` | ✓ | 証明書ドメイン。例 `lab.iigtn.com` |
| `tags` | `map(string)` |  | 共通タグ |

## 出力

| 名前 | 用途 |
|---|---|
| `certificate_arn` | CloudFront `viewer_certificate` にアタッチ |
| `certificate_domain_name` | 確認用 |
| `validation_records` | **Squarespace に手動で登録すべき CNAME 一覧** |

---

## 呼び出し例（envs/prod/main.tf）

```hcl
provider "aws" {
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "network_dns" {
  source      = "../../modules/network_dns"
  domain_name = "lab.iigtn.com"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "validation_records" {
  value = module.network_dns.validation_records
}
```

---

## 運用手順

### 第 1 段階: 証明書だけ作る

```bash
terraform apply -target=module.network_dns.aws_acm_certificate.this
terraform output -json validation_records
```

出力例:
```json
{
  "lab.iigtn.com": {
    "name":  "_abc123.lab.iigtn.com.",
    "type":  "CNAME",
    "value": "_def456.acm-validations.aws."
  },
  "*.lab.iigtn.com": {
    "name":  "_abc123.lab.iigtn.com.",
    "type":  "CNAME",
    "value": "_def456.acm-validations.aws."
  }
}
```

> 通常 `<domain>` と `*.<domain>` は同一の検証 CNAME に集約されるため、登録は **1 個だけ** で済むことが多い。

### 第 2 段階: 親 DNS (Squarespace 等) に CNAME 登録

| Host | Type | Data | TTL |
|---|---|---|---|
| `_abc123.lab` | CNAME | `_def456.acm-validations.aws.` | 5 min |

> Host は親ドメイン (`iigtn.com`) を除いた部分。Squarespace UI が自動補完する。

### 第 3 段階: 検証完了

```bash
terraform apply
```

ACM が CNAME を引いて成功すると証明書が `ISSUED` になり apply 完了。

---

## トラブル

| 症状 | 対処 |
|---|---|
| 75 分タイムアウト | DNS 反映を `dig CNAME _abc123.lab.iigtn.com @8.8.8.8` で確認、未反映なら Squarespace 側の登録ミス |
| Squarespace で CNAME 登録できない | Host 値の末尾が誤ってないか確認。`_abc123.lab` の形（FQDN ではない） |
| 「証明書がすでに存在」 | 同一ドメイン構成は重複可（`create_before_destroy`）。手動で削除した残骸が ACM に残ってないか確認 |
