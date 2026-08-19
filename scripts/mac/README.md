# Off-Pi dead-man's switch

Everything in `ansible/roles/resilience` runs **on** the Pi, so none of it can
report the Pi being down: a power cut, a kernel panic and a dead `tailscale0`
all look identical from the inside — silence — and silence is indistinguishable
from health. Only something off the machine can tell those apart.

The Pi-side half of this is `HEARTBEAT_URL` in the resilience role: the
watchdog pings outward every run and a far end alerts when the pings stop.
That needs an always-on third party (healthchecks.io or similar) and an
account, so it ships disabled.

This directory is the half that needs no third-party account: the Mac watches
the Pi from outside.

## What it does

`pi-watchdog.sh` runs every 10 minutes under launchd and alerts through the
homelab-bot Telegram token when the Pi stops answering — reporting transitions
only, so a lasting outage is one message rather than six an hour.

Two design points worth keeping:

- **It must not confuse "the Pi is down" with "I am offline."** A watcher that
  cries wolf on every flight and every cafe wifi teaches you to ignore the real
  alarm. Both Tailscale being up locally *and* a reachable uplink are required
  before absence means anything.
- **Two independent reachability signals.** A tailnet ping can fail on a NAT
  hiccup while the host is fine; a TCP connect to 4646 can fail while Nomad
  restarts. Only both failing counts as gone.

## Its honest limit

A laptop sleeps. This catches an outage while the Mac is awake — which is when
you are around to act on it — and misses one that starts at 4am. `RunAtLoad`
means opening the lid surfaces an outage that began overnight, but that is
detection on wake, not detection at the time. For always-on coverage, arm
`resilience_heartbeat_url`.

## Install

```sh
cp pi-watchdog.sh ~/.config/homelab/pi-watchdog.sh
chmod 700 ~/.config/homelab/pi-watchdog.sh
cp com.artback.pi-watchdog.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.artback.pi-watchdog.plist
```

Credentials live in `~/.config/homelab/alert.env` (0600, never in this repo),
copied from the Nomad variable `nomad/jobs/homelab-bot`. Local on purpose: when
the Pi is down, Nomad cannot be queried for the token.

```sh
umask 077
nomad var get -out=json nomad/jobs/homelab-bot | python3 -c \
  'import json,sys; print("TELEGRAM_TOKEN=%s\nTELEGRAM_CHAT_ID=485643205" %
   json.load(sys.stdin)["Items"]["telegram_token"])' > ~/.config/homelab/alert.env
```
