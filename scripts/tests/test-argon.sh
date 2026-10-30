#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/tests/firmware-fixture.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
firmware_sources "$WORK/tree"
LUCI="$WORK/tree/feeds/luci/modules/luci-base/root/etc/config/luci"
HOOK="$WORK/tree/package/luci-theme-argon/root/etc/uci-defaults/30_luci-theme-argon"
for pass in 1 2; do bash "$ROOT/scripts/configure-argon.sh" "$WORK/tree" full; done
grep -q "option mediaurlbase '/luci-static/argon'" "$LUCI"
grep -q "option lang 'auto'" "$LUCI"
! grep -q 'set luci.main.mediaurlbase' "$HOOK"
sh -n "$HOOK"
export CALLS="$WORK/calls"
# An unregistered theme must be registered without changing an existing choice.
for theme in bootstrap argon material; do
    : > "$CALLS"
    (
        uci() {
            case "$1" in
                get) return 1 ;;
                batch) cat >> "$CALLS" ;;
                *) echo "unexpected UCI call" >&2; exit 1 ;;
            esac
        }
        PKG_UPGRADE=0
        . "$HOOK"
    )
    grep -q 'set luci.themes.Argon=' "$CALLS"
    ! grep -q 'luci.main' "$CALLS"
    echo "ok: registering Argon does not override retained $theme/language"
done
bash "$ROOT/scripts/configure-argon.sh" "$WORK/tree" recovery
grep -q "option mediaurlbase '/luci-static/bootstrap'" "$LUCI"
bash "$ROOT/scripts/configure-argon.sh" "$WORK/tree" full
grep -q "option mediaurlbase '/luci-static/argon'" "$LUCI"
echo "ok: fresh full defaults to Argon; recovery defaults to Bootstrap"
