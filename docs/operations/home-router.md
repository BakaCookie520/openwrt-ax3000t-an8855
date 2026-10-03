# Xiaomi AX3000T (AN8855) 路由器 / Tailscale 组网配置说明

> **时间**：2026-08-15
> **作者**：hugh
> **适用范围**：Xiaomi Mi Router AX3000T（AN8855）上 OpenWrt 配置与 Tailscale 组网交接
> **文档目的**：记录设备当前配置、组网拓扑与交接要点，供后续维护/换手参考。
> **状态**：生效（对应 OpenWrt SNAPSHOT r0-9f3157a）

## 变更记录

| 版本 | 日期 | 作者 | 变更说明 |
|------|------|------|----------|
| 1.0 | 2026-08-15 | hugh | 补充 DOC_HEADER 头部（内容同原稿） |

## 项目目标

记录 `192.168.31.1` 这台 **Xiaomi Mi Router AX3000T（AN8855 交换机）** 的配置与交接要点，
重点是 PPPoE 拨号上网 + 单臂访问光猫、Tailscale 组网（通告子网），以及与办公室节点互连。

## 设备与环境

- 型号：Xiaomi Mi Router AX3000T（AN8855 5 口千兆交换机）
- 系统：OpenWrt SNAPSHOT `r0-9f3157a`，架构 `aarch64_cortex-a53`
- 主机名：`OpenWrt`；Tailscale 节点：`xiaomi-ax3000t`，组网 IP **`100.104.191.81`**
- 登录：`ssh root@192.168.31.1`（本机 LAN）

## 网络拓扑与角色

- LAN：`br-lan` = `192.168.31.1/24`（桥接 `lan2/lan3/lan4`，即 AN8855 下游口）
- WAN：`wan@eth0`，**PPPoE 拨号**（账号/密码见 `/etc/config/network`），`pppoe-wan` 获公网 `100.77.x`
- 单臂访问光猫：同一物理 WAN 口上另配静态 `192.168.1.99/24` 用于访问光猫 `192.168.1.1`
- 角色：家中路由器；同时是 Tailscale 组网节点，**通告子网 `192.168.31.0/24`**，
  使远端组网设备能经它访问家庭局域网。

## 关键配置

### 网络（/etc/config/network）

| 接口 | 协议 | 地址 | 说明 |
|------|------|------|------|
| `br-lan` | static | `192.168.31.1/24` | LAN，桥接 `lan2/lan3/lan4` |
| `wan` | pppoe | 拨号 | 上行 PPPoE 拨号上网 |
| `Modem` | static | `192.168.1.99/24`，device=`wan` | 单臂访问光猫 `192.168.1.1`（与 PPPoE 共用 WAN 口） |
| `tailscale0` | TUN | `100.104.191.81/32` | tailscaled 动态创建，不在 network 配置里 |

要点：
- `Modem` 接口的 `device` 必须是 `wan`（DSA 从端口），不能是 `eth0`（master CPU 口），
  否则 ARP 不通、ping 光猫失败。
- `Modem` 接口当前配了 `gateway 192.168.1.1`，但实测**不会抢默认路由**（默认路由由 PPPoE 的
  `default via 100.77.x dev pppoe-wan` 提供，上网正常）。若出现上网走光猫的异常，可去掉该 gateway。

### Tailscale
- 节点 `xiaomi-ax3000t`，组网 IP `100.104.191.81`，状态：已登录、运行中
- **通告路由**：`192.168.31.0/24`（已在控制台审批，`PrimaryRoutes` 生效），`NoSNAT: true`（保留真实源地址）
- `CorpDNS: false`（**MagicDNS 关闭**；访问一律用 IP）
- `RouteAll: false`（本机不主动接受其它节点通告的路由——仅通告方需要，按需开启）
- `RunSSH: false`；开机自启；状态持久化 `/etc/tailscale/tailscaled.state`
- 自动恢复：init.d 脚本已含 `procd respawn`，tailscaled 崩溃自动重启；断网重连由内置机制处理

### 防火墙（firewall4 / nftables）
- zone：`lan`（ACCEPT）、`wan`（REJECT，masq）、`modem`（ACCEPT，masq，network=`Modem`）、
  **`tailscale`**（ACCEPT，network=`tailscale`）
