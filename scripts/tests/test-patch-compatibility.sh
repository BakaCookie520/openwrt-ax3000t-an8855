#!/bin/bash
# Exercise the real patch through every entry point, not a reimplementation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SCRIPT_DIR="$ROOT/scripts"
export REPO_PATCH_DIR="$ROOT/patches"

fixture() {
    local variant="$2" mediatek="$1/target/linux/mediatek"
    mkdir -p "$mediatek"/{image,dts,filogic/base-files/etc/board.d,filogic/base-files/lib/upgrade}
    cat > "$mediatek/filogic/base-files/etc/board.d/02_network" <<'EOF'
#!/bin/sh
mediatek_setup_interfaces() {
	case "$board" in
	other,board)
		ucidef_set_interface_lan "lan1 lan2 eth1"
		;;
	xiaomi,mi-router-ax3000t|\
	xiaomi,mi-router-ax3000t-ubootmod|\
	xiaomi,mi-router-wr30u-stock|\
	xiaomi,mi-router-wr30u-ubootmod|\
	other,network)
		;;
	esac
}
mediatek_setup_macs() {
	case "$board" in
	other,mac)
		wan_mac="$(macaddr_add $lan_mac 1)"
		;;
	xiaomi,mi-router-ax3000t|\
	xiaomi,mi-router-ax3000t-ubootmod|\
	xiaomi,mi-router-wr30u-stock|\
	xiaomi,mi-router-wr30u-ubootmod|\
	other,network)
		;;
	esac
}
EOF
    cat > "$mediatek/filogic/base-files/lib/upgrade/platform.sh" <<'EOF'
platform_do_upgrade() {
	case "$board" in
	cudy,wr3000p-v1|\
	huasifei,wh3000-pro-nand|\
	huasifei,wh3000r-nand|\
EOF
    case "$variant" in
        main) printf '\tjiorouter,ax6000-jidu6101)\n' ;;
        stable) printf '\tjiorouter,ax6000-jidu6101|\\\n\tjiorouter,ax6000-jidu6j01)\n' ;;
        future) printf '\tjiorouter,ax6000-jidu6101|\\\n\tjiorouter,ax6000-jidu6j01|\\\n\tfuture,device)\n' ;;
    esac >> "$mediatek/filogic/base-files/lib/upgrade/platform.sh"
    cat >> "$mediatek/filogic/base-files/lib/upgrade/platform.sh" <<'EOF'
		CI_UBIPART="ubi"
		nand_do_upgrade "$1"
		;;
	esac
}
EOF
    cat > "$mediatek/image/filogic.mk" <<'EOF'
define Device/xiaomi_mi-router-ax3000t
endif
endef
TARGET_DEVICES += xiaomi_mi-router-ax3000t

define Device/xiaomi_mi-router-ax3000t-ubootmod
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router AX3000T (OpenWrt U-Boot layout)
endef
EOF
    cat > "$mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t.dtsi" <<'EOF'
&i2c0 {
	status = "okay";
	nfc@57 { compatible = "nt082c"; reg = <0x57>; };
};
EOF
}

for entry in ci stable-latest local; do
    if [ "$entry" = local ]; then
        awk '
            /=== 步骤 2.5:/ { found=1 }
            found && /=== 步骤 3:/ { exit }
            found { print }
        ' "$ROOT/setup.sh" > "$WORK/patch-step"
    else
        awk '
            /- name: Apply an8855 patches/ { found=1; next }
            found && /- name:/ { exit }
            found && /run: \|/ { code=1; next }
            code { sub(/^          /, ""); print }
        ' "$ROOT/.github/workflows/$entry.yml" > "$WORK/patch-step"
    fi
    grep -q -- '--fuzz=0' "$WORK/patch-step"
    for variant in main stable future; do
        export OPENWRT_DIR="$WORK/$entry-$variant"
        fixture "$OPENWRT_DIR" "$variant"
        platform="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
        cp "$platform" "$WORK/before"
        (cd "$OPENWRT_DIR"; bash -e "$WORK/patch-step") > "$WORK/output" 2>&1
        python3 "$SCRIPT_DIR/check-an8855.py" --source-only "$OPENWRT_DIR"
        sed '/xiaomi,mi-router-ax3000t-an8855/d' "$platform" > "$WORK/after"
        cmp "$WORK/before" "$WORK/after"
        [ "$(grep -c 'xiaomi,mi-router-ax3000t-an8855' \
            "$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network")" = 2 ]
        bash -n "$platform"
        (cd "$OPENWRT_DIR"; bash -e "$WORK/patch-step") > "$WORK/output" 2>&1
        [ "$(grep -c 'xiaomi,mi-router-ax3000t-an8855' "$platform")" = 1 ]
        echo "ok: $entry applies real patch to $variant, preserves existing devices and is repeatable"
        sed -i 's/CI_UBIPART="ubi"/CI_UBIPART="ubi_kernel"/' "$platform"
        if python3 "$SCRIPT_DIR/check-an8855.py" --source-only "$OPENWRT_DIR" > "$WORK/output" 2>&1; then
            echo "FAIL: source guard accepted a changed upgrade handler"; exit 1
        fi
        grep -q 'single-UBI upgrade handler is missing' "$WORK/output"
    done

    export OPENWRT_DIR="$WORK/$entry-drift"
    fixture "$OPENWRT_DIR" stable
    network="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
    sed -i 's/huasifei,wh3000-pro-nand/changed,upstream/' \
        "$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
    cp "$network" "$WORK/before"
    if (cd "$OPENWRT_DIR"; bash -e "$WORK/patch-step") > "$WORK/output" 2>&1; then
        echo "FAIL: $entry accepted incompatible context"; exit 1
    fi
    cmp "$network" "$WORK/before"
    if grep -q 'Device/xiaomi_mi-router-ax3000t-an8855' "$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"; then
        echo "FAIL: $entry partially applied a rejected patch"; exit 1
    fi
    echo "ok: $entry rejects real context drift before modifying patched sources"
done
