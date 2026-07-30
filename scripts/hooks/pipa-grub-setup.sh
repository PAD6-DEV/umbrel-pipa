#!/bin/bash
set -eux

ROOTFS_LABEL="${ROOTFS_LABEL:-umbrel-pipa}"
BOOT_LABEL="${BOOT_LABEL:-boot}"
CMDLINE="root=LABEL=$ROOTFS_LABEL rw rootwait boot=LABEL=$BOOT_LABEL console=tty0 earlycon quiet clk_ignore_unused pd_ignore_unused"

printf '%s\n' "$CMDLINE" > /etc/cmdline
mkdir -p /boot
printf '%s\n' "$CMDLINE" > /boot/cmdline.txt

mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/10-pipa-image.conf <<'EOF'
hostonly="no"
EOF

KERNEL_VER="$(ls /usr/lib/modules 2>/dev/null | head -n1 || true)"
if [ -n "$KERNEL_VER" ]; then
    if command -v pipa-refresh-initramfs >/dev/null 2>&1; then
        pipa-refresh-initramfs || true
    elif command -v dracut >/dev/null 2>&1; then
        dracut --force --no-hostonly --kver "$KERNEL_VER" "/boot/initramfs-${KERNEL_VER}.img" || true
        cp -f "/boot/initramfs-${KERNEL_VER}.img" /boot/initramfs-linux-pipa.img || true
    elif command -v update-initramfs >/dev/null 2>&1; then
        update-initramfs -c -k "$KERNEL_VER" || update-initramfs -u || true
    fi
fi

mkdir -p /boot/grub
cat > /boot/grub/grub.cfg <<EOF
search --no-floppy --label --set=boot $BOOT_LABEL
set prefix=(\$boot)/grub
configfile (\$boot)/grub/grub.cfg
EOF

if command -v pipa-refresh-grub-config >/dev/null 2>&1; then
    pipa-refresh-grub-config || true
fi

install_pipa_efi() {
    local esp="${1:-/boot/efi}"
    local grub_mod_dir="/usr/lib/grub/arm64-efi"
    local vendor_dir="$esp/EFI/ubuntu"
    local boot_dir="$esp/EFI/BOOT"

    mkdir -p "$vendor_dir" "$boot_dir"

    if [ ! -d "$grub_mod_dir" ]; then
        echo "pipa-grub-setup: missing $grub_mod_dir" >&2
        return 1
    fi
    if ! command -v grub-mkimage >/dev/null 2>&1; then
        echo "pipa-grub-setup: grub-mkimage not found" >&2
        return 1
    fi

    local modules=(
        all_video boot cat chain configfile echo ext2 fat gzio help
        linux loadenv ls lsefi lsefimmap normal part_gpt part_msdos
        reboot regexp search search_fs_file search_fs_uuid search_label
        sleep test true
    )

    grub-mkimage \
        -d "$grub_mod_dir" \
        -O arm64-efi \
        -o "$vendor_dir/grubaa64.efi" \
        -p /EFI/ubuntu \
        "${modules[@]}"

    local shim_src=""
    for candidate in \
        /usr/lib/shim/shimaa64.efi.signed.latest \
        /usr/lib/shim/shimaa64.efi.signed \
        /usr/lib/shim/shimaa64.efi; do
        [ -f "$candidate" ] || continue
        shim_src="$candidate"
        break
    done
    if [ -z "$shim_src" ]; then
        shim_src="$(ls /usr/lib/shim/shimaa64.efi* 2>/dev/null | head -n1 || true)"
    fi

    if [ -n "$shim_src" ] && [ -f "$shim_src" ]; then
        cp -f "$shim_src" "$vendor_dir/shimaa64.efi"
        cp -f "$shim_src" "$boot_dir/BOOTAA64.EFI"
    else
        cp -f "$vendor_dir/grubaa64.efi" "$boot_dir/BOOTAA64.EFI"
    fi
    cp -f "$vendor_dir/grubaa64.efi" "$boot_dir/grubaa64.efi"

    for dest in "$vendor_dir" "$boot_dir"; do
        cat > "$dest/grub.cfg" <<EOF
search --no-floppy --label $BOOT_LABEL --set prefix
if [ -d (\$prefix)/grub ]; then
  set prefix=(\$prefix)/grub
  configfile \$prefix/grub.cfg
elif [ -d (\$prefix)/boot/grub ]; then
  set prefix=(\$prefix)/boot/grub
  configfile \$prefix/grub.cfg
fi
boot
EOF
    done
}

if mountpoint -q /boot/efi 2>/dev/null || [ -d /boot/efi ]; then
    install_pipa_efi /boot/efi || {
        echo "pipa-grub-setup: EFI install failed" >&2
        exit 1
    }
fi

rm -f /etc/machine-id /var/lib/dbus/machine-id
: > /etc/machine-id
