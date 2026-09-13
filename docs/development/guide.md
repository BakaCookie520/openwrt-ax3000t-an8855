# Development Guide — OpenWrt AX3000T AN8855

> **Date**: 2026-08-21
> **Author**: hugh
> **Scope**: infrastructure
> **Purpose**: Complete build environment, customization, troubleshooting, and contribution guide
> **Status**: active

---

This document consolidates all developer-facing information from `docs/operations/home-router.md`, `docs/reports/build-experience.md`, and `docs/reference/router-state.md`. For user onboarding, see [README.md](../../README.md) / [README.zh.md](../../README.zh.md).

---

## Build Environment

### Host Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Linux x86_64 (WSL2 supported) | Ubuntu 22.04+ / Debian 12+ |
| RAM | 8 GB | 16 GB+ |
| Disk | 80 GB free | 150 GB+ (for ccache/sstate) |
| Proxy | SOCKS5 for China mainland | `ALL_PROXY=socks5h://host:port` |

### Required Packages

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-setuptools \
    rsync swig unzip zlib1g-dev file wget ccache

# Arch Linux
sudo pacman -S --needed base-devel gcc git ncurses openssl python3 rsync swig unzip zlib ccache
```

### Version Pinning

Use `mise` / `asdf` / `nvm` for reproducible toolchains:

```bash
# Example .tool-versions
nodejs 20.18.0
pnpm 9.12.0
go 1.22.0
```

---

## Build Process Deep Dive

### What `setup.sh` Does

```bash
# Step 1: Clone OpenWrt main (or --branch)
git clone --depth 1 --branch main https://git.openwrt.org/openwrt/openwrt.git openwrt-ax3000t

# Step 2: Lock to verified commit (main branch only)
# Reads patches/VERIFIED_COMMIT, fetches & checks out that SHA
# Prevents mainline drift breaking patches

# Step 3: Apply AN8855 patches (main branch only)
# patches/0001-add-an8855-target.patch → filogic.mk + platform.sh + 02_network
# patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts → single UBI DTS
# Dry-run validation before/after application

# Step 4: Add OpenClash feed
echo "src-git openclash https://github.com/vernesong/OpenClash.git" >> feeds.conf

# Step 5: Update & install feeds
./scripts/feeds update -a && ./scripts/feeds install -a

# Step 6: Generate defconfig (an8855 target + Tailscale + curated kmods + USTC mirror)
make defconfig
```

### Key Patch Details

| File | Purpose |
|------|---------|
| `patches/0001-add-an8855-target.patch` | Adds `Device/xiaomi_mi-router-ax3000t-an8855` to `target/linux/mediatek/image/filogic.mk`; sets `CI_UBIPART="ubi"` in `platform.sh`; adds AN8855 LAN/WAN/MAC rules in `02_network` |
| `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | Defines single UBI partition: `partition@600000 { label="ubi"; reg=<0x600000 0x7000000> }` (112MB @ 0x600000) |

### Curated Kernel Module Set

Pre-selected in `defconfig` to fit <26MB initramfs FIT limit:

| Category | Modules |
|----------|---------|
| Memory | `kmod-zram`, `zram-swap` |
| Firewall/NAT | `kmod-ipt-core`, `kmod-nft-*`, `kmod-nf-nathelper` |
| Tunnels | `kmod-wireguard`, `kmod-tun`, `kmod-veth`, `kmod-tcp-bbr` |
| QoS | `kmod-sched-cake`, `kmod-sched-fq-pie`, `tc-full` |
| Filesystem | `kmod-fs-ext4` |
| Diagnostics | `tcpdump`, `conntrack`, `ipset`, `ip-full`, `ip-bridge`, `iperf3`, `ethtool`, `mtr`, `nlbwmon` |

**Excluded** (to fit size budget): USB/storage kmods (btrfs, xfs, usb-core, etc.), exotic tunnels (l2tp, team, macsec), heavy filesystems.

### Image Size Validation

