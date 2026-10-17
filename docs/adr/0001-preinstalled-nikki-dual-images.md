# ADR 0001: preinstalled Nikki with separate recovery and full images

- Date: 2026-10-17
- Status: accepted

## Context

The stock-bootloader AN8855 target has a measured 26 MiB initramfs FIT limit.
Preinstalling Mihomo together with existing Tailscale functionality increases
userspace size. Disabling the size check risks an unbootable recovery image.
Users also need kernel modules from the same build, not unrelated official ABIs.

## Decision

Refresh the official Nikki `main` feed once per build and record its resolved
commit. Preinstall Nikki, stable Mihomo, Simplified Chinese LuCI support, ttyd
and its LuCI interface into the complete sysupgrade image. Retain Tailscale.
Keep Nikki disabled by default and retain upstream authenticated ttyd defaults.

Build the complete profile first. Save its sysupgrade, manifest, configuration,
build metadata and matching package archive before changing the rootfs profile.
Build a recovery profile with Nikki/Mihomo/yq/Tailscale userspace set to `m`,
keeping all kernel module selections. Check the kernel package/ABI is identical.
Publish only the full sysupgrade and the size-checked recovery initramfs.
Use distinct `full-`/`recovery-` prefixes and restore full config on exit.

## Consequences

Image assembly runs twice, but compiler/download caches and package builds are
reused. Recovery retains basic administration but is not a preinstalled proxy
environment. Builds fail closed on missing modules, leaked recovery packages,
ABI differences or oversized recovery FIT; they never fall back to forced
package dependencies or relaxed size checks. A conservative 100 MiB full-image
budget leaves room within the 112 MiB UBI partition but does not replace device
testing or pre-upgrade backups. Preserved user configuration is not overwritten.
