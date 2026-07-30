#!/bin/bash
# Build upstream umbrelOS generic arm64 rootfs tarball.
# Runs on the CI/host with Docker available (not nested).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBREL_REF="${UMBREL_REF:-1.7.4}"
UMBREL_SRC="${UMBREL_SRC:-$REPO_ROOT/work/umbrel-src}"
OUT_TAR="${1:-$REPO_ROOT/work/umbrelos-root-arm64.tar}"

mkdir -p "$(dirname "$OUT_TAR")" "$REPO_ROOT/work"

if [ ! -d "$UMBREL_SRC/.git" ]; then
    echo "=== Cloning getumbrel/umbrel @ $UMBREL_REF ==="
    rm -rf "$UMBREL_SRC"
    git clone --depth 1 --branch "$UMBREL_REF" \
        https://github.com/getumbrel/umbrel.git "$UMBREL_SRC"
else
    echo "=== Using existing umbrel source at $UMBREL_SRC ==="
fi

echo "=== Building umbrelOS arm64 Docker image ==="
# Context must be the umbrel repo root so packages/ui and packages/umbreld are available.
docker build \
    --platform linux/arm64 \
    --build-arg BASE_VARIANT= \
    -f "$UMBREL_SRC/packages/os/umbrelos.Dockerfile" \
    -t umbrelos-arm64 \
    "$UMBREL_SRC"

echo "=== Exporting root filesystem ==="
cid="$(docker create --platform linux/arm64 umbrelos-arm64 /bin/true)"
docker export --output "$OUT_TAR" "$cid"
docker rm "$cid" >/dev/null

echo "=== Rootfs tarball ready: $OUT_TAR ($(du -h "$OUT_TAR" | awk '{print $1}')) ==="
