# ADR 0004: NFC synchronization on explicit wireless apply

- Date: 2026-10-31
- Status: accepted
- Amends: ADR 0002's prohibition on automatic writes, only for an explicit
  authenticated wireless Save & Apply with the NFC option selected.

## Decision

Add a default-checked "同时更改 NFC" flag in the interface Wireless Security tab.
It is a one-shot browser instruction, never a wireless/hostapd UCI option.
Render it only for users with wireless-view write permission and existing
`luci.xinfc.write` permission on supported hardware with the writer installed.
Do not expand RPC ACLs. Retain the original APK, writer binary, first backup and
hardware validation. Release r3 adds a separate integration module; r4 adjusts
the RPC backend's backup-directory preparation and updates its payload checksum.
The original APK and its metadata remain unchanged as provenance.

Wrap only the modal map's save: after successful save, track interfaces whose
SSID/key/encryption changed with the flag selected. Do not write on modal open,
Save, cancellation, validation failure, installation, first boot, restart or
unrelated network edits. Keep only section IDs and a 30-minute expiry in
sessionStorage, scoped to the current login, never credentials. The pending
choice can survive a page reload but cannot initiate a write by itself.

Wrap LuCI's apply entry point and recheck actual pending credential changes.
Discard ineligible APs, disabled interfaces/radios, PPSK and unsupported
encryption. If several interfaces are edited, use the interface with the
latest local edit sequence; there is no target-selection modal. Editing only
5 GHz therefore writes 5 GHz, and editing only 2.4 GHz writes 2.4 GHz.

Submit the existing NFC write RPC with the current SSID/password/encryption
before starting an unchecked wireless apply. This deliberately avoids LuCI's
90-second connectivity confirmation, since changing a wireless password can
disconnect the browser before it confirms the apply. Consume intent before the
RPC and do not retry on failure. A submitted task is not chip-readback success:
the user must check readback verification in Services / AX3000T NFC. NFC
failure cannot roll back an already applied Wi-Fi configuration. Revert clears
intent.
This opted-in path intentionally has no wireless automatic rollback. Explain
that warning in the form and recommend wired access. If the subsequent wireless
apply fails, the submitted NFC data can temporarily differ from active Wi-Fi;
verify both states before retrying. This is not an atomic transaction.

## Build integration

Use checked, reversible source edits in `scripts/configure-wireless-nfc.py`
when applying the full profile. Await ACL/hardware discovery before rendering
the modal. Unknown LuCI anchors fail the build rather than silently omitting
the feature. Recovery removes the hook and excludes the helper; restore full
source changes when the dual-image build exits. Check both installed surfaces
in staged rootfs. Installing only the package on an older image does not add
the wireless-page hook; use a firmware built with this source integration.

## Verification and limitations

The r4 package repairs a root-owned `/etc/xinfc` with incorrect mode to 0700
during package preinstall, first-boot initialization and runtime status/write
checks; foreign owners and symlinks remain rejected.

Node VM tests execute the real module against mocked LuCI forms, browser events
and RPC. They cover default selection, permission denial, staged changes,
write-before-apply order, unchecked apply, revert, most-recent interface, expiry,
session isolation and failures without performing any hardware writes.
Existing package/offline lifecycle checks still apply. These tests and source
compatibility checks do not establish real router UI behavior, NFC hardware
compatibility or completed cross-compilation. First hardware testing should use
a temporary test Wi-Fi password and a backup, with wired management access.
