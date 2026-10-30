# Xiaomi Mi Router AX3000T (AN8855) OpenWrt 编译实战总结

> **时间**：2026-08-15（原始记录 2026-06，2026-08 更新）
> **作者**：hugh
> **适用范围**：Xiaomi Mi Router AX3000T（AN8855）OpenWrt 编译踩坑记录（WSL2/Ubuntu，mediatek_filogic）
> **文档目的**：沉淀编译过程中遇到的 WSL PATH、fakeroot 死锁、代理加速、断点续编等问题的排查经验。
> **状态**：生效（早期 24.10 内容对主线编译仍适用，内核/fwx 补丁相关描述除外）

## 变更记录

| 版本 | 日期 | 作者 | 变更说明 |
|------|------|------|----------|
| 1.0 | 2026-08-15 | hugh | 补充 DOC_HEADER 头部，重组原有时间/平台元数据 |

> **现状提醒(更新于 2026-08):** 本文是早期 24.10 + 自定义 AN8855/fwx 补丁的踩坑记录。
> 当前仓库已切换到 **OpenWrt 主线 (main, ≈内核 6.18)**:**AN8855 交换芯片的驱动/内核支持已原生进入主线**,
> 但**启动布局目标仍需手工重建**——主线只有 stock 双分区(`xiaomi_mi-router-ax3000t`)
> 与 ubootmod 目标,AN8855 + 原厂 U-Boot 必须用**单 UBI 目标
> `xiaomi_mi-router-ax3000t-an8855`**,由 `patches/` 里的补丁重建(与 24.10 官方 an8855
> 目标布局一致)。所以"不再需要任何 target 补丁"的说法**不成立**,只是不再需要自定义
> **内核/fwx** 补丁而已。固件目标统一用该单 UBI 目标。
> 下面记录的 **WSL PATH、fakeroot 死锁、代理加速、断点续编** 等问题对主线编译同样适用,
> 仅"核心改动"中与自定义内核补丁相关的描述不再适用。
>
> **原始背景:** 为 AX3000T (外挂 AN8855) 从源码编译 OpenWrt 24.10 固件。
> **时间:** 2026-06 ｜ **平台:** WSL2 (Ubuntu) ｜ **目标:** mediatek_filogic (MT7981)

---

## 目录