```bash
# Runs automatically in setup.sh build mode; manual:
cd openwrt-ax3000t
../scripts/check-image-size.sh
```

Validates `*-initramfs-kernel.bin` (FIT) ≤ 26MB. **Excludes** `*-initramfs-factory.ubi` (UBI container, not loaded by U-Boot directly).

---

## Customization

### Changing Target Profile

```bash
cd openwrt-ax3000t
make menuconfig
# Target System: MediaTek Ralink ARM
# Subtarget: Filogic 820/830 (MT7981/MT7986)
# Target Profile: Xiaomi Mi Router AX3000T (AN8855)  ← MUST SELECT THIS
```

### Adding Kernel Modules

```bash
make menuconfig
# Kernel modules → [category] → select desired kmods
# Rebuild: make -j$(nproc) V=s
```

### Switching to OpenWrt 24.10 Stable

```bash
# 24.10 has official AN8855 target; no patches needed
bash setup.sh --branch openwrt-24.10 build
```

**Behavior difference**:
- `main`: clones main + locks `VERIFIED_COMMIT` + applies AN8855 patches
- `openwrt-24.10`: clones 24.10 branch, **skips commit lock & patches** (official target exists)

### Custom Feed / Package

```bash
# Add to feeds.conf before ./scripts/feeds update -a
src-git custom https://github.com/user/repo.git

# Or add to package/feeds/ manually, then:
./scripts/feeds install -a -p custom
```

---

## Troubleshooting

### Build Failures

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `fakeroot` hangs at `package/libs/toolchain/compile` | Stale `faked` daemon | `kill -9 $(pgrep -f 'faked\|fakeroot')` |
| Download <10 KB/s | No proxy configured | `export ALL_PROXY=socks5h://host:port` |
| `find: relative path in PATH` (WSL) | Windows PATH pollution | `PATH=$(echo "$PATH" \| tr ':' '\n' \| grep -v '^/mnt/' \| tr '\n' ':') make ...` |
| `GnuTLS recv error (-110)` | Direct GitHub connection failed | Use proxy; or `git config --global url."https://github.com/".insteadOf git://github.com/` |
| `Patch failed! No file to patch` (kernel prepare) | `PATCH_DIR` env var collision | `setup.sh` uses `REPO_PATCH_DIR` — ensure not overridden |
| `No more mirrors to give up` | Corrupted download in `dl/` | `rm dl/<bad-file>*` and retry |

### Runtime Issues (Post-Flash)

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Sysupgrade → bootloop to recovery | Wrong target (dual-partition) | Must use `xiaomi_mi-router-ax3000t-an8855` single-UBI |
| OpenClash installed but no LuCI menu | Missing Lua runtime (LuCI 26) | `apk add luci-compat && /etc/init.d/uhttpd restart` |
| `fw_printenv` missing | `uboot-envtools` not configured | Not needed; stock U-Boot managed by upgrade scripts |
| Tailscale `logged out` | WAN down → no control plane | Restore WAN; `tailscaled` auto-reconnects via `procd respawn` |

### Image Size Issues

```bash
# Check current initramfs size
ls -lh bin/targets/mediatek/filogic/*initramfs-kernel.bin

# If >26MB: reduce kmods in menuconfig
# Common culprits: kmod-fs-*, kmod-usb-*, kmod-crypto-*
```

---

## Router Runtime Configuration

*Source: `docs/operations/home-router.md` + `docs/reference/router-state.md`*

### Network Topology

```
LAN: br-lan = 192.168.31.1/24 (bridged lan2/lan3/lan4 via AN8855)
WAN: wan@eth0 → PPPoE (public IP 100.77.x)
Modem: static 192.168.1.99/24 on wan device (single-arm modem access)
Tailscale: tailscale0 TUN (100.104.191.81/32) — advertises 192.168.31.0/24
```

### Key UCI Configs

