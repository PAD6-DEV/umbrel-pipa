#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo -E "$0" "$@"
fi

export PIPA_PKGS_URL="${PIPA_PKGS_URL:-https://thespider2.github.io/pipa-pkgs/repo/ubuntu/}"
export BUILD_GIT_REV="${BUILD_GIT_REV:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
export UMBREL_REF="${UMBREL_REF:-1.7.4}"

"$REPO_ROOT/scripts/build-umbrel-rootfs.sh"
"$REPO_ROOT/scripts/ci-build.sh"
