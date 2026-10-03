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
#   * 无自定义 fwx 内核补丁,保持纯净主线。
#   * OpenClash (luci-app-openclash) 以独立 apk 提供,不进固件(避免 initramfs
#     超过原厂 U-Boot 加载体积上限);装时 apk add 并自动拉 luci-compat 等依赖。
#   * 内核模块只能编译期打入(无法 apk 安装),本脚本预置了**精简工具集**:
#     zram、iptables+nftables 双栈 + 核心 netfilter、wireguard/veth/tun 隧道、
#     QoS(cake/fq-pie)、ext4、tcpdump/conntrack/ipset/tc-full 等诊断工具。
#     原"完整工具集"含 179 个 kmod,使 initramfs-FIT 达 27.9MB,超过原厂 U-Boot
#     加载上限(26MB 可启动)导致反复 panic/复位,已精简以适配。
#
# 用法:
#   1) bash setup.sh                     # 只做克隆 + feeds + 配置 (main 分支)
#   2) bash setup.sh build               # 直接开始编译 (main 分支)
#   3) bash setup.sh --branch openwrt-24.10 [build]
#                                        # 换分支编译;非 main 分支跳过补丁与 commit 锁定
#   (--branch 与 build 可任意顺序;默认 main,行为与旧版一致)
# ============================================================

set -e

# 先做自身与依赖脚本的 bash 语法自检,语法错误第一时间失败,避免编到一半才崩。
bash -n "$0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash -n "${SCRIPT_DIR}/scripts/check-image-size.sh"

# ---- 参数解析:支持 --branch <分支> 与位置参数 build,任意顺序 ----
BRANCH="main"
BUILD_MODE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --branch)
            [ $# -ge 2 ] || { echo "  ❌ --branch 需带分支名,示例: bash setup.sh --branch openwrt-24.10" >&2; exit 1; }
            BRANCH="$2"
            shift 2
            ;;
        --branch=*)
            BRANCH="${1#*=}"
            shift
            ;;
        build)
            BUILD_MODE=1
            shift
            ;;
        *)
            echo "  ❌ 未知参数: $1 (支持: build / --branch <分支>)" >&2
            exit 1
            ;;
    esac
done
if [ -z "$BRANCH" ]; then
    echo "  ❌ --branch 分支名为空" >&2
    exit 1
fi

export OPENWRT_DIR="$(pwd)/openwrt-ax3000t"
# 外层仓库的 patches/ 目录(含 an8855 目标补丁),相对本脚本所在目录推导
export REPO_PATCH_DIR="$(cd "$(dirname "$0")" && pwd)/patches"
# 本仓库 scripts/ 目录(构建后体积校验等)
export SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/scripts"
OPENCLASH_URL="https://github.com/vernesong/OpenClash.git"
OPENCLASH_CFG="src-git openclash ${OPENCLASH_URL}"

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
# commit 锁定仅对 main 生效(VERIFIED_COMMIT 记录的是 main 分支已验证 commit)。
# 其它分支(如 openwrt-24.10)历史不同,不能直接 checkout 该 sha,故跳过锁定。
if [ "$BRANCH" = "main" ] && [ -n "$OPENWRT_COMMIT" ]; then
    echo "  锁定到已验证 commit: $OPENWRT_COMMIT"
    git -C "$OPENWRT_DIR" fetch --depth 1 origin "$OPENWRT_COMMIT" \
        || { echo "  无法获取 commit $OPENWRT_COMMIT,检查 patches/VERIFIED_COMMIT" >&2; exit 1; }
    git -C "$OPENWRT_DIR" checkout --force "$OPENWRT_COMMIT"
elif [ "$BRANCH" = "main" ]; then
    echo "  ⚠️ 未设置 OPENWRT_COMMIT(patches/VERIFIED_COMMIT 缺失),跟随 main 最新,补丁可能漂移失效。"
else
    echo "  非 main 分支($BRANCH),跳过 commit 锁定与 an8855 补丁,跟随分支最新。"
fi

cd "$OPENWRT_DIR"

echo ""
echo "=== 步骤 2: 添加 OpenClash feed ==="
# 注意:必须把 feed 加到官方的 feeds.conf.default(含 luci/packages 等官方源),
# 而不是只新建 feeds.conf(那会让 OpenWrt 只认 feeds.conf 而丢掉官方源)。
if [ ! -f feeds.conf ]; then
    cp feeds.conf.default feeds.conf
fi
if ! grep -q "OpenClash" feeds.conf; then
    cat >> feeds.conf <<EOF
