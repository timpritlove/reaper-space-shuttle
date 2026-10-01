# ADR-0011: Use REAPER's console for diagnostics only; keep user messages for a settings window

- Status: accepted
- Date: 2026-10-01

## Context

`ShowConsoleMessage` opens the ReaScript console window. Release 0.1 wrote failures, the fallback to native HID and
confirmations of its own actions there unconditionally, so a normal start without the 3Dconnexion helper popped the
console up although the fallback worked (Ultraschall, 2026-10-01). Tim (2026-10-01): the console is good for
debugging, but nothing to show a normal user automatically; settings (speed) and messages belong in a configuration
UI of our own, opened through a REAPER action.

## Decision

- Messages a user may want to see (input failures, fallback, missing autoscroll actions, settings reloaded,
  navigation on/off) go into `Navigator.messages` (the last 100, with date) — the source for the settings window to
  come. They reach the console only while diagnostics are on; during development they also go to the log file.
- The console stays for diagnostics (setting `diagnostics`, `SPACESHUTTLE_DIAGNOSTICS=1` from `make run`, or the
  action "Space Shuttle: Toggle diagnostics in console", whose own on/off confirmation is written to the console).

## Consequences

- Without diagnostics, a failure is silent until the settings window exists; until then the diagnostics action shows
  what happened from then on, not before.
- "Toggle navigation" gives no visible confirmation; a toggle state for the action (menu check mark, toolbar) would.

## Rules

- Never write to the console unless diagnostics are on or the user asked for diagnostics.
- Every message meant for users goes through `report`, so the settings window sees it.

## Enforced and verified by

- `Navigator.report`, `Navigator.console`.
- Open checks: REAPER start without the helper and diagnostics off opens no console.
