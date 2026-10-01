# ADR-0014: Twist moves the play cursor by rate control, never while recording

- Status: accepted
- Date: 2026-10-01

## Context

Until now twist (rz) scrolled the timeline like sliding left/right (ADR-0005), so two movements did the same thing.
Tim wants the twist to move the play cursor instead, in the same continuous way: deflection sets the speed. It must
never touch the transport during a recording; during playback and while stopped it may. Scrolling and moving the play
cursor at the same time was allowed at first, to find out how it feels; it did not work well (Tim): while the view
scrolls, the twist must not count, and the other way round.

REAPER moves the edit cursor with `SetEditCurPos(time, moveview, seekplay)`; with `seekplay` it also seeks playback.
While stopped, the play cursor is the edit cursor. While playing, `GetPlayPosition` may report a seek only after the
audio buffers caught up.

## Decision

- New role `playhead` (setting `playhead_axis`, `playhead_invert`), default twist (`rz`); scrolling keeps only the
  slide (`scroll_axis` default `x`). Twist clockwise = later.
- Rate control like scrolling (ADR-0004): `playhead_speed` view widths per second at full deflection (default 1),
  times the overall `speed`, so it feels the same at every zoom level; the position stops at 0.
- Stopped: `SetEditCurPos(t, false, false)`. Playing or paused: `SetEditCurPos(t, false, true)`, which moves the edit
  cursor along and seeks playback every tick while the cap is twisted.
- `PlayheadMotion` keeps its own position while twisting and advances it by the play rate (`Master_GetPlayRate`)
  while playing; it adopts REAPER's position only when the two differ by more than 0.2 s (loop, user, lagging seek).
- Recording (play state bit 4): the role's value is forced to 0.
- Scrolling and the play cursor exclude each other (`ExclusiveGate`): the one that starts first wins until it comes
  back to rest; if both start in the same tick, the stronger one. Zoom and the track list are not affected.
- The view does not follow the play cursor (`moveview` false); autoscroll and the glide back (ADR-0006) stay as they
  are. The vertical lock counts the play cursor as horizontal movement.
- A click of the right button starts and stops playback by default (`right_click_action=40044`, "Transport:
  Play/stop"; Tim): with the play cursor on the twist, the transport belongs on the cap's buttons too.
- Right button held + twist still changes the track height; the twist then leaves the play cursor (`whileHeld`).

## Consequences

- Seeking at the tick rate during playback may sound like scrubbing or stutter; this is an experiment.
- The play cursor can leave the view while stopped; the slide brings the view along.
- Users who set `scroll_axis=x,rz` themselves move both the view and the play cursor with the twist.

## Rules

- Never move the edit cursor or seek while REAPER records.
- Never scroll and move the play cursor in the same movement.
- Move the play cursor by elapsed time, never by a fixed amount per tick or report.

## Enforced and verified by

- `NavigationCore/PlayheadMotion.swift`, `Settings.swift`, `Navigator.movePlayhead`, `PlayheadMotionTests`,
  `PlayheadSettingsTests`, `ExclusiveGateTests`, `AxisShapingTests.twistMovesThePlayCursorAndSlidingScrolls`.
- Only built. Open checks at the device: how seeking every tick sounds during playback; whether `GetPlayPosition`
  lags behind a seek (diagnostics count "play cursor sets"); speed of 1 width per second; twisting during recording
  does nothing; the exclusion between scroll and twist.
- Tested by Tim 2026-10-01: scrolling and twisting together did not work well → exclusion added.
