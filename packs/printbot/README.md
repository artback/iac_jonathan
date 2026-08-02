# Printbot Nomad Pack

Telegram bot for printing from anywhere — no Tailscale needed on the sending
device, and nothing newly exposed: the bot only makes **outbound long-polling**
calls to api.telegram.org (no webhook, no open port). Send it a PDF, JPEG, PNG
or .txt and it submits the file to CUPS; if the printer is powered off, the job
waits in the CUPS queue (`printer-error-policy=retry-job`) and prints when the
printer comes back.

## Safety model

- Only chat IDs in `allowed_chat_ids` may print; everyone else gets a refusal
  (which includes their ID, so onboarding yourself is easy).
- Bot token lives in gitignored `vars/printbot.hcl`, injected via Nomad
  template env.
- The container has no listening ports and only reaches Telegram + CUPS.

## Setup

1. In Telegram, talk to **@BotFather** → `/newbot` → copy the token.
2. `echo 'telegram_token = "PASTE_TOKEN_HERE"' >> vars/printbot.hcl`
3. Deploy: `nomad-pack run packs/printbot -f vars/printbot.hcl`
4. Message the bot — it replies "Not authorized. Your chat id is `N`".
5. `echo 'allowed_chat_ids = "N"' >> vars/printbot.hcl` and re-run the pack.

## Commands

- send a file/photo — queues it for printing
- `/status` — printer + queue state
- `/ink` — cartridge levels (as last reported by the hpcups driver)
- `/cancel N` — cancel job N
- `/clear` — cancel all waiting jobs (only jobs the bot submitted; SSH-submitted
  jobs belong to another user and are skipped)
- `/help` — command list

## Host prerequisites (already applied to the Pi, 2026-08-02)

- **The ENVY 6000's IPP-over-USB is broken at the firmware level** — via
  `ipp-usb`, jobs are accepted and marked complete but come out blank or
  not at all (while the printer's own info page prints fine). Every
  driverless variant fails the same way. `ipp-usb` is therefore
  **masked**, and the queue uses the classic hplip stack instead:
  `lpadmin -p HP_ENVY_6000 -E -v "hp:/usb/ENVY_6000_series?serial=..." \
    -m drv:///hpcups.drv/hp-envy_6000_series.ppd \
    -o printer-is-shared=true -o printer-error-policy=retry-job`
  (URI from `sudo lpinfo -v`; needs `hplip`. `lpinfo -m` silently lists
  nothing without sudo.)
- `printer-error-policy=retry-job` so an offline printer holds, not stops,
  the queue.
- UFW: 631/tcp on eth0 + tailscale0, 5353/udp on eth0.
- cupsd.conf: `Allow from 100.64.0.0/10` in `<Location />` for tailnet printing.

## Ink levels pipeline

`files/ink-report.sh` is installed on the host at `/usr/local/bin/ink-report.sh`
and run by root cron every 6h (`17 */6 * * *`). It reads `hp-levels` (root-only
USB access), writes `/home/dwight/ink.json`, which the dashboard nginx serves
at `/ink.json` — the bot's `/ink` command and anything else can read it there.
hpcups never reports marker levels to CUPS for this model, hence the sidecar.

## Membership & invites

The repo stays generic: no chat IDs or tokens live here. Bootstrap members come
from gitignored `vars/printbot.hcl` (`allowed_chat_ids`); everyone else joins at
runtime — an existing member runs `/invite` (one-time code, 24h expiry), the
newcomer sends `/join CODE`. Dynamic members persist in the `printbot_data`
docker volume (`/data/members.json`), outside both repo and job spec. Joins are
broadcast to all members; `/members` lists everyone, `/revoke ID` removes
invited members (vars-file members are removed in the vars file).
