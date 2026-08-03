# Mailbot Nomad Pack

Local-first email triage — the custom-Python successor to the n8n workflow lost
in the June postgres incident, now covering **all** mail.

## How it works

Every 2 minutes the bot opens the IMAP inbox **read-only** (`SELECT` readonly:
the mailbox cannot be modified — no moves, no deletes, not even read-flags) and
fetches anything newer than the last seen UID. Each new email is classified by
`llama3.2:3b` on the Pi's Ollama (category, importance, one-line summary — the
mail never leaves the tailnet). Urgent or high-importance mail pings Telegram
immediately; everything lands in the 08:00 digest, grouped by category.

- First run baselines at the current newest message — no backlog storm.
- State (last UID + triage log) is sqlite in the `mailbot_data` volume,
  which is part of the nightly app-state backup.
- The Telegram token is send-only here — shared with printbot safely
  (only one process may *poll* a token; any number may send).

## Secrets (gitignored `vars/mailbot.hcl`)

```hcl
imap_password  = "..."  # iCloud app-specific password (appleid.apple.com)
telegram_token = "..."  # same token as printbot
```

Deploy: `nomad-pack run packs/mailbot -f vars/mailbot.hcl`

## Tuning

Categories/prompt live in the template. If classification quality disappoints,
try a bigger model (`model` var) — the Pi has RAM headroom. Digest hour via
`digest_hour` (default 08:00 local).
