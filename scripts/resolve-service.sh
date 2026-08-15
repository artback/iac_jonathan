#!/usr/bin/env bash
# Resolve a service name to a pack directory and vars file.
# Prints shell assignments for eval: PACK=<pack> VAR_FLAG='-f <varsfile>'
#
# Resolution rules:
#   pack: explicit $2 > packs/<service> if it exists > generic
#   vars: vars/<service>.hcl > vars/<service>-kalmar.pkrvars.hcl > none
set -euo pipefail

SERVICE="${1:?usage: resolve-service.sh <service> [pack]}"
PACK="${2:-}"

if [ -z "$PACK" ]; then
  if [ -d "packs/$SERVICE" ]; then
    PACK="$SERVICE"
  else
    PACK="generic"
  fi
fi

if [ ! -d "packs/$PACK" ]; then
  echo "echo 'error: pack packs/$PACK does not exist' >&2; exit 1"
  exit 0
fi

VAR_FLAG=""
for f in "vars/$SERVICE.hcl" "vars/$SERVICE-kalmar.pkrvars.hcl"; do
  if [ -f "$f" ]; then
    VAR_FLAG="-f $f"
    break
  fi
done

if [ -z "$VAR_FLAG" ] && [ "$PACK" = "generic" ]; then
  echo "echo 'error: generic pack needs a vars file — expected vars/$SERVICE.hcl (create one with: task new:service NAME=$SERVICE IMAGE=... PORT=...)' >&2; exit 1"
  exit 0
fi

echo "PACK='$PACK' VAR_FLAG='$VAR_FLAG'"
