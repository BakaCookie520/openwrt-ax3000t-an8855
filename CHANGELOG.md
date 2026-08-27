## [1.0.1](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/compare/v1.0.0...v1.0.1) (2026-08-27)


### Bug Fixes

* **ci:** force standalone OpenClash APK build ([ba14b80](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/ba14b8098ad85efe01044f6d6aa7bc3b98650e91))

# 1.0.0 (2026-08-26)


### Bug Fixes

* **ci:** remove obsolete python distutils dependency ([0de1004](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/0de1004c1e0b8ef6c72d9ac24836b7046e59ff66))
* set default LAN IP to 192.168.31.1 (Xiaomi standard) ([d06c6fd](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/d06c6fdcfe0b7ad21916d771c565e9361f5b6499))
* 精简工具集至 26MB 内,修复 initramfs 超 U-Boot 上限无法启动 ([d35e1b3](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/d35e1b39648dabb43f18c5ab62e3bab5acea5c9b))
* 补回 luci-compat/luci-lua-runtime,修复 LuCI ucodebridge 报错 ([b3dc9b7](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/b3dc9b7e1744b56eb5142ba931ceed107295c2d4))


### Features

* enable WiFi by default on first boot ([f60d4b3](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/f60d4b370e8af80fead584a43279416d550850b3))
* OpenClash 改为独立 apk,不进固件 ([f083935](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/f083935f4a06f7bd465fb8044f9eb0902d043ca0))
* 内置完整内核模块工具集 + USTC 软件源 ([5a26684](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/5a26684f1c054192fd688f8f4a3877f37aaed326))
* 固化 an8855 目标补丁 + luci-compat,支持 OpenClash 于主线 LuCI 26 ([1cb6113](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/1cb6113f918aa8668b79fe1acfc6e92d04f8dad1))
* 构建流水线防漂移加固(体积校验/commit锁定/变量隔离) ([7703a83](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/7703a83ac981bda34cd58c178de0265a0b465955))
* 迁移到 OpenWrt 主线 (main),集成 OpenClash 与 Tailscale ([a900333](https://github.com/BakaCookie520/openwrt-ax3000t-an8855/commit/a9003336385947d02d76f1f1f305ed3eb5042193))

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
