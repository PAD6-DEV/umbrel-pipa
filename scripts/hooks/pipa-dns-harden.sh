#!/bin/bash
# Harden DNS for pipa: no RTC + first-boot WiFi races break App Store / Docker.
# Logs showed: getaddrinfo EAI_AGAIN github.com and 127.0.0.53 "server misbehaving"
# while wlan0 already had a DHCP lease — DNSSEC/clock + single upstream DNS.
set -eux

mkdir -p /etc/systemd/resolved.conf.d /etc/NetworkManager/conf.d \
    /etc/systemd/system/umbrel.service.d /usr/local/sbin

# DNSSEC fails hard when the clock is wrong (no battery RTC on Pad 6).
# Also provide multi-provider FallbackDNS so one blocked upstream isn't fatal.
cat > /etc/systemd/resolved.conf.d/99-pipa.conf <<'EOF'
[Resolve]
DNSSEC=no
DNSOverTLS=no
# Prefer IPv4 public resolvers; some networks break IPv6 to Cloudflare/Google.
DNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
FallbackDNS=9.9.9.9 149.112.112.112
EOF

# Upstream umbrel forces Cloudflare only (helps bad router DNS, but fails when
# 1.1.1.1 is blocked/unreliable). Keep the file name umbrel-dns-sync expects.
cat > /etc/NetworkManager/conf.d/10-cloudflaredns.conf <<'EOF'
# pipa: multi-resolver DNS (Cloudflare + Google + Quad9), IPv4-only.
# Original umbrel comment: some routers provide unreliable DNS that breaks
# Docker pulls; exclusive Cloudflare also fails on some regional networks.
[global-dns-domain-*]
servers=1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9
EOF

# Wait until DNS works before umbreld clones umbrel-apps / pulls images.
cat > /usr/local/sbin/pipa-wait-dns <<'EOF'
#!/bin/bash
set -u

deadline=$((SECONDS + 120))
echo "pipa-wait-dns: waiting for DNS (up to 120s)..."

while (( SECONDS < deadline )); do
    if getent hosts github.com >/dev/null 2>&1; then
        echo "pipa-wait-dns: github.com resolved"
        exit 0
    fi
    if getent hosts registry-1.docker.io >/dev/null 2>&1; then
        echo "pipa-wait-dns: registry-1.docker.io resolved"
        exit 0
    fi
    # Direct query bypasses a wedged stub cache after large clock jumps.
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches >/dev/null 2>&1 || true
        if resolvectl query github.com >/dev/null 2>&1; then
            echo "pipa-wait-dns: resolvectl query ok"
            exit 0
        fi
    fi
    sleep 2
done

echo "pipa-wait-dns: DNS still unavailable; starting umbreld anyway" >&2
exit 0
EOF
chmod 755 /usr/local/sbin/pipa-wait-dns

cat > /etc/systemd/system/umbrel.service.d/99-pipa-wait-dns.conf <<'EOF'
[Unit]
# network-online is not enough: we need working DNS for app-store git clone.
Wants=network-online.target NetworkManager-wait-online.service systemd-timesyncd.service
After=network-online.target NetworkManager-wait-online.service systemd-resolved.service systemd-timesyncd.service docker.service

[Service]
ExecStartPre=/usr/local/sbin/pipa-wait-dns
EOF

systemctl enable systemd-resolved systemd-timesyncd NetworkManager-wait-online.service || true
systemctl daemon-reload || true
