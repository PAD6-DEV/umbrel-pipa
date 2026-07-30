#!/bin/bash
# Create a 3-partition disk image from umbrelOS rootfs tar, inject pipa packages.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS_TAR="${1:-$REPO_ROOT/work/umbrelos-root-arm64.tar}"
OUT_IMG="${2:-$REPO_ROOT/work/umbrel-pipa.img}"
PIPA_PKGS_URL="${PIPA_PKGS_URL:-https://thespider2.github.io/pipa-pkgs/repo/ubuntu/}"
IMAGE_SIZE_GIB="${IMAGE_SIZE_GIB:-16}"

ROOTFS_LABEL="umbrel-pipa"
BOOT_LABEL="boot"
ESP_LABEL="UMBRESP"

if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root"
    exit 1
fi

if [ ! -f "$ROOTFS_TAR" ]; then
    echo "Missing umbrelOS rootfs tar: $ROOTFS_TAR"
    echo "Run scripts/build-umbrel-rootfs.sh first."
    exit 1
fi

read_pkg_list() {
    grep -vE '^\s*(#|$)' "$1" | tr '\n' ' '
}

PIPA_PKGS="$(read_pkg_list "$REPO_ROOT/manifests/pipa-common.txt")"

WORK="$(mktemp -d)"
ROOT="$WORK/root"
LOOP=""
mkdir -p "$ROOT" "$(dirname "$OUT_IMG")"

