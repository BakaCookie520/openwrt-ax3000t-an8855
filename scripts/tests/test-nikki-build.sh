#!/bin/bash
# Offline contract tests: no cross compiler, downloads or router are required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tools"
export PATH="$WORK/tools:$PATH"

cat > "$WORK/tools/make" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$*" != defconfig ] || exit 0
case "$*" in *package/feeds/openclash/*) exit 0 ;; esac
target=bin/targets/mediatek/filogic
mkdir -p "$target/packages" bin/packages/test/nikki
image="$target/openwrt-test-xiaomi_mi-router-ax3000t-an8855"
kernel='6.12.test~matching-r1'
if grep -qx CONFIG_PACKAGE_nikki=y .config; then
    printf 'full-image-with-mihomo\n' > "$image-squashfs-sysupgrade.bin"
    truncate -s $((27*1024*1024)) "$image-initramfs-kernel.bin"
    printf 'oversize-full-recovery-must-not-be-published\n' > "$image-initramfs-factory.ubi"
    {
        printf 'kernel - %s\n' "$kernel"
        for p in nikki mihomo-meta luci-app-nikki luci-i18n-nikki-zh-cn \
            ttyd luci-app-ttyd tailscale luci-app-tailscale-community \
            kmod-inet-diag kmod-dummy kmod-nft-socket kmod-nft-tproxy kmod-tun; do
            printf '%s - 1.0\n' "$p"
        done
    } > "$target/openwrt-test.manifest"
    for p in kmod-inet-diag kmod-dummy kmod-nft-socket; do
        if [ "${TEST_MISSING_MODULE:-0}" = 1 ] && [ "$p" = kmod-dummy ]; then continue; fi
        printf 'matching package\n' > "$target/packages/${p}_1.0_test.apk"
    done
    printf 'package\n' > bin/packages/test/nikki/nikki_1.0_test.apk
else
    printf 'recovery-overwrites-target-sysupgrade\n' > "$image-squashfs-sysupgrade.bin"
    truncate -s $(( ${TEST_OVERSIZE_RECOVERY:-1} *1024*1024)) "$image-initramfs-kernel.bin"
    printf 'safe-recovery\n' > "$image-initramfs-factory.ubi"
    [ "${TEST_CHANGED_ABI:-0}" != 1 ] || kernel='6.12.test~WRONG-r1'
    printf 'kernel - %s\nttyd - 1.0\nluci-app-ttyd - 1.0\n' "$kernel" \
        > "$target/openwrt-test.manifest"
fi
EOF
chmod +x "$WORK/tools/make"

fixture() {
    local tree="$1"
    mkdir -p "$tree/scripts"
    git -C "$tree" init -q
    git -C "$tree" -c user.name=Fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false commit --allow-empty -qm fixture
    printf 'fixture-source-sha\n' > "$tree/nikki-source.commit"
    printf 'CONFIG_CUSTOM_KEEP=y\nCONFIG_PACKAGE_kmod-custom=y\n' > "$tree/.config"
}

fixture "$WORK/profile"
bash "$ROOT/scripts/apply-build-profile.sh" "$WORK/profile" full
grep -qx CONFIG_PACKAGE_nikki=y "$WORK/profile/.config"
grep -qx CONFIG_PACKAGE_mihomo-meta=y "$WORK/profile/.config"
grep -qx CONFIG_PACKAGE_luci-i18n-nikki-zh-cn=y "$WORK/profile/.config"
grep -qx CONFIG_PACKAGE_ttyd=y "$WORK/profile/.config"
bash "$ROOT/scripts/apply-build-profile.sh" "$WORK/profile" recovery
grep -qx CONFIG_PACKAGE_nikki=m "$WORK/profile/.config"
grep -qx CONFIG_PACKAGE_tailscale=m "$WORK/profile/.config"
grep -qx CONFIG_PACKAGE_yq=m "$WORK/profile/.config"
grep -qx CONFIG_PACKAGE_kmod-custom=y "$WORK/profile/.config"
grep -qx CONFIG_CUSTOM_KEEP=y "$WORK/profile/.config"
[ "$(grep -c '^CONFIG_PACKAGE_nikki=' "$WORK/profile/.config")" = 1 ]
if (cd "$WORK/profile"; FIRMWARE_PROFILE=invalid bash "$ROOT/scripts/generate-config-seed.sh"); then
    echo "FAIL: invalid profile accepted"; exit 1
fi
echo "ok: full/recovery profiles keep kernel and unrelated settings"

fixture "$WORK/success"
BUILD_JOBS=1 bash "$ROOT/scripts/build-firmware.sh" "$WORK/success" "$WORK/success-out"
grep -q full-image-with-mihomo "$WORK/success-out"/full-*-sysupgrade.bin
grep -q safe-recovery "$WORK/success-out"/recovery-*-factory.ubi
grep -qx CONFIG_PACKAGE_nikki=y "$WORK/success/.config"
[ "$(find "$WORK/success-out" -name '*initramfs*' | wc -l)" -eq 2 ]
tar -tzf "$WORK/success-out/packages.tar.gz" | grep -q kmod-dummy
(cd "$WORK/success-out"; sha256sum -c SHA256SUMS.txt)
echo "ok: full image survives recovery pass, matching packages exported, full config restored"

for failure in oversize abi missing-module; do
    fixture "$WORK/$failure"
    case "$failure" in
        oversize) export TEST_OVERSIZE_RECOVERY=27 ;;
        abi) export TEST_CHANGED_ABI=1 ;;
        missing-module) export TEST_MISSING_MODULE=1 ;;
    esac
    if BUILD_JOBS=1 bash "$ROOT/scripts/build-firmware.sh" \
        "$WORK/$failure" "$WORK/$failure-out" > "$WORK/$failure.log" 2>&1; then
        echo "FAIL: unsafe build accepted: $failure"; exit 1
    fi
    case "$failure" in
        oversize) grep -q 'initramfs 超过' "$WORK/$failure.log" ;;
        abi) grep -q 'Kernel ABI changed' "$WORK/$failure.log" ;;
        missing-module) grep -q 'Missing matching kernel package artifact' "$WORK/$failure.log" ;;
    esac
    unset TEST_OVERSIZE_RECOVERY TEST_CHANGED_ABI TEST_MISSING_MODULE
    grep -qx CONFIG_PACKAGE_nikki=y "$WORK/$failure/.config"
    [ ! -e "$WORK/$failure-out/SHA256SUMS.txt" ]
    echo "ok: $failure fails closed and restores full configuration"
done

# Feed setup is idempotent and refreshes main, even when a stale pin exists.
fixture "$WORK/feeds"
mkdir -p "$WORK/feeds/feeds/nikki"
git -C "$WORK/feeds/feeds/nikki" init -q
git -C "$WORK/feeds/feeds/nikki" -c user.name=Fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false commit --allow-empty -qm nikki
cat > "$WORK/feeds/scripts/feeds" <<'EOF'
#!/bin/sh
echo "$*" >> feed-calls
EOF
chmod +x "$WORK/feeds/scripts/feeds"
printf 'src-git base https://example.invalid/base\nsrc-git nikki https://example.invalid/old^pinned\n' \
    > "$WORK/feeds/feeds.conf"
for pass in 1 2; do bash "$ROOT/scripts/prepare-feeds.sh" "$WORK/feeds"; done
[ "$(grep -c '^src-git nikki ' "$WORK/feeds/feeds.conf")" = 1 ]
grep -qx 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' \
    "$WORK/feeds/feeds.conf"
[ "$(grep -c '^update -a$' "$WORK/feeds/feed-calls")" = 2 ]
grep -qx 'install -f -p nikki nikki luci-app-nikki mihomo-meta' "$WORK/feeds/feed-calls"
[ -s "$WORK/feeds/nikki-source.commit" ]
echo "ok: feed refresh is idempotent, follows main, and records its source revision"

for workflow in ci stable-latest; do
    grep -q 'prepare-feeds.sh' "$ROOT/.github/workflows/$workflow.yml"
    grep -q 'build-firmware.sh' "$ROOT/.github/workflows/$workflow.yml"
done
grep -q 'apply-build-profile.sh' "$ROOT/setup.sh"
grep -q 'build-firmware.sh' "$ROOT/setup.sh"
echo "ok: local, main, 24.10 and stable workflows use the shared implementation"
