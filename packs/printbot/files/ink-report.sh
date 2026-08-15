#!/bin/sh
# Publish printer ink levels as JSON for the dashboard/printbot.
#
# Reads through ipp-usb's local IPP endpoint instead of hplip's hp-levels.
# ipp-usb is what drives scanning (eSCL) and it claims the printer's USB
# channel exclusively, so hp-levels has answered "Channel write error" for
# every run since scanning was enabled on 2026-08-02. Because this script only
# overwrites on a good reading, that failed silently: the bot kept serving the
# 2026-08-02 snapshot as though it were current, for 13 days.
#
# Writes in place (no mv) so bind-mounts keep seeing the same inode.
# Only overwrites on a successful reading — a busy or unplugged device keeps
# the last one, by design (the printer is unplugged for stretches).
OUT=/home/dwight/ink.json
IPP_URL=${IPP_URL:-ipp://localhost:60000/ipp/print}

RAW=$(timeout 45 ipptool -tv "$IPP_URL" get-printer-attributes.test 2>/dev/null)
echo "$RAW" | grep -q "marker-levels" || exit 0

echo "$RAW" | python3 -c '
import sys, re, json, datetime

t = sys.stdin.read()


def attr(name):
    m = re.search(r"^\s*%s \([^)]*\) = (.*)$" % re.escape(name), t, re.M)
    return [v.strip() for v in m.group(1).split(",")] if m else []


names = attr("marker-names")
levels = attr("marker-levels")
# Colours are themselves comma-separated per marker, so they cannot be zipped
# positionally with the rest — the tri-colour cartridge reports three of them.
lows = attr("marker-low-levels")

supplies = []
for i, (n, l) in enumerate(zip(names, levels)):
    pct = int(l)
    low = int(lows[i]) if i < len(lows) else 5
    supplies.append({
        "name": n[:1].upper() + n[1:],
        "percent": pct,
        "health": "Low" if pct <= low else "Good/OK",
    })

if not supplies:
    raise SystemExit(1)

# Black first, matching the order hp-levels used to report.
supplies.sort(key=lambda s: s["name"])

print(json.dumps({
    "updated": datetime.datetime.now().isoformat(timespec="minutes"),
    "supplies": supplies,
}))
' > "$OUT".tmp && cat "$OUT".tmp > "$OUT" && rm "$OUT".tmp && chmod 644 "$OUT"
