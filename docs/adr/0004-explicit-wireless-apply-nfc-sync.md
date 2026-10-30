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
Do not expand RPC ACLs. Retain the original APK, six-file payload, checksums,
backup behavior, writer and hardware validation unchanged. Package release r3
adds the integration module separately from the imported payload.

Wrap only the modal map's save: after successful save, track interfaces whose
SSID/key/encryption changed with the flag selected. Do not write on modal open,
Save, cancellation, validation failure, installation, first boot, restart or
unrelated network edits. Keep only section IDs and a 30-minute expiry in
sessionStorage, scoped to the current login, never credentials. The pending
choice can survive a page reload but cannot initiate a write by itself.

Wrap LuCI's apply entry point and recheck actual pending credential changes.
Discard ineligible APs, disabled interfaces/radios, PPSK and unsupported
encryption. If several interfaces have different credentials, ask which single
network should occupy the one physical NFC tag before starting apply. Identical
dual-band credentials require only one write. Cancelling selection cancels
this apply attempt. Do not implicitly select the last edited radio.

Only the `uci-applied` event emitted after successful LuCI apply confirmation
submits the existing NFC write RPC, with a section name and empty credential
arguments. The backend reads committed wireless configuration, validates it,
and uses its existing serialized worker and first backup. Revert clears intent.
Consume intent before RPC and do not retry on failure or lost replies. A
submitted task is not success: the user must check readback verification in
Services / AX3000T NFC. NFC failure cannot roll back an already applied Wi-Fi
configuration. If the browser disconnects/closes before confirmation, no NFC
write is guaranteed and manual synchronization may be necessary.

## Build integration

Use checked, reversible source edits in `scripts/configure-wireless-nfc.py`
when applying the full profile. Await ACL/hardware discovery before rendering
the modal. Unknown LuCI anchors fail the build rather than silently omitting
the feature. Recovery removes the hook and excludes the helper; restore full
source changes when the dual-image build exits. Check both installed surfaces
in staged rootfs. Installing only the r3 package on an older image does not add
the wireless-page hook; use a firmware built with this source integration.

## Verification and limitations

Node VM tests execute the real module against mocked LuCI forms, browser events
and RPC. They cover default selection, permission denial, staged changes,
confirmation, revert, multi-interface selection, duplicate events, expiry,
session isolation and failures without performing any hardware writes.
Existing package/offline lifecycle checks still apply. These tests and source
compatibility checks do not establish real router UI behavior, NFC hardware
compatibility or completed cross-compilation. First hardware testing should use
a temporary test Wi-Fi password and a backup, with wired management access.
