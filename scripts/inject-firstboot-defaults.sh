#!/bin/bash
# ============================================================
# Inject board defaults for new AX3000T-AN8855 installations
# Called from GitHub Actions CI workflow
# ============================================================

set -euo pipefail

OPENWRT_DIR="${1:?Usage: $0 <openwrt-dir>}"

BASE_ETC="$OPENWRT_DIR/package/base-files/files/etc"
BOARDDEF_DIR="$BASE_ETC/board.d"
mkdir -p "$BOARDDEF_DIR"

cat > "$BOARDDEF_DIR/99-router-home-custom" <<'EOF'
#!/bin/sh
# Seed board.json rather than write UCI settings after sysupgrade restores them.
# OpenWrt's config generator leaves an existing network configuration intact.
# Wi-Fi uses upstream defaults (disabled on a clean installation).
. /lib/functions/uci-defaults.sh

case "$(board_name)" in
    xiaomi,mi-router-ax3000t-an8855) ;;
    *) exit 0 ;;
esac

board_config_update
ucidef_set_interface "lan" ipaddr "192.168.31.1" netmask "255.255.255.0"
board_config_flush
exit 0
EOF

chmod +x "$BOARDDEF_DIR/99-router-home-custom"
# Reused build trees must not retain the old configuration-overwriting script.
rm -f "$BASE_ETC/uci-defaults/99-router-home-custom"
echo "Injected: $BOARDDEF_DIR/99-router-home-custom"
