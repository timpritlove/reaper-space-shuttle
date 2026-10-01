# ADR-0012: A settings window in SwiftUI inside the extension, with a window class for edit keys

- Status: accepted
- Date: 2026-10-01

## Context

Users need a place for settings and messages that is not the ReaScript console (ADR-0011). Tim (2026-10-01): one
window, opened through an action, with a speed slider whose middle is the normal speed, used the same way with the
3DxWare driver (assuming its own speed slider stays in the middle) and natively, so both modes have one UI. The window
shows the mode and explains the controls; changing the button assignments comes later.

Three ways were weighed: a separate app (second install, needs a channel to the extension), SWELL dialogs (REAPER's
Win32 layer), and a Cocoa window of the extension itself — REAPER is a Cocoa app and the extension already runs on
its main thread with AppKit loaded. The spike of 2026-10-01 (docs/feasibility.md) measured the keyboard:

- Plain keys reach a focused text field in Cocoa and SWELL alike; REAPER does not take space or letters from it.
- Cmd-A/C/V/Z go to REAPER's main menu from a plain Cocoa window (Cmd-Z undid the project); from a SWELL edit field
  Cmd-A/C/V work but Cmd-Z still undoes the project. The `accelerator` hook changes none of this.
- A window subclass whose `performKeyEquivalent:` sends the edit commands to the first responder fixes it for an
  `NSTextField` and for a SwiftUI `TextField` in an `NSHostingController` alike (repeated runs; the project state
  stayed untouched, field undo worked). Two early runs failed while REAPER was apparently not the active app, where
  no key window exists; real keystrokes always come with REAPER active.

## Decision

- Action "Space Shuttle: Settings…" opens one window (`SettingsWindowController`), SwiftUI in an
  `NSHostingController`, hosted by `EditKeysWindow`: Cmd-A/C/V/X/Z and Shift-Cmd-Z go to a focused text field,
  Cmd-W and Escape close the window. Closed on unload.
- Content: input mode (3DxWare driver or native) with a one-line explanation and the connection status; the speed
  slider; the cap and button assignments as the current settings define them (`ControlsDescription`, read-only); the
  last messages (ADR-0011).
- Speed slider (`SpeedScale`): logarithmic, position −1…+1 ↔ speed ÷4…×4, middle = 1 (the measured baseline that
  matches the 3DxWare slider in its middle), snaps to the middle near it, "Normal" button. Changes act at once and are
  saved to the extension state (`speed`) when the slider is let go. In driver mode the window asks to leave the
  3DxWare speed slider in the middle.
- UI text in English, like REAPER and the action names.
- The window follows the macOS light/dark setting and its changes (`AppleInterfaceStyle`,
  `AppleInterfaceThemeChangedNotification`) by setting its own appearance: REAPER's Info.plist sets
  `NSRequiresAquaSystemAppearance`, which would keep it light (Tim, 2026-10-01: "does not react to Dark Mode").

## Consequences

- One UI for both modes; the 3DxWare slider is no longer the place to set the speed.
- The window stays a Cocoa window inside REAPER: it hides REAPER's shortcuts only for edit keys in text fields;
  everything else (e.g. space with the slider focused) still reaches REAPER, as in REAPER's own windows.
- `speed` values outside ÷4…×4 set by hand in the ini still work; the slider then shows its end.

## Rules

- Settings UI only in this window, never in the console.
- Every window of the extension that can hold a text field uses `EditKeysWindow` (or the same key handling).
- Every setting the window changes takes effect at once and is saved in the `spaceshuttle` extension state.

## Enforced and verified by

- `SpaceShuttleExtension/SettingsWindow.swift`, `Navigator` (settings window section), `NavigationCore/SpeedScale.swift`,
  `ControlsDescription.swift`, `SpeedScaleTests`, `ControlsDescriptionTests`.
- Keyboard behaviour: spike 2026-10-01 with synthesized key events (docs/feasibility.md).
- Verified 2026-10-01 in the development REAPER (Tim): the window opens through the action; it follows Dark Mode.
- Open checks: the window in REAPER (layout, slider feel, live speed change, value kept after restart); real
  keystrokes once a text field exists.
