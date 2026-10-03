#!/bin/bash
# board_detect sources every file in board.d, including patch/editor backups.
set -euo pipefail

OPENWRT_DIR="${1:?Usage: $0 <openwrt-dir>}"
bad=0
for dir in \
    "$OPENWRT_DIR/package/base-files/files/etc/board.d" \
    "$OPENWRT_DIR/target/linux/mediatek/base-files/etc/board.d" \
    "$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d" \
    "$OPENWRT_DIR/files/etc/board.d" \
    "$OPENWRT_DIR"/build_dir/target-*/root-*/etc/board.d; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do
        printf 'FAIL: unsafe board.d backup/reject file: %s\n' "$file" >&2
        bad=1
    done < <(find "$dir" \( -type f -o -type l \) \
        \( -name '*.orig' -o -name '*.rej' -o -name '*~' \) -print0)
done
if [ "$bad" -ne 0 ]; then
    echo "Remove backups from runtime board.d directories before building." >&2
    exit 1
fi
echo "ok: board.d directories contain no patch/editor backups"
