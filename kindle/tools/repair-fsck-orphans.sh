#!/bin/sh
# Restore files that FAT32's fsck orphaned into FSCK####.REN.
#
# When /mnt/us is corrupted, fsck.vfat finds clusters of intact data whose
# directory entry was destroyed. It cannot recover the name -- the name lived
# in that entry -- so it writes the data out as FSCK0000.REN. The file is
# perfectly good; only its label is gone. KOReader then dies claiming a module
# does not exist while the module sits beside it, anonymous.
#
# This restores names by asking the code what it is missing, then matching each
# orphan to a missing module by content. Run with the Kindle mounted:
#   sh repair-fsck-orphans.sh /Volumes/Kindle
set -u
ROOT="${1:-/Volumes/Kindle}"
KO="$ROOT/koreader"
[ -d "$KO" ] || { echo "no koreader/ under $ROOT"; exit 1; }

orphans=$(find "$ROOT" -name 'FSCK*.REN' 2>/dev/null | grep -v Spotlight)
[ -n "$orphans" ] || { echo "no orphans found -- nothing to repair"; exit 0; }
echo "orphans found:"; echo "$orphans" | sed 's/^/  /'

# An orphan whose content matches a file that already exists is a leftover
# duplicate from a previous repair, not a loss. Report and skip those.
echo
echo "-- classifying --"
for o in $orphans; do
  d=$(dirname "$o")
  h=$(md5 -q "$o" 2>/dev/null || md5sum "$o" 2>/dev/null | cut -d' ' -f1)
  twin=""
  for f in "$d"/*; do
    case "$f" in *FSCK*) continue;; esac
    [ -f "$f" ] || continue
    fh=$(md5 -q "$f" 2>/dev/null || md5sum "$f" 2>/dev/null | cut -d' ' -f1)
    [ "$fh" = "$h" ] && { twin="$f"; break; }
  done
  if [ -n "$twin" ]; then
    echo "  DUPLICATE  ${o#$ROOT/}  (same as $(basename "$twin")) -- safe to delete"
  else
    # A lua module names itself: its own requires and ids identify it. Show the
    # first require and any id field so the operator can confirm the match.
    echo "  UNIQUE     ${o#$ROOT/}"
    grep -m1 -oE 'id *= *"[a-z_]+"' "$o" 2>/dev/null | sed 's/^/               /'
    grep -m1 -oE 'require\("[^"]+"\)' "$o" 2>/dev/null | sed 's/^/               /'
  fi
done

echo
echo "-- modules required but absent (these are what the orphans should be) --"
cd "$KO" || exit 1
grep -rhoE 'require\("[^"]+"\)' plugins frontend 2>/dev/null \
  | sed 's/require("//;s/")//' | sort -u | while read -r m; do
      case "$m" in ffi/*|socket*|ssl*|rapidjson|json) continue;; esac
      [ -f "$m.lua" ] || [ -f "frontend/$m.lua" ] || [ -f "common/$m.lua" ] || echo "  MISSING: $m"
    done

echo
echo "Program files are better restored by re-extracting the KOReader release"
echo "zip over the top -- it is authoritative and does not touch settings or"
echo "third-party plugins. Use this for plugin files the zip cannot supply."
