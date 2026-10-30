#!/bin/bash
# ============================================================
# 一键构建脚本 - Xiaomi Mi Router AX3000T (AN8855)
#
# 本脚本基于 OpenWrt 主线 (main, ~内核 6.18) 编译。
#
# 重要变化:
#   * 主线 OpenWrt 已原生支持 AN8855 交换芯片 (驱动),但**没有**独立的
#     an8855 启动布局目标,必须手工重建单 UBI 目标
#     (xiaomi_mi-router-ax3000t-an8855)。patches/ 里的补丁会自动打上。
#   * 原厂 U-Boot + AN8855 只能用**单 UBI 布局**才能持久启动;
#     官方 stock 双分区目标 (xiaomi_mi-router-ax3000t) 在本机会落回恢复页,
#     勿用。详见 docs/reference/router-state.md §0。
#   * 完整升级固件预装 Nikki/Mihomo 与 ttyd；精简恢复镜像不带大型 Go 服务。
#   * 无自定义 fwx 内核补丁,保持纯净主线。
#   * 自编译内核需使用同一次构建的匹配模块包,本脚本预置了**精简工具集**:
#     zram、iptables+nftables 双栈 + 核心 netfilter、wireguard/veth/tun 隧道、
#     QoS(cake/fq-pie)、ext4、tcpdump/conntrack/ipset/tc-full 等诊断工具。
#     原"完整工具集"含 179 个 kmod,使 initramfs-FIT 达 27.9MB,超过原厂 U-Boot
#     加载上限(26MB 可启动)导致反复 panic/复位,已精简以适配。
#
# 用法:
#   1) bash setup.sh                     # 只做克隆 + feeds + 配置 (main 分支)
#   2) bash setup.sh build               # 直接开始编译 (main 分支)
#   固定构建带 AN8855 补丁的主线；正式稳定版使用独立 Actions 工作流。
# ============================================================

set -euo pipefail

# 先做自身与依赖脚本的 bash 语法自检,语法错误第一时间失败,避免编到一半才崩。
bash -n "$0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash -n "${SCRIPT_DIR}/scripts/check-image-size.sh"

# ---- 参数解析:本地只构建带补丁的主线 ----
BRANCH="main"
BUILD_MODE=0
while [ $# -gt 0 ]; do
    case "$1" in
        build)
            BUILD_MODE=1
            shift
            ;;
        *)
            echo "  ❌ 未知参数: $1 (支持: build)" >&2
            exit 1
            ;;
    esac
done

export OPENWRT_DIR="$(pwd)/openwrt-ax3000t"
# 外层仓库的 patches/ 目录(含 an8855 目标补丁),相对本脚本所在目录推导
export REPO_PATCH_DIR="$(cd "$(dirname "$0")" && pwd)/patches"
# 本仓库 scripts/ 目录(构建后体积校验等)
export SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/scripts"

# 锁定到一个已验证可编译的 main commit(防主线漂移导致补丁失效)。
# 值由 patches/VERIFIED_COMMIT 提供;置空则跟随 main 最新(不推荐)。
# 切换/更新:构建前把新 sha 写进 patches/VERIFIED_COMMIT 并在 dry-run 全过后再 build。
if [ -f "$REPO_PATCH_DIR/VERIFIED_COMMIT" ]; then
    # 取第一行非空、非 # 注释行作为 commit sha
    OPENWRT_COMMIT="$(grep -vE '^\s*(#|$)' "$REPO_PATCH_DIR/VERIFIED_COMMIT" | head -n1 | tr -d '[:space:]' || true)"
else
    OPENWRT_COMMIT=""
fi

echo ""
echo "=== 步骤 1: 克隆 OpenWrt (分支: $BRANCH) ==="
if [ ! -d "$OPENWRT_DIR" ]; then
    git clone --depth 1 --branch "$BRANCH" --single-branch \
        https://git.openwrt.org/openwrt/openwrt.git "$OPENWRT_DIR"