cleanup() {
    umount -R "$ROOT" 2>/dev/null || true
    if [ -n "${LOOP}" ] && [ -b "$LOOP" ]; then
        losetup -d "$LOOP" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== Creating ${IMAGE_SIZE_GIB}GiB disk image ==="
rm -f "$OUT_IMG"
truncate -s "${IMAGE_SIZE_GIB}G" "$OUT_IMG"

sgdisk -Z "$OUT_IMG" >/dev/null
sgdisk -n 1:0:+512M -t 1:EF00 -c 1:ESP "$OUT_IMG" >/dev/null
sgdisk -n 2:0:+1G -t 2:8300 -c 2:boot "$OUT_IMG" >/dev/null
sgdisk -n 3:0:0 -t 3:8300 -c 3:root "$OUT_IMG" >/dev/null

LOOP=$(losetup --find --show --partscan "$OUT_IMG")
partprobe "$LOOP" 2>/dev/null || true
for _ in $(seq 1 30); do
    [ -b "${LOOP}p1" ] && [ -b "${LOOP}p2" ] && [ -b "${LOOP}p3" ] && break
    sleep 0.2
done
if [ ! -b "${LOOP}p1" ] || [ ! -b "${LOOP}p3" ]; then
    echo "ERROR: loop partitions not found for $LOOP"
    ls -l "${LOOP}"* || true
    exit 1
fi

ESP_PART="${LOOP}p1"
BOOT_PART="${LOOP}p2"
ROOT_PART="${LOOP}p3"

mkfs.vfat -F 32 -n "$ESP_LABEL" "$ESP_PART"
MKE2FS_DEVICE_PHYS_SECTSIZE=4096 MKE2FS_DEVICE_SECTSIZE=4096 \
    mkfs.ext4 -F -L "$BOOT_LABEL" "$BOOT_PART"
MKE2FS_DEVICE_PHYS_SECTSIZE=4096 MKE2FS_DEVICE_SECTSIZE=4096 \
    mkfs.ext4 -F -L "$ROOTFS_LABEL" "$ROOT_PART"

mount "$ROOT_PART" "$ROOT"
mkdir -p "$ROOT/boot"
mount "$BOOT_PART" "$ROOT/boot"
mkdir -p "$ROOT/boot/efi"
mount "$ESP_PART" "$ROOT/boot/efi"

echo "=== Extracting umbrelOS rootfs ==="
tar -xf "$ROOTFS_TAR" -C "$ROOT"

# Docker export includes /proc /sys /dev entries; clear and remount for chroot.
rm -rf "$ROOT/proc" "$ROOT/sys" "$ROOT/dev" "$ROOT/run"
mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev" "$ROOT/run" "$ROOT/tmp"

# Critical: docker export leaves /.dockerenv, which makes systemd think the
# real device is a container and skips units like systemd-timesyncd
# (ConditionVirtualization=!container).
rm -f "$ROOT/.dockerenv" "$ROOT/run/systemd/container"
rm -f "$ROOT/etc/mtab"

mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount -t tmpfs tmpfs "$ROOT/run"

# DNS for apt inside chroot
if [ -f /etc/resolv.conf ]; then
    cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
fi

mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/preferences.d" "$ROOT/etc/apt/apt.conf.d"
cat > "$ROOT/etc/apt/apt.conf.d/99-no-languages" <<'EOF'
Acquire::Languages "none";
EOF

cat > "$ROOT/etc/apt/sources.list.d/pipa-pkgs.list" <<EOF
deb [trusted=yes] $PIPA_PKGS_URL ./
EOF

cat > "$ROOT/etc/apt/preferences.d/pipa-kernel.pref" <<'EOF'
Package: linux-image-arm64 linux-image-generic linux-headers-arm64
Pin: release *
Pin-Priority: -1

Package: linux-image-pipa linux-modules-pipa linux-headers-pipa
Pin: release *
Pin-Priority: 1001
EOF

echo "=== Updating apt and installing pipa packages ==="
chroot "$ROOT" apt-get update

pkg_available() {
    chroot "$ROOT" apt-cache show "$1" >/dev/null 2>&1
}

# pipa-metapkg Depends on Ubuntu's linux-firmware; Debian ships firmware-linux.
# Install a tiny Provides shim so the Ubuntu-oriented dependency resolves.
install_linux_firmware_compat() {
    local stage="$ROOT/tmp/linux-firmware-compat"
    mkdir -p "$stage/DEBIAN"
    cat > "$stage/DEBIAN/control" <<'EOF'
Package: pipa-linux-firmware-compat
Version: 1.0
Section: misc
Priority: optional
Architecture: all
Maintainer: umbrel-pipa <pipa@local>
Provides: linux-firmware
Depends: firmware-linux, firmware-atheros, firmware-qcom-soc
Description: Compatibility shim mapping Ubuntu linux-firmware to Debian firmware packages
EOF
    chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        firmware-linux firmware-atheros firmware-qcom-soc
    dpkg-deb -b "$stage" "$ROOT/tmp/pipa-linux-firmware-compat.deb"
    chroot "$ROOT" dpkg -i /tmp/pipa-linux-firmware-compat.deb
    rm -rf "$stage" "$ROOT/tmp/pipa-linux-firmware-compat.deb"
}

export DEBIAN_FRONTEND=noninteractive
install_linux_firmware_compat

# Debian dracut treats /boot/vmlinuz-<ver>.uncompressed (shipped by linux-image-pipa)
# as a separate kernel. Install with triggers deferred, then move those files
# completely out of /boot before running configure/triggers.
mkdir -p "$ROOT/boot/grub" "$ROOT/var/log/apt" "$ROOT/var/lib/pipa/boot-stash" "$ROOT/usr/local/sbin"
cat > "$ROOT/usr/local/sbin/pipa-stash-uncompressed-kernels" <<'EOF'
#!/bin/sh
set -eu
mkdir -p /var/lib/pipa/boot-stash /boot/grub /var/log/apt
for f in /boot/vmlinuz-*.uncompressed /boot/System.map-*.uncompressed \
         /boot/vmlinuz-*.uncompressed.pipa-hide /boot/System.map-*.uncompressed.pipa-hide \
         /boot/initrd.img-*.uncompressed /boot/initrd.img-*.uncompressed.pipa-hide \
         /boot/initramfs-*.uncompressed /boot/initramfs-*.uncompressed.pipa-hide; do
    [ -e "$f" ] || continue
    mv -f "$f" "/var/lib/pipa/boot-stash/$(basename "$f" | sed 's/\.pipa-hide$//')"
done
# Also remove any bogus initrds already generated for the fake kver.
rm -f /boot/initrd.img-*.uncompressed /boot/initrd.img-*.uncompressed.pipa-hide \
      /boot/initramfs-*.uncompressed /boot/initramfs-*.uncompressed.pipa-hide \
      /boot/initrd.img-*.uncompressed.pipa-hide 2>/dev/null || true
exit 0
EOF
chmod +x "$ROOT/usr/local/sbin/pipa-stash-uncompressed-kernels"

REQUIRED=()
MISSING=()
for pkg in $PIPA_PKGS; do
    # Skip names already satisfied by the compat shim / Debian firmware.
    case "$pkg" in
        linux-firmware) continue ;;
    esac
    if pkg_available "$pkg"; then
        REQUIRED+=("$pkg")
    else
        MISSING+=("$pkg")
    fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "ERROR: required packages not found in apt:"
    printf '  - %s\n' "${MISSING[@]}"
    exit 1
