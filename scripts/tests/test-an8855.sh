#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/tests/firmware-fixture.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CHECK="$ROOT/scripts/check-an8855.py"
for scenario in valid wrong-target multi-target multi-profile missing-target dual-partition \
    wrong-size no-upgrade no-nfc no-i2c-controller disabled-i2c overridden-i2c deleted-nfc; do
    tree="$WORK/$scenario"
    firmware_sources "$tree"
    firmware_config "$tree"
    dts="$tree/target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts"
    case "$scenario" in
        wrong-target) sed -i 's/DEVICE_xiaomi_mi-router-ax3000t-an8855/DEVICE_xiaomi_mi-router-ax3000t/' "$tree/.config" ;;
        multi-target) echo 'CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-ubootmod=y' >> "$tree/.config" ;;
        multi-profile) echo 'CONFIG_TARGET_MULTI_PROFILE=y' >> "$tree/.config" ;;
        missing-target) : > "$tree/target/linux/mediatek/image/filogic.mk" ;;
        dual-partition) echo '&partitions { partition@2800000 { label = "ubi_kernel"; reg = <0x2800000 0x4e00000>; }; };' >> "$dts" ;;
        wrong-size) sed -i 's/0x7000000/0x4e00000/' "$dts" ;;
        no-upgrade) : > "$tree/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh" ;;
        no-nfc) sed -i 's/nt082c/unsupported/' "$tree/target/linux/mediatek/dts/common.dtsi" ;;
        no-i2c-controller) sed -i '/CONFIG_I2C_MT65XX/d' "$tree/target/linux/mediatek/filogic/config-test" ;;
        disabled-i2c) sed -i 's/"okay"/"disabled"/' "$tree/target/linux/mediatek/dts/common.dtsi" ;;
        overridden-i2c) echo '&i2c0 { status = "disabled"; };' >> "$dts" ;;
        deleted-nfc) echo '&i2c0 { /delete-node/ nfc@57; };' >> "$dts" ;;
    esac
    if [ "$scenario" = valid ]; then
        python3 "$CHECK" "$tree"
        python3 "$CHECK" --source-only "$tree"
    elif python3 "$CHECK" "$tree" > "$WORK/check.log" 2>&1; then
        echo "FAIL: unsafe configuration accepted: $scenario"; exit 1
    else
        grep -q 'AN8855 safety check failed' "$WORK/check.log"
        echo "ok: rejected $scenario"
    fi
done
