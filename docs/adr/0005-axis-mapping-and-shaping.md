# ADR-0005: Map four cap movements to scroll and zoom, shaped by dead zone, curve and crosstalk suppression

- Status: accepted
- Date: 2026-10-01

## Context

The cap has six axes with large crosstalk: up to 151/350 on an unintended axis (sliding forward lifts z; stagehand
findings, "Axis directions"). stagehand's buttons model uses only the strongest direction (ADR-0084 there), but here
scroll and zoom must work at the same time. Spacer's rate control uses a dead zone of 0.12 and exponent 2.

## Decision

- Default mapping (setting `<role>_axis` = one axis, a comma list or `none`; `<role>_invert`). A role may take
  several axes; their shaped values add up, limited to ±1:
  - slide left/right (x) **and** twist (rz) → horizontal scroll, right/clockwise = later;
  - push/pull (z) → horizontal zoom, push down = zoom in;
  - slide forward/back (y) → vertical scroll of the track list, forward = up;
  - track height (`vzoom`): no axis. REAPER changes it only in coarse steps, which does not fit the stepless rest.
- Shaping per axis (`AxisShaping`): normalize by `full_scale`, dead zone `deadzone` (0.12), curve
  |v|^`exponent` (3) rescaled beyond the dead zone; an axis counts only while it reaches `crosstalk` (0.5) of the
  strongest axis (0 = off). Top speeds (ADR-0004): 3 widths per second, zoom ×e³ per second.
- Revised 2026-10-01 after Tim's first test (not yet committed then): exponent 2 → 3 and doubled top speeds for more
  acceleration at high deflection (half deflection stays as fast as before, finer below); twist added to scrolling;
  track height taken off the twist. Second round the same day: vertical scroll 20 → 200 steps per second ("ten times
  faster", then 500 and track height 8 → 80), track height on right button + twist, zoom out project on a double click of the right button.
- Vertical scroll and track height go through `CSurf_OnScroll(0, n)` / `CSurf_OnZoom(0, n)`; a `StepAccumulator`
  turns the rate (`vscroll_steps` = 500, `vzoom_steps` = 80 per second at full deflection) into whole steps.
- One overall factor `speed` (default 1 = the tested baseline) multiplies every top speed: scroll, zoom, track list,
  track height (Tim: the baseline equals the 3DxWare speed slider in the middle; experienced users may want about
  1.5).
- Buttons: left toggles autoscroll (ADR-0006). The right button is a modifier, a click and a double click
  (`ModifierButton`): held, it gives the twist to the track height (`<role>_axis_held`, default `vzoom_axis_held=rz`;
  the axis leaves every other role meanwhile) and counts as no click; a click runs `right_click_action` (default
  none); a double click within the system's double-click interval runs `right_double_click_action` (default 40295,
  "View: Zoom out project").

## Consequences

- Deliberate diagonals (scroll and zoom together) survive, crosstalk up to 0.43 does not.
- Signs of the driver's axes may differ from the native ones; inversion per role fixes it without code.
- Vertical motion is stepped, not smooth; smooth vertical scrolling would need the arrange window's scroll bar
  (SWELL), a later decision.

## Rules

- Axis signs and mapping live only in `AxisMapping`/settings, never in the motion code.
- Speeds follow deflection continuously; no fixed-speed modes.

## Enforced and verified by

- `NavigationCore/AxisShaping.swift`, `Settings.swift`, `AxisShapingTests`, `SettingsTests`, `StepAccumulatorTests`.
- Tested by Tim 2026-10-01 (native HID): scroll, zoom and track list work and feel right in principle; peaks reach
  350 on x, z and rz, so `full_scale` 350 fits. Wanted: more acceleration at the top (done), twist = slide (done),
  track height did not fit (removed).
- Open checks: the revised curve at the device; driver axis signs.