# OpenClash (Clash/Mihomo 客户端)
${OPENCLASH_CFG}
EOF
    echo "  已添加: ${OPENCLASH_CFG}"
else
    echo "  OpenClash feed 已存在,跳过"
fi

echo ""
echo "=== 步骤 2.5: 应用 an8855 单 UBI 目标补丁(仅 main 分支,关键!) ==="
# 主线 main 只有 stock 双分区 / ubootmod 目标,AN8855 + 原厂 U-Boot 需要
# 独立的单 UBI 目标才能持久启动。补丁文件固化在外层仓库 patches/ 下。
# 若已应用(设备已在 filogic.mk 中定义)则跳过,避免重复打补丁报错。
# 非 main 分支(如 openwrt-24.10)官方自带 an8855 单 UBI 目标,无需补丁,整体跳过。
if [ "$BRANCH" != "main" ]; then
    echo "  非 main 分支($BRANCH),官方自带 an8855 单 UBI 目标,跳过补丁应用"
elif grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
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
echo "=== 步骤 3: 更新并安装 feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

echo ""
echo "=== 步骤 4: 生成默认配置 ==="
make defconfig

echo ""
echo "=== 步骤 5: 预置本设备目标 + OpenClash + LuCI ==="
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
    PACKAGE_luci-app-openclash PACKAGE_luci-app-nlbwmon \
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
cat >> .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y

# 软件源(apk)镜像:换为中科大 USTC,国内下载快
# 注意:VERSION_* 挂在 VERSIONOPT 菜单下,必须先 CONFIG_VERSIONOPT=y 才会生效
CONFIG_VERSIONOPT=y
CONFIG_VERSION_REPO="https://mirrors.ustc.edu.cn/openwrt/snapshots"

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_LUCI_LANG_zh_Hans=y

# 剔除用不到的默认 LuCI 模块(路由器无用,保持菜单干净)
# CONFIG_PACKAGE_luci-mod-dsl is not set
# CONFIG_PACKAGE_luci-i18n-dsl-zh-cn is not set

# ⚠️ OpenClash 不再打进固件:其 apk 约 8MB(含 clash core),会使 initramfs-FIT
# 超过原厂 U-Boot 的加载体积上限(26MB 可启动,34MB 起不来)。改为单独编译成
# package,装时从 apk 源 `apk add luci-app-openclash` 即可。需要时在最后一步
# make package/.../compile 单独产出。
# ── 但 luci-compat(+luci-lua-runtime)必须保留:luci-base 渲染依赖其提供的
#    luci.ucodebridge 模块,缺失会报 "module 'luci.ucodebridge' not found"。
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y
# CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale-community=y


# ================= 工具集(精简版,控制体积以适配原厂 U-Boot) =================
# 背景:5a26684 一次性加了 179 个 kmod,initramfs-FIT 撑到 27.9MB,超过原厂
# U-Boot 加载上限(26MB 可启动,27.9MB 起不来,内核反复 panic/复位)。故只保留
# 核心常用模块,去掉重文件系统(btrfs/xfs/ntfs3 等)、USB 驱动、异类隧道/协议、
# 多余 sched 变体与启动高危项(mtdoops/softdog/phylink/of-mdio/fixed-phy),
# 使 initramfs 回到 26MB 以内。更多功能在 make menuconfig 按需勾选,或单独
# 编译为 apk 再装。
# --- zram:内存压缩 ---
CONFIG_PACKAGE_kmod-zram=y
CONFIG_PACKAGE_zram-swap=y

# --- 防火墙:iptables + nftables 双栈(fw4 默认 nftables) ---
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_ip6tables-nft=y
CONFIG_PACKAGE_xtables-legacy=y
CONFIG_PACKAGE_xtables-nft=y

# --- nftables/iptables 内核模块(核心,OpenClash 兼容/Tailscale 常用) ---
CONFIG_PACKAGE_kmod-ipt-core=y
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_kmod-ipt-conntrack=y
CONFIG_PACKAGE_kmod-ipt-ipset=y
CONFIG_PACKAGE_kmod-ipt-offload=y
CONFIG_PACKAGE_kmod-nft-bridge=y
CONFIG_PACKAGE_kmod-nft-compat=y
CONFIG_PACKAGE_kmod-nft-netdev=y
CONFIG_PACKAGE_kmod-nf-ipt=y
CONFIG_PACKAGE_kmod-nf-ipt6=y
CONFIG_PACKAGE_kmod-nf-nathelper=y
CONFIG_PACKAGE_kmod-nf-nathelper-extra=y
CONFIG_PACKAGE_kmod-nf-nathelper-pptp=y
CONFIG_PACKAGE_kmod-nf-nathelper-tftp=y
CONFIG_PACKAGE_kmod-nf-conncount=y

