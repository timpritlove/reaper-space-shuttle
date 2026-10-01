# ADR-0015: Seize the device natively only while REAPER is active, so other programs can have it meanwhile

- Status: accepted
- Date: 2026-10-01
- Supersedes: in ADR-0003 the native input holding the device for as long as the extension runs

## Context

- With the 3DxWare helper stopped, Space Shuttle (`auto` falls back to native when the helper is not running) and
  SpaceScroll (`~/src/timpritlove/spacescroll`, a menu bar app scrolling every other app with the SpaceMouse) could not
  run side by side (Tim, 2026-10-01): both opened the device seized at start and held it until quit, so whoever came
  second got `kIOReturnExclusiveAccess`.
- The device admits one seized open at a time. Native input has no driver to route data; the programs have to take
  turns.
- Space Shuttle already calls `setActive` when REAPER becomes or stops being the active app; for native HID that did
  nothing. SpaceScroll leaves the device to REAPER (its `excluded_apps`, SpaceScroll ADR-0004).
- Both react to the same app switch at nearly the same moment; the one that wants the device may try before the other
  has let go.

## Decision

- `NativeSpaceMouse.setActive` seizes the device on `true` and closes it on `false`. The HID manager keeps watching, so
  a connected device is reopened when REAPER is active again.
- `SeizeClaim` (pure, tested) decides when to open and close. An open that fails with `kIOReturnExclusiveAccess` is
  retried every 0.1 s for about 2 s; any other failure, and a busy device after the retries, is reported as `.failed`.
  A new `setActive` starts a fresh round and drops retries scheduled before it.
- Letting go sends no event; reopening sends `.connected` again.
- `SpaceMouseKit` is the same as in SpaceScroll for this (ADR-0007 there).

## Consequences

- Space Shuttle and SpaceScroll work side by side on the native path; stagehand and Spacer can also have the device
  while REAPER is in the background.
- If another program still holds the device when REAPER comes to the front, Space Shuttle reports "device busy" after
  the retries and tries again at the next activation.
- Between letting go and the other side's open, nobody holds the device. Whether macOS turns the cap into scroll events
  of its own in that gap is not measured.
- The LED after a reopen shows whatever the device keeps; an LED pattern (ADR-0010) can only run while the device is
  open, i.e. while REAPER is active, which is when the buttons work anyway.
- The settings window's native mode text says so ("Held only while REAPER is in front").

## Rules

- The native input holds the device only while REAPER is active (`setActive(true)`).
- Retry only `kIOReturnExclusiveAccess`, only for a bounded time, and only while still wanted.
- Open/close decisions live in `SeizeClaim`; the two copies of `SpaceMouseKit` stay identical in this.

## Enforced and verified by

- `SpaceMouseKit/SeizeClaim.swift`, `SpaceMouseKit/NativeSpaceMouse.swift` (`HIDReader`), `SeizeClaimTests`.
- Verified 2026-10-01 at the device, helper stopped: the development REAPER with SpaceScroll (`input = native`),
  both work, switching between REAPER and other apps (docs/feasibility.md, "Results").
- Open checks: Cmd-Tab with the cap deflected; no "device busy" in either log; the LED after a reopen.