1. [环境与配置](#1-环境与配置)
2. [源码准备](#2-源码准备)
3. [核心改动](#3-核心改动)
4. [编译过程中的关键问题](#4-编译过程中的关键问题)
5. [最终产物](#5-最终产物)
6. [经验总结](#6-经验总结)
7. [附录：问题快速排查表](#7-附录问题快速排查表)

---

## 1. 环境与配置

| 项目 | 值 |
|------|-----|
| 主机系统 | WSL2 (Ubuntu 24.04, 内核 6.6.114.1) |
| 工具链 | gcc 13.3.0 (OpenWrt 内置交叉编译) |
| OpenWrt 版本 | 24.10 (openwrt-24.10 分支, Linux 6.6.141) |
| 代理环境 | SOCKS5 (192.168.110.134:7890) — 国内下载加速 |
| 编译参数 | `make -j1 V=s`（单线程调试） |
| 构建目录 | `openwrt_compile_database/` |
| 下载缓存 | 共享 `dl/` 目录（与其他 OpenWrt 构建共用） |

---

## 2. 源码准备

### 克隆与初始化

```bash
git clone --depth 1 --branch openwrt-24.10 \
    https://git.openwrt.org/openwrt/openwrt.git openwrt_compile_database
cd openwrt_compile_database
./scripts/feeds update -a
./scripts/feeds install -a
```

### 关键配置（.config）

```
CONFIG_TARGET_mediatek_filogic=y
CONFIG_DEVICE_xiaomi_mi-router-ax3000t-an8855=y
```

通过 `make menuconfig` 设置：
- Target System → `MediaTek Ralink ARM`
- Subtarget → `Filogic 820/830 (MT7981/MT7986)`
- Target Profile → `Xiaomi Mi Router AX3000T (AN8855)`

---

## 3. 核心改动

共修改/创建 **6 个文件**，分为两个层面：

### 3.1 设备定义（OpenWrt 主线源码改动）

| 文件 | 操作 | 说明 |
|------|------|------|
| `target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | **新建** | AN8855 设备树 — 定义单 UBI 分区布局 (112MB) |
| `target/linux/mediatek/image/filogic.mk` | **修改** | 添加 `xiaomi_mi-router-ax3000t-an8855` 镜像构建目标 |
| `target/linux/mediatek/filogic/base-files/etc/board.d/02_network` | **修改** | 新增 AN8855 的 VLAN 划分、MAC 地址获取规则,默认 IP 设为 `192.168.31.1` |
| `target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh` | **修改** | 添加 AN8855 的 mtdparts 初始化和系统升级入口 |

> ℹ️ **当前实际改动范围(以 `patches/` 为准):** 上述 4 项。早期曾改过
> `etc/board.d/04_defaults` 来加 WiFi 默认配置,现已**废弃**——首启 WiFi/LAN 定制改由
> `setup.sh` 注入的 `uci-defaults/99-router-home-custom` 脚本实现(见 `setup.sh` 步骤 6)。
> 所有改动都由 `setup.sh` 步骤 2.5 自动应用(dry-run 校验 + 生效校验)。

### 3.2 编译环境适配（WSL 专有）

| 文件 | 操作 | 说明 |
|------|------|------|
| `staging_dir/host/bin/fakeroot` | **修改** | 硬编码旧路径 → 自动推导路径（`$(dirname "$0")`） |
| `include/rootfs.mk` | **修改** | `-execdir` → `-exec`（绕过 WSL PATH 安全问题） |

> 部分补丁文件位于 [`patches/`](patches/) 目录。

---

## 4. 编译过程中的关键问题

### 🔥 问题 1：fakeroot/faked 死锁

**现象：** 编译卡在 `package/libs/toolchain/compile`，`fakeroot ipkg-build` 无响应。`ps aux` 显示 `faked` 进程处于 Ss 状态但没有任何进展。

**分析过程：**
1. 检查 `staging_dir/host/bin/fakeroot` 脚本 — 发现硬编码了旧构建目录路径
   ```bash
   # 旧代码 (bug):
   FAKEROOT_PREFIX=/home/hugh/openwrt-build-ax3000t/staging_dir/host
   ```
2. 该路径指向已删除的旧项目目录，但 `STAGING_DIR_HOST` 环境变量未设置，导致找不到 `libfakeroot.so`
3. 根源：`faked` 守护进程在父进程（make）被 `kill -9` 后仍然存活，遗留的管道/信号量造成死锁

**解决方案：**

1. 修复硬编码路径，改为自动推导：
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   FAKEROOT_PREFIX="${SCRIPT_DIR}/.."
   ```

2. 每次重新编译前，确保清除残留 `faked`：
   ```bash
   kill -9 $(pgrep faked) 2>/dev/null
   ```

3. 验证 fakeroot 可用性：
   ```bash
   STAGING_DIR_HOST=$(pwd)/staging_dir/host \
       staging_dir/host/bin/fakeroot \
       staging_dir/host/bin/bash -c "echo fakeroot_works"
   ```

---

### 🔥 问题 2：下载缓慢 / 连接超时

**现象：** 编译卡在下载阶段：
- `linux-firmware-20241110.tar.xz`（387MB）— 3% 进度，预计 6 小时
- `openvswitch-2.17.9.tar.gz`（8MB）— 1.2KB/s，预计 1 小时+
- `ath10k-ct` 从 GitHub clone — `GnuTLS recv error (-110): TLS connection was non-properly terminated`
- `openvpn-dco`、`mt76`、`rtpengine` 等包同样缓慢

**分析过程：**
1. 服务器在国内，直接连接 kernel.org / GitHub / openvswitch.org 非常慢或不可达
2. OpenWrt 使用 `curl`/`git clone` 直接下载，默认不使用代理
3. 之前使用的 `pp`（proxychains4）通过 `LD_PRELOAD` 劫持 socket 调用，导致与 fakeroot 的 `LD_PRELOAD` 冲突

**解决方案（三种方案对比）：**

| 方案 | 优点 | 缺点 | 最终选择 |
|------|------|------|---------|
| `pp make` (proxychains) | 全局代理 | LD_PRELOAD 与 fakeroot 冲突 ❌ | ✗ |
| 手动 `pp wget` 下载 | 精确控制 | 需手动监控，逐个下载 | 应急可用 |
| `ALL_PROXY=socks5h://...` | git/curl 原生支持，无 LD_PRELOAD | 无 | **✓ 最佳方案** |

最终采用环境变量方案：
```bash
export ALL_PROXY=socks5h://192.168.110.134:7890
make -j1 V=s
```
- Git 和 curl 原生支持 `ALL_PROXY`，无需 LD_PRELOAD
- 下载速度从 **1.2KB/s 提升到 34.2MB/s**（差 28500 倍）
- 编译子进程（gcc 等）不受影响

---

### 🔥 问题 3：WSL 环境 PATH 污染

**现象：** 编译在最后阶段（`package/install`）崩溃：
```
find: The relative path 'Files/coreutils/bin' is included in the PATH
environment variable, which is insecure in combination with the
-execdir action of find.
```

**分析过程：**
1. WSL 默认将 Windows 的 PATH 追加到 Linux PATH
2. `/mnt/c/Program Files/coreutils/bin` 包含空格，PATH 解析后被拆为两个条目：`/mnt/c/Program` 和 `Files/coreutils/bin`
3. `Files/coreutils/bin` 是**相对路径**，触发了 `find -execdir` 的安全检测
4. 发生在 `include/rootfs.mk` 的 `prepare_rootfs` 函数中

**解决方案：**

1. 修改 `include/rootfs.mk`，将 `-execdir` 改为 `-exec`：
   ```makefile
   # 修改前:
   find $(1)/ -mindepth 1 -execdir touch -hcd "@$(SOURCE_DATE_EPOCH)" "{}" +
   # 修改后:
   find $(1)/ -mindepth 1 -exec touch -hcd "@$(SOURCE_DATE_EPOCH)" "{}" +
   ```
   > 理由：在编译环境中，`-execdir` 的安全优势（避免工作目录竞争）对于 timestamp 设置场景无意义，`-exec` 完全等效且兼容性更好。

2. 运行时清理 PATH：
   ```bash
   PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':')
   make package/install V=s
   ```
   > `export PATH=...` 在 WSL 中无效（WSL 每执行命令重新附加 Windows 路径），必须用内联方式。

---

### 🔥 问题 4：断点续编的陷阱 — faked 残留进程

**现象：** 使用 `kill -9` 中断编译后，重新启动 `make` 立即卡在 `fakeroot`。

**根因：**
- `fakeroot` 启动 `faked` 守护进程（pidfile/socket）
- `kill -9` 杀死 make 和 fakeroot，但 `faked` 作为独立守护进程**没有退出**
- 新的 `fakeroot` 尝试连接被占用的 socket 或与残留的 `faked` 通信，造成死锁
- `faked` 进程状态显示 `Ss`（正常休眠），但实际功能已损坏

**根本解决方案：**

```bash
# 重新编译前，确保清理所有 fakeroot 残留
kill -9 $(pgrep -f 'faked|fakeroot') 2>/dev/null
```

这是最可靠的方案，比手动查找 PID 或重启 shell 都彻底。

---

## 5. 最终产物

编译完成后，固件位于 `bin/targets/mediatek/filogic/`：

| 文件 | 大小 | 说明 |
|------|------|------|
| `...-xiaomi_mi-router-ax3000t-an8855-squashfs-sysupgrade.bin` | 8.4 MB | **主固件** — 用于 sysupgrade 刷入 |
| `...-xiaomi_mi-router-ax3000t-an8855-initramfs-kernel.bin` | 8.2 MB | 内存启动内核，用于调试 |
| `...-xiaomi_mi-router-ax3000t-an8855.manifest` | 3.9 KB | 包含的包列表 |
| `sha256sums` | 1.2 KB | 所有文件的 SHA256 校验和 |

编译统计（ccache）：
- 总调用：43,554 次
- 命中率：13.4%（首次编译较低）
- 缓存占用：0.9 / 5.0 GiB

---

## 6. 经验总结

### 6.1 WSL 环境下编译 OpenWrt 的关键注意事项

| 类别 | 注意点 |
|------|--------|
| **PATH 管理** | WSL 追加 Windows 路径，PATH 中的空格会拆出相对路径。`make` 中使用 PATH 时务必 `grep -v '/mnt/'` 过滤 |
| **代理配置** | 使用 `ALL_PROXY` 环境变量（git/curl 原生支持），避免 `LD_PRELOAD` 方案与 fakeroot 冲突 |
| **进程清理** | `faked` 守护进程在 `kill -9` 后仍残留，须单独 `kill -9` 清理。建议写 kill 脚本 |
| **断点续编** | OpenWrt 的 stamp 机制支持续编，但 `faked` 残留和部分下载的文件头会打断续编流程 |

### 6.2 fakeroot 架构理解

```
make → fakeroot → faked (daemon, background)
                → bash → ipkg-build (under LD_PRELOAD=libfakeroot.so)
```

- `fakeroot` 是一个 shell 包装脚本
- `faked` 是后台守护进程，通过 socket 与 `libfakeroot.so` 通信
- `libfakeroot.so` 通过 `LD_PRELOAD` 劫持 `stat()`/`chown()`/`chmod()` 等系统调用，让进程以为自己在 root 下运行
- `faked` 在 `kill -9` 父进程后不会自动退出，需要单独处理

### 6.3 编译性能优化建议

| 策略 | 效果 | 说明 |
|------|------|------|
| `-j$(nproc)` | 首次 2-6h → 30min | 多核编译，但首次受 I/O 限制 |
| ccache | 后续快 3-5x | 勾选 `Use ccache` 即可 |
| 共享 `dl/` | 节省带宽 | 多个项目共用下载缓存 |
| `ALL_PROXY` | 下载快 28500x | 国内必备，Socks5 比 HTTP 代理更稳定 |

---

## 7. 附录：问题快速排查表

| 症状 | 快速诊断 | 解决方案 |
|------|----------|----------|
| 编译卡住，最后一行是 `fakeroot` | `ps aux \| grep faked` | `kill -9 \`pgrep faked\`` |
| 下载极慢 (<10KB/s) | 检查是否配了 `ALL_PROXY` | `export ALL_PROXY=socks5h://...` |
| `find: relative path in PATH` | 检查 WSL 的 `/mnt/` 路径 | 删 `-execdir` 或内联清 PATH |
| `GnuTLS recv error` | 直连 GitHub 失败 | 使用代理 clone |
| `No more mirrors to give up` | dl 文件损坏 | `rm dl/badfile*` 重跑 |
| `make: Nothing to be done` | stamp 文件存在但产物缺失 | `rm staging_dir/.../stamp/.target` |
| 刷机起不来，落回恢复页 | 用了 stock 双分区目标 | 必须用 `-an8855` 单 UBI 目标，见 §5 |
| **内核 prepare 报 `Patch failed! .../patches/0001...`** | `setup.sh` 里用了 `PATCH_DIR` 变量名 | 改名 `REPO_PATCH_DIR`，见 §9 |
| **体积校验误报 factory.ubi 超限** | 拿 `.ubi` 容器当 FIT 判体积 | 只盯 `-initramfs-kernel.bin`(FIT)，见 §10 |

## 8. 已移除的旧代理集成

旧集成的安装与兼容性教程已移除，当前固件的软件包以 README 和配置种子为准。

## 9. 坑:PATCH_DIR 环境变量污染内核补丁路径(2026-08-15 实测)

**现象:** `setup.sh build` 在内核 prepare 阶段报:
```
Patch failed!  Please fix /home/hugh/.../patches/0001-add-an8855-target.patch!
No file to patch.  Skipping patch.
```
即 OpenWrt 把**外层仓库的 `patches/` 目录当成内核补丁目录**,尝试把 an8855 **目标文件补丁**
(filogic.mk / platform.sh / 02_network)应用到内核树,当然"No file to patch"。

**根因:** OpenWrt 的 `include/kernel.mk:43` 用**条件赋值**定义:
```make
PATCH_DIR ?= $(CURDIR)/patches-$(KERNEL_PATCHVER)
```
而旧版 `setup.sh` 里 `export PATCH_DIR=".../patches"`(指外层仓库的补丁目录)会**预定义**该变量,
`?=` 因此不再赋默认值 —— 内核构建于是把外层 `patches/` 当作 `$(PATCH_DIR)` 去打内核补丁。

**修复:** 把 `setup.sh` 里的变量改名为 `REPO_PATCH_DIR`(与 OpenWrt 内部变量彻底隔离),
`export REPO_PATCH_DIR=".../patches"`,所有引用处同步改名。**绝不要用 `PATCH_DIR`/`FILES_DIR`/
`KDIR` 这类与 OpenWrt Makefile 同名的变量。**

**验证:** 改名后内核 prepare 正常打补丁、编译到内核/软件包全部通过。

## 10. 坑:initramfs 体积校验要盯 FIT,不是 factory.ubi

**现象:** `check-image-size.sh` 把 `-initramfs-factory.ubi`(27MB)报成"超 26MB 上限"而失败。

**根因:** 原厂 U-Boot 加载进 RAM 的是 **FIT 内核镜像**(`*-initramfs-kernel.bin`,实际是 DTB 格式的
FIT,`file` 显示 "Device Tree Blob version 17"),本机实测 **24.9MB**。而 `-initramfs-factory.ubi`
是**写给 NAND 的 UBI 容器**(含 UBI 头 + 擦除块对齐),比 FIT 大(27MB),**U-Boot 并不直接加载它**,
不能拿它判体积。

**修复:** 体积校验只针对 `*-initramfs-kernel.bin` / `*.itb`(FIT),排除 `.ubi`。判断上限用的
唯一指标是 FIT 大小。

---

*本文初稿生成于 2026-06-05(基于 OpenWrt 24.10 Linux 6.6.141);§9/§10 为 2026-08-15 主线(main ~6.18)实测补充。*
