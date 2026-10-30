#!/bin/bash
# Resolve main once per invocation. Never silently build an old pin or discard edits.
set -euo pipefail

TREE="${1:?Usage: $0 <openwrt-dir>}"
if [ ! -e "$TREE" ]; then
    git clone --depth 1 --branch main --single-branch \
        https://git.openwrt.org/openwrt/openwrt.git "$TREE"
else
    [ -e "$TREE/.git" ] || {
        echo "Not an OpenWrt checkout: $TREE" >&2
        exit 1
    }
    git -C "$TREE" fetch --depth 1 origin \
        +refs/heads/main:refs/remotes/origin/main
fi

latest="$(git -C "$TREE" rev-parse refs/remotes/origin/main)"
current="$(git -C "$TREE" rev-parse HEAD)"
if [ "$latest" != "$current" ]; then
    if ! git -C "$TREE" diff --quiet || ! git -C "$TREE" diff --cached --quiet; then
        echo "Upstream main changed, but the checkout has tracked edits (possibly applied board patches)." >&2
        echo "Preserve your edits and use a clean checkout; refusing to overwrite them or build stale main." >&2
        exit 1
    fi
    git -C "$TREE" checkout --detach "$latest"
fi
printf 'Selected latest OpenWrt main: %s\n' "$latest"
