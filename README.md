# OpenWrt AX3000T (AN8855)

**简体中文（默认）** | [English](README.en.md)

![持续集成](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/actions/workflows/ci.yml/badge.svg)
![发布](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/actions/workflows/release.yml/badge.svg)
![许可证](https://img.shields.io/badge/license-GPL--2.0-blue.svg)

为搭载 AN8855 交换芯片的小米 AX3000T 构建可复现的 OpenWrt 固件。
项目使用适配原厂 U-Boot 的单 UBI 固件布局，生成两套产物：完整 sysupgrade
预装 Nikki、稳定版 Mihomo、中文管理界面、ttyd 和 Tailscale；精简 initramfs
用于恢复，严格保持在 26 MiB 内。完整固件另含 Argon 主题、主题设置中文翻译及 xinfc NFC 管理。

## 重要警告

本固件仅适用于 **AX3000T AN8855 硬件版本**，请勿刷入其他 AX3000T 硬件版本。
AN8855 目标使用单 UBI 布局；标准双分区目标可能导致设备进入恢复模式或无法持久启动。
刷机可能永久损坏路由器，操作前请确认硬件型号，并准备好恢复方案。

## 支持的构建

| 构建类型 | 源码分支／版本 | 目标处理方式 |
| --- | --- | --- |
| 主线开发快照 | `main` | 应用本仓库 AN8855 补丁，并锁定到 `patches/VERIFIED_COMMIT`。 |
| 最新正式稳定版 | `stable-latest` | 构建时动态选择版本号最高的非预发布 OpenWrt 标签，并应用本仓库 AN8855 补丁。 |

完整固件包含 Nikki/Mihomo、ttyd、Tailscale、中文 Argon、xinfc、LuCI、`luci-compat`、网络与诊断
工具、WireGuard、QoS、zram，以及 Nikki 所需的匹配内核模块。
每次构建通过官方 Nikki feed 的 `main` 分支更新源码，不使用本地下载的旧安装包；
Mihomo 使用该 feed 定义的稳定版本，而非 alpha。实际 Nikki 提交号记录在产物中。
精简恢复镜像不包含 Nikki/Mihomo、yq、Tailscale、Argon 或 xinfc，但保留 LuCI 和 ttyd。

GitHub Actions 仅保留带 AN8855 补丁的主线开发快照构建。稳定版使用独立工作流，
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

首次完整构建可能耗时数小时，并占用较多磁盘空间。

## 构建产物

固件镜像输出目录：

```text
openwrt-ax3000t/bin/targets/mediatek/filogic/
```

本地与 Actions 使用同一构建入口，验证后的产物输出到：

```text
openwrt-ax3000t/bin/ax3000t-artifacts/
```

- `full-*-squashfs-sysupgrade.bin`：日常使用的完整预装固件；已有同布局 OpenWrt 可直接升级。
- `recovery-*-initramfs-factory.ubi`：精简临时恢复系统，不是完整预装版。
- `recovery-*-initramfs-kernel.bin`／`.itb`：经过 26 MiB 安全检查的恢复 FIT。
- `packages.tar.gz`：同次构建的软件包与索引，包含 Nikki、Argon、xinfc 及匹配的内核模块。
  使用对应源码的原生 APK/IPK 格式，不混用包格式。
- `full.manifest`、`recovery.manifest`、对应 `.config` 和 `BUILD-INFO.txt`：包清单、配置与源码提交号。
- `SHA256SUMS.txt`：校验所有交付文件。

完整构建生成的较大 initramfs **不会发布**。完整 sysupgrade 另设保守的
100 MiB 文件体积上限，为 112 MiB UBI 分区预留余量；它不能替代用户刷机前的
镜像校验和备份。恢复镜像与完整镜像的 kernel 包版本／ABI 必须相同，否则停止发布。

输出目录必须为空；本地重复构建可通过第二个参数指定新的输出目录：

```sh
bash scripts/build-firmware.sh openwrt-ax3000t /path/to/new-artifacts
```

## 刷机与升级

首次安装或迁移分区布局时，先刷入 initramfs，再进行持久 sysupgrade。
**以下流程不保留现有配置。**

```sh
# 在原厂或恢复系统中执行。
scp recovery-*-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'mtd -f write /tmp/recovery-*-initramfs-factory.ubi ubi && reboot'

# 路由器启动进入内存系统后执行。
scp full-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'sysupgrade -n /tmp/full-*-squashfs-sysupgrade.bin'
```

相同 AN8855 单 UBI 布局的后续升级，可直接在 LuCI 上传
`*-squashfs-sysupgrade.bin`，并勾选 **保留当前配置**；
或执行 `sysupgrade /tmp/<image>-squashfs-sysupgrade.bin`，不要添加 `-n`。
升级前请下载配置备份。保留配置不等于保留后装的软件包，
升级后仍需重新安装与新固件兼容的软件。

新安装默认 LAN 地址为 `192.168.31.1`，Wi-Fi 默认禁用。
板级默认值不会在升级时覆盖保留的 LAN、SSID、加密方式或密码。
首次启动后请设置 root 密码，并在启用 Wi-Fi 前配置加密。
Nikki 预装但默认不启用代理，订阅和节点由用户自行配置。纯 AP 桥接模式下，
预装插件不等于自动接管无线客户端流量；代理拓扑需另行规划。

新安装的 ttyd 使用上游 `@lan` 绑定（自动解析到 LAN 桥）和 `/bin/login`，
不写入任何账号密码，也不使用免密 root 自动登录。保留配置升级时不会覆盖用户的
旧 ttyd 配置；若旧接口仍写作 `lan4`，需自行改为 `@lan` 或 `br-lan`。

新安装默认使用 **Argon**，包含主题设置和简体中文翻译
（`luci-i18n-argon-config-zh-cn`），无需另装旧的独立主题设置插件。
保留配置升级时不覆盖已有主题或语言选择；恢复镜像使用 Bootstrap。

**xinfc** 来源为仓库固定保存的 1.0.1-r1 APK，按各分支原生格式重新打包为
1.0.1-r2；程序载荷保持原样，安装脚本适配离线构建。安装与首次启动不写入 NFC，
NFC 写入必须由用户主动操作；首次备份保存在 `/etc/xinfc/`，并随配置备份保留。
原包、提取载荷和 SHA256 在 `packages/luci-app-xinfc/`；构建信息记录来源校验值。
二进制源码未随原包提供，公开再分发前需另行确认 GPL 对应源码可用性。

## 仓库结构

```text
patches/                             AN8855 补丁和已验证的源码提交
setup.sh                             构建入口
scripts/check-image-size.sh          initramfs 体积检查
scripts/check-board-scripts.sh       板级脚本备份安全检查
scripts/generate-config-seed.sh      可复现的软件包／配置种子
scripts/check-an8855.py              AN8855 布局和 NFC 前置条件校验
packages/luci-app-xinfc/              固定 APK、原始载荷与原生打包定义
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
| 从已准备的源码构建双镜像 | `bash scripts/build-firmware.sh openwrt-ax3000t` |
| 离线测试双镜像安全策略 | `bash scripts/tests/test-nikki-build.sh` |
| 配置软件包 | `cd openwrt-ax3000t && make menuconfig` |
| 检查 initramfs 体积 | `scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic` |
| 检查板级脚本备份 | `bash scripts/check-board-scripts.sh openwrt-ax3000t` |
| 仓库基线检查 | `scripts/repository-check` |

本地和 Actions 共用 `scripts/check-an8855.py`：检查选中目标、单 UBI 分区、
升级处理及 I²C/NFC 声明；缺失或选错时直接失败，不回退到标准双分区目标。

## GitHub Actions

CI 工作流在仓库 `master` 的推送／拉取请求上构建 OpenWrt `main` 开发快照，
构建并校验 AN8855 双镜像，并上传固件、配套软件包和构建信息。
独立的 `stable-latest.yml` 工作流对最新 OpenWrt 正式稳定版执行同样的构建。
两个工作流均缓存下载文件和编译结果；GitHub Actions 产物保留 90 天。

`master` 固件构建成功后，semantic-release 根据约定式提交确定版本，
生成变更日志、创建标签，并发布包含已验证双镜像和配套包的 GitHub Release。

## 限制与注意事项

- 原厂引导程序要求使用 AN8855 单 UBI 布局。
- initramfs FIT 镜像不得超过 26 MiB。
- Nikki/Mihomo、Tailscale、Argon 和 xinfc 仅完整 sysupgrade 预装。
- 标准 AX3000T／MT7531 目标不能与本目标混用。
- OpenWrt 源码和构建产物属于本地忽略文件，不纳入仓库版本管理。

## 文档

- [开发指南](docs/development/guide.md)
- [路由器运维](docs/operations/home-router.md)
- [构建经验](docs/reports/build-experience.md)
- [路由器状态](docs/reference/router-state.md)

## 许可证

GPL-2.0，与 OpenWrt 保持一致。