- 转发：`lan→wan`、`lan→modem`、`tailscale→lan`、`lan→tailscale`（后两条实现组网↔局域网互访）
- 本机自身被组网访问：Tailscale 自带 `ts-input`（`iifname "tailscale0*" accept`）放行 TCP

## 关键配置 1：单臂拨号 + 访问光猫

一根 WAN 线同时 PPPoE 拨号上网、又能访问光猫管理页：

```sh
# Modem 接口（静态 192.168.1.99 绑到 wan，与 PPPoE 同物理口）
uci set network.Modem.device='wan'
uci set network.Modem.proto='static'
uci set network.Modem.ipaddr='192.168.1.99'
uci set network.Modem.netmask='255.255.255.0'
uci commit network

# modem zone：允许入站 + masq（让 LAN 设备访问光猫时，光猫看到的源是 192.168.1.99）
uci set firewall.@zone[2].name='modem'
uci set firewall.@zone[2].network='Modem'
uci set firewall.@zone[2].input='ACCEPT'
uci set firewall.@zone[2].output='ACCEPT'
uci set firewall.@zone[2].forward='ACCEPT'
uci set firewall.@zone[2].masq='1'
uci add firewall forwarding            # lan -> modem
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='modem'
uci commit firewall
```

验证：`echo -e "GET / HTTP/1.0\r\n\r" | nc 192.168.1.1 80` 应返回 `HTTP/1.0 200 OK`。

## 关键配置 2：Tailscale 子网通告（远端访问家庭局域网）

```sh
# 通告 192.168.31.0/24，保留真实源地址，保持 MagicDNS 关闭
tailscale up --accept-dns=false --advertise-routes=192.168.31.0/24 --snat-subnet-routes=false

# 创建 tailscale zone + 转发（组网 ↔ 局域网互访）
uci set network.tailscale='interface'
uci set network.tailscale.ifname='tailscale0'
uci set network.tailscale.proto='none'
uci commit network

uci add firewall zone
uci set firewall.@zone[-1].name='tailscale'
uci set firewall.@zone[-1].network='tailscale'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci commit firewall

uci add firewall forwarding          # tailscale -> lan
uci set firewall.@forwarding[-1].src='tailscale'
uci set firewall.@forwarding[-1].dest='lan'
uci add firewall forwarding          # lan -> tailscale
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='tailscale'
uci commit firewall
```

**远端侧要求：**
1. 子网路由 `192.168.31.0/24` 已在 Tailscale 控制台审批（`PrimaryRoutes` 生效）
2. 远端客户端需开启 **accept-routes**，例如 Ubuntu：`tailscale up --reset --accept-routes --accept-dns=false --ssh`
3. 生效后远端可 `ping 192.168.31.x` 直接访问家庭局域网设备（走直连隧道，约 10–70ms）

## 关键配置 3：系统 / WiFi 基础优化

- 时区：`Asia/Shanghai`（CST-8），NTP 用阿里/腾讯国内源
- DNS：保持运营商上游，不启用 MagicDNS
- WiFi：双频统一 SSID `猪猪之家`，WPA2/WPA3-PSK；2.4G 信道 1/HE20，5G 信道 149(实际 153)/HE80，country=`CN`，Tx 28dBm
- 默认防火墙 wan zone `input=REJECT`，公网无法访问 80/443/22

## 使用方式

- 组网内任何节点访问本机：`ssh root@100.104.191.81`
- 远端访问家庭局域网设备：`ssh root@192.168.31.x` 或直接访问 `192.168.31.x`（需子网路由已审批 + 客户端 accept-routes）
- 因 MagicDNS 关闭，一律使用 IP。

## 常用命令（本机）

```sh
tailscale status                       # 组网状态
tailscale ping 100.104.191.81        # 控制面连通性
tailscale debug prefs | grep -i corp  # 确认 MagicDNS 关闭
tailscale debug prefs | grep -iA1 AdvertiseRoutes  # 确认通告子网
/etc/init.d/tailscale restart
/etc/init.d/firewall reload
```

## 交接要点 / 坑

- **单臂访问光猫的 IP 必须绑 `wan`**，不是 `eth0`；且 `Modem` 接口**不要配 gateway**（会抢默认路由）。
- **ICMP 被拒 ≠ SSH 被拒**：本机 SSH 正常但 ping 报 `Destination Port Unreachable` 是 fw4 兜底，
  需 `tailscale0` zone 或 include 脚本放行 input。
