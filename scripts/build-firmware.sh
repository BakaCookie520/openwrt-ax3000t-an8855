#!/bin/bash
# Build a full installed system, then a small recovery system with the same ABI.
# Only the full sysupgrade and the size-checked recovery initramfs are exported.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="$(cd "${1:?Usage: $0 <openwrt-dir> [output-dir]}" && pwd)"
OUT="${2:-$TREE/bin/ax3000t-artifacts}"
TARGET="$TREE/bin/targets/mediatek/filogic"
JOBS="${BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN)}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
[ -z "$(find "$OUT" -mindepth 1 -print -quit)" ] || {
    echo "Artifact output must be empty; use a new output directory: $OUT" >&2
    exit 1
}
WORK="$(mktemp -d)"
restore_config() {
    [ ! -f "$WORK/full.config" ] || cp "$WORK/full.config" "$TREE/.config"
    if [ -f "$WORK/full.config" ]; then
        bash "$ROOT/scripts/configure-argon.sh" "$TREE" full
        python3 "$ROOT/scripts/configure-wireless-nfc.py" "$TREE" full
    fi
    rm -rf "$WORK"
}
trap restore_config EXIT

one_file() {
    local dir="$1" pattern="$2" files=()
    mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name "$pattern" | sort)
    [ "${#files[@]}" -eq 1 ] || {
        echo "Expected exactly one $pattern in $dir, got ${#files[@]}" >&2
        return 1
    }
    printf '%s\n' "${files[0]}"
}
require_package() {
    grep -Eq "^$2[[:space:]]+-[[:space:]]+" "$1" || {
        echo "Required installed package is missing from manifest: $2" >&2
        return 1
    }
}
build() {
    (cd "$TREE"; make -j"$JOBS" V=s) 2>&1 | tee -a "$OUT/build.log"
}

bash "$ROOT/scripts/check-board-scripts.sh" "$TREE"
# Do not silently repair a user-selected stock/multi-device image at build time.
python3 "$ROOT/scripts/check-an8855.py" "$TREE"
bash "$ROOT/scripts/apply-build-profile.sh" "$TREE" full
cp "$TREE/.config" "$WORK/full.config"
build
manifest="$(one_file "$TARGET" '*.manifest')"
for pkg in nikki mihomo-meta luci-app-nikki luci-i18n-nikki-zh-cn \
    ttyd luci-app-ttyd tailscale luci-app-tailscale-community \
    luci-theme-argon luci-i18n-argon-config-zh-cn luci-app-xinfc \
    kmod-inet-diag kmod-dummy kmod-nft-socket kmod-nft-tproxy kmod-tun; do
    require_package "$manifest" "$pkg"
done
# A package name alone does not prove the Chinese catalog/default reached rootfs.
mapfile -t roots < <(find "$TREE/build_dir" -maxdepth 3 -type d -name root-mediatek)
[ "${#roots[@]}" -eq 1 ] || { echo "Expected one staged Mediatek rootfs" >&2; exit 1; }
full_root="${roots[0]}"
[ -s "$full_root/www/luci-static/resources/xinfc/wireless.js" ] &&
    grep -q 'xinfc.wireless' "$full_root/www/luci-static/resources/view/network/wireless.js" || {
    echo "Wireless NFC integration is missing from full rootfs" >&2; exit 1;
}
[ -s "$full_root/usr/lib/lua/luci/i18n/argon-config.zh-cn.lmo" ] || {
    echo "Compiled Argon Simplified Chinese catalog is missing" >&2; exit 1;
}
grep -Eq "option[[:space:]]+mediaurlbase[[:space:]]+['\"]?/luci-static/argon" \
    "$full_root/etc/config/luci" || {
    echo "Full rootfs does not default to Argon" >&2; exit 1;
}
full_kernel="$(awk '$1 == "kernel" { print $3 }' "$manifest")"
[ -n "$full_kernel" ] || { echo "Missing full-image kernel ABI" >&2; exit 1; }
image="$(one_file "$TARGET" '*-squashfs-sysupgrade.bin')"
case "$image" in *ax3000t-an8855*) ;; *) echo "Wrong sysupgrade board: $image" >&2; exit 1 ;; esac
# Reserve 12 MiB of the 112 MiB UBI partition for overhead and writable storage.
[ "$(wc -c < "$image")" -le $((100 * 1024 * 1024)) ] || {
    echo "Full sysupgrade exceeds the conservative 100 MiB flash budget" >&2
    exit 1
}
cp "$image" "$OUT/full-$(basename "$image")"
cp "$manifest" "$OUT/full.manifest"
cp "$TREE/.config" "$OUT/full.config"
[ ! -f "$TARGET/config.buildinfo" ] || cp "$TARGET/config.buildinfo" "$OUT/full-config.buildinfo"
[ ! -f "$TARGET/feeds.buildinfo" ] || cp "$TARGET/feeds.buildinfo" "$OUT/full-feeds.buildinfo"

