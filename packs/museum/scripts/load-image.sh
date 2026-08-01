#!/usr/bin/env bash
# Builds the museum image and loads it straight into the Pi's docker daemon.
#
# The registry-free route, and the one currently in use: the gh token on this
# Mac has no write:packages scope, so GHCR is not available without refreshing
# it. This Mac and the Pi are both arm64, so the image built here runs there
# unchanged — no cross-compilation, no emulation, no registry.
#
# Nomad only pulls an image when it is absent from the local daemon, so a job
# referring to "museum:0.1.0" with no registry prefix uses what this loaded.
#
#   ./load-image.sh 0.1.0 [path-to-museum-checkout]
#
# The tradeoff against a registry: nothing else can fetch this image. A second
# client added to the cluster would not be able to run the job until this had
# been run against it too. scripts/publish-image.sh is the registry route.
set -euo pipefail

TAG="${1:?usage: load-image.sh TAG [repo-path]}"
REPO="${2:-$HOME/Code/museum}"
PI="${PI:-dwight@100.116.81.88}"
IMAGE="museum:$TAG"

if [ ! -f "$REPO/Dockerfile" ]; then
    echo "No Dockerfile at $REPO — pass the museum checkout as the second argument." >&2
    exit 1
fi

echo "Building $IMAGE from $REPO"
docker build --platform linux/arm64 -t "$IMAGE" "$REPO"

# Confirmed rather than assumed: a Mac that is not Apple silicon would have
# built amd64 here, and the failure would otherwise surface as an opaque
# "exec format error" inside Nomad half an hour later.
ARCH="$(docker image inspect "$IMAGE" --format '{{.Architecture}}')"
if [ "$ARCH" != "arm64" ]; then
    echo "Built $ARCH, but the Pi needs arm64. Use scripts/publish-image.sh with buildx instead." >&2
    exit 1
fi

echo "Shipping $IMAGE to $PI"
docker save "$IMAGE" | gzip | ssh "$PI" 'gunzip | docker load'

echo
echo "On the Pi:"
ssh "$PI" "docker image inspect $IMAGE --format '{{.RepoTags}} {{.Architecture}}/{{.Os}}'"

cat <<EOT

Set this in vars/museum-kalmar.pkrvars.hcl if it is not already:

  image = "$IMAGE"

then redeploy:

  nomad-pack run packs/museum -f vars/museum-kalmar.pkrvars.hcl
EOT
