#!/bin/bash
# Refresh upstream sources on every build; do not use downloaded release APKs.
set -euo pipefail

TREE="${1:?Usage: $0 <openwrt-dir>}"
cd "$TREE"
[ -f feeds.conf ] || cp feeds.conf.default feeds.conf
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk '$1 ~ /^src-/ && ($2 == "openclash" || $2 == "nikki") { next } { print }' \
    feeds.conf > "$tmp"
cat "$tmp" > feeds.conf
printf '\nsrc-git openclash https://github.com/vernesong/OpenClash.git\n' >> feeds.conf
printf 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main\n' >> feeds.conf

./scripts/feeds update -a
./scripts/feeds install -a
# Explicitly choose Nikki's stable Mihomo provider, not another feed's provider.
./scripts/feeds install -f -p nikki nikki luci-app-nikki mihomo-meta
git -C feeds/nikki rev-parse HEAD > nikki-source.commit
printf 'Nikki source revision: %s\n' "$(cat nikki-source.commit)"
