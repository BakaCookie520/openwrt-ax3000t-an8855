#!/bin/bash
# Run the real patch steps with an offset hunk, which normally creates .orig.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SCRIPT_DIR="$ROOT/scripts"
export REPO_PATCH_DIR="$WORK/patches"
mkdir -p "$REPO_PATCH_DIR"
printf 'test DTS\n' > "$REPO_PATCH_DIR/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts"
cat > "$REPO_PATCH_DIR/test.patch" <<'EOF'
--- a/target/linux/mediatek/filogic/base-files/etc/board.d/02_network
+++ b/target/linux/mediatek/filogic/base-files/etc/board.d/02_network
@@ -1,3 +1,3 @@
 #!/bin/sh
-printf '%s\n' lan1 lan2 lan3 lan4 >> "$TEST_PORTS"
+printf '%s\n' lan2 lan3 lan4 >> "$TEST_PORTS"
 # end
--- a/target/linux/mediatek/image/filogic.mk
+++ b/target/linux/mediatek/image/filogic.mk
@@ -1 +1 @@
-Device/placeholder
+Device/xiaomi_mi-router-ax3000t-an8855
--- a/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh
+++ b/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh
@@ -1 +1 @@
-placeholder
+xiaomi,mi-router-ax3000t-an8855
EOF

fixture() {
    export OPENWRT_DIR="$1"
    export TEST_PORTS="$1/ports"
    mkdir -p "$1/target/linux/mediatek/"{image,dts,filogic/base-files/etc/board.d,filogic/base-files/lib/upgrade}
    # Extra leading line forces an offset instead of an exact match.
    cat > "$1/target/linux/mediatek/filogic/base-files/etc/board.d/02_network" <<'EOF'
# shifted upstream source
#!/bin/sh
printf '%s\n' lan1 lan2 lan3 lan4 >> "$TEST_PORTS"
# end
EOF
    printf 'Device/placeholder\n' > "$1/target/linux/mediatek/image/filogic.mk"
    printf 'placeholder\n' > "$1/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
}

assert_ports() {
    : > "$TEST_PORTS"
    for script in "$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/"*; do
        sh "$script"
    done
    printf 'lan2\nlan3\nlan4\n' > "$WORK/expected"
    if ! cmp -s "$WORK/expected" "$TEST_PORTS"; then
        echo "FAIL: backup scripts introduced duplicate/phantom ports"
        cat "$TEST_PORTS"
        exit 1
    fi
}

for workflow in ci stable-latest; do
    awk '
        /- name: Apply an8855 patches/ { found=1; next }
        found && /- name:/ { exit }
        found && /run: \|/ { code=1; next }
        code { sub(/^          /, ""); print }
    ' "$ROOT/.github/workflows/$workflow.yml" > "$WORK/patch-step"
    fixture "$WORK/$workflow"
    bash -e "$WORK/patch-step"
    assert_ports
    echo "ok: $workflow offset patch cannot add duplicate ports"
    printf '#!/bin/sh\nprintf "lan1\\nlan2\\n" >> "$TEST_PORTS"\n' \
        > "$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network.orig"
    bash -e "$WORK/patch-step"
    assert_ports
    echo "ok: $workflow reused source tree removes 02_network.orig"
done

awk '
    /=== 步骤 2.5:/ { found=1 }
    found && /=== 步骤 3:/ { exit }
    found { print }
' "$ROOT/setup.sh" > "$WORK/local-patch-step"
fixture "$WORK/local"
export BRANCH=main
( cd "$OPENWRT_DIR"; bash -e "$WORK/local-patch-step" )
assert_ports
echo "ok: local offset patch cannot add duplicate ports"

# A reused tree skips patching, but must still remove the known old backup.
printf '#!/bin/sh\nprintf "lan1\\nlan2\\n" >> "$TEST_PORTS"\n' \
    > "$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network.orig"
( cd "$OPENWRT_DIR"; bash -e "$WORK/local-patch-step" )
assert_ports
echo "ok: reused source tree does not retain 02_network.orig"

CHECK="$ROOT/scripts/check-board-scripts.sh"
bash "$CHECK" "$OPENWRT_DIR"
for dir in \
    "$OPENWRT_DIR/package/base-files/files/etc/board.d" \
    "$OPENWRT_DIR/target/linux/mediatek/base-files/etc/board.d" \
    "$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d" \
    "$OPENWRT_DIR/files/etc/board.d" \
    "$OPENWRT_DIR/build_dir/target-test/root-mediatek/etc/board.d"; do
    mkdir -p "$dir"
    for suffix in .orig .rej '~'; do
        printf '#!/bin/sh\n' > "$dir/02_network$suffix"
        if bash "$CHECK" "$OPENWRT_DIR" > "$WORK/guard.log" 2>&1; then
            echo "FAIL: board script guard missed $dir/02_network$suffix"
            exit 1
        fi
        grep -qF "unsafe board.d backup/reject file: $dir/02_network$suffix" "$WORK/guard.log"
        rm "$dir/02_network$suffix"
    done
done
echo "ok: guard rejects backup/reject files in source, overrides and staged roots"
