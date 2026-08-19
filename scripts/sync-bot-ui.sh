#!/bin/sh
# Copy the canonical Telegram UI kit into every bot pack that opts in.
#
# A pack opts in by containing these two marker lines inside its embedded
# Python; everything between them is replaced:
#
#   # --- BEGIN SHARED UI (managed by scripts/sync-bot-ui.sh) ---
#   # --- END SHARED UI ---
#
# nomad-pack has no cross-pack include, so this is the substitute for one.
# Run it after editing packs/_shared/telegram_ui.py, then redeploy the packs it
# reports as changed.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KIT="$ROOT/packs/_shared/telegram_ui.py"
[ -f "$KIT" ] || { echo "missing $KIT" >&2; exit 1; }

python3 - "$ROOT" "$KIT" <<'PY'
import sys, glob, os, re
root, kitpath = sys.argv[1], sys.argv[2]
# Drop the file header: it documents the file, not the injected region.
kit = kitpath and open(kitpath).read()
kit = kit.split('\n\nOK, WARN, BAD', 1)
kit = ("OK, WARN, BAD" + kit[1]) if len(kit) > 1 else kit[0]
BEGIN = "# --- BEGIN SHARED UI (managed by scripts/sync-bot-ui.sh) ---"
END   = "# --- END SHARED UI ---"
changed = skipped = 0
for tpl in sorted(glob.glob(os.path.join(root, "packs/*/templates/*.nomad.tpl"))):
    src = open(tpl).read()
    if BEGIN not in src or END not in src:
        continue
    pre, rest = src.split(BEGIN, 1)
    _, post = rest.split(END, 1)
    new = pre + BEGIN + "\n" + kit.rstrip() + "\n" + END + post
    name = os.path.basename(os.path.dirname(os.path.dirname(tpl)))
    if new != src:
        open(tpl, "w").write(new); changed += 1
        print("  updated  " + name)
    else:
        skipped += 1
        print("  current  " + name)
if changed == 0 and skipped == 0:
    print("  no packs opt in yet (add the marker comments to a bot template)")
PY
