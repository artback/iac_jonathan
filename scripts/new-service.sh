#!/usr/bin/env bash
# Scaffold a vars file for the generic pack.
# Usage: new-service.sh <name> <image> <port> [url_prefix]
set -euo pipefail

NAME="${1:?usage: new-service.sh <name> <image> <port> [url_prefix]}"
IMAGE="${2:?missing image}"
PORT="${3:?missing port}"
PREFIX="${4:-/$NAME}"

FILE="vars/$NAME.hcl"

if [ -e "$FILE" ]; then
  echo "error: $FILE already exists" >&2
  exit 1
fi

mkdir -p vars

cat > "$FILE" <<EOF
# Service: $NAME (deployed via packs/generic)
# Reference for all options: packs/generic/README.md
# NOTE: vars/ is gitignored — safe for secrets, but keep a backup.

job_name = "$NAME"
image    = "$IMAGE"
port     = $PORT

# Fabio route: https://raspberrypi.tailb9a8bb.ts.net$PREFIX
url_prefix        = "$PREFIX"
strip_prefix      = true
health_check_path = "/"

count  = 1
cpu    = 200
memory = 256

env_vars = {
  TZ = "Europe/Stockholm"
}

# volumes    = ["/opt/$NAME:/data"]   # host path must exist on the node
# static_port = 0                     # set for apps that need a fixed host port
EOF

echo "Created $FILE"
echo
echo "Next steps:"
echo "  task plan   SERVICE=$NAME   # dry run"
echo "  task deploy SERVICE=$NAME   # deploy"
