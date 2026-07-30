#!/bin/bash
set -euo pipefail

fail() { echo "HW validate FAIL: $*" >&2; exit 1; }
ok() { echo "HW validate OK: $*"; }

# Kernel / boot
ls /boot/Image* >/dev/null 2>&1 || ls /boot/vmlinuz-* >/dev/null 2>&1 || fail "kernel image missing"
[ -d /boot/dtbs/qcom ] || fail "DTB directory missing"
ok "kernel"

# Firmware
[ -d /usr/lib/firmware/qcom/sm8250/xiaomi/pipa ] \
    || [ -d /lib/firmware/qcom/sm8250/xiaomi/pipa ] \
    || fail "pipa qcom firmware missing"
ok "firmware"

# Networking essentials for umbrel.local
command -v NetworkManager >/dev/null 2>&1 || fail "NetworkManager missing"
command -v avahi-daemon >/dev/null 2>&1 || fail "avahi-daemon missing"
ok "network"

# umbrelOS / umbreld presence (paths vary by upstream version)
if [ -x /usr/bin/umbreld ] || [ -x /usr/local/bin/umbreld ] || command -v umbreld >/dev/null 2>&1; then
    ok "umbreld"
elif systemctl list-unit-files 2>/dev/null | grep -qi umbrel; then
    ok "umbrel units"
else
    echo "HW validate WARN: umbreld binary not found in PATH (may live under /umbrel)" >&2
    ls -la /umbrel 2>/dev/null | head -20 || true
fi

if mountpoint -q /boot/efi 2>/dev/null || [ -d /boot/efi/EFI ]; then
    [ -f /boot/efi/EFI/ubuntu/grubaa64.efi ] || [ -f /boot/efi/EFI/BOOT/grubaa64.efi ] \
        || fail "ESP missing grubaa64.efi"
    ok "esp grubaa64"
fi

echo "Hardware validation passed."
