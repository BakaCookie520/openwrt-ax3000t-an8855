# 1.0.0 (2026-10-30)


### Bug Fixes

* action fail ([cb2c19d](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/cb2c19d98f299acdf0c7db5e1bd85674dee649e2))
* **ci:** detect OpenClash APK filenames ([7b15efa](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/7b15efa7aa38ab4dd4b29294b4382d3295cae5d5))
* **ci:** resolve upstream branch from base_ref on pull_request events ([4a397e4](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/4a397e455e5a8fd4cf97c356dc8f93307735c947))
* preserve upgrade settings and prevent duplicate AN8855 ports ([5ac76af](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/5ac76af28ab0ec997bffc41b9b2d00b22f8ca61a))
* **release:** allow validated artifact download ([be1ee7c](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/be1ee7c8ca7d38529adcacdeab11490f82a9b66c))
* repair CI failures and release repo drift ([a081138](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/a081138604b4222784d32f8ba75940324aef44ff))
* set default LAN IP to 192.168.31.1 (Xiaomi standard) ([d06c6fd](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/d06c6fdcfe0b7ad21916d771c565e9361f5b6499))
* **tests:** drain archive listings to avoid GNU tar SIGPIPE ([1a45d2f](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/1a45d2f491c0c3c4a8db9d74f67f7cbda0089382))
* 精简工具集至 26MB 内,修复 initramfs 超 U-Boot 上限无法启动 ([d35e1b3](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/d35e1b39648dabb43f18c5ab62e3bab5acea5c9b))
* 补回 luci-compat/luci-lua-runtime,修复 LuCI ucodebridge 报错 ([b3dc9b7](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/b3dc9b7e1744b56eb5142ba931ceed107295c2d4))


### Features

* **ci:** add dynamic latest stable OpenWrt build ([6855590](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/68555909ae7fb1e452f5a10bda56bf1d55e1e342))
* **ci:** add dynamic latest stable OpenWrt build ([a0df265](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/a0df26547976fd6c720764557c91a8958b3385ec))
* enable WiFi by default on first boot ([f60d4b3](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/f60d4b370e8af80fead584a43279416d550850b3))
* OpenClash 改为独立 apk,不进固件 ([f083935](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/f083935f4a06f7bd465fb8044f9eb0902d043ca0))
* preinstall Chinese Argon and xinfc for AN8855 firmware ([6f881db](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/6f881db8930469b2a75e39dba1f51ef4b0fb2f5f))
* preinstall Nikki and ttyd with safe dual-image builds ([70d1c01](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/70d1c01704e5c5bd18d395681226fb4d71c2da6e))
* 内置完整内核模块工具集 + USTC 软件源 ([5a26684](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/5a26684f1c054192fd688f8f4a3877f37aaed326))
* 固化 an8855 目标补丁 + luci-compat,支持 OpenClash 于主线 LuCI 26 ([1cb6113](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/1cb6113f918aa8668b79fe1acfc6e92d04f8dad1))
* 构建流水线防漂移加固(体积校验/commit锁定/变量隔离) ([7703a83](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/7703a83ac981bda34cd58c178de0265a0b465955))
* 迁移到 OpenWrt 主线 (main),集成 OpenClash 与 Tailscale ([a900333](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/a9003336385947d02d76f1f1f305ed3eb5042193))

## [1.0.4](https://github.com/HughZadora/openwrt-ax3000t-an8855/compare/v1.0.3...v1.0.4) (2026-09-06)


### Bug Fixes

* action fail ([cb2c19d](https://github.com/HughZadora/openwrt-ax3000t-an8855/commit/cb2c19d98f299acdf0c7db5e1bd85674dee649e2))
* **release:** allow validated artifact download ([be1ee7c](https://github.com/HughZadora/openwrt-ax3000t-an8855/commit/be1ee7c8ca7d38529adcacdeab11490f82a9b66c))

## [1.0.3](https://github.com/HughZadora/openwrt-ax3000t-an8855/compare/v1.0.2...v1.0.3) (2026-09-05)


### Bug Fixes

* **ci:** detect OpenClash APK filenames ([7b15efa](https://github.com/HughZadora/openwrt-ax3000t-an8855/commit/7b15efa7aa38ab4dd4b29294b4382d3295cae5d5))

## [1.0.2](https://github.com/HughZadora/openwrt-ax3000t-an8855/compare/v1.0.1...v1.0.2) (2026-09-04)


### Bug Fixes

* **ci:** resolve upstream branch from base_ref on pull_request events ([4a397e4](https://github.com/HughZadora/openwrt-ax3000t-an8855/commit/4a397e455e5a8fd4cf97c356dc8f93307735c947))

## [1.0.1](https://github.com/HughZadora/openwrt-ax3000t-an8855/compare/v1.0.0...v1.0.1) (2026-09-04)


### Bug Fixes

* repair CI failures and release repo drift ([a081138](https://github.com/HughZadora/openwrt-ax3000t-an8855/commit/a081138604b4222784d32f8ba75940324aef44ff))

# 1.0.0 (2026-08-21)


### Bug Fixes

* set default LAN IP to 192.168.31.1 (Xiaomi standard) ([d06c6fd](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/d06c6fdcfe0b7ad21916d771c565e9361f5b6499))
* 精简工具集至 26MB 内,修复 initramfs 超 U-Boot 上限无法启动 ([d35e1b3](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/d35e1b39648dabb43f18c5ab62e3bab5acea5c9b))
* 补回 luci-compat/luci-lua-runtime,修复 LuCI ucodebridge 报错 ([b3dc9b7](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/b3dc9b7e1744b56eb5142ba931ceed107295c2d4))


### Features

* enable WiFi by default on first boot ([f60d4b3](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/f60d4b370e8af80fead584a43279416d550850b3))
* OpenClash 改为独立 apk,不进固件 ([f083935](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/f083935f4a06f7bd465fb8044f9eb0902d043ca0))
* 内置完整内核模块工具集 + USTC 软件源 ([5a26684](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/5a26684f1c054192fd688f8f4a3877f37aaed326))
* 固化 an8855 目标补丁 + luci-compat,支持 OpenClash 于主线 LuCI 26 ([1cb6113](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/1cb6113f918aa8668b79fe1acfc6e92d04f8dad1))
* 构建流水线防漂移加固(体积校验/commit锁定/变量隔离) ([7703a83](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/7703a83ac981bda34cd58c178de0265a0b465955))
* 迁移到 OpenWrt 主线 (main),集成 OpenClash 与 Tailscale ([a900333](https://github.com/Clint000832/openwrt-ax3000t-an8855/commit/a9003336385947d02d76f1f1f305ed3eb5042193))
