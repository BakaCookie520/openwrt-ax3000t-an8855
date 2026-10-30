#!/bin/bash
# Real local Git remotes: update a reused checkout without pins or data loss.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CHECK="$ROOT/scripts/checkout-openwrt-main.sh"
git init -q -b main "$WORK/upstream"
git -C "$WORK/upstream" config user.name test
git -C "$WORK/upstream" config user.email test@example.invalid
echo original > "$WORK/upstream/source"
git -C "$WORK/upstream" add source
git -C "$WORK/upstream" commit -qm initial

# Redirect only the production clone URL to the local fixture, using real Git.
TEST_REAL_GIT="$(command -v git)"
export TEST_REAL_GIT
export TEST_UPSTREAM="file://$WORK/upstream"
mkdir "$WORK/tools"
cat > "$WORK/tools/git" <<'EOF'
#!/bin/bash
set -euo pipefail
arguments=()
for argument in "$@"; do
    if [ "$argument" = https://git.openwrt.org/openwrt/openwrt.git ]; then
        argument="$TEST_UPSTREAM"
    fi
    arguments+=("$argument")
done
exec "$TEST_REAL_GIT" "${arguments[@]}"
EOF
chmod +x "$WORK/tools/git"
PATH="$WORK/tools:$PATH" bash "$CHECK" "$WORK/fresh"
[ "$(git -C "$WORK/fresh" rev-parse HEAD)" = "$(git -C "$WORK/upstream" rev-parse HEAD)" ]
echo "ok: fresh checkout clones main at the resolved upstream revision"

git clone -q "file://$WORK/upstream" "$WORK/tree"
old="$(git -C "$WORK/tree" rev-parse HEAD)"

advance() {
    echo "$1" > "$WORK/upstream/source"
    git -C "$WORK/upstream" commit -qam "$1"
}
advance newer
bash "$CHECK" "$WORK/tree"
new="$(git -C "$WORK/upstream" rev-parse HEAD)"
[ "$old" != "$new" ]
[ "$(git -C "$WORK/tree" rev-parse HEAD)" = "$new" ]
grep -qx newer "$WORK/tree/source"
echo "ok: reused checkout follows latest main, even from an older commit"

# Reusing the same revision preserves applied patches and untracked config.
echo local-edit > "$WORK/tree/source"
echo config > "$WORK/tree/.config"
bash "$CHECK" "$WORK/tree"
grep -qx local-edit "$WORK/tree/source"
grep -qx config "$WORK/tree/.config"

advance newest
if bash "$CHECK" "$WORK/tree" > "$WORK/error" 2>&1; then
    echo "FAIL: update discarded tracked edits"; exit 1
fi
grep -q 'refusing to overwrite' "$WORK/error"
[ "$(git -C "$WORK/tree" rev-parse HEAD)" = "$new" ]
grep -qx local-edit "$WORK/tree/source"
git -C "$WORK/tree" add source
if bash "$CHECK" "$WORK/tree" > "$WORK/error" 2>&1; then
    echo "FAIL: update discarded staged edits"; exit 1
fi
grep -qx local-edit "$WORK/tree/source"
echo "ok: dirty or staged trees fail closed instead of losing edits or building stale main"

# Test-only reset in this disposable fixture, never in the user's source tree.
git -C "$WORK/tree" reset --hard -q HEAD
bash "$CHECK" "$WORK/tree"
[ "$(git -C "$WORK/tree" rev-parse HEAD)" = "$(git -C "$WORK/upstream" rev-parse HEAD)" ]
grep -qx config "$WORK/tree/.config"
git -C "$WORK/tree" remote set-url origin "$WORK/missing-upstream"
if bash "$CHECK" "$WORK/tree" > "$WORK/error" 2>&1; then
    echo "FAIL: failed fetch silently reused old main"; exit 1
fi
mkdir "$WORK/not-a-checkout"
if bash "$CHECK" "$WORK/not-a-checkout" > "$WORK/error" 2>&1; then
    echo "FAIL: accepted non-checkout"; exit 1
fi
echo "ok: failed fetch or invalid checkout cannot fall back to old sources"

CI="$ROOT/.github/workflows/ci.yml"
grep -qF "cron: '0 2 * * *'" "$CI"
grep -qF 'checkout-openwrt-main.sh' "$CI"
grep -qF 'checkout-openwrt-main.sh' "$ROOT/setup.sh"
if grep -qE 'VERIFIED_COMMIT|update-verified-commit|checkout --force' "$CI" "$ROOT/setup.sh" "$CHECK"; then
    echo "FAIL: latest-main entry point contains an old pin or forced checkout"; exit 1
fi
grep -q "OpenWrt commit:.*git -C.*rev-parse HEAD" "$ROOT/scripts/build-firmware.sh"
echo "ok: local and daily CI share latest-main checkout; build metadata records the actual revision"
