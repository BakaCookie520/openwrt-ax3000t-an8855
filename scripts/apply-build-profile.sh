#!/bin/bash
# Change userspace inclusion without discarding unrelated kernel selections.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="$(cd "${1:?Usage: $0 <openwrt-dir> [full|recovery]}" && pwd)"
PROFILE="${2:-full}"
case "$PROFILE" in full|recovery) ;; *) echo "Unknown profile: $PROFILE" >&2; exit 1 ;; esac
cd "$TREE"
FIRMWARE_PROFILE="$PROFILE" bash "$ROOT/scripts/generate-config-seed.sh"
[ -f .config ] || touch .config
if [ "$PROFILE" = recovery ]; then
    # A removed userspace dependency must not silently deselect a kernel module.
    while IFS= read -r selection; do
        symbol="${selection%%=*}"
        grep -q "^${symbol}=" .config.seed || printf '%s\n' "$selection" >> .config.seed
    done < <(grep -E '^CONFIG_PACKAGE_kmod-[^=]+=[ym]$' .config || true)
fi
tmp="$(mktemp)"
trap 'rm -f "$tmp" .config.seed' EXIT
awk '
    function key(line) {
        sub(/^# /, "", line)
        sub(/[ =].*$/, "", line)
        return line
    }
    NR == FNR { if (key($0) ~ /^CONFIG_/) keys[key($0)] = 1; next }
    !(key($0) in keys) { print }
' .config.seed .config > "$tmp"
cat "$tmp" .config.seed > .config
make defconfig
bash "$ROOT/scripts/configure-argon.sh" "$TREE" "$PROFILE"
python3 "$ROOT/scripts/check-an8855.py" "$TREE"
