#!/bin/bash
# Change image defaults, never write the retained runtime UCI configuration.
set -euo pipefail
TREE="${1:?Usage: $0 <openwrt-dir> [full|recovery]}"
PROFILE="${2:-full}"
case "$PROFILE" in full) theme=argon ;; recovery) theme=bootstrap ;; *) exit 1 ;; esac
DEFAULTS="$TREE/package/luci-theme-argon/root/etc/uci-defaults/30_luci-theme-argon"
LUCI="$TREE/feeds/luci/modules/luci-base/root/etc/config/luci"
[ -f "$DEFAULTS" ] && [ -f "$LUCI" ] || {
    echo "Missing Argon/LuCI sources; run prepare-feeds.sh first" >&2; exit 1;
}
# Upstream registers Argon and selects it if the theme has not been registered.
# Retained Bootstrap/other selections must survive the first boot after upgrade.
sed -i '\|^[[:space:]]*set luci.main.mediaurlbase=/luci-static/argon$|d' "$DEFAULTS"
if ! grep -q "option mediaurlbase " "$LUCI"; then
    echo "Unrecognized LuCI theme default" >&2; exit 1
fi
sed -i "s|option mediaurlbase .*|option mediaurlbase '/luci-static/$theme'|" "$LUCI"
