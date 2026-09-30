# ADR-0003: Read the SpaceMouse through the 3DxWare client API first, natively over HID as fallback

- Status: accepted; driver registration superseded by ADR-0008
- Date: 2026-10-01

## Context

Two ways to get the SpaceMouse's data into the REAPER process, both explored in stagehand
(`stagehand/docs/spacemouse-findings.md`, ADR-0083/0084 there) and Spacer (ADR-0012 there):

- **3DxWare client API** (`/Library/Frameworks/3DconnexionClient.framework`, public headers on disk). Most SpaceMouse
  owners have the vendor driver installed, and while its helper runs it holds the device exclusively. The driver
  routes device data per *active application*; a background client registered with `'****'` got nothing. A *manual*
  client (`'++++'`) receives data as soon as it is activated with `ConnexionClientControl('3dac')`, and starves the
  frontmost app's own client meanwhile; `'3ddc'` deactivates. Axis values arrive as `ConnexionDeviceState` (48 bytes)
  and are already scaled by the driver's preferences (−260…+522 seen, not ±350). Whether the driver repeats an
  unchanged deflection is not measured.
- **Native HID**: VID 0x256F, PID 0xC635, usage 0x01/0x08, opened seized (shared, macOS turns it into scroll events).
  Report 1 = x y z, report 2 = rx ry rz (int16, ±350), a pair every ~16 ms while deflected, an all-zero pair on
  release; report 3 = buttons, on change. Fails with `kIOReturnExclusiveAccess` while the 3DxWare helper runs.

## Decision

- One protocol `SpaceMouseInput` with two implementations, events always on the main thread.
- `DriverSpaceMouse` (default when the framework is installed): loads the framework with `dlopen`, registers a manual
  client (`'++++'`, takeover mode, all axes and buttons) and activates it exactly while REAPER is the active app
  (`NSApplication` activation notifications).
- `NativeSpaceMouse`: Spacer's `SpaceMouseHID`, seized, SpaceMouse Compact only.
- Setting `input` = `auto` (driver if installed, falls back to native if the driver fails), `driver` or `native`.

## Consequences

- With the driver, other apps keep their SpaceMouse; REAPER gets it only while in front.
- Driver values are pref-scaled: `full_scale` may need tuning; diagnostics report peaks.
- A watchdog (silence = released) is only safe for the native input, which streams while deflected.
- stagehand and Spacer hold the device seized too: only one of them works at a time in native mode.

## Rules

- Never kill or unload the 3Dconnexion helper, stagehand or Spacer to get the device.
- Native: match vendor **and** product ID; open seized only; write nothing to the device.
- Driver: activate the manual client only while REAPER is active; deactivate and unregister on unload.
- Do not treat silence from the driver as release until it is measured that the driver repeats unchanged states.

## Enforced and verified by

- `SpaceMouseKit/DriverSpaceMouse.swift`, `NativeSpaceMouse.swift`, `SpaceMouseValues.swift`,
  `SpaceMouseKitTests` (report and device-state decoding).
- Open checks: manual client inside REAPER receives data while REAPER is active and stops when it is not; the
  frontmost-app behaviour after `'3ddc'`; driver event rate while holding still; sign conventions of the driver's
  axes; native fallback with the helper stopped.
