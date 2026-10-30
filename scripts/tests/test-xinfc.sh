#!/bin/bash
# Exercise the real package install recipe and scripts without a cross compiler.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGE="$ROOT/packages/luci-app-xinfc"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
require_ipk_writer() {
    # Drain the listing; grep -q can SIGPIPE GNU tar under set -o pipefail.
    tar -tzf - | grep -x './usr/sbin/xinfc-wsc' >/dev/null
}
(cd "$PACKAGE"; sha256sum -c SHA256SUMS)
python3 - "$PACKAGE" "$WORK" <<'PY'
import io
import json
import struct
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1]) / "files"
writer = (root / "usr/sbin/xinfc-wsc").read_bytes()
assert writer[:5] == b"\x7fELF\x02", "Writer must be ELF64"
assert struct.unpack_from("<H", writer, 18)[0] == 183, "Writer must be AArch64"
phoff = struct.unpack_from("<Q", writer, 32)[0]
phsize, phnum = struct.unpack_from("<HH", writer, 54)
assert all(struct.unpack_from("<I", writer, phoff + n * phsize)[0] != 3
           for n in range(phnum)), "Writer must not have a dynamic interpreter"
for path in root.rglob("*.json"):
    json.loads(path.read_text())
assert (root / "lib/upgrade/keep.d/xinfc").read_text().strip() == "/etc/xinfc/"
print("ok: original payload hashes, static ARM64 ELF, JSON and backup preservation")
# Force the listing to exceed pipe buffers, with the required entry first.
# This catches grep -q closing the tar pipe before the producer has finished.
with tarfile.open(Path(sys.argv[2]) / "listing-regression.tar.gz", "w:gz") as archive:
    for name in ["./usr/sbin/xinfc-wsc", *[
        f"./usr/share/listing-fixture/{index:05d}-" + "x" * 90
        for index in range(3000)
    ]]:
        entry = tarfile.TarInfo(name)
        entry.size = 0
        archive.addfile(entry, io.BytesIO())
with tarfile.open(Path(sys.argv[2]) / "missing-writer.tar.gz", "w:gz") as archive:
    entry = tarfile.TarInfo("./usr/sbin/not-the-required-writer")
    archive.addfile(entry, io.BytesIO())
PY
require_ipk_writer < "$WORK/listing-regression.tar.gz"
if require_ipk_writer < "$WORK/missing-writer.tar.gz"; then
    echo "FAIL: IPK listing accepted a missing NFC writer"; exit 1
fi
echo "ok: IPK listing validation drains large producer output under pipefail"

mkdir -p "$WORK/sdk/include"
: > "$WORK/sdk/rules.mk"
cat > "$WORK/sdk/include/package.mk" <<'EOF'
PKG_BUILD_DIR:=$(TEST_WORK)/build
INSTALL_DIR:=install -d -m0755
INSTALL_BIN:=install -m0755
INSTALL_DATA:=install -m0644
define BuildPackage
$(foreach script,preinst postinst postrm,$(file >$(TEST_WORK)/$(script),$(Package/$(1)/$(script))))
.PHONY: all
all:
	$$(Build/Prepare)
	$$(call Package/$(1)/install,$$(TEST_DEST))
endef
EOF
make -s -C "$PACKAGE" TOPDIR="$WORK/sdk" INCLUDE_DIR="$WORK/sdk/include" \
    TEST_WORK="$WORK" TEST_DEST="$WORK/root" all
for file in usr/sbin/xinfc-wsc usr/libexec/rpcd/luci.xinfc etc/uci-defaults/95-xinfc-state; do
    [ "$(stat -c %a "$WORK/root/$file")" = 755 ]
done
for file in lib/upgrade/keep.d/xinfc usr/share/luci/menu.d/luci-app-xinfc.json \
    usr/share/rpcd/acl.d/luci-app-xinfc.json www/luci-static/resources/view/xinfc.js; do
    [ "$(stat -c %a "$WORK/root/$file")" = 644 ]
    cmp "$WORK/root/$file" "$PACKAGE/files/$file"
done
cmp "$WORK/root/usr/sbin/xinfc-wsc" "$PACKAGE/files/usr/sbin/xinfc-wsc"
cmp "$WORK/root/usr/libexec/rpcd/luci.xinfc" "$PACKAGE/files/usr/libexec/rpcd/luci.xinfc"

