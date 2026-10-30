#!/bin/bash
# Refresh Nikki and install the pinned Argon theme and repository packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="$(cd "${1:?Usage: $0 <openwrt-dir>}" && pwd)"
cd "$TREE"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Regenerate managed feeds from upstream defaults, not stale third-party feeds.
awk '$1 ~ /^src-/ && ($2 == "nikki" || $2 == "ax3000t") { next } { print }' \
    feeds.conf.default > "$tmp"
cat "$tmp" > feeds.conf
ARGON_COMMIT="$(tr -d '[:space:]' < "$ROOT/scripts/argon.commit")"
[[ "$ARGON_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid Argon source pin" >&2; exit 1; }
printf '\nsrc-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main\n' >> feeds.conf
printf 'src-link ax3000t %s/packages\n' "$ROOT" >> feeds.conf

# Argon is a standalone package, not a feed containing package subdirectories.
# Its directory name also determines LUCI_NAME in luci.mk.
ARGON="$TREE/package/luci-theme-argon"
if [ ! -d "$ARGON/.git" ]; then
    [ ! -e "$ARGON" ] || { echo "Unmanaged Argon package directory: $ARGON" >&2; exit 1; }
    git clone --depth 1 --no-checkout https://github.com/jerrykuku/luci-theme-argon.git "$ARGON"
fi
git -C "$ARGON" fetch --depth 1 https://github.com/jerrykuku/luci-theme-argon.git "$ARGON_COMMIT"
git -C "$ARGON" checkout --force --detach "$ARGON_COMMIT"
git -C "$ARGON" rev-parse HEAD > argon-source.commit
[ "$(cat argon-source.commit)" = "$ARGON_COMMIT" ] || {
    echo "Argon source does not match the pinned revision" >&2; exit 1;
}
[ -s "$ARGON/po/zh_Hans/argon-config.po" ] || {
    echo "Argon Simplified Chinese translation source is missing" >&2; exit 1;
}

./scripts/feeds uninstall -a
./scripts/feeds update -a
./scripts/feeds install -a
# Explicitly choose Nikki's stable Mihomo provider, not another feed's provider.
./scripts/feeds install -f -p nikki nikki luci-app-nikki mihomo-meta
./scripts/feeds install -f -p ax3000t luci-app-xinfc
git -C feeds/nikki rev-parse HEAD > nikki-source.commit
bash "$ROOT/scripts/configure-argon.sh" "$TREE" full
printf 'Nikki source revision: %s\n' "$(cat nikki-source.commit)"
