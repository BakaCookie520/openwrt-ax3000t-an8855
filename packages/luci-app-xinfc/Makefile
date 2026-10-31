# SPDX-License-Identifier: GPL-2.0-or-later
# Imported prebuilt ARM64 payload; source APK and checksums live beside this file.
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-xinfc
PKG_VERSION:=1.0.1
PKG_RELEASE:=4
PKG_LICENSE:=GPL-2.0-or-later
PKG_FLAGS:=nonshared

# The supplied writer is already statically linked. Do not strip/relink it.
STRIP:=:
RSTRIP:=:

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-xinfc
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AX3000T NFC management
  DEPENDS:=@TARGET_mediatek_filogic +base-files +busybox +coreutils-stat +flock +jshn +luci-base +rpcd +ubus +kmod-i2c-core
  PROVIDES:=xinfc
endef

define Package/luci-app-xinfc/description
  Imported AX3000T NFC LuCI application and static ARM64 writer.
  Installation never programs the chip. The writer retains its hardware checks.
endef

define Build/Prepare
	cd $(CURDIR) && sha256sum -c SHA256SUMS
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-xinfc/install
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d $(1)/usr/libexec/rpcd $(1)/usr/sbin
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/xinfc $(1)/lib/upgrade/keep.d/
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/luci.xinfc $(1)/usr/libexec/rpcd/
	$(INSTALL_BIN) ./files/usr/sbin/xinfc-wsc $(1)/usr/sbin/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-xinfc.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-xinfc.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view $(1)/etc/uci-defaults
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/xinfc.js $(1)/www/luci-static/resources/view/
	$(INSTALL_BIN) ./runtime/95-xinfc-state $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/xinfc
	$(INSTALL_DATA) ./runtime/wireless.js $(1)/www/luci-static/resources/xinfc/
endef

define Package/luci-app-xinfc/preinst
#!/bin/sh
# Offline image assembly must never inspect or operate on the build host.
[ -z "$${IPKG_INSTROOT:-}" ] || exit 0
set -eu
fail() { echo "xinfc: $$*" >&2; exit 1; }
[ "$$(id -u)" = 0 ] || fail 'Root required.'
COMPATIBLE=/proc/device-tree/compatible
NFC_COMPATIBLE=/sys/bus/i2c/devices/0-0057/of_node/compatible
[ -r "$$COMPATIBLE" ] || fail 'AX3000T device tree not found.'
if ! tr '\000' '\n' < "$$COMPATIBLE" |
	grep -qxE 'xiaomi,mi-router-ax3000t(-ubootmod)?'; then
	tr '\000' '\n' < "$$COMPATIBLE" |
		grep -Fxq 'xiaomi,mi-router-ax3000t-an8855' &&
		[ -r "$$NFC_COMPATIBLE" ] &&
		tr '\000' '\n' < "$$NFC_COMPATIBLE" | grep -Fxq nt082c ||
		fail 'Only supported AX3000T device trees are permitted.'
fi
[ -c /dev/i2c-0 ] || fail 'Missing /dev/i2c-0; check firmware I2C support.'
[ ! -e /sys/bus/i2c/devices/0-0057/driver ] ||
	fail 'NFC chip is already bound to a kernel driver.'
[ ! -d /tmp/xinfc/job.lock ] || fail 'An NFC job is active; retry when it finishes.'
for dependency in flock jshn ubus stat mktemp; do
	command -v "$$dependency" >/dev/null || fail "Missing $$dependency."
done
if [ -e /etc/xinfc ] || [ -L /etc/xinfc ]; then
	[ ! -L /etc/xinfc ] && [ -d /etc/xinfc ] &&
		[ "$$(stat -c '%u' /etc/xinfc)" = 0 ] &&
		chmod 700 /etc/xinfc &&
		[ "$$(stat -c '%u:%a' /etc/xinfc)" = '0:700' ] ||
		fail 'Existing /etc/xinfc must be a root-owned directory with mode 0700.'
fi
exit 0
endef

define Package/luci-app-xinfc/postinst
#!/bin/sh
[ -z "$${IPKG_INSTROOT:-}" ] || exit 0
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
[ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd restart
exit 0
endef

define Package/luci-app-xinfc/postrm
#!/bin/sh
[ -z "$${IPKG_INSTROOT:-}" ] || exit 0
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
[ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd restart
# /etc/xinfc and its first backup must never be deleted.
exit 0
endef

$(eval $(call BuildPackage,luci-app-xinfc))
