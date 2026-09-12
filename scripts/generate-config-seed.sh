#!/bin/bash
# ============================================================
# Generate .config seed for OpenWrt AX3000T-AN8855 build
# Called from GitHub Actions CI workflow
# ============================================================

set -euo pipefail

VERSION_REPO="${OPENWRT_VERSION_REPO:-https://mirrors.ustc.edu.cn/openwrt/snapshots}"

cat > .config.seed <<CONFIG_EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y

CONFIG_VERSIONOPT=y
CONFIG_VERSION_REPO="${VERSION_REPO}"

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_LUCI_LANG_zh_Hans=y

# CONFIG_PACKAGE_luci-mod-dsl is not set
# CONFIG_PACKAGE_luci-i18n-dsl-zh-cn is not set

CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y
# Build OpenClash as a standalone APK, but do not include it in the firmware image.
CONFIG_PACKAGE_luci-app-openclash=m
CONFIG_PACKAGE_luci-app-nlbwmon=y

CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale-community=y

CONFIG_PACKAGE_kmod-zram=y
CONFIG_PACKAGE_zram-swap=y

CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_ip6tables-nft=y
CONFIG_PACKAGE_xtables-legacy=y
CONFIG_PACKAGE_xtables-nft=y

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

CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-tcp-bbr=y

CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-sched-fq-pie=y

CONFIG_PACKAGE_kmod-fs-ext4=y

CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ip-bridge=y
CONFIG_PACKAGE_tc-full=y

CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_mtr-json=y
CONFIG_PACKAGE_nlbwmon=y

CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_openssl-util=y
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_iftop=y
CONFIG_EOF
