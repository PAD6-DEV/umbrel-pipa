# umbrelOS for Xiaomi Pad 6 (pipa)

Flashable [umbrelOS](https://umbrel.com/umbrelos) image for the Xiaomi Pad 6 (Mu-Silicium UEFI). After boot, open http://umbrel.local.

## Build (CI)

GitHub Actions on `ubuntu-24.04-arm` builds upstream umbrelOS arm64, injects [pipa-pkgs](https://thespider2.github.io/pipa-pkgs/repo/ubuntu/) device packages, and publishes a release artifact.

Push to `main`, tag `v*` / `nightly-*`, or run **workflow_dispatch**.

## Build (local)

```bash
make image
```

## Flash

```bash
tar -xJf umbrel-pipa-YYYYMMDD.tar.xz
cd umbrel-pipa-YYYYMMDD
./flash.sh
```

| Image | Partition |
|-------|-----------|
| `silicium.img` | `boot_ab` |
| `umbrel_esp.raw` | `rawdump` |
| `umbrel_boot.raw` | `cust` |
| `umbrel_rootfs.raw` | `userdata` |