fi

set +e
chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confnew" \
    -o DPkg::Options::="--no-triggers" \
    "${REQUIRED[@]}"
APT_RC=$?
set -e

chroot "$ROOT" /usr/local/sbin/pipa-stash-uncompressed-kernels

set +e
chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive dpkg --configure -a
CONFIG_RC=$?
set -e

if [ "$APT_RC" -ne 0 ] || [ "$CONFIG_RC" -ne 0 ]; then
    echo "WARNING: apt/dpkg needed recovery (apt=$APT_RC configure=$CONFIG_RC)"
    chroot "$ROOT" /usr/local/sbin/pipa-stash-uncompressed-kernels || true
    chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive dpkg --configure -a
fi

# Keep uncompressed kernels stashed out of /boot permanently so later apt
# triggers cannot invent kver "*.uncompressed". Image/Image.gz remain in /boot.
# Optionally expose a non-vmlinuz name for tooling that wants the uncompressed image.
chroot "$ROOT" sh -c '
  for f in /var/lib/pipa/boot-stash/vmlinuz-*.uncompressed; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    ver="${base#vmlinuz-}"
    ver="${ver%.uncompressed}"
    if [ ! -f /boot/Image ]; then
      cp -f "$f" /boot/Image
    fi
    cp -f "$f" "/boot/Image-${ver}.uncompressed"
  done
'

for pkg in linux-image-pipa pipa-metapkg; do
    chroot "$ROOT" dpkg -s "$pkg" >/dev/null 2>&1 || {
        echo "ERROR: required package $pkg is not installed" >&2
        exit 1
    }
done

# Ensure optional follow-up installs also stash before triggers.
cat > "$ROOT/etc/apt/apt.conf.d/00-pipa-dracut-guard" <<'EOF'
DPkg::Pre-Invoke { "/usr/local/sbin/pipa-stash-uncompressed-kernels"; };
EOF

# Best-effort USB gadget networking helpers if published
for opt in usb-network qrtr-tools rmtfs tqftpserv pd-mapper; do
    if pkg_available "$opt"; then
        chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$opt" || true
    fi
done

chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    grub-efi-arm64 grub-efi-arm64-bin shim-signed || true

echo "=== Running post-install hooks ==="
HOOKS=(
    pipa-apt-repo.sh
    pipa-grub-setup.sh
    pipa-services.sh
    pipa-network-polkit.sh
    pipa-validate-hardware.sh
)
for hook in "${HOOKS[@]}"; do
    src="$REPO_ROOT/scripts/hooks/$hook"
    echo "--- $hook ---"
    cp "$src" "$ROOT/tmp/hook.sh"
    chmod +x "$ROOT/tmp/hook.sh"
    chroot "$ROOT" /tmp/hook.sh
    rm -f "$ROOT/tmp/hook.sh"
done

cat > "$ROOT/etc/fstab" <<EOF
LABEL=$ROOTFS_LABEL / ext4 defaults,x-systemd.growfs 0 1
LABEL=$BOOT_LABEL /boot ext4 defaults 0 2
LABEL=$ESP_LABEL /boot/efi vfat umask=0077 0 1
EOF

# umbrelOS is headless; ensure multi-user (or graphical if umbrel wants it)
chroot "$ROOT" systemctl set-default multi-user.target || true
chroot "$ROOT" systemctl enable NetworkManager ssh avahi-daemon || true

chroot "$ROOT" apt-get clean || true
rm -rf "$ROOT/var/cache/apt/archives"/*.deb
rm -f "$ROOT/etc/machine-id" "$ROOT/var/lib/dbus/machine-id"
: > "$ROOT/etc/machine-id"

umount "$ROOT/run" 2>/dev/null || true
umount "$ROOT/sys" 2>/dev/null || true
umount "$ROOT/proc" 2>/dev/null || true
umount "$ROOT/dev/pts" 2>/dev/null || true
umount "$ROOT/dev" 2>/dev/null || true
umount "$ROOT/boot/efi"
umount "$ROOT/boot"
umount "$ROOT"

losetup -d "$LOOP"
LOOP=""

echo "=== Disk image ready: $OUT_IMG ==="
