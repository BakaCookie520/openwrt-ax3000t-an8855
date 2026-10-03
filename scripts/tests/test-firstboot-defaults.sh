#!/bin/bash
# Exercise the generated defaults without touching the host's configuration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TREE="$WORK/openwrt"
BASE="$TREE/package/base-files/files/etc"
mkdir -p "$BASE/uci-defaults" "$WORK/config"

bash "$ROOT/scripts/inject-firstboot-defaults.sh" "$TREE"

# Regression: the previous script issued UCI writes even after config restore.
export TEST_CALLS="$WORK/calls"
: > "$TEST_CALLS"
if [ -f "$BASE/uci-defaults/99-router-home-custom" ]; then
    (
        uci() {
            printf 'uci %s\n' "$*" >> "$TEST_CALLS"
            case "$*" in *get*) return 1 ;; esac
        }
        wifi() { printf 'wifi %s\n' "$*" >> "$TEST_CALLS"; }
        . "$BASE/uci-defaults/99-router-home-custom"
    )
fi
if [ -s "$TEST_CALLS" ]; then
    echo "FAIL: retained configuration would be overwritten"
    cat "$TEST_CALLS"
    exit 1
fi

HOOK="$BASE/board.d/99-router-home-custom"
[ -x "$HOOK" ] || { echo "FAIL: missing executable board defaults"; exit 1; }
[ ! -e "$BASE/uci-defaults/99-router-home-custom" ]
sh -n "$HOOK"

export TEST_HELPERS="$WORK/helpers"
cat > "$TEST_HELPERS" <<'EOF'
board_name() { printf '%s\n' "$TEST_BOARD"; }
board_config_update() { echo update >> "$TEST_CALLS"; }
board_config_flush() { echo flush >> "$TEST_CALLS"; }
ucidef_set_interface() { printf 'seed %s\n' "$*" >> "$TEST_CALLS"; }
uci() { echo "FAIL: board defaults must not write UCI" >&2; return 1; }
wifi() { echo "FAIL: board defaults must not reload Wi-Fi" >&2; return 1; }
EOF
# Replace only runtime library imports, using mocks for board JSON operations.
sed 's@^\. /lib/functions.*@. "$TEST_HELPERS"@' "$HOOK" > "$WORK/hook"

export TEST_BOARD='xiaomi,mi-router-ax3000t-an8855'
: > "$TEST_CALLS"
sh "$WORK/hook"
grep -qx 'seed lan ipaddr 192.168.31.1 netmask 255.255.255.0' "$TEST_CALLS"
[ "$(wc -l < "$TEST_CALLS")" -eq 3 ]
echo "ok: fresh AN8855 installation gets the LAN address seed"

# Retained settings must not be inspected, committed, or overwritten.
printf 'retained LAN, WPA2/WPA3, SSID and password\n' > "$WORK/config/network"
printf 'retained wireless configuration\n' > "$WORK/config/wireless"
cp -a "$WORK/config" "$WORK/original"
: > "$TEST_CALLS"
sh "$WORK/hook"
diff -r "$WORK/original" "$WORK/config"
! grep -Eq '^(uci|wifi) ' "$TEST_CALLS"
! grep -Eq '(^|[[:space:]])(uci|wifi)[[:space:]]' "$HOOK"
echo "ok: board seed never writes existing LAN or wireless configuration"

export TEST_BOARD='xiaomi,mi-router-ax3000t'
: > "$TEST_CALLS"
sh "$WORK/hook"
[ ! -s "$TEST_CALLS" ]
echo "ok: other targets are unchanged"

# Reusing a build tree must remove the old, unsafe uci-defaults payload.
printf 'unsafe legacy defaults\n' > "$BASE/uci-defaults/99-router-home-custom"
cp "$HOOK" "$WORK/original-hook"
bash "$ROOT/scripts/inject-firstboot-defaults.sh" "$TREE"
[ ! -e "$BASE/uci-defaults/99-router-home-custom" ]
cmp "$HOOK" "$WORK/original-hook"
echo "ok: reinjection is idempotent and removes legacy defaults"

# Local builds must use the same generator as Actions, not a stale inline copy.
awk '
    /=== 步骤 6:/ { found=1 }
    found && /^if \[ "\$BUILD_MODE"/ { exit }
    found { print }
' "$ROOT/setup.sh" > "$WORK/local-default-step"
SCRIPT_DIR="$ROOT/scripts" OPENWRT_DIR="$TREE" bash -e "$WORK/local-default-step"
[ ! -e "$BASE/uci-defaults/99-router-home-custom" ]
cmp "$HOOK" "$WORK/original-hook"
echo "ok: local builds use the same safe board defaults as Actions"
