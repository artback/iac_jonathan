# n8n workflows (IaC copies)

Source-of-truth JSON for the n8n workflows on the Pi. Secrets never live here —
nodes reference credentials **by name**; the credentials themselves are created
in n8n (UI or API) and live in n8n's encrypted store:

- `iCloud IMAP` — imap.mail.me.com:993 SSL, jonathan_artback@icloud.com + app-specific password
- `Homelab Postgres` — 100.116.81.88:5432, db n8n_data (root password in vars/backup.hcl)
- `Telegram Printbot` — the printbot token (send-only here; no polling conflict)

## Email Triage (`email-triage.json`)

IMAP trigger (leaves mail unread) → dedupe against `email_triage` table →
llama3.2:3b on the Pi's Ollama classifies (category/importance/summary, JSON
mode) → log to postgres → urgent/high-importance → immediate Telegram ping.
Mail is never moved, deleted, or marked — triage is notification-only by design.

## Email Digest (`email-digest.json`)

Daily 08:00: last 24h of classified mail from postgres → grouped digest →
Telegram. Empty day = no message.
