domain_name  = "lab.iigtn.com"
github_owner = "iigtn"
# github_repo, github_allowed_branches はデフォルト ("iigtn-platform", ["main"])

# apex (iigtn.com) と www を CloudFront alias に追加 + 証明書 SAN にも追加
# Squarespace が apex CNAME 不可のため、apex → www.iigtn.com を 301 で誘導する構成
# *.lab.iigtn.com は lab. 下のみカバーするため、 *.iigtn.com を別途追加して www. 等もカバー
additional_san_names = ["iigtn.com", "*.iigtn.com"]
additional_aliases   = ["iigtn.com", "www.iigtn.com"]  # CloudFront 側は両方受ける

# ── SES 設定 ──────────────────────────────────────────────────
# 送信元 / 送信先 ともに contact@iigtn.com を使う (sandbox なので両方 verify 済必須)
# 本番化したい場合: SES Production Access 申請
ses_from = "contact@iigtn.com"
ses_to   = "contact@iigtn.com"

# ── Observability 通知先 (任意。CloudWatch Alarm + Budgets) ─
# alarm_email = "contact@iigtn.com"
