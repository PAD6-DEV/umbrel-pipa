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

# WiFi (ath11k / QCA6390)
[ -f /lib/firmware/ath11k/QCA6390/hw2.0/amss.bin ] \
    || [ -f /usr/lib/firmware/ath11k/QCA6390/hw2.0/amss.bin ] \
    || fail "ath11k QCA6390 amss.bin missing (install firmware-atheros)"
[ -f /lib/firmware/ath11k/QCA6390/hw2.0/board-2.bin ] \
    || [ -f /usr/lib/firmware/ath11k/QCA6390/hw2.0/board-2.bin ] \
    || fail "ath11k QCA6390 board-2.bin missing"
ok "wifi-firmware"

# Networking essentials for umbrel.local
command -v NetworkManager >/dev/null 2>&1 || fail "NetworkManager missing"
command -v avahi-daemon >/dev/null 2>&1 || fail "avahi-daemon missing"
ok "network"

# DNS harden (App Store / Docker pulls need working resolver on first boot)
[ -f /etc/systemd/resolved.conf.d/99-pipa.conf ] || fail "pipa resolved drop-in missing"
[ -x /usr/local/sbin/pipa-wait-dns ] || fail "pipa-wait-dns missing"
[ -f /etc/systemd/system/umbrel.service.d/99-pipa-wait-dns.conf ] || fail "umbrel wait-dns drop-in missing"
grep -q '8.8.8.8' /etc/NetworkManager/conf.d/10-cloudflaredns.conf \
    || fail "multi-resolver DNS config missing"
ok "dns"

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
