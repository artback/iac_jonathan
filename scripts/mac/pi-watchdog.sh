#!/bin/sh
# Off-Pi dead-man's switch for the homelab.
#
# The watchdog on the Pi cannot report the Pi being down -- a power cut, a
# panic or a dead tailscale0 all look like silence. This runs on the Mac, so
# it sees that silence from the outside.
#
# Its honest limit: a laptop sleeps. It catches an outage while the Mac is
# awake, which is when you are around to act on it, and misses one at 4am.
# healthchecks.io remains the always-on answer; this is the part that needs
# no third-party account.
#
# Managed from the iac_jonathan repo (scripts/pi-watchdog.sh). 
set -u

ENV_FILE="${PI_WATCHDOG_ENV:-$HOME/.config/homelab/alert.env}"
STATE="${PI_WATCHDOG_STATE:-$HOME/.config/homelab/pi-watchdog.state}"
PI="${PI_ADDR:-100.116.81.88}"
TS="${TAILSCALE_BIN:-/usr/local/bin/tailscale}"

[ -r "$ENV_FILE" ] || exit 0
# shellcheck source=/dev/null
. "$ENV_FILE"
[ -n "${TELEGRAM_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0

# A watcher that cannot tell "the Pi is down" from "I am offline" will cry wolf
# on every flight and every cafe wifi, and a false alarm teaches you to ignore
# the real one. Both gates below must pass before absence means anything.
"$TS" status >/dev/null 2>&1 || exit 0          # Tailscale itself is not up here
curl -sf -m 8 -o /dev/null https://api.telegram.org || exit 0   # no usable uplink

# Two independent signals, because either alone lies. A tailnet ping can fail
# on a NAT hiccup while the host is fine; a TCP connect can fail while Nomad
# restarts. Only both failing is treated as "gone".
reachable=no
if "$TS" ping -c 1 --timeout 5s "$PI" >/dev/null 2>&1; then
	reachable=yes
elif nc -z -G 5 "$PI" 4646 >/dev/null 2>&1; then
	reachable=yes
fi

previous=""
[ -r "$STATE" ] && previous=$(cat "$STATE")
[ "$reachable" = "yes" ] && current=up || current=down

# Report transitions only: a lasting outage is one message, not one every ten
# minutes until you mute the bot.
if [ "$current" != "$previous" ]; then
	if [ "$current" = "down" ]; then
		text="🔴 <b>Pi unreachable</b> from $(scutil --get ComputerName 2>/dev/null || hostname)
Tailscale is up here and the internet is reachable, but ${PI} answers neither a tailnet ping nor TCP 4646.
<i>Power, kernel or tailscaled — the Pi cannot tell you this itself.</i>"
	else
		# Say nothing on first-ever run when all is well: no news is not news.
		[ -n "$previous" ] || { printf '%s' "$current" >"$STATE"; exit 0; }
		text="🟢 <b>Pi reachable again</b> — back on the tailnet."
	fi
	curl -sf -m 15 -o /dev/null \
		-X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
		--data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
		--data-urlencode "text=${text}" \
		--data-urlencode "parse_mode=HTML" || exit 1
	printf '%s' "$current" >"$STATE"
fi