```bash
# Network
uci show network
# br-lan: static 192.168.31.1/24, ifname=lan2 lan3 lan4
# wan: proto=pppoe
# Modem: proto=static, ipaddr=192.168.1.99, netmask=255.255.255.0, device=wan

# Firewall (fw4/nftables)
# zones: lan(ACCEPT), wan(REJECT+masq), modem(ACCEPT+masq), tailscale(ACCEPT)
# forwards: lan→wan, lan→modem, tailscale↔lan

# Tailscale
tailscale up --accept-dns=false --advertise-routes=192.168.31.0/24 --snat-subnet-routes=false
# prefs persisted in /etc/tailscale/tailscaled.state
# CorpDNS=false (MagicDNS off), NoSNAT=true, RouteAll=false
```

### WiFi Config (Current)

| Band | SSID | Channel | Width | Encryption | TX Power |
|------|------|---------|-------|------------|----------|
| 2.4G | 猪猪之家 | 1 (HE20) | 20MHz | sae-mixed (WPA3/WPA2) | 20 dBm |
| 5G | 猪猪之家 | 149 (HE80) | 80MHz | sae-mixed | 28 dBm |

**Note**: 5G ch 149 avoids DFS; 802.11r/ft_psk disabled (causes hostapd error on single AP).

### Stability Tuning (Applied)

```bash
# /etc/sysctl.d/99-stability.conf
vm.swappiness=10
net.core.netdev_max_backlog=4096
net.core.somaxconn=4096
net.ipv4.tcp_slow_start_after_idle=0
net.netfilter.nf_conntrack_max=32768
net.netfilter.nf_conntrack_tcp_timeout_established=3600
net.netfilter.nf_conntrack_udp_timeout=60
net.netfilter.nf_conntrack_icmp_timeout=10
kernel.panic=3
kernel.panic_on_oops=1
```

- Hardware watchdog: `procd` feeds `/dev/watchdog` (30s timeout, 5s interval)
- zram swap: `/dev/zram0` 118MB, priority 100
- No NAND swap (prevents flash wear)
- No scheduled reboots (7×24 target)

---

## Device State Reference

*Source: `docs/reference/router-state.md` (2026-08-14 data)*

### Hardware

| Item | Value |
|------|-------|
| Model | Xiaomi Mi Router AX3000T |
| Switch | **AN8855** (external, not MT7531) |
| SoC | MediaTek MT7981 (Filogic 820), aarch64 Cortex-A53 |
| RAM | 256MB (239088K available) |
| Flash | 128MB SPI-NAND |
| U-Boot | **Stock** (not OpenWrt U-Boot) |
| board_name | `xiaomi,mi-router-ax3000t-an8855` |

### Flash Partitions (`/proc/mtd`)

| mtd | Name | Size | Notes |
|-----|------|------|-------|
| mtd0 | BL2 | 1MB | Boot header |
| mtd1 | Nvram | 256KB | |
| mtd2 | Bdata | 256KB | |
| mtd3 | Factory | 2MB | EEPROM |
| mtd4 | FIP | 2MB | |
| mtd5 | crash | 256KB | |
| mtd6 | crash_log | 256KB | |
| mtd7 | KF | 256KB | |
| **mtd8** | **ubi** | **112MB** | **System partition (single UBI)** |

### UBI Volumes (`ubinfo -a`)

| Vol ID | Name | Size | Role |
|--------|------|------|------|
| 0 | kernel | 4.2 MiB | Kernel image |
| 1 | fit | 4.2 MiB | FIT kernel |
| 2 | rootfs | 25.6 MiB | Squashfs RO rootfs |
| 3 | rootfs_data | 71.5 MiB | Overlay (RW config/data) |

Mount: `/dev/root` (vol rootfs) → `/rom` RO; `ubi0_3` → `/overlay`.

### Upgrade Path (Critical)

**Current**: Single UBI 112MB + stock U-Boot + custom board_name
**Mainline stock**: Dual-partition (ubi_kernel + ubi) — **INCOMPATIBLE**

```
Do NOT sysupgrade stock image directly.
Use: initramfs-factory.ubi → mtd write ubi → reboot → sysupgrade -n squashfs-sysupgrade.bin
```