# Every lifecycle script must return before even attempting id/stat/service calls.
mkdir -p "$WORK/tools"
for command in id stat mkdir rm; do
    printf '#!/bin/sh\necho "FAIL: touched host: %s" >&2\nexit 42\n' "$command" > "$WORK/tools/$command"
    chmod +x "$WORK/tools/$command"
done
for script in "$WORK/preinst" "$WORK/postinst" "$WORK/postrm" "$WORK/root/etc/uci-defaults/95-xinfc-state"; do
    sh -n "$script"
    IPKG_INSTROOT="$WORK/root" PATH="$WORK/tools:$PATH" sh "$script"
done
[ ! -e "$WORK/root/etc/xinfc" ]
echo "ok: actual package install preserves modes and all offline hooks avoid the host"
if env -u IPKG_INSTROOT sh "$WORK/preinst" > "$WORK/preinst.log" 2>&1; then
    echo "FAIL: runtime install accepted a non-router host"; exit 1
fi
grep -Eq 'Root required|AX3000T device tree not found' "$WORK/preinst.log"
echo "ok: runtime preinstall retains the hardware checks"

# Exercise first-boot storage initialization in a sandbox, never on /etc/xinfc.
sed "s|/etc/xinfc|$WORK/state|g; s|0:700|$(id -u):700|g" \
    "$PACKAGE/runtime/95-xinfc-state" > "$WORK/initialize"
env -u IPKG_INSTROOT sh "$WORK/initialize"
[ "$(stat -c %a "$WORK/state")" = 700 ]
printf 'first NFC backup\n' > "$WORK/state/nfc_ndef_backup.bin"
cp "$WORK/state/nfc_ndef_backup.bin" "$WORK/first-backup"
env -u IPKG_INSTROOT sh "$WORK/initialize"
cmp "$WORK/first-backup" "$WORK/state/nfc_ndef_backup.bin"
chmod 755 "$WORK/state"
if env -u IPKG_INSTROOT sh "$WORK/initialize"; then
    echo "FAIL: insecure state directory accepted"; exit 1
fi
chmod 700 "$WORK/state"
mv "$WORK/state" "$WORK/real-state"
ln -s "$WORK/real-state" "$WORK/state"
if env -u IPKG_INSTROOT sh "$WORK/initialize"; then
    echo "FAIL: symlink state directory accepted"; exit 1
fi
! grep -q 'xinfc-wsc' "$PACKAGE/runtime/95-xinfc-state"
echo "ok: first boot creates private storage, preserves the first backup and rejects unsafe paths"

# Optional native APK smoke test. The normal OpenWrt recipe handles both formats.
if command -v apk >/dev/null; then
    apk mkpkg --info name:luci-app-xinfc --info version:1.0.1-r2 \
        --info arch:aarch64_cortex-a53 --files "$WORK/root" \
        --script "pre-install:$WORK/preinst" --script "post-install:$WORK/postinst" \
        --script "post-deinstall:$WORK/postrm" --output "$WORK/xinfc.apk"
    mkdir "$WORK/extracted"
    apk --allow-untrusted extract --destination "$WORK/extracted" "$WORK/xinfc.apk"
    diff -r "$WORK/root" "$WORK/extracted"
    echo "ok: native APK packaging and extraction preserve the staged root"
fi
if command -v ar >/dev/null; then
    mkdir "$WORK/ipk"
    printf '2.0\n' > "$WORK/ipk/debian-binary"
    printf 'Package: luci-app-xinfc\nVersion: 1.0.1-r2\nArchitecture: aarch64_cortex-a53\n' > "$WORK/control"
    tar -czf "$WORK/ipk/control.tar.gz" -C "$WORK" control preinst postinst postrm
    tar -czf "$WORK/ipk/data.tar.gz" -C "$WORK/root" .
    (cd "$WORK/ipk"; ar cr "$WORK/xinfc.ipk" debian-binary control.tar.gz data.tar.gz)
    ar p "$WORK/xinfc.ipk" data.tar.gz | require_ipk_writer
    echo "ok: IPK container smoke test includes the same static writer and package hooks"
fi
