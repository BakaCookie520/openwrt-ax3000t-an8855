#!/bin/bash
# CI-only pinned checkout. Local setup still resolves latest main by default.
set -euo pipefail
TREE="${1:?Usage: $0 <openwrt-dir> <main-or-stable-tag> <resolved-commit>}"
REF="${2:?Missing source ref}"
COMMIT="${3:?Missing resolved source commit}"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid source SHA" >&2; exit 1; }
[[ "$REF" = main || "$REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Invalid source ref" >&2; exit 1;
}
if [ ! -e "$TREE" ]; then
    git init -q "$TREE"
    git -C "$TREE" remote add origin https://git.openwrt.org/openwrt/openwrt.git
fi
[ -e "$TREE/.git" ] || { echo "Not an OpenWrt checkout: $TREE" >&2; exit 1; }
current="$(git -C "$TREE" rev-parse --verify HEAD 2>/dev/null || true)"
if [ "$current" != "$COMMIT" ]; then
    if ! git -C "$TREE" diff --quiet || ! git -C "$TREE" diff --cached --quiet; then
        echo "Pinned checkout has tracked edits; refusing to overwrite them." >&2
        exit 1
    fi
    git -C "$TREE" fetch --depth 1 origin "$COMMIT"
    [ "$(git -C "$TREE" rev-parse 'FETCH_HEAD^{commit}')" = "$COMMIT" ] || {
        echo "Fetched source differs from resolved SHA" >&2; exit 1;
    }
    git -C "$TREE" checkout --detach "$COMMIT"
fi
printf 'Selected OpenWrt %s at resolved commit: %s\n' "$REF" "$COMMIT"
