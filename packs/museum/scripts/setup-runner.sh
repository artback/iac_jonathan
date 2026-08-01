#!/usr/bin/env bash
# Prepares the Pi to act as the GitHub Actions runner that deploys museum.
#
# Run this from the Mac; it provisions the Pi over SSH. It is idempotent —
# re-running it updates nomad-pack and the IaC checkout and leaves everything
# else alone.
#
# What it puts on the Pi:
#   /opt/iac_jonathan                        clone of the IaC repository
#   /opt/museum/museum-kalmar.pkrvars.hcl    the vars file, copied from here
#   /opt/museum/certs/                       the Nomad mTLS client certificates
#   nomad-pack                               installed to /usr/local/bin
#
# The vars file and the certificates are copied rather than committed: the vars
# file holds the database and MinIO passwords and is gitignored, and the certs
# are what authenticate to the cluster. Neither belongs in a repository or in
# GitHub's secret store when the runner is already inside the network.
#
# Registering the runner with GitHub needs a token that only you can get, so
# that last step is printed rather than performed.
#
#   ./setup-runner.sh
set -euo pipefail

PI="${PI:-dwight@100.116.81.88}"
IAC_REPO="${IAC_REPO:-https://github.com/artback/iac_jonathan.git}"
IAC_DIR="${IAC_DIR:-/opt/iac_jonathan}"
MUSEUM_DIR="${MUSEUM_DIR:-/opt/museum}"
PACK_VERSION="${PACK_VERSION:-0.1.2}"

# Where the pieces live on this Mac.
HERE="$(cd "$(dirname "$0")/../../.." && pwd)"
VARS_SRC="${VARS_SRC:-$HERE/vars/museum-kalmar.pkrvars.hcl}"
CERT_SRC="${CERT_SRC:-$HOME/.config/homelab/certs}"

[ -r "$VARS_SRC" ] || { echo "No vars file at $VARS_SRC" >&2; exit 1; }
[ -d "$CERT_SRC" ] || { echo "No certificate directory at $CERT_SRC" >&2; exit 1; }

echo "=== Creating directories on the Pi ==="
ssh "$PI" "sudo mkdir -p '$MUSEUM_DIR/certs' '$IAC_DIR' &&
           sudo chown -R \$(id -u):\$(id -g) '$MUSEUM_DIR' '$IAC_DIR'"

echo "=== Copying the vars file and certificates ==="
scp -q "$VARS_SRC" "$PI:$MUSEUM_DIR/museum-kalmar.pkrvars.hcl"
scp -q "$CERT_SRC/nomad-ca.pem" "$CERT_SRC/nomad-cli.pem" "$CERT_SRC/nomad-cli-key.pem" \
    "$PI:$MUSEUM_DIR/certs/"
# The key is a credential for the whole cluster; it should not be world
# readable just because /opt is.
ssh "$PI" "chmod 700 '$MUSEUM_DIR/certs' && chmod 600 '$MUSEUM_DIR/certs/'*.pem &&
           chmod 600 '$MUSEUM_DIR/museum-kalmar.pkrvars.hcl'"

echo "=== Cloning or updating the IaC repository ==="
ssh "$PI" "if [ -d '$IAC_DIR/.git' ]; then
             git -C '$IAC_DIR' fetch --quiet origin main &&
             git -C '$IAC_DIR' reset --hard --quiet origin/main
           else
             git clone --quiet '$IAC_REPO' '$IAC_DIR'
           fi
           echo \"iac at \$(git -C '$IAC_DIR' rev-parse --short HEAD)\""

echo "=== Installing nomad-pack ==="
ssh "$PI" "set -eu
    if command -v nomad-pack >/dev/null && nomad-pack --version 2>&1 | grep -q '$PACK_VERSION'; then
        echo 'nomad-pack $PACK_VERSION already installed'
    else
        TMP=\$(mktemp -d)
        cd \"\$TMP\"
        curl -fsSL -o pack.zip \
            'https://releases.hashicorp.com/nomad-pack/$PACK_VERSION/nomad-pack_${PACK_VERSION}_linux_arm64.zip'
        unzip -o -q pack.zip
        sudo install -m 0755 nomad-pack /usr/local/bin/nomad-pack
        cd / && rm -rf \"\$TMP\"
        echo \"installed \$(nomad-pack --version 2>&1 | head -1)\"
    fi"

cat <<EOT

=== Done, except for registering the runner ===

Registering needs a token only you can generate. On the Pi:

  # Get a fresh token from:
  #   https://github.com/artback/museumscraper/settings/actions/runners/new
  mkdir -p ~/actions-runner && cd ~/actions-runner
  curl -fsSL -o runner.tar.gz \\
    https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-arm64-2.319.1.tar.gz
  tar xzf runner.tar.gz
  ./config.sh --url https://github.com/artback/museumscraper \\
              --token <TOKEN> --labels self-hosted,linux,ARM64 --unattended
  sudo ./svc.sh install && sudo ./svc.sh start

The runner's user must be able to run docker without sudo:

  sudo usermod -aG docker \$USER    # then log out and back in

After that, a push to main builds the image on the Pi and deploys it. The
workflow is .github/workflows/deploy.yml in the museum repository.
EOT