**Recovery**: Power off → hold Reset → power on → 192.168.31.1 recovery page

---

## Historical Build Experience

*Source: `docs/reports/build-experience.md` (2026-06/08 records)*

### WSL-Specific Fixes

1. **fakeroot path hardcode** — `staging_dir/host/bin/fakeroot` had hardcoded old path. Fixed to auto-derive: `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`
2. **PATH pollution** — `/mnt/c/Program Files/...` creates relative `Files/...` entry. Fixed in `include/rootfs.mk`: `-execdir` → `-exec`
3. **Proxy** — `ALL_PROXY` works natively with git/curl; no `proxychains` (conflicts with fakeroot LD_PRELOAD)

### Performance Baselines

| Strategy | First Build | Rebuild (ccache) |
|----------|-------------|------------------|
| `-j$(nproc)` | 2–6 hours | 30 min |
| ccache hit rate | ~13% | 60%+ |
| `ALL_PROXY` speedup | 1.2 KB/s → 34 MB/s | N/A |

### Key Lessons

- **Kernel modules are compile-time only** — cannot `apk add kmod-*` post-flash
- **Initramfs size is hard constraint** — every kmod counts; audit with `check-image-size.sh`
- **OpenClash + LuCI 26** — requires `luci-compat` (Lua runtime removed in LuCI 26)
- **PATCH_DIR collision** — never export `PATCH_DIR`/`FILES_DIR`/`KDIR` in build scripts

---

## Contribution Workflow

### Before PR

```bash
# 1. Test build
bash setup.sh build

# 2. Verify image size
scripts/check-image-size.sh

# 3. Run validation gates (if available)
# python3 .config/opencode/gates/configuration/verify-project-documentation.py

# 4. Update docs if user-facing change
# README.md / README.zh.md / docs/development/guide.md
```

### Commit Convention

Conventional Commits:
- `feat:` new feature
- `fix:` bug fix
- `docs:` documentation only
- `refactor:` code restructure
- `chore:` build/tooling
- `ci:` CI config

Example: `fix(patches): correct AN8855 MAC address extraction`

### PR Checklist

- [ ] Build passes (`bash setup.sh build`)
- [ ] Image size ≤26MB initramfs
- [ ] Docs updated (README/DEVELOPMENT if user-facing)
- [ ] No secrets in diff
- [ ] Conventional commit message

---

## Architecture Decisions

| Decision | Rationale | Reference |
|----------|-----------|-----------|
| Single UBI target on mainline | Stock U-Boot + AN8855 only boots single UBI | `docs/reference/router-state.md` §0 |
| OpenClash as APK not in firmware | initramfs >26MB with OpenClash → U-Boot load fail | `README.md` FAQ |
| Curated kmod set | 179 kmods → 27.9MB initramfs (fail); curated → ~25MB | `docs/reports/build-experience.md` §6.3 |
| USTC mirror default | Domestic download 28500x faster | `docs/reports/build-experience.md` §4.2 |
| `VERIFIED_COMMIT` lock | Prevent mainline drift breaking patches | `setup.sh` §75-83 |
| `REPO_PATCH_DIR` not `PATCH_DIR` | Avoids OpenWrt kernel.mk variable collision | `docs/reports/build-experience.md` §9 |

---

## Verification Gates

### Pre-Commit (Local)

```bash
# Check documentation sync
python3 .config/opencode/gates/configuration/verify-project-documentation.py

# Lint (if configured in .agents/config.yaml)
# <project-lint-command>
```

### Pre-Push (CI)

```bash
# Full validation
python3 .config/opencode/gates/configuration/verify-project-documentation.py
actionlint .github/workflows/
shellcheck setup.sh scripts/check-image-size.sh
markdownlint-cli2 README.md README.zh.md docs/development/guide.md
yaml-lint .agents/config.yaml .opencode/skill-config.yaml
```

---

## CI/CD Pipeline

### Overview

This project uses GitHub Actions for continuous integration and semantic-release for automated versioning.

### Workflows

