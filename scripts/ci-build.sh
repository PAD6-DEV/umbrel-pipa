#!/bin/bash
# CI / Docker entrypoint: expect umbrelos rootfs tar already present OR build it
# when Docker is available on the host socket.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p "$REPO_ROOT/work" "$REPO_ROOT/output"

ROOTFS_TAR="$REPO_ROOT/work/umbrelos-root-arm64.tar"
RAW_IMG="$REPO_ROOT/work/umbrel-pipa.img"

export PIPA_PKGS_URL="${PIPA_PKGS_URL:-https://thespider2.github.io/pipa-pkgs/repo/ubuntu/}"
export BUILD_GIT_REV="${BUILD_GIT_REV:-unknown}"
export UMBREL_REF="${UMBREL_REF:-1.7.4}"

if [ ! -f "$ROOTFS_TAR" ]; then
    if command -v docker >/dev/null 2>&1 && [ -S /var/run/docker.sock ]; then
        echo "=== Building umbrelOS rootfs via Docker socket ==="
        "$REPO_ROOT/scripts/build-umbrel-rootfs.sh" "$ROOTFS_TAR"
    else
        echo "ERROR: $ROOTFS_TAR missing and Docker socket unavailable."
        echo "CI should run scripts/build-umbrel-rootfs.sh on the runner first."
        exit 1
    fi
fi

echo "=== Creating pipa disk image from umbrelOS rootfs ==="
"$REPO_ROOT/scripts/build-disk-image.sh" "$ROOTFS_TAR" "$RAW_IMG"

echo "=== Post-processing flash artifacts ==="
"$REPO_ROOT/scripts/post-process-image.sh" "$RAW_IMG"

echo "=== umbrelOS pipa build complete ==="
ls -lh "$REPO_ROOT/output/"
