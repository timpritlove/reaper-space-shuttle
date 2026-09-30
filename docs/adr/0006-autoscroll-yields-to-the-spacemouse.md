# ADR-0006: Suspend autoscroll while the SpaceMouse moves the view; the left button toggles it

- Status: accepted
- Date: 2026-10-01

## Context

REAPER's "auto-view-scroll during playback" (action 40036) and "… while recording" (40262) move the view to follow
the play position and would fight the SpaceMouse. Tim's wish (2026-10-01): the left button switches autoscroll on and
off; while the SpaceMouse steers, autoscroll is off temporarily and comes back after a short rest.

## Decision

- `AutoscrollGuard` (pure state machine) gets REAPER's state every tick. While the view moves horizontally (scroll
  or zoom), every autoscroll option that is on is switched off and remembered. After `autoscroll_grace` seconds
  (default 1.5) without horizontal motion, exactly the remembered options are switched on again.
- If the play position is running and out of sight when the grace time ends, the view first **glides back** to it
  (`ReturnGlide`): speeding up to half the distance, then slowing down, measured in view widths, 0.4–1.8 s depending
  logarithmically on the distance, following the moving play position. It ends with the play position at
  `return_position` (0.5 = middle), and only then autoscroll comes back. Moving the cap during the glide stops it and
  starts a fresh hold; the left button during the glide cancels it (autoscroll stays off).
- The left button toggles both options together: on if both are off, else off. While the guard holds autoscroll
  (moving or within the grace time), the button changes what comes back instead of switching now.
- Vertical movement does not suspend autoscroll.
- On unload, disconnect, disabling navigation or REAPER going to the background, remembered options come back at
  once.
- The action IDs are checked by name at start (`kbd_getTextFromCmd`); if the names do not match, autoscroll handling
  is off and the console says so.

## Consequences

- Scrolling during playback or recording works without a fight; following resumes by itself.
- Toggling uses REAPER's own actions, so menus and toolbar buttons show the real state.
- If REAPER crashes during a suspension, autoscroll stays off (REAPER saves its options itself).

## Rules

- Only ever switch back on what the guard itself switched off, or what the button asked for.
- Never switch autoscroll by writing configuration variables; only via the two actions.

## Enforced and verified by

- `NavigationCore/AutoscrollGuard.swift`, `Navigator` (autoscroll section), `AutoscrollGuardTests`.
- `ReturnGlide`, `ReturnGlideTests`, `AutoscrollReturnTests`.
- Verified 2026-10-01 in REAPER 7.81: action names found by name (IDs 40036 and 40262); suspending and restoring
  during playback works (Tim: "works well, could come back a bit later" → grace 0.75 → 1.5 s, glide added).
- Open checks: the glide at the device; behaviour while recording; whether toggling adds undo points.