- **不要**改动 `CorpDNS` 开启 MagicDNS（需求要求关闭）。
- 子网通告需**控制台审批** + **远端 accept-routes**，缺一不可。
- WAN 断线会导致无默认路由、DNS 失败、Tailscale 无法登录控制面（`tailscale status` 显示 logged out）。
  先保证 WAN 有链路；`procd respawn` 保证 tailscaled 崩溃自启。
- **root 密码**务必设置：局域网内设备可直接 SSH 登录（公网已被 wan zone REJECT 挡住）。

## 与办公室节点互连

- 本机 `xiaomi-ax3000t`（100.104.191.81，家中）与办公室 `dev`（100.95.46.79，Ubuntu）
  同账号组网，`tailscale ping` 直连约 10ms。
- 办公室 `dev` 已开 accept-routes，可从办公室访问家庭 `192.168.31.x` 实测通（路由器 11ms、局域网 Mac 65ms）。

## 已知限制

- 远端访问家庭 LAN 内其它设备需子网路由审批 + 客户端 accept-routes（已在本机与办公室 `dev` 验证）。
- 依赖家庭网络链路正常；WAN 掉线即失去外部可达性。

## 固件升级与配置保留

- 相同 AN8855 单 UBI 布局的日常升级，在 LuCI 使用 sysupgrade 镜像并勾选
  **保留当前配置**。先下载配置备份；不要重新走 initramfs/`mtd write` 的首次安装流程。
- 命令行日常升级使用 `sysupgrade /tmp/<固件>-squashfs-sysupgrade.bin`。
  `sysupgrade -n` 明确不保留配置，只用于首次安装或有意清空配置的迁移。
- 新固件通过 board.json 为全新安装提供 `192.168.31.1`，不再用 uci-defaults
  覆盖 LAN 或 Wi-Fi。全新安装保持上游 Wi-Fi 禁用默认值；保留配置升级不应
  改动原 SSID、加密方式、Wi-Fi 密码或 root 密码。
- 旧固件的 `99-router-home-custom` 会在保留配置升级后仍重设 LAN 和开放 Wi-Fi。
  修复源码不会追溯恢复已经被旧固件覆盖的无线设置；需要根据自己的备份手动恢复。
- 保留配置不等于保留后装的软件包。主题、ttyd 等可能只剩配置文件，必须安装
  与新固件及包管理器兼容的版本；不要把旧版本内核模块或整个 overlay 强行恢复。
- ttyd 的 root 自动登录仅跳过终端内的登录步骤，不应同时取消网页访问认证。
  只允许通过 LAN 访问，使用 HTTPS，禁止向 WAN 开放免认证 root 终端；
  凭据不写入仓库。ttyd 的 Basic Authentication 凭据独立于系统密码，
  修改 root 密码后需要同步更新 ttyd 凭据；配置和私钥应仅允许 root 读取，
  并将独立的 TLS 文件目录加入 sysupgrade 保留清单。

## 端口状态重复

- LuCI 的物理端口列表来自板级定义，不等同于当前 LAN/WAN 接口配置。
  如果 `lan2/lan3/lan4` 重复并出现不存在的 `lan1`，检查 `/etc/board.json`
  的 `network.lan.ports` 以及 `/etc/board.d/02_network.orig`。
- OpenWrt 的 board_detect 会执行 board.d 中的所有非空文件，补丁备份 `.orig`
  也会被执行。AN8855 补丁前后的 `02_network` 同时运行会累加 LAN 端口，
  导致重复显示。不是 Argon 主题问题，也不表示真实接口或流量翻倍。
- 本地和云端应用补丁均禁用不匹配备份，并移除复用源码中的已知
  `02_network.orig`；构建前后检查运行时 board.d，遇到其他 `.orig`、`.rej`
  或 `~` 备份即停止构建。
- 在线修复前备份板级文件，屏蔽错误备份脚本，再单独生成、验证并替换
  `/etc/board.json`。只修复板级元数据，不重写 `/etc/config/network`，
  不执行 config_generate，也不重启网络；刷新 LuCI 查看结果。
