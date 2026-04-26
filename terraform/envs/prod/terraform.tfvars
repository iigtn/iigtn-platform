domain_name  = "lab.iigtn.com"
github_owner = "iigtn"
# github_repo, github_allowed_branches はデフォルト ("iigtn-platform", ["main"])

# ── SES 設定 ──────────────────────────────────────────────────
# 送信元 / 送信先 ともに contact@iigtn.com を使う (sandbox なので両方 verify 済必須)
# 本番化したい場合: SES Production Access 申請
ses_from = "contact@iigtn.com"
ses_to   = "contact@iigtn.com"

# ── Observability 通知先 (任意。CloudWatch Alarm + Budgets) ─
# alarm_email = "contact@iigtn.com"