fi
# VERIFIED_COMMIT 记录主线已验证提交；本地不再提供跳过锁定或补丁的分支入口。
if [ -n "$OPENWRT_COMMIT" ]; then
    echo "  锁定到已验证 commit: $OPENWRT_COMMIT"
    git -C "$OPENWRT_DIR" fetch --depth 1 origin "$OPENWRT_COMMIT" \
        || { echo "  无法获取 commit $OPENWRT_COMMIT,检查 patches/VERIFIED_COMMIT" >&2; exit 1; }
    git -C "$OPENWRT_DIR" checkout --force "$OPENWRT_COMMIT"
else
    echo "  ⚠️ 未设置 OPENWRT_COMMIT(patches/VERIFIED_COMMIT 缺失),跟随 main 最新,补丁可能漂移失效。"
fi

cd "$OPENWRT_DIR"

echo ""
echo "=== 步骤 2: 准备 Nikki / Argon / 本地软件包 feed 配置 ==="
# Feeds are refreshed after applying board patches (step 3).
echo ""
echo "=== 步骤 2.5: 应用 an8855 单 UBI 目标补丁(仅 main 分支,关键!) ==="
# 主线 main 只有 stock 双分区 / ubootmod 目标,AN8855 + 原厂 U-Boot 需要
# 独立的单 UBI 目标才能持久启动。补丁文件固化在外层仓库 patches/ 下。
# 若已应用(设备已在 filogic.mk 中定义)则跳过,避免重复打补丁报错。
if grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
    echo "  an8855 目标已存在,跳过打补丁"
