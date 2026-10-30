# Project State

> **Date**: 2026-10-30
> **Author**: Agent (auto-maintained per AGENTS.md)
> **Scope**: openwrt-ax3000t-an8855
> **Purpose**: Record Agent knowledge state verification results and next steps
> **Status**: active

## Common Entry Points

- Build entry: `setup.sh` (one-command build)
- Dev commands: `bash setup.sh` / `bash setup.sh build`
- Build command: `make -j$(nproc) V=s` (in openwrt-ax3000t/ directory)
- Test command: `bash scripts/repository-check` and `scripts/tests/test-*.sh`; cross-build/hardware validation remains separate
- Documentation entry: `README.md`, `README.zh.md`, `docs/development/guide.md`, `docs/reference/router-state.md`, `docs/reports/build-experience.md`, `docs/operations/home-router.md`
- Agent rules entry: Global `/home/hugh/agent-config/AGENTS.md`
- Current working directory: `/home/hugh/Projects/openwrt-ax3000t-an8855/`

## Core Modules

| Module | Path | Responsibility | Key Dependencies | Risk Level | Last Changed |
|--------|------|----------------|------------------|------------|--------------|
| Build script | `setup.sh` | Clone OpenWrt main, apply patches, configure feeds, generate defconfig | git, patch, make | High (drift lock) | 2026-08-18 |
| AN8855 patches | `patches/` | Single UBI target rebuild patches, VERIFIED_COMMIT lock | OpenWrt main DTS | Critical (boot layout) | 2026-08-14 |
| UI/NFC packages | `scripts/prepare-feeds.sh`, `packages/luci-app-xinfc/` | Pinned Chinese Argon and offline-safe imported xinfc | Nikki/Argon feeds, native OpenWrt packaging | Medium | 2026-10-30 |
| Documentation | `README.md`, `README.zh.md`, `docs/development/guide.md`, `docs/reference/router-state.md`, `docs/reports/build-experience.md`, `docs/operations/home-router.md` | Build guide, device state, troubleshooting archive | None | Medium | 2026-08-21 |
| Curated kmod set | `setup.sh` defconfig | Kernel module selection, controls initramfs size < 26MB | OpenWrt kmod | High (size limit) | 2026-08-14 |
| CI/CD Pipeline | `.github/workflows/ci.yml`, `.github/workflows/release.yml` | Automated builds, scheduled, multi-branch, semantic-release, VERIFIED_COMMIT auto-update | GitHub Actions, semantic-release | Medium | 2026-08-21 |

## Verification Commands

| Type | Command | Scope | Side Effects | Last Result |
|------|---------|-------|--------------|-------------|
| Syntax check | `bash -n setup.sh` | setup.sh | None | Pass |
| Patch validation | `patch --dry-run -p1 -i patches/0001-add-an8855-target.patch` | patches/ | None | N/A (needs OpenWrt source) |
| Image size check | `scripts/check-image-size.sh` | Build artifacts | None | N/A (needs build artifacts) |
| Git status | `git status` | Repository | None | Pass |
| Workflow syntax | `actionlint .github/workflows/` | CI/CD | None | Pass (warnings only) |
| Script syntax | `bash -n scripts/*.sh` | All scripts | None | Pass |

## Evidence Read

- README.md (new bilingual)
- README.zh.md (new Chinese mirror)
- docs/development/guide.md (new consolidated, moved from DEVELOPMENT.md)
- docs/reference/router-state.md (moved from ROUTER_STATE.md)
- docs/reports/build-experience.md (moved from BUILD_EXPERIENCE.md)
- docs/operations/home-router.md (moved from PROJECT.md)
- setup.sh
- patches/0001-add-an8855-target.patch
- patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts
- patches/VERIFIED_COMMIT

## Tech Stack

- OpenWrt main (kernel ≈ 6.18)
- MediaTek MT7981 (Filogic 820) / Airoha AN8855
- Bash build orchestration
- Mermaid diagrams in README

## Conventions

- Conventional Commits for git history
- Bilingual README (English canonical + Chinese mirror)
- README = user onboarding; docs/development/guide.md = developer guide
- No duplication between README and docs/development/guide.md
- AGENT-MANAGED block at end of README files

## Unknowns

- Automated firmware testing not implemented
- Hardware test automation not implemented

## Verification Time

- Last verified: 2026-08-21
- Verified commit: 1c5eff5 (HEAD)

## Recommended Next Steps

1. Add firmware validation framework (hardware flash testing)
2. Consider adding hardware test automation
3. Configure branch protection rules on GitHub (require CI pass)
