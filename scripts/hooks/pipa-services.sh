#!/bin/bash
set -x

# Headless umbrelOS services for Xiaomi Pad 6
mkdir -p /etc/cloud
touch /etc/cloud/cloud-init.disabled
systemctl disable --now cloud-init.service cloud-init-local.service \
    cloud-config.service cloud-final.service 2>/dev/null || true
systemctl mask cloud-init.service cloud-init-local.service \
    cloud-config.service cloud-final.service 2>/dev/null || true

systemctl set-default multi-user.target || true

systemctl enable ssh.service || systemctl enable sshd.service || true
systemctl enable NetworkManager iwd bluetooth systemd-resolved systemd-timesyncd || true
systemctl enable avahi-daemon || true

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-iwd.conf <<'EOF'
[device]
wifi.backend=iwd
EOF

# Allow mDNS for umbrel.local
if [ -f /etc/nsswitch.conf ]; then
    sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf || true
fi

systemctl enable bootmac-bluetooth || true
systemctl enable swclock-offset-boot.service swclock-offset-shutdown.service || true
systemctl enable pd-mapper rmtfs tqftpserv || true
systemctl enable \
    pipa-sensors-persist \
    hexagonrpcd-sdsp \
    hexagonrpcd-adsp-sensorspd \
    iio-sensor-proxy \
    pipa-audio-init || true
systemctl mask hexagonrpcd-adsp-rootpd.service || true

# USB gadget ethernet for first-boot access without WiFi
systemctl enable usb-network.service || true
