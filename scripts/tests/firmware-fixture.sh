#!/bin/bash
# Minimal valid sources for offline firmware contract tests.
firmware_sources() {
    local tree="$1"
    local mediatek="$tree/target/linux/mediatek"
    mkdir -p "$mediatek"/{dts,image,filogic/base-files/lib/upgrade} \
        "$tree/package/luci-theme-argon/root/etc/uci-defaults" \
        "$tree/package/luci-theme-argon/po/zh_Hans" \
        "$tree/feeds/luci/modules/luci-base/root/etc/config"
    printf 'msgid "Argon Config"\nmsgstr "Argon 主题设置"\n' \
        > "$tree/package/luci-theme-argon/po/zh_Hans/argon-config.po"
    cat > "$mediatek/image/filogic.mk" <<'EOF'
define Device/xiaomi_mi-router-ax3000t-an8855
  DEVICE_DTS := mt7981b-xiaomi-mi-router-ax3000t-an8855
endef
EOF
    cat > "$mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts" <<'EOF'
/dts-v1/;
#include "common.dtsi"
/ { compatible = "xiaomi,mi-router-ax3000t-an8855"; };
&partitions {
    partition@600000 { label = "ubi"; reg = <0x600000 0x7000000>; };
};
EOF
    cat > "$mediatek/dts/common.dtsi" <<'EOF'
&i2c0 {
    status = "okay";
    nfc@57 { compatible = "nt082c"; reg = <0x57>; };
};
EOF
    cat > "$mediatek/filogic/base-files/lib/upgrade/platform.sh" <<'EOF'
case "$board" in
    xiaomi,mi-router-ax3000t-an8855)
        CI_UBIPART="ubi"
        nand_do_upgrade "$1"
        ;;
esac
EOF
    printf 'CONFIG_I2C=y\nCONFIG_I2C_CHARDEV=y\nCONFIG_I2C_MT65XX=y\n' \
        > "$mediatek/filogic/config-test"
    cat > "$tree/package/luci-theme-argon/root/etc/uci-defaults/30_luci-theme-argon" <<'EOF'
#!/bin/sh
if [ "$PKG_UPGRADE" != 1 ]; then
    uci get luci.themes.Argon >/dev/null 2>&1 || \
    uci batch <<-UCI
        set luci.themes.Argon=/luci-static/argon
        set luci.main.mediaurlbase=/luci-static/argon
        commit luci
UCI
fi
exit 0
EOF
    printf "config core 'main'\n\toption lang 'auto'\n\toption mediaurlbase '/luci-static/bootstrap'\n" \
        > "$tree/feeds/luci/modules/luci-base/root/etc/config/luci"
}

firmware_config() {
    cat > "$1/.config" <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y
EOF
}
