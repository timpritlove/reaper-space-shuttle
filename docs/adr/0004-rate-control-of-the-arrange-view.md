# ADR-0004: Drive the arrange view by rate control through GetSet_ArrangeView2

- Status: accepted
- Date: 2026-10-01

## Context

Wanted: an "endless trackpad". While the cap is deflected, REAPER scrolls and zooms continuously, the pressure
setting the speed, scroll and zoom at the same time, until the cap is released. A trackpad cannot do this (the finger
reaches the edge), synthesized scroll events would land in whatever window is under the pointer, need Accessibility,
and pinch zoom cannot be synthesized with public API.

`GetSet_ArrangeView2(proj, isSet, 0, 0, &start, &end)` reads or sets the visible time range of the arrange view in
seconds (doubles): one call sets scroll and zoom together. `CSurf_OnScroll`/`CSurf_OnZoom` and `adjustZoom` move in
whole steps only.

## Decision

- Deflection is a velocity; the view moves by elapsed time per tick (`ArrangeMotion.step`):
  - width' = width · e^(−zoom · zoom_speed · dt) around an anchor that stays in place;
  - start' += scroll · scroll_speed · width' · dt (speed in view widths per second, so it feels the same at every
    zoom level; zoom is exponential for the same reason).
- Ticks come from a main-queue timer at `tick_rate` (default 60 Hz, about the device's report rate; 30 is the
  fallback if 60 turns out too costly). The timer runs only while something moves.
- The extension keeps its own fractional view while moving and only adopts REAPER's when it differs by more than
  1.5 pixels (`ArrangeMotion.diverged`): REAPER may round to pixels, and slow motion must still add up; a larger
  difference means someone else moved the view or REAPER clamped it.
- Zoom anchor (setting `zoom_anchor`): `auto` = play position while playing and visible, else the edit cursor if
  visible, else the middle; or fixed `center`, `edit`, `play`.

## Consequences

- Stepless speed from barely moving to fast, identical at 30 and 60 Hz (tested).
- Every tick redraws the arrange view; cost in large projects is an open check.
- Vertical movement has no such API and uses REAPER's steps (ADR-0005).

## Rules

- Move by elapsed time, never by a fixed amount per tick or per device report.
- Set the horizontal view only through `GetSet_ArrangeView2`.
- Do not tick while nothing moves.

## Enforced and verified by

- `NavigationCore/ArrangeMotion.swift`, `Navigator.tick`, `ArrangeMotionTests`.
- Open checks: smoothness and CPU at 60 and 30 Hz in a real project; whether REAPER rounds the view to pixels;
  clamping at project start and at maximum zoom; whether an explicit timeline redraw is needed.
