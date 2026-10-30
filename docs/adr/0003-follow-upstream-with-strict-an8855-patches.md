# ADR 0003: Follow upstream main with strict AN8855 patches

- Date: 2026-10-30
- Status: accepted

## Context

The previous workflow cloned main and immediately checked out the historical
`VERIFIED_COMMIT`. Its success-only pin updater therefore could not advance the
source revision. Separately, stable v25.12.6 has an extra device at the end of
the single-UBI upgrade group, so the old patch failed on its terminal context
despite the upgrade handler retaining the required behavior.

## Decision

Local setup and mainline Actions share `scripts/checkout-openwrt-main.sh`.
Clone main for new trees; fetch and resolve `origin/main` for existing trees.
Never force-overwrite tracked edits or silently fall back to an older source
when fetch/update fails. If main advanced and a reused patched tree is dirty,
the user must preserve edits and provide a clean checkout. Each invocation
selects one revision before applying patches; compilation never follows a
moving branch. Run mainline CI daily at 02:00 UTC as well as on existing push,
PR and manual triggers. This is scheduled polling, not an upstream webhook.

Retain `patches/VERIFIED_COMMIT` as historical reference only. Remove the
success-only script that pushed directly to master. Record the actual source
SHA in the existing `BUILD-INFO.txt` artifact instead. Builds only need read
access to this repository.

Insert AN8855 at the beginning of the existing single-UBI upgrade device group
instead of replacing its last device. Keep all upstream entries intact.
Use zero-fuzz patch preflight/application in local setup and both Actions
workflows. Keep source, target, single-UBI, upgrade, NFC/I2C, manifest, size and
dual-image ABI gates. Never substitute stock/ubootmod targets or publish an
unvalidated image.

## Consequences

The patch tolerates device additions at the end of this group and line offsets,
not arbitrary future semantic changes. Mainline or stable upstream changes may
still require a reviewed patch update. Failure is visible rather than hidden
by pinning old source. Daily mainline builds may build an unchanged revision;
stable keeps its independent monthly/manual workflow and dynamic tag resolution.

Offline regressions exercise the actual patch through all three entry points
with original, stable-extra-device and future-extra-device fixtures. They
verify preservation of upstream entries and refusal of incompatible context.
Local Git remote tests cover source advancement, retained local edits, staged
changes and fetch failure. Passing these checks or upstream patch dry-runs
does not establish cross-compile success, image size, bootability or NFC
hardware operation.