| Workflow | File | Triggers | Purpose |
|----------|------|----------|---------|
| **CI Build** | `.github/workflows/ci.yml` | Push/PR to `master`/`openwrt-24.10`, manual dispatch | Build the two snapshot variants, validate image size, upload firmware/APK artifacts |
| **Stable Build** | `.github/workflows/stable-latest.yml` | Monthly cron (02:00 UTC), manual dispatch | Resolve the latest stable OpenWrt release and build firmware + OpenClash APK |
| **Release** | `.github/workflows/release.yml` | Push to `master` (after CI passes) | semantic-release: analyze commits → version → tag → GitHub Release with artifacts |

### CI Build Details

**Matrix builds**:
- `master` branch: Full pipeline with VERIFIED_COMMIT lock + AN8855 patches
- `openwrt-24.10` branch: Build without VERIFIED_COMMIT lock (official AN8855 target exists)

The `stable-latest` build is intentionally outside the PR/push matrix so a
slow full release build cannot delay normal pull-request feedback. Both
workflows use GitHub Actions cache for the OpenWrt `dl/` download directory and
the ccache directory.

**Artifacts** (90-day retention):
- `*-initramfs-factory.ubi` — Flash via recovery/mtd
- `*-squashfs-sysupgrade.bin` — Sysupgrade from running OpenWrt
- `luci-app-openclash-*.apk` — Install via `apk add`
- `SHA256SUMS.txt` — Checksums for verification

**Image size gate**: `scripts/check-image-size.sh` runs with `STRICT=1` — build fails if initramfs > 26MB.

**VERIFIED_COMMIT auto-update**: On successful `master` builds (non-PR), CI extracts the OpenWrt commit SHA and updates `patches/VERIFIED_COMMIT`, committing and pushing back to `master`.

### Release Process

1. Push conventional commits to `master` (e.g., `feat: add new kmod`, `fix: patch drift`)
2. CI builds and validates → passes
3. `release.yml` triggers `semantic-release`
4. semantic-release:
   - Analyzes commits since last tag
   - Determines version bump (major/minor/patch)
   - Generates changelog (updates `CHANGELOG.md`)
   - Creates git tag `vX.Y.Z`
   - Creates GitHub Release with firmware + APK artifacts
   - Commits `CHANGELOG.md` update

**Commit conventions** (enforced by semantic-release):
- `feat:` → minor version
- `fix:` `perf:` `refactor:` `docs:` `build:` → patch version
- `chore:` `ci:` `style:` `test:` → no release
- `BREAKING CHANGE:` footer → major version

### Manual Release (if needed)

```bash
# Dry-run to preview
npx semantic-release --dry-run --no-ci

# Force release (bypasses commit analysis)
npx semantic-release --no-ci --branch master
```

### Local CI Testing

```bash
# Validate workflow syntax
actionlint .github/workflows/

# Test semantic-release config
npx semantic-release --dry-run --no-ci

# Run image size check locally
cd openwrt-ax3000t
../scripts/check-image-size.sh bin/targets/mediatek/filogic
```

### Required Repository Settings

1. **Actions permissions**: Settings → Actions → General → Allow all actions and reusable workflows
2. **Workflow permissions**: Settings → Actions → General → Workflow permissions → "Read and write permissions" (for VERIFIED_COMMIT push, semantic-release tag/release)
3. **Branch protection** (recommended): Protect `master` → Require status checks → `ci.yml` build job

---

## References

- [README.md](../../README.md) — User onboarding (English)
- [README.zh.md](../../README.zh.md) — 用户入门 (中文)
- [home-router.md](../operations/home-router.md) — Router runtime config (Tailscale, network)
- [build-experience.md](../reports/build-experience.md) — Build troubleshooting archive
- [router-state.md](../reference/router-state.md) — Device partition/UBI/firmware state
- OpenWrt Build System: https://openwrt.org/docs/guide-developer/build-system/start
- AX3000T Forum: https://forum.openwrt.org/t/openwrt-support-for-router-home/180490
