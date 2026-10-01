# ADR-0010: Write the SpaceMouse LED natively; flash it to confirm the autoscroll button

- Status: accepted; supersedes the "write nothing to the device" rule of ADR-0003
- Date: 2026-10-01

## Context

The left button toggles autoscroll (ADR-0006), but the hand on the cap may not see REAPER, and while the guard holds
autoscroll the button only changes what comes back later, so nothing visible happens at once. Tim's wish
(2026-10-01): flash the LED once when autoscroll is switched on and twice when it is switched off, with feature
parity between the driver and the native input as the general goal.

What the LED allows:

- **Driver**: `ConnexionClientControl('3dsl', ledState)` (`kConnexionCtlSetLEDState`) is accepted with error 0 for
  on and off, but the SpaceMouse Compact's LED does not change (stagehand findings, 2026-09-26; confirmed by Tim in
  REAPER, 2026-10-01, application registration). Writing the physical device past the driver fails while the helper
  runs: `IOHIDDeviceSetReport` without an open returns `kIOReturnNotOpen`, a shared open
  `kIOReturnExclusiveAccess` (measured 2026-10-01).
- **Native**: output report 4, one bit (`04 01` on, `04 00` off) switches the LED reliably (stagehand, five blink
  cycles at the device). The device cannot report the LED state.

ADR-0003 forbade writing to the device natively. Tim lifted that (2026-10-01): we want to address the LEDs.

## Decision

- `SpaceMouseInput.setLED(_:)`, fire and forget. `NativeSpaceMouse` writes output report 4 on its HID queue (the
  transfer never blocks REAPER's main thread) and reports a failure once per opened device. `DriverSpaceMouse` sends
  `'3dsl'` anyway, for models that may honour it, and stays silent on errors.
- `LEDFlash` (pure) builds the pattern: dark for 0.15 s and lit again, once for on, twice for off. It always ends lit,
  because the LED is lit while the device is in use and its state cannot be read.
- `Navigator` flashes after every press of the left button that changes autoscroll — REAPER's new state, or, while
  the guard holds, the state that will come back. A new pattern cancels the rest of an older one; unloading switches
  the LED on if a pattern ran.

## Consequences

- Native input: LED feedback. Driver input with the Compact: none, until 3Dconnexion's driver honours `'3dsl'`; parity
  is not reachable there, because the helper holds the device exclusively.
- Suspending and restoring by the guard does not flash; only the button does.
- If the LED was off, it is on after the first flash.

## Rules

- Natively, write only output reports the device's descriptor defines and we understand (today: report 4, the LED);
  never sweep or write the vendor-page feature reports.
- LED failures never stop or switch the input; in particular the driver never reports `.failed` for `'3dsl'`, which
  would make `auto` fall back to native HID.
- Every LED pattern ends with the LED on.
- Never open the device past the 3Dconnexion helper to reach the LED (ADR-0003: never kill the helper).

## Enforced and verified by

- `NavigationCore/LEDFlash.swift`, `LEDFlashTests`, `NativeSpaceMouse.setLED`, `DriverSpaceMouse.setLED`,
  `Navigator.flashLED`.
- Verified 2026-10-01: driver path, no visible flash (as expected from stagehand's finding).
- Open checks: the native flash at the device inside REAPER; whether 0.15 s reads well.
