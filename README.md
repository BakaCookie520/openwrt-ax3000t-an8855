# OpenWrt AX3000T (AN8855)

![CI Build](https://github.com/HughZadora/openwrt-ax3000t-an8855/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/HughZadora/openwrt-ax3000t-an8855/actions/workflows/release.yml/badge.svg)
![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg)

Build reproducible OpenWrt firmware for the Xiaomi Mi Router AX3000T with the
AN8855 switch variant. The project produces a single-UBI firmware target for
stock U-Boot, includes Tailscale in the image, and publishes OpenClash as a
separate APK so the initramfs remains within the bootloader limit.

## Important warning

This firmware is for the **AX3000T AN8855 hardware variant**. Do not flash it
to an unrelated AX3000T variant. The AN8855 target uses a single UBI layout;
the standard dual-partition target can boot into recovery or fail to persist.
Flashing firmware can permanently damage a router. Keep a recovery path and
verify the exact hardware before proceeding.

## Supported builds

| Build | Source branch/release | Target handling |
| --- | --- | --- |
| Mainline snapshot | `master` | Applies the repository AN8855 patch set and locks to `patches/VERIFIED_COMMIT`. |
| OpenWrt 24.10 snapshot | `openwrt-24.10` | Uses the upstream AN8855 target without the repository patch set. |
| Latest stable release | `stable-latest` | Resolves the highest non-prerelease OpenWrt release tag at build time and applies the repository AN8855 patch set. |

The build includes Tailscale, LuCI, `luci-compat`, networking and diagnostic
packages, WireGuard, QoS modules, zram, and a curated filesystem/module set.
OpenClash is built separately as an APK.

GitHub Actions builds all three variants in parallel. The stable variant is
resolved dynamically and is therefore not pinned to a specific release tag.

## Quick start

### Requirements

- Linux x86_64 or WSL2
- At least 8 GB RAM and 80 GB free disk space
- Bash, Git, and a working OpenWrt build environment
- Optional proxy for domestic downloads:
  `export ALL_PROXY=socks5h://host:port`

### Prepare and build

```sh
git clone https://github.com/HughZadora/openwrt-ax3000t-an8855.git
cd openwrt-ax3000t-an8855

# Prepare the source tree, feeds, and configuration.
bash setup.sh

# Or prepare and compile in one command.
bash setup.sh build
```

To build OpenWrt 24.10:

```sh
bash setup.sh --branch openwrt-24.10 build
```

The first full build may take several hours and requires substantial disk space.

## Build outputs

Firmware images are written to:

```text
openwrt-ax3000t/bin/targets/mediatek/filogic/
```

Typical outputs include:

- `*-initramfs-factory.ubi` — temporary RAM boot image;
- `*-squashfs-sysupgrade.bin` — persistent sysupgrade image;
- `*-initramfs.itb` — initramfs image checked against the 26 MiB limit.

The OpenClash package is written to:

```text
openwrt-ax3000t/bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash_<version>_<arch>.apk
```

The underscore-separated filename is intentional: it is the package naming
format emitted by OpenWrt's APK builder.

## Flashing

The recommended sequence is initramfs first, then persistent sysupgrade:

```sh
# From the stock/recovery system.
scp openwrt-*-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'mtd -f write /tmp/openwrt-*-initramfs-factory.ubi ubi && reboot'

# After the router boots the RAM system.
scp openwrt-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin'
```

After the first boot, set a root password and configure Wi-Fi encryption before
connecting the router to an untrusted network. Install OpenClash separately:

```sh
scp luci-app-openclash_*.apk root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'apk add /tmp/luci-app-openclash_*.apk luci-compat'
```

## Repository layout

```text
patches/                         AN8855 patch set and verified source commit
setup.sh                         Build orchestration entry point
scripts/check-image-size.sh      Initramfs size validation
scripts/generate-config-seed.sh  Reproducible package/config seed
scripts/inject-firstboot-defaults.sh  First-boot defaults
openwrt-ax3000t/                 Ignored OpenWrt source/build tree
docs/                            Stable development and operations reference
.github/workflows/               CI, release, and repository checks
```

## Common commands

| Task | Command |
| --- | --- |
| Prepare source | `bash setup.sh` |
| Full build | `bash setup.sh build` |
| Build OpenWrt 24.10 | `bash setup.sh --branch openwrt-24.10 build` |
| Configure packages | `cd openwrt-ax3000t && make menuconfig` |
| Compile OpenClash | `cd openwrt-ax3000t && make package/feeds/openclash/luci-app-openclash/compile V=s` |
| Validate initramfs size | `scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic` |
| Repository baseline | `scripts/repository-check` |

## GitHub Actions

The CI workflow builds both supported branches, checks the initramfs size,
compiles OpenClash, and uploads firmware/APK artifacts. Build artifacts are
retained by GitHub Actions for 90 days.

After a successful `master` firmware build, semantic-release determines the
version from conventional commits, generates the changelog, creates a tag, and
publishes a GitHub Release with the validated firmware/APK assets.

## Constraints

- The stock bootloader requires the AN8855 single-UBI layout.
- The initramfs FIT image must remain at or below 26 MiB.
- OpenClash is intentionally not included in the firmware image.
- The standard AX3000T/MT7531 target is not interchangeable with this target.
- OpenWrt source and build outputs are local ignored artifacts, not repository
  state.

## Documentation

- [Development guide](docs/development/guide.md)
- [Router operations](docs/operations/home-router.md)
- [Build experience](docs/reports/build-experience.md)
- [Router state](docs/reference/router-state.md)

## License

GPL-2.0, consistent with OpenWrt.
