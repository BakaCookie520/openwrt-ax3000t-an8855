# Project Status

> **Date**: 2026-10-30
> **Scope**: openwrt-ax3000t-an8855
> **Status**: implementation and offline validation; firmware/hardware validation pending

## Current State

AN8855 single-UBI dual-image builds. The full profile selects Nikki/stable Mihomo,
Tailscale, ttyd, integrated Argon settings with Simplified Chinese, and imported
xinfc. Recovery excludes these larger applications except ttyd/LuCI and uses
Bootstrap. Runtime theme/language choices survive retained-config upgrades.
Historical changelog entries remain; the removed proxy has no active build path.

## Validation

- Entry point: `bash scripts/repository-check`.
- Offline contracts: `for test in scripts/tests/test-*.sh; do bash "$test" || exit; done`.
- No firmware cross-build, measured new image sizes, or hardware NFC validation
  has been completed for this change. Offline tests are not a firmware result.
- The user Ubuntu WSL distributions cannot mount their configured VHD paths;
  an isolated Alpine userspace under the available WSL utility distribution
  is sufficient for offline contracts, not a complete OpenWrt build environment.

## Constraints and next steps

- Never build the stock dual-partition or ubootmod target. Source and config
  guards must fail closed on missing targets, wrong layouts or missing NFC/I2C.
- Only patched mainline and dynamic stable builds remain. The old fixed-release
  workflow entry and local source-branch overrides have been removed.
- Argon source is pinned in `scripts/argon.commit`; the integrated configuration
  translation package remains `luci-i18n-argon-config-zh-cn`.
- xinfc 1.0.1-r2 wraps the unchanged 1.0.1-r1 ARM64 payload. Original archive,
  metadata and hashes are in `packages/luci-app-xinfc/`. Establish corresponding
  GPL source availability before public binary redistribution.
- Run native builds for compatible sources and validate manifest, image sizes
  and ABI equality, then inspect Argon/Chinese and read-only NFC status on hardware.
- Documentation decisions: `docs/adr/0002-argon-xinfc-and-target-guards.md`.
