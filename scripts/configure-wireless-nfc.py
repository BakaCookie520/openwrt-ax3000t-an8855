#!/usr/bin/env python3
"""Reversible, fail-closed LuCI integration for full/recovery source profiles."""
import sys
from pathlib import Path

REQUIRE = "'require xinfc.wireless as xinfcWireless';\n"
HOOK = "\t\t\t\tawait xinfcWireless.addOption(ss);\n"
TAB = "\t\t\t\tss.tab('encryption', _('Wireless Security'));\n"
MODAL = "return network.getWifiNetwork(s.section).then(function(radioNet) {"
ASYNC_MODAL = "return network.getWifiNetwork(s.section).then(async function(radioNet) {"


def configure(tree, profile):
    path = tree / "feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js"
    text = path.read_text(encoding="utf-8")
    # Only reverse a complete owned integration, never an upstream async change.
    markers = (text.count(REQUIRE), text.count(HOOK))
    if markers != (0, 0):
        if markers != (1, 1) or text.count(ASYNC_MODAL) != 1:
            raise ValueError("Incomplete or changed wireless NFC integration")
        text = text.replace(REQUIRE, "").replace(HOOK, "").replace(ASYNC_MODAL, MODAL)
    if profile == "full":
        if (text.count("'require form';\n") != 1 or text.count(TAB) != 1
                or text.count(MODAL) != 1):
            raise ValueError("Unsupported LuCI wireless form: NFC integration anchors changed")
        text = text.replace("'require form';\n", "'require form';\n" + REQUIRE)
        # LuCI waits for ACL/hardware discovery before rendering the modal.
        text = text.replace(MODAL, ASYNC_MODAL)
        text = text.replace(TAB, TAB + HOOK)
    elif profile != "recovery":
        raise ValueError("Unknown firmware profile")
    path.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    try:
        configure(Path(sys.argv[1]), sys.argv[2])
    except (IndexError, OSError, ValueError) as error:
        sys.exit(f"Wireless NFC configuration failed: {error}")
