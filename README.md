# OpenWrt AX3000T (AN8855)

**简体中文（默认）** | [English](README.en.md)

![持续集成](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/actions/workflows/ci.yml/badge.svg)
![发布](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/actions/workflows/release.yml/badge.svg)
![许可证](https://img.shields.io/badge/license-GPL--2.0-blue.svg)

为搭载 AN8855 交换芯片的小米 AX3000T 构建可复现的 OpenWrt 固件。
项目使用适配原厂 U-Boot 的单 UBI 固件布局，内置 Tailscale，并将 OpenClash
作为独立 APK 发布，避免 initramfs 超过引导程序的加载体积限制。

## 重要警告

本固件仅适用于 **AX3000T AN8855 硬件版本**，请勿刷入其他 AX3000T 硬件版本。
AN8855 目标使用单 UBI 布局；标准双分区目标可能导致设备进入恢复模式或无法持久启动。
刷机可能永久损坏路由器，操作前请确认硬件型号，并准备好恢复方案。

## 支持的构建

| 构建类型 | 源码分支／版本 | 目标处理方式 |
| --- | --- | --- |
| 主线开发快照 | `master` | 应用本仓库 AN8855 补丁，并锁定到 `patches/VERIFIED_COMMIT`。 |
| OpenWrt 24.10 开发快照 | `openwrt-24.10` | 使用上游 AN8855 目标，不应用本仓库补丁。 |
| 最新正式稳定版 | `stable-latest` | 构建时动态选择版本号最高的非预发布 OpenWrt 标签，并应用本仓库 AN8855 补丁。 |

固件包含 Tailscale、LuCI、`luci-compat`、网络与诊断工具、WireGuard、
QoS 模块、zram，以及精简的文件系统与内核模块。OpenClash 单独构建为 APK。

GitHub Actions 并行构建两个开发快照版本。稳定版使用独立工作流，
每次动态解析最新正式版本，不固定到某个发布标签。

## 快速开始

### 环境要求

- Linux x86_64 或 WSL2
- 至少 8 GB 内存和 80 GB 可用磁盘空间
- Bash、Git 和可用的 OpenWrt 构建环境
- 可选：配置代理以改善下载速度：
  `export ALL_PROXY=socks5h://host:port`

### 准备源码与构建

```sh
git clone https://github.com/HughZadora/openwrt-ax3000t-an8855.git
cd openwrt-ax3000t-an8855

# 准备源码、feeds 和配置。
bash setup.sh

# 或一次完成准备和编译。
bash setup.sh build
```

构建 OpenWrt 24.10：

```sh
bash setup.sh --branch openwrt-24.10 build
```

首次完整构建可能耗时数小时，并占用较多磁盘空间。

## 构建产物

固件镜像输出目录：

```text
openwrt-ax3000t/bin/targets/mediatek/filogic/
```

常见产物：

- `*-initramfs-factory.ubi`：用于临时内存系统启动的镜像；
- `*-squashfs-sysupgrade.bin`：用于持久安装和升级的镜像；
- `*-initramfs.itb`：需通过 26 MiB 体积限制检查的 initramfs 镜像。

OpenClash 软件包输出路径：

```text
openwrt-ax3000t/bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash_<version>_<arch>.apk
```

文件名中的下划线是 OpenWrt APK 构建器生成的软件包命名格式，并非拼写错误。

## 刷机与升级

首次安装或迁移分区布局时，先刷入 initramfs，再进行持久 sysupgrade。
**以下流程不保留现有配置。**

```sh
# 在原厂或恢复系统中执行。
scp openwrt-*-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'mtd -f write /tmp/openwrt-*-initramfs-factory.ubi ubi && reboot'

# 路由器启动进入内存系统后执行。
scp openwrt-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin'
```

相同 AN8855 单 UBI 布局的后续升级，可直接在 LuCI 上传
`*-squashfs-sysupgrade.bin`，并勾选 **保留当前配置**；
或执行 `sysupgrade /tmp/<image>-squashfs-sysupgrade.bin`，不要添加 `-n`。
升级前请下载配置备份。保留配置不等于保留后装的软件包，
升级后仍需重新安装与新固件兼容的软件。

新安装默认 LAN 地址为 `192.168.31.1`，Wi-Fi 默认禁用。
板级默认值不会在升级时覆盖保留的 LAN、SSID、加密方式或密码。
首次启动后请设置 root 密码，并在启用 Wi-Fi 前配置加密。
OpenClash 需单独安装：

```sh
scp luci-app-openclash_*.apk root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'apk add /tmp/luci-app-openclash_*.apk luci-compat'
```

## 仓库结构

```text
patches/                             AN8855 补丁和已验证的源码提交
setup.sh                             构建入口
scripts/check-image-size.sh          initramfs 体积检查
scripts/check-board-scripts.sh       板级脚本备份安全检查
scripts/generate-config-seed.sh      可复现的软件包／配置种子
scripts/inject-firstboot-defaults.sh  新安装的板级默认值
openwrt-ax3000t/                     忽略提交的 OpenWrt 源码与构建目录
docs/                                开发与运维参考文档
.github/workflows/                   构建、发布和仓库检查
```

## 常用命令

| 任务 | 命令 |
| --- | --- |
| 准备源码 | `bash setup.sh` |
| 完整构建 | `bash setup.sh build` |
| 构建 OpenWrt 24.10 | `bash setup.sh --branch openwrt-24.10 build` |
| 配置软件包 | `cd openwrt-ax3000t && make menuconfig` |
| 编译 OpenClash | `cd openwrt-ax3000t && make package/feeds/openclash/luci-app-openclash/compile V=s` |
| 检查 initramfs 体积 | `scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic` |
| 检查板级脚本备份 | `bash scripts/check-board-scripts.sh openwrt-ax3000t` |
| 仓库基线检查 | `scripts/repository-check` |

## GitHub Actions

CI 工作流构建 `master` 和 `openwrt-24.10` 开发快照，
检查 initramfs 体积、编译 OpenClash，并上传固件和 APK 产物。
独立的 `stable-latest.yml` 工作流对最新 OpenWrt 正式稳定版执行同样的构建。
两个工作流均缓存下载文件和编译结果；GitHub Actions 产物保留 90 天。

`master` 固件构建成功后，semantic-release 根据约定式提交确定版本，
生成变更日志、创建标签，并发布包含已验证固件和 APK 的 GitHub Release。

## 限制与注意事项

- 原厂引导程序要求使用 AN8855 单 UBI 布局。
- initramfs FIT 镜像不得超过 26 MiB。
- OpenClash 特意不内置于固件镜像。
- 标准 AX3000T／MT7531 目标不能与本目标混用。
- OpenWrt 源码和构建产物属于本地忽略文件，不纳入仓库版本管理。

## 文档

- [开发指南](docs/development/guide.md)
- [路由器运维](docs/operations/home-router.md)
- [构建经验](docs/reports/build-experience.md)
- [路由器状态](docs/reference/router-state.md)

## 许可证

GPL-2.0，与 OpenWrt 保持一致。
