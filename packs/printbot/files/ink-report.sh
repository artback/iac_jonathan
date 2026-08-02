#!/bin/sh
# Publish printer ink levels as JSON for the dashboard/printbot.
# Writes in place (no mv) so bind-mounts keep seeing the same inode.
# Only overwrites on a successful reading — a busy USB device keeps the last one.
OUT=/home/dwight/ink.json
RAW=$(timeout 45 hp-levels 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
echo "$RAW" | grep -q "approx" || exit 0
echo "$RAW" | python3 -c '
import sys, re, json, datetime
t = sys.stdin.read()
names = re.findall(r"^(\S.*cartridge.*)$", t, re.M)
levels = re.findall(r"approx\. (\d+)%", t)
healths = re.findall(r"^Health: (.*)$", t, re.M)
supplies = [
    {"name": n.strip(), "percent": int(l), "health": h.strip()}
    for n, l, h in zip(names, levels, healths)
]
print(json.dumps({
    "updated": datetime.datetime.now().isoformat(timespec="minutes"),
    "supplies": supplies,
}))
' > "$OUT".tmp && cat "$OUT".tmp > "$OUT" && rm "$OUT".tmp && chmod 644 "$OUT"
