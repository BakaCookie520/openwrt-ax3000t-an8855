# ADR 0002: Chinese Argon, imported xinfc and fail-closed AN8855 builds

- Date: 2026-10-30
- Status: accepted

## Decision

Keep only the patched mainline and stable build entry points, and require
the AN8855 image definition, single 112 MiB UBI partition at `0x600000`, upgrade
handler and NFC declaration before downloading feeds. After `defconfig`, require
exactly the AN8855 device selection and I2C kernel support. Never substitute the
standard AX3000T or ubootmod target. The retired fixed-release build and local
source-branch overrides are removed.

Use Jerrykuku's Argon source pinned in `scripts/argon.commit`. Its integrated
settings retain the `argon-config` translation domain. Clone the standalone
package into `package/luci-theme-argon` (not a feed root): LuCI derives its package
name from that directory. This checkout is managed and reset to the pin on refresh. The full image includes
the theme and `luci-i18n-argon-config-zh-cn`. Set the image's default LuCI config
to Argon; remove the upstream runtime theme-selection write, retaining theme
registration and Argon's own configuration migrations. Restored UCI files keep
their theme/language choices. Recovery uses Bootstrap without Argon or xinfc.
Restore both full build config and full source theme defaults on exit.

Import the user-supplied xinfc 1.0.1-r1 APK using apk-tools 3.0.3 `adbdump` and
`extract --allow-untrusted`. This flag is used only to unpack the explicit local
artifact, never to install firmware dependencies. Retain the original APK,
metadata, byte-identical six-file payload and SHA256 list in the local package.
The static AArch64 writer is not stripped or relinked.

Wrap the payload as a normal OpenWrt package (1.0.1-r2) for native APK/IPK
packaging. Add the explicit flock/I2C prerequisites. Offline lifecycle scripts
return before host inspection or service operations. First boot only initializes
private backup storage; manual runtime installation retains the original
hardware checks. Keep `/etc/xinfc/` in the upgrade backup list and never delete
or overwrite the first NFC backup. No automatic NFC writes are introduced.

## Consequences and limitations

`feeds.conf` is managed output regenerated from `feeds.conf.default`; configure
additional upstream feeds in the latter. Reinstall feed links to avoid stale
third-party packages. Removed proxy integration is not built or documented;
historical changelog entries remain unchanged.

The supplied APK declares GPL-2.0-or-later but contains no corresponding writer
source. Its source provenance/license obligations must be resolved before public
redistribution; this import does not claim a reproducible binary from source.

On 2026-10-30, the GitHub upstream `openwrt-24.10` source inspected during this
change had no `xiaomi_mi-router-ax3000t-an8855` image definition. The repository's
earlier unconditional claim of native support cannot be relied on. Per the
user's follow-up decision, remove that workflow matrix entry and local override
instead of keeping a permanently failing build job.
The GitHub source files inspected were `target/linux/mediatek/image/filogic.mk`
and the corresponding DTS directory on that branch.

Offline contracts test target rejection, manifest gates, theme preservation,
payload integrity, install permissions and host-safe hooks. These are not a
substitute for OpenWrt cross-builds, measured image sizes or hardware NFC tests.
The full-image export also requires a nonempty compiled Chinese LMO catalog in
the staged rootfs and an Argon default there; recovery must contain neither that
catalog nor an Argon default.