else
    echo "  复制 DTS ..."
    cp "${REPO_PATCH_DIR}/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts" \
       target/linux/mediatek/dts/
    echo "  应用 filogic.mk / platform.sh / 02_network 补丁 ..."
    # 先 dry-run 全量校验,任一 hunk 不匹配(主线已漂移)则整体失败并给友好提示,
    # 避免编到一半才因补丁问题崩溃。
    for p in "${REPO_PATCH_DIR}"/*.patch; do
        echo "    dry-run: $(basename "$p")"
        if ! patch -p1 --forward --no-backup-if-mismatch --dry-run -i "$p"; then
            echo "  ❌ 补丁 $(basename "$p") 无法应用:main 已漂移。" >&2
            echo "     方案A: 把 main 锁定到 patches/VERIFIED_COMMIT 里的已验证 commit。" >&2
            echo "     方案B: 手工修此补丁后重试。" >&2
            exit 1
        fi
    done
    for p in "${REPO_PATCH_DIR}"/*.patch; do
        patch -p1 --forward --no-backup-if-mismatch -i "$p"
    done
    echo "  已应用 an8855 目标补丁"
    # 应用后显式校验关键符号确实出现,防止"看似成功实则没生效"。
    if ! grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
        echo "  ❌ 应用后 filogic.mk 未出现 an8855 目标,补丁未真正生效。" >&2
        exit 1
    fi
    if ! grep -q "xiaomi,mi-router-ax3000t-an8855" target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh; then
        echo "  ❌ 应用后 platform.sh 未出现 an8855 升级入口,补丁未真正生效。" >&2
        exit 1
    fi
    echo "  补丁生效校验通过。"
fi

# Remove only this repository's known legacy patch backup, also on reused trees.
rm -f target/linux/mediatek/filogic/base-files/etc/board.d/02_network.orig
bash "${SCRIPT_DIR}/check-board-scripts.sh" "$OPENWRT_DIR"

echo ""
echo "=== 步骤 3: 校验 AN8855 源码并安装 feeds ==="
python3 "${SCRIPT_DIR}/check-an8855.py" --source-only "$OPENWRT_DIR"
bash "${SCRIPT_DIR}/prepare-feeds.sh" "$OPENWRT_DIR"

echo ""
echo "=== 步骤 4: 生成默认配置 ==="
make defconfig

echo ""
echo "=== 步骤 5: 预置 AN8855 目标 + 中文 Argon + xinfc + LuCI ==="
# 用标准 Kconfig 符号种子化 .config,再 defconfig 让它自动补全依赖。
# (符号名遵循 OpenWrt metadata 约定:
#    CONFIG_TARGET_<target>_<subtarget>_DEVICE_<device>)
# 先清掉可能已存在的相关行,避免 "key 多次定义" 警告/被覆盖。
# 清空我们即将写入的全部符号,确保脚本可重复执行(多次运行不产生重复 key)。
for s in \
    TARGET_mediatek TARGET_mediatek_filogic \
    TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855 \
    VERSIONOPT VERSION_REPO \
    PACKAGE_luci PACKAGE_luci-ssl LUCI_LANG_zh_Hans \
    PACKAGE_luci-compat PACKAGE_luci-lua-runtime \
    PACKAGE_luci-mod-dsl PACKAGE_luci-i18n-dsl-zh-cn \
    PACKAGE_luci-app-nlbwmon \
    PACKAGE_tailscale PACKAGE_luci-app-tailscale-community \
    PACKAGE_iptables PACKAGE_iptables-nft PACKAGE_ip6tables-nft \
    PACKAGE_xtables-legacy PACKAGE_xtables-nft \
    PACKAGE_iptables-mod-extra PACKAGE_iptables-mod-conntrack-extra \
    PACKAGE_iptables-mod-ipopt PACKAGE_iptables-mod-iprange \
    PACKAGE_iptables-mod-filter PACKAGE_iptables-mod-hashlimit \
    PACKAGE_iptables-mod-nat-extra PACKAGE_iptables-mod-trace \
    PACKAGE_iptables-mod-u32 PACKAGE_iptables-mod-ipset \
    PACKAGE_kmod-ipt-core PACKAGE_kmod-ipt-extra \
    PACKAGE_kmod-ipt-nat PACKAGE_kmod-ipt-nat-extra PACKAGE_kmod-ipt-nat6 \
    PACKAGE_kmod-ipt-conntrack PACKAGE_kmod-ipt-conntrack-extra \
    PACKAGE_kmod-ipt-conntrack-label PACKAGE_kmod-ipt-ipopt \
    PACKAGE_kmod-ipt-iprange PACKAGE_kmod-ipt-filter \
    PACKAGE_kmod-ipt-hashlimit PACKAGE_kmod-ipt-ipset \
    PACKAGE_kmod-ipt-offload PACKAGE_kmod-ipt-raw PACKAGE_kmod-ipt-raw6 \
    PACKAGE_kmod-ipt-u32 PACKAGE_kmod-ipt-physdev \
    PACKAGE_kmod-ipt-rpfilter PACKAGE_kmod-ipt-socket \
    PACKAGE_kmod-ipt-tee PACKAGE_kmod-ipt-tproxy \
    PACKAGE_kmod-ipt-checksum PACKAGE_kmod-ipt-led \
    PACKAGE_kmod-ipt-nflog PACKAGE_kmod-ipt-nfqueue \
    PACKAGE_kmod-ipt-cluster PACKAGE_kmod-ipt-ipsec \
    PACKAGE_kmod-ipt-debug \
    PACKAGE_kmod-nft-bridge PACKAGE_kmod-nft-compat \
    PACKAGE_kmod-nft-connlimit PACKAGE_kmod-nft-queue \
    PACKAGE_kmod-nft-socket PACKAGE_kmod-nft-dup-inet \
    PACKAGE_kmod-nft-netdev PACKAGE_kmod-nft-xfrm PACKAGE_kmod-nft-arp \
    PACKAGE_kmod-nf-nat6 PACKAGE_kmod-nf-ipt PACKAGE_kmod-nf-ipt6 \
    PACKAGE_kmod-nf-ipvs PACKAGE_kmod-nf-ipvs-ftp PACKAGE_kmod-nf-ipvs-sip \
    PACKAGE_kmod-nf-nathelper \
    PACKAGE_kmod-nf-nathelper-amanda PACKAGE_kmod-nf-nathelper-broadcast \
    PACKAGE_kmod-nf-nathelper-extra PACKAGE_kmod-nf-nathelper-h323 \
    PACKAGE_kmod-nf-nathelper-irc PACKAGE_kmod-nf-nathelper-netbios \
    PACKAGE_kmod-nf-nathelper-pptp PACKAGE_kmod-nf-nathelper-sane \
    PACKAGE_kmod-nf-nathelper-sip PACKAGE_kmod-nf-nathelper-snmp \
    PACKAGE_kmod-nf-nathelper-tftp PACKAGE_kmod-nf-conncount \
    PACKAGE_kmod-nf-socket PACKAGE_kmod-nf-dup-inet \
    PACKAGE_kmod-nfnetlink-cthelper PACKAGE_kmod-nfnetlink-cttimeout \
    PACKAGE_kmod-nfnetlink-log PACKAGE_kmod-nfnetlink-queue \
    PACKAGE_kmod-gre PACKAGE_kmod-gre6 PACKAGE_kmod-ipip \
    PACKAGE_kmod-sit PACKAGE_kmod-ip6-tunnel PACKAGE_kmod-ip-vti \
    PACKAGE_kmod-ip6-vti PACKAGE_kmod-iptunnel4 PACKAGE_kmod-iptunnel6 \
    PACKAGE_kmod-vxlan PACKAGE_kmod-geneve PACKAGE_kmod-fou \
    PACKAGE_kmod-fou6 PACKAGE_kmod-udptunnel4 PACKAGE_kmod-udptunnel6 \
    PACKAGE_kmod-wireguard PACKAGE_kmod-veth PACKAGE_kmod-l2tp \
    PACKAGE_kmod-l2tp-eth PACKAGE_kmod-l2tp-ip PACKAGE_kmod-pppol2tp \
    PACKAGE_kmod-ppp-synctty PACKAGE_kmod-bonding PACKAGE_kmod-team \
    PACKAGE_kmod-team-mode-activebackup PACKAGE_kmod-team-mode-broadcast \
    PACKAGE_kmod-team-mode-loadbalance PACKAGE_kmod-team-mode-random \
    PACKAGE_kmod-team-mode-roundrobin PACKAGE_kmod-macsec \
    PACKAGE_kmod-mpls PACKAGE_kmod-vrf PACKAGE_kmod-sctp \
    PACKAGE_kmod-tcp-bbr PACKAGE_kmod-tcp-hybla PACKAGE_kmod-tcp-scalable \
    PACKAGE_kmod-netem PACKAGE_kmod-ipsec PACKAGE_kmod-ipsec4 \
    PACKAGE_kmod-ipsec6 PACKAGE_kmod-xfrm-interface \
    PACKAGE_kmod-sched-core PACKAGE_kmod-sched-cake \
    PACKAGE_kmod-sched-fq-pie PACKAGE_kmod-sched-skbprio \
    PACKAGE_kmod-sched-flower PACKAGE_kmod-sched-bpf \
    PACKAGE_kmod-sched-pie PACKAGE_kmod-sched-red \
    PACKAGE_kmod-sched-prio PACKAGE_kmod-sched-drr \
    PACKAGE_kmod-sched-mqprio PACKAGE_kmod-sched-mqprio-common \
    PACKAGE_kmod-sched-ctinfo PACKAGE_kmod-sched-connmark \
    PACKAGE_kmod-sched-ipset PACKAGE_kmod-sched-act-vlan \
    PACKAGE_kmod-sched-act-police PACKAGE_kmod-sched-act-sample \
    PACKAGE_kmod-fs-ext4 PACKAGE_kmod-fs-f2fs PACKAGE_kmod-fs-exfat \
    PACKAGE_kmod-fs-vfat PACKAGE_kmod-fs-msdos PACKAGE_kmod-fs-ntfs3 \
    PACKAGE_kmod-fs-isofs PACKAGE_kmod-fs-hfsplus PACKAGE_kmod-fs-udf \
    PACKAGE_kmod-fs-configfs PACKAGE_kmod-fs-exportfs \
    PACKAGE_kmod-fs-btrfs PACKAGE_kmod-fs-xfs \
    PACKAGE_kmod-usb-storage PACKAGE_kmod-usb-storage-uas \
    PACKAGE_kmod-usb-storage-extras PACKAGE_kmod-usb-printer \
    PACKAGE_kmod-usb-serial PACKAGE_kmod-usb-serial-ch341 \
    PACKAGE_kmod-usb-serial-ftdi PACKAGE_kmod-usb-serial-cp210x \
    PACKAGE_kmod-usb-serial-pl2303 PACKAGE_kmod-usb-serial-option \
    PACKAGE_kmod-usb-serial-wwan PACKAGE_kmod-usb-net-cdc-eem \
    PACKAGE_kmod-usb-net-cdc-ether PACKAGE_kmod-usb-net-cdc-mbim \
    PACKAGE_kmod-usb-net-cdc-ncm PACKAGE_kmod-usb-net-cdc-subset \
    PACKAGE_kmod-usb-net-huawei-cdc-ncm PACKAGE_kmod-usb-gadget \
    PACKAGE_kmod-usb-gadget-eth PACKAGE_kmod-usb-gadget-serial \
    PACKAGE_kmod-usb-gadget-mass-storage \
    PACKAGE_kmod-nls-cp437 PACKAGE_kmod-nls-cp850 PACKAGE_kmod-nls-cp852 \
    PACKAGE_kmod-nls-cp866 PACKAGE_kmod-nls-cp932 PACKAGE_kmod-nls-cp936 \
    PACKAGE_kmod-nls-cp950 PACKAGE_kmod-nls-iso8859-1 \
    PACKAGE_kmod-nls-iso8859-15 PACKAGE_kmod-nls-utf8 \
    PACKAGE_kmod-nls-ucs2-utils \
    PACKAGE_kmod-softdog PACKAGE_kmod-mtdoops PACKAGE_kmod-fixed-phy \
    PACKAGE_kmod-phylink PACKAGE_kmod-of-mdio PACKAGE_kmod-input-evdev \
    PACKAGE_kmod-input-gpio-keys PACKAGE_kmod-input-gpio-keys-polled \
    PACKAGE_kmod-input-uinput PACKAGE_kmod-leds-pwm PACKAGE_kmod-leds-uleds \
    PACKAGE_kmod-zram PACKAGE_zram-swap \
    PACKAGE_conntrack PACKAGE_conntrackd PACKAGE_ipset \
    PACKAGE_ip-full PACKAGE_tc-full PACKAGE_ip-bridge \
    PACKAGE_tcpdump PACKAGE_iperf3 PACKAGE_ethtool PACKAGE_mtr-json \
    PACKAGE_nlbwmon PACKAGE_curl PACKAGE_wget-ssl PACKAGE_nano \
    PACKAGE_openssl-util PACKAGE_openssh-client PACKAGE_coreutils \
    PACKAGE_htop PACKAGE_iftop; do
    sed -i "/^CONFIG_$s=/d; /^# CONFIG_${s} is not set\$/d" .config
done
bash "${SCRIPT_DIR}/apply-build-profile.sh" "$OPENWRT_DIR" full

echo ""
echo "  已自动选中:"
echo "    Target Profile -> Xiaomi Mi Router AX3000T (AN8855, 单 UBI, 原厂 U-Boot)"
echo "    LuCI (+ SSL,中文)"
echo "    完整版预装 Nikki/Mihomo、ttyd、Tailscale、中文 Argon 和 xinfc；恢复版保持精简"
echo "    zram 内存压缩 / iptables+nftables 双栈 / 核心 netfilter / wireguard 隧道 / QoS(cake/fq-pie)"
echo "    tcpdump / conntrack / ipset / tc-full / ext4 / 诊断工具 (精简版,适配原厂 U-Boot 体积上限)"
echo ""
echo "  如需调整运行: make menuconfig"

echo ""
echo "=== 步骤 6: 注入新安装板级默认值(保留升级配置) ==="
bash "${SCRIPT_DIR}/inject-firstboot-defaults.sh" "$OPENWRT_DIR"
echo "  新安装: LAN=192.168.31.1, WiFi 默认禁用；升级不覆盖已有配置。"

if [ "$BUILD_MODE" = "1" ]; then
    echo "=== 步骤 7: 构建完整升级镜像和精简恢复镜像 ==="
    bash "${SCRIPT_DIR}/build-firmware.sh" "$OPENWRT_DIR"
else
    echo "准备完成。构建双镜像请执行:"
    echo "  bash ${SCRIPT_DIR}/build-firmware.sh $OPENWRT_DIR"
fi
