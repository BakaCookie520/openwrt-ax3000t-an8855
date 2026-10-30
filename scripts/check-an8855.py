#!/usr/bin/env python3
"""Fail closed on an incorrect AX3000T target, flash layout or NFC support."""

import re
import sys
from pathlib import Path

DEVICE = "xiaomi_mi-router-ax3000t-an8855"
COMPATIBLE = "xiaomi,mi-router-ax3000t-an8855"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def uncomment(text):
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def block_at(text, start):
    """Read one brace-delimited DTS node, including nested nodes."""
    opening = text.index("{", start)
    depth = 1
    for pos in range(opening + 1, len(text)):
        depth += (text[pos] == "{") - (text[pos] == "}")
        if depth == 0:
            return text[opening + 1 : pos]
    raise ValueError("Unterminated device-tree node")


def check(tree, source_only=False):
    config = "" if source_only else (tree / ".config").read_text()
    if not source_only:
        selected = re.findall(r"^(CONFIG_TARGET_\S+_DEVICE_\S+)=y$", config, re.M)
        require(
            selected == [f"CONFIG_TARGET_mediatek_filogic_DEVICE_{DEVICE}"],
            "Only the AN8855 target may be selected (no stock/ubootmod/multi-device images)",
        )
        require("CONFIG_TARGET_MULTI_PROFILE=y" not in config, "Multi-profile builds are forbidden")
        for symbol in ("CONFIG_TARGET_mediatek", "CONFIG_TARGET_mediatek_filogic"):
            require(f"{symbol}=y" in config.splitlines(), f"Missing target selection: {symbol}")
    mediatek = tree / "target/linux/mediatek"
    image = (mediatek / "image/filogic.mk").read_text()
    definition = re.search(
        rf"^define Device/{DEVICE}\s*$(.*?)^endef\s*$", image, re.M | re.S
    )
    require(definition, "AN8855 image definition is missing; patches are incomplete")
    dts_match = re.search(r"^\s*DEVICE_DTS\s*:?=\s*(\S+)", definition[1], re.M)
    require(dts_match, "AN8855 DEVICE_DTS must be explicit")
    dts_root = mediatek / "dts"
    entry = dts_root / f"{dts_match[1]}.dts"
    visited = set()

    def read_dts(path):
        path = path.resolve()
        require(path.is_relative_to(dts_root.resolve()), "Device-tree include escapes DTS directory")
        if path in visited:
            return ""
        visited.add(path)
        text = uncomment(path.read_text())
        # SoC DTSIs come from the kernel's DTS include path, not this directory.
        # Board-local includes define flash partitions and NFC and must exist.
        includes = re.findall(r'(?:#include|/include/)\s*"([^"]+\.dtsi?)"', text)
        includes = [name for name in includes if not re.fullmatch(r"mt\d+[a-z]?\.dtsi", name)]
        return "\n".join([*(read_dts(path.parent / name) for name in includes), text])

    dts = read_dts(entry)
    require(f'"{COMPATIBLE}"' in dts, "AN8855 device-tree compatible is missing")
    require(not re.search(r'label\s*=\s*"ubi_kernel"', dts), "Dual-partition ubi_kernel is forbidden")
    ubi = []
    for match in re.finditer(r"\bpartition@[0-9a-fA-F]+\s*\{", dts):
        node = block_at(dts, match.start())
        if re.search(r'label\s*=\s*"ubi"\s*;', node):
            ubi.append(node)
    require(len(ubi) == 1, "Expected exactly one UBI partition")
    cells = re.search(r"\breg\s*=\s*<([^>]+)>", ubi[0])
    require(cells, "UBI partition has no address/size")
    require(
        [int(cell, 0) for cell in cells[1].split()] == [0x600000, 0x7000000],
        "AN8855 requires the 112 MiB single UBI partition at 0x600000",
    )
    platform = uncomment((mediatek / "filogic/base-files/lib/upgrade/platform.sh").read_text())
    # The board may share a case arm with other single-UBI devices.
    upgrade = re.search(rf"{re.escape(COMPATIBLE)}[^)]*\)(.*?);;", platform, re.S)
    require(
        upgrade and re.search(r'CI_UBIPART=["\']?ubi["\']?\s', upgrade[1])
        and "nand_do_upgrade" in upgrade[1],
        "AN8855 single-UBI upgrade handler is missing",
    )
    i2c_nodes = [
        block_at(dts, match.start()) for match in re.finditer(r"&i2c0\s*\{", dts)
    ]
    statuses = [
        status for node in i2c_nodes
        for status in re.findall(r'\bstatus\s*=\s*"([^"]+)"', node)
    ]
    require(statuses and statuses[-1] == "okay", "NFC I2C bus must be enabled")
    require(not re.search(r"/delete-node/\s+nfc@57", dts), "NFC node must not be deleted")
    nfc_nodes = [
        block_at(dts, match.start()) for match in re.finditer(r"\bnfc@57\s*\{", dts)
    ]
    compatibles = [
        value for node in nfc_nodes
        for value in re.findall(r'\bcompatible\s*=\s*"([^"]+)"', node)
    ]
    require(compatibles and compatibles[-1] == "nt082c", "NT082C NFC declaration is missing")
    addresses = [
        value for node in nfc_nodes
        for value in re.findall(r"\breg\s*=\s*<([^>]+)>", node)
    ]
    require(addresses and addresses[-1].strip() == "0x57", "Wrong NFC address")
    if source_only:
        print("ok: AN8855 single-UBI sources and NFC declaration")
        return
    kernel_configs = list((mediatek / "filogic").glob("config-*"))
    require(kernel_configs, "Missing Filogic kernel configuration")
    for path in kernel_configs:
        kernel = path.read_text().splitlines()
        require("CONFIG_I2C_MT65XX=y" in kernel, f"Missing I2C controller support: {path.name}")
        for symbol in ("I2C", "I2C_CHARDEV"):
            require(
                f"CONFIG_{symbol}=y" in kernel
                or "CONFIG_PACKAGE_kmod-i2c-core=y" in config.splitlines(),
                f"Missing {symbol} support",
            )
    print("ok: AN8855-only target, single UBI upgrade layout and NFC support")


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        source_only = "--source-only" in arguments
        arguments = [arg for arg in arguments if arg != "--source-only"]
        require(len(arguments) == 1, "Usage: check-an8855.py [--source-only] <openwrt-dir>")
        check(Path(arguments[0]), source_only)
    except (IndexError, OSError, ValueError) as error:
        sys.exit(f"AN8855 safety check failed: {error}")
