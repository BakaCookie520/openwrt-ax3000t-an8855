# OpenWrt AX3000T (AN8855)

[简体中文（默认）](README.md) | **English**

![CI Build](https://github.com/HughZadora/openwrt-ax3000t-an8855/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/HughZadora/openwrt-ax3000t-an8855/actions/workflows/release.yml/badge.svg)
![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg)

Build reproducible OpenWrt firmware for the Xiaomi Mi Router AX3000T with the
AN8855 switch variant. The project produces a single-UBI firmware target for
stock U-Boot. Its full sysupgrade preinstalls Nikki/Mihomo, ttyd and Tailscale;
a separate slim recovery initramfs stays within the bootloader limit.
The full image also includes Argon, its Simplified Chinese settings translation, and xinfc NFC management.

## Preinstalled services and dual-image artifacts

Every build refreshes `nikkinikki-org/OpenWrt-nikki` from its official `main` feed.
The full sysupgrade image includes Nikki, its LuCI interface and Simplified Chinese
translation, the feed-selected stable `mihomo-meta` core, matching kernel modules,
ttyd/LuCI terminal, and existing Tailscale functionality. Nikki starts disabled;
no subscriptions, router passwords, or proxy credentials are embedded.

`bash setup.sh build` and all Actions builds use the same dual-pass builder.
Validated files are saved under `openwrt-ax3000t/bin/ax3000t-artifacts/`:

- `full-*-squashfs-sysupgrade.bin`: the complete daily-use system.
- `recovery-*-initramfs*`: a temporary recovery system without Nikki/Mihomo,
  yq, Tailscale, Argon or xinfc, but with LuCI/ttyd; recovery FIT must not exceed 26 MiB.
- `packages.tar.gz`: matching APK/IPK packages and indexes, including kernel modules
  and the preinstalled applications. Use the native package format for the branch.
- Manifests, full/recovery configs, build provenance and SHA256 checksums.

Oversized full initramfs files are never exported. Full sysupgrade files have a
conservative 100 MiB limit for the 112 MiB UBI partition. Kernel package/ABI values
must match between both passes. The original full build config is restored even
on failure. An existing artifact output directory must be empty; optionally pass
a new output directory to `bash scripts/build-firmware.sh <tree> <output>`.

Use the `full-` image for persistent upgrades and `recovery-` only for recovery.
Preserved network/Wi-Fi settings are not overwritten. Upstream ttyd defaults bind
`@lan` and run `/bin/login`; retained old ttyd settings are not migrated automatically.
An old `lan4` binding should be corrected to `@lan`/`br-lan` manually. A bridged AP
still needs a separately planned proxy topology; installation alone does not
redirect client traffic. Test offline with `bash scripts/tests/test-nikki-build.sh`.

## Important warning

This firmware is for the **AX3000T AN8855 hardware variant**. Do not flash it
to an unrelated AX3000T variant. The AN8855 target uses a single UBI layout;
the standard dual-partition target can boot into recovery or fail to persist.
Flashing firmware can permanently damage a router. Keep a recovery path and
verify the exact hardware before proceeding.

## Supported builds

| Build | Source branch/release | Target handling |
| --- | --- | --- |
| Mainline snapshot | Latest `main` | Fetches the latest mainline commit and strictly applies the repository AN8855 patch set. |
| Latest stable release | `stable-latest` | Resolves the highest non-prerelease OpenWrt release tag at build time and applies the repository AN8855 patch set. |

The build includes Tailscale, LuCI, `luci-compat`, networking and diagnostic
packages, WireGuard, QoS modules, zram, and a curated filesystem/module set.
The shared target guard rejects stock/ubootmod selections, incorrect single-UBI layouts,
incomplete upgrade handlers, or missing NFC/I2C prerequisites.

GitHub Actions builds only the patched mainline snapshot. The stable
variant runs in a separate workflow, is resolved dynamically, and is therefore
not pinned to a specific release tag.

Mainline Actions runs daily at 02:00 UTC (10:00 Asia/Shanghai; scheduling can be
delayed), as well as on push/PR and manual dispatch. Each build uses the source
revision resolved at startup, never a moving checkout during compilation.
`patches/VERIFIED_COMMIT` is historical only, not a pin or fallback. The actual
source SHA is recorded in `BUILD-INFO.txt`. Patches allow line offsets but no
fuzz; incompatible context or failed single-UBI/upgrade/NFC gates stops the build.
Local setup also refreshes main: if upstream advanced and a reused source tree
has tracked edits (including previously applied board patches), preserve those
edits and use a clean checkout. Setup never force-overwrites edits or silently
builds stale main.

## Quick start

### Requirements

- Linux x86_64 or WSL2
- At least 8 GB RAM and 80 GB free disk space
- Bash, Git, and a working OpenWrt build environment
- Optional proxy to improve download speeds:
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

The first full build may take several hours and requires substantial disk space.

## Build outputs

Firmware images are written to:

```text
openwrt-ax3000t/bin/targets/mediatek/filogic/
```

Use validated deliverables from `openwrt-ax3000t/bin/ax3000t-artifacts/`, not
unfiltered files from the intermediate target directory. See the dual-image
section above for the full/recovery prefixes, package archive and provenance.

## Flashing and upgrading

For an initial installation or a layout migration, use initramfs first, then
persistent sysupgrade. **This procedure does not preserve existing settings.**

```sh
# From the stock/recovery system.
scp recovery-*-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'mtd -f write /tmp/recovery-*-initramfs-factory.ubi ubi && reboot'

# After the router boots the RAM system.
scp full-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'sysupgrade -n /tmp/full-*-squashfs-sysupgrade.bin'
```

For subsequent upgrades with the same AN8855 single-UBI layout, use the
`*-squashfs-sysupgrade.bin` image directly in LuCI with **Keep settings** enabled,
or run `sysupgrade /tmp/<image>-squashfs-sysupgrade.bin` without `-n`.
Download a configuration backup first. Configuration preservation does not
reinstall extra packages; reinstall compatible packages after the upgrade.

New installations default to LAN IP `192.168.31.1` with Wi-Fi disabled.
The board defaults do not overwrite retained LAN, SSID, encryption, or password
settings during an upgrade. After the first boot, set a root password and
configure Wi-Fi encryption before enabling wireless access. Nikki is preinstalled
but disabled until configured.

Fresh full installations default to Argon, including the integrated settings page
and `luci-i18n-argon-config-zh-cn`. Retained theme and language settings are never
overwritten. Recovery uses Bootstrap and excludes Argon/xinfc.

xinfc imports the pinned 1.0.1-r1 APK payload from `packages/luci-app-xinfc/` and
repackages it as 1.0.1-r3 using each branch's APK/IPK tooling. Installation hooks
support offline builds; the payload and runtime hardware checks are unchanged.
Installation and first boot never program NFC. The first backup under `/etc/xinfc/`
is retained during upgrades. Original APK checksums are recorded in build info.
The supplied APK does not include corresponding source; establish GPL source
availability before public redistribution.

The full image adds a default-checked **同时更改 NFC** option to the wireless
interface's Wireless Security tab. Only a confirmed Save & Apply of changed
SSID/key/encryption submits NFC synchronization; opening, saving a draft,
unchecking, reverting or changing unrelated settings does not. Existing NFC
write permission is required. Different networks require choosing one NFC
target; identical dual-band credentials are written once. Disabled APs, PPSK
and unsupported encryption are excluded. NFC supports WPA2-AES or WPA2/WPA3
mixed mode, SSIDs of 2–28 bytes and passphrases of 8–63 bytes. Verify completion
in Services / AX3000T NFC: RPC submission is not readback success. Connection
loss may prevent synchronization; NFC failures do not undo applied Wi-Fi or
automatically retry. This requires a rebuilt firmware, not just a package
update on an older image. Installation and first boot still never write NFC.

## Repository layout

```text
patches/                             AN8855 patch set and verified source commit
setup.sh                             Build orchestration entry point
scripts/check-image-size.sh          Initramfs size validation
scripts/check-board-scripts.sh       Board script backup safety validation
scripts/generate-config-seed.sh      Reproducible package/config seed
scripts/inject-firstboot-defaults.sh  New-installation board defaults
openwrt-ax3000t/                     Ignored OpenWrt source/build tree
docs/                                Stable development and operations reference
.github/workflows/                   CI, release, and repository checks
```

## Common commands

| Task | Command |
| --- | --- |
| Prepare source | `bash setup.sh` |
| Full build | `bash setup.sh build` |
| Configure packages | `cd openwrt-ax3000t && make menuconfig` |
| Validate initramfs size | `scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic` |
| Check board script backups | `bash scripts/check-board-scripts.sh openwrt-ax3000t` |
| Repository baseline | `scripts/repository-check` |

## GitHub Actions

The CI workflow builds OpenWrt `main` on repository `master` pushes and pull requests,
checks the target/layout and initramfs size, and uploads firmware/package
artifacts. The separate `stable-latest.yml` workflow performs the same build
for the latest stable OpenWrt release. Both workflows cache OpenWrt downloads
and compiler results; artifacts are retained by GitHub Actions for 90 days.

After a successful `master` firmware build, semantic-release determines the
version from conventional commits, generates the changelog, creates a tag, and
publishes a GitHub Release with the validated firmware/APK assets.

## Constraints

- The stock bootloader requires the AN8855 single-UBI layout.
- The initramfs FIT image must remain at or below 26 MiB.
- Nikki/Mihomo, Tailscale, Argon and xinfc are installed only in the full image.
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
