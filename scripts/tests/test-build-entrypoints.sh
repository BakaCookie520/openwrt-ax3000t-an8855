#!/bin/bash
# Removed branch overrides must fail before source checkout/download/build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tools"
export GIT_CALLS="$WORK/git-calls"
cat > "$WORK/tools/git" <<'EOF'
#!/bin/sh
echo "$*" >> "$GIT_CALLS"
exit 99
EOF
chmod +x "$WORK/tools/git"
export PATH="$WORK/tools:$PATH"
for argument in --branch --branch=openwrt-24.10 --branch=main; do
    arguments=("$argument")
    [ "$argument" != --branch ] || arguments+=(openwrt-24.10)
    if (cd "$WORK"; bash "$ROOT/setup.sh" "${arguments[@]}") > "$WORK/output" 2>&1; then
        echo "FAIL: retired source override accepted: $argument"; exit 1
    fi
    grep -q '未知参数' "$WORK/output"
    [ ! -e "$GIT_CALLS" ]
    [ ! -e "$WORK/openwrt-ax3000t" ]
done
CI="$ROOT/.github/workflows/ci.yml"
! grep -Eq 'openwrt-24\.10|matrix\.|strategy:' "$CI"
[ "$(grep -cF 'branches: [master]' "$CI")" = 2 ]
grep -qx '  BUILD_REF: main' "$CI"
grep -qF 'name: firmware-master-${{ github.sha }}' "$CI"
for workflow in ci stable-latest; do
    grep -q 'Apply an8855 patches' "$ROOT/.github/workflows/$workflow.yml"
    grep -q 'check-an8855.py' "$ROOT/.github/workflows/$workflow.yml"
    grep -q 'build-firmware.sh' "$ROOT/.github/workflows/$workflow.yml"
done
echo "ok: only patched mainline and stable builds remain; retired overrides fail before git"