# --- 隧道/虚拟网卡(常用) ---
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-tcp-bbr=y

# --- QoS / tc(保留 cake/fq-pie,其余按需) ---
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-sched-fq-pie=y

# --- 文件系统(仅保留 ext4,重文件系统已剔除以控制体积) ---
CONFIG_PACKAGE_kmod-fs-ext4=y

# --- 连接跟踪 / IP 集 / 路由 / 流量工具 ---
CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ip-bridge=y
CONFIG_PACKAGE_tc-full=y

# --- 网络诊断/抓包 ---
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_mtr-json=y
CONFIG_PACKAGE_nlbwmon=y

# --- 基础实用工具 ---
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_openssl-util=y
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_iftop=y
EOF
make defconfig

echo ""
echo "  已自动选中:"
echo "    Target Profile -> Xiaomi Mi Router AX3000T (AN8855, 单 UBI, 原厂 U-Boot)"
echo "    LuCI (+ SSL,中文)"
echo "    OpenClash 仅单独编译为 apk(不进固件) / Tailscale + luci-app-tailscale-community"
echo "    zram 内存压缩 / iptables+nftables 双栈 / 核心 netfilter / wireguard 隧道 / QoS(cake/fq-pie)"
echo "    tcpdump / conntrack / ipset / tc-full / ext4 / 诊断工具 (精简版,适配原厂 U-Boot 体积上限)"
echo ""
echo "  如需调整运行: make menuconfig"

echo ""
echo "=== 步骤 6: 注入新安装板级默认值(保留升级配置) ==="
bash "${SCRIPT_DIR}/inject-firstboot-defaults.sh" "$OPENWRT_DIR"
echo "  新安装: LAN=192.168.31.1, WiFi 默认禁用；升级不覆盖已有配置。"

if [ "$BUILD_MODE" = "1" ]; then
    echo ""
    echo "=== 步骤 7: 开始编译(固件不含 OpenClash) ==="
    echo "  运行: make -j\$(nproc) V=s | tee build.log"
    bash "${SCRIPT_DIR}/check-board-scripts.sh" "$OPENWRT_DIR"
    make -j"$(nproc)" V=s 2>&1 | tee build.log

    echo ""
    echo "=== 步骤 7.5: initramfs 体积校验(原厂 U-Boot 上限) ==="
    TARGET_DIR="$OPENWRT_DIR/bin/targets/mediatek/filogic"
    bash "${SCRIPT_DIR}/check-board-scripts.sh" "$OPENWRT_DIR"
    STRICT=1 bash "${SCRIPT_DIR}/check-image-size.sh" "$TARGET_DIR" \
        || { echo "  ❌ initramfs 超限,停止 OpenClash 编译以避免在坏产物上继续。" >&2; exit 1; }

    echo ""
    echo "=== 步骤 8: 单独编译 OpenClash 为 apk(不进固件,装时 apk add) ==="
    echo "  运行: make package/feeds/openclash/luci-app-openclash/compile V=s"
    make package/feeds/openclash/luci-app-openclash/compile V=s 2>&1 | tee -a build.log
    # 校验 apk 确实生成
    APK_GLOB="$OPENWRT_DIR/bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash-*.apk"
    if ! ls $APK_GLOB >/dev/null 2>&1; then
        echo "  ❌ 未生成 OpenClash apk(路径:$APK_GLOB),请检查 openclash feed 是否安装成功。" >&2
        exit 1
    fi
    echo "  OpenClash apk 已生成:"
    ls -lh $APK_GLOB

    echo ""
    echo "=== 步骤 9: 产物汇总(体积校验 + sha256) ==="
    STRICT=1 bash "${SCRIPT_DIR}/check-image-size.sh" "$TARGET_DIR"
    echo ""
    echo "  OpenClash apk:"
    for f in $APK_GLOB; do
        printf "    %s  %s\n" "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")"
    done
    echo ""
else
    echo ""
    echo "============================================"
    echo "  准备完成!请执行:"
    echo "    make menuconfig   # 可微调软件包(目标已预置)"
    echo "    make -j\$(nproc) V=s | tee build.log"
    echo "============================================"
fi