# Export matching packages before the recovery pass changes package metadata.
for pkg in kmod-inet-diag kmod-dummy kmod-nft-socket; do
    [ -n "$(find "$TARGET/packages" -type f \
        \( -name "${pkg}[_-]*.apk" -o -name "${pkg}[_-]*.ipk" \) -print -quit)" ] || {
        echo "Missing matching kernel package artifact: $pkg" >&2; exit 1;
    }
done
tar -czf "$OUT/packages.tar.gz" -C "$TREE/bin" \
    packages targets/mediatek/filogic/packages
while IFS= read -r key; do cp "$key" "$OUT/$(basename "$key")"; done \
    < <(find "$TREE" -maxdepth 1 -type f -name '*.pub')

# Switching only userspace packages to =m preserves kernel module selections.
# They are still buildable packages, but are not installed in the recovery root.
bash "$ROOT/scripts/apply-build-profile.sh" "$TREE" recovery
cp "$TREE/.config" "$OUT/recovery.config"
build
manifest="$(one_file "$TARGET" '*.manifest')"
recovery_kernel="$(awk '$1 == "kernel" { print $3 }' "$manifest")"
[ "$full_kernel" = "$recovery_kernel" ] || {
    echo "Kernel ABI changed between full and recovery; refusing to publish" >&2
    exit 1
}
for pkg in nikki mihomo-meta luci-app-nikki tailscale luci-app-tailscale-community yq \
    luci-theme-argon luci-i18n-argon-config-zh-cn luci-app-xinfc; do
    if grep -Eq "^$pkg[[:space:]]+-[[:space:]]+" "$manifest"; then
        echo "Heavy package leaked into recovery image: $pkg" >&2; exit 1
    fi
done
require_package "$manifest" ttyd
require_package "$manifest" luci-app-ttyd
grep -Eq "option[[:space:]]+mediaurlbase[[:space:]]+['\"]?/luci-static/bootstrap" \
    "$full_root/etc/config/luci" || {
    echo "Recovery rootfs does not default to Bootstrap" >&2; exit 1;
}
[ ! -e "$full_root/usr/lib/lua/luci/i18n/argon-config.zh-cn.lmo" ] || {
    echo "Argon catalog leaked into recovery rootfs" >&2; exit 1;
}
[ ! -e "$full_root/www/luci-static/resources/xinfc/wireless.js" ] &&
    ! grep -q 'xinfc.wireless' "$full_root/www/luci-static/resources/view/network/wireless.js" || {
    echo "Wireless NFC integration leaked into recovery rootfs" >&2; exit 1;
}
STRICT=1 HARD_LIMIT_MB=26 WARN_LIMIT_MB=25 \
    bash "$ROOT/scripts/check-image-size.sh" "$TARGET"
bash "$ROOT/scripts/check-board-scripts.sh" "$TREE"
image="$(one_file "$TARGET" '*-initramfs-factory.ubi')"
cp "$image" "$OUT/recovery-$(basename "$image")"
while IFS= read -r image; do
    cp "$image" "$OUT/recovery-$(basename "$image")"
done < <(find "$TARGET" -maxdepth 1 -type f \
    \( -name '*-initramfs-kernel.bin' -o -name '*-initramfs-kernel.itb' -o -name '*-initramfs.itb' \))
cp "$manifest" "$OUT/recovery.manifest"

{
    printf 'OpenWrt commit: %s\n' "$(git -C "$TREE" rev-parse HEAD)"
    printf 'Nikki main commit at feed refresh: %s\n' "$(cat "$TREE/nikki-source.commit")"
    printf 'Argon source commit: %s\n' "$(cat "$TREE/argon-source.commit")"
    printf 'xinfc original APK SHA256: %s\n' \
        "$(awk 'NR == 1 { print $1 }' "$ROOT/packages/luci-app-xinfc/SHA256SUMS")"
    printf 'Kernel package/ABI (both images): %s\n' "$full_kernel"
    printf 'Mihomo: stable mihomo-meta selected by the refreshed Nikki feed\n'
    printf 'full-*-sysupgrade.bin: Nikki/Mihomo, Tailscale, ttyd, Argon/Chinese and xinfc\n'
    printf 'recovery-*-initramfs*: no Nikki/Mihomo, Tailscale, Argon or xinfc\n'
    printf 'Argon is the clean-install default; retained theme/language choices are preserved.\n'
    printf 'xinfc never programs NFC during installation or first boot.\n'
    printf 'Full-image wireless security has default-checked NFC sync after confirmed Save & Apply.\n'
    printf 'NFC submission is not readback success; verify in Services / AX3000T NFC.\n'
    printf 'Nikki is disabled until a user configures and enables it.\n'
    printf 'ttyd uses upstream @lan binding and /bin/login; no credentials are embedded.\n'
    printf 'Preserved upgrade configs override defaults; check old ttyd bindings manually.\n'
} > "$OUT/BUILD-INFO.txt"
(cd "$OUT"; find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -print0 \
    | sort -z | xargs -0 sha256sum > SHA256SUMS.txt)
printf 'Validated dual-image artifacts: %s\n' "$OUT"
