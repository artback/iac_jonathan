#!/usr/bin/env bash
# Builds the museum image for the Pi and pushes it to GHCR.
#
# The client is a Raspberry Pi, so the image must be linux/arm64. A plain
# "docker build" on a Mac produces whatever the Mac is — on Apple silicon that
# happens to be arm64 too, which is exactly the sort of accident that works
# until you build somewhere else. The platform is named explicitly here.
#
#   ./publish-image.sh 0.1.0 [path-to-museum-checkout]
#
# Requires a GHCR login:
#   echo "$GITHUB_TOKEN" | docker login ghcr.io -u artback --password-stdin
set -euo pipefail

TAG="${1:?usage: publish-image.sh TAG [repo-path]}"
REPO="${2:-$HOME/Code/museum}"
IMAGE="${IMAGE_NAME:-ghcr.io/artback/museum}"

if [ ! -f "$REPO/Dockerfile" ]; then
    echo "No Dockerfile at $REPO — pass the museum checkout as the second argument." >&2
    exit 1
fi

# A named builder, because the default "docker" driver cannot cross-build or
# push a multi-platform image.
if ! docker buildx inspect museum-builder >/dev/null 2>&1; then
    echo "Creating buildx builder 'museum-builder'..."
    docker buildx create --name museum-builder --driver docker-container --bootstrap
fi

echo "Building $IMAGE:$TAG for linux/arm64 from $REPO"
docker buildx build \
    --builder museum-builder \
    --platform linux/arm64 \
    --tag "$IMAGE:$TAG" \
    --push \
    "$REPO"

echo
echo "Pushed $IMAGE:$TAG"
echo "Verifying the manifest really is arm64:"
docker manifest inspect "$IMAGE:$TAG" | grep -A2 '"platform"' | head -20

cat <<EOT

Next: set this tag in vars/museum-kalmar.pkrvars.hcl

  image = "$IMAGE:$TAG"

If the Pi cannot pull it, the package is private — make it public at
https://github.com/users/artback/packages/container/museum/settings
or give the client a pull credential.
EOT
