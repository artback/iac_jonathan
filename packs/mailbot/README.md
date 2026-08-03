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

## What it extracts

Beyond category/importance/summary, tracked categories get a second LLM pass
that pulls structured fields (stored in `extracts`, surfaced in the digest and
`mailstats.json`):

- **orders** → carrier, tracking number, ETA, merchant → "packages in flight"
- **travel** → mode, carrier, number, date, route, booking ref → "upcoming travel"
- **finance** → payee, amount, due date → "due soon"
- **job** (when tracked) → company, role, stage, fit score → Obsidian notes + Top Jobs

Travel bookings and shipped packages also ping immediately.

## Noise handling

`marketing` and `newsletter` never ping and are never itemized — the digest
shows a single "🔇 N ignored" line. Any mail carrying a `List-Unsubscribe`
header is treated as noise unless it classified as urgent/finance/travel/
orders/job, and the header's unsubscribe URL is harvested per sender. **Monday
digests append the 5 noisiest senders with their unsubscribe links** — a
one-tap weekly cleanup list. The bot never unsubscribes on your behalf.

## Cost & CPU

Classification runs on the Pi's own Ollama — **no API, no per-email cost**. The
real budget is CPU: ~27s per LLM call on a Pi 5 (llama3.2:3b).

Two controls keep that sane:

- **Header prefilter** — bulk mail (`List-Unsubscribe`, `List-Id`, `Precedence:
  bulk`) skips the LLM entirely and is filed as marketing/newsletter, *unless*
  the subject looks transactional (order/shipment/flight/invoice/… incl. FR
  terms), which still goes to the model. Typically removes half the inbox from
  the LLM path at zero cost.
- **Burst cap** — `MAX_LLM_PER_CYCLE` (10) per 2-minute poll; a flood is spread
  over cycles instead of pegging the CPU. The UID cursor only advances on
  processed mail, so nothing is skipped.

`mailstats.json` reports `llm_calls` vs `llm_skipped` so the saving is visible.

**RAM:** llama3.2:3b holds ~2.5GB resident while loaded. Ollama's 5-minute
default keep-alive plus 2-minute polling would pin that permanently on a box
running ~20 other services, so every call passes `keep_alive` (default `30s`,
the `keep_alive` var) — measured to release the memory promptly between bursts.

## Commands

The bot long-polls its own token (no conflict with printbot/mediabot) and
answers only the configured `chat_id` — anyone else gets "this mailbox bot is
private".

- `/today` — last 24h grouped by category, noise counted not listed
- `/travel` — upcoming trips · `/packages` — parcels in transit · `/bills` — due soon
- `/noise` — noisiest senders with unsubscribe links
- `/search WORD` — find past mail by subject or summary
- `/stats` — 30-day breakdown incl. how much CPU the header prefilter saved
- `/digest` — send the morning digest right now
