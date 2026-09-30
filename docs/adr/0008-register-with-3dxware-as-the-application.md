# ADR-0008: Register with 3DxWare as the application, after REAPER has launched

- Status: accepted
- Date: 2026-10-01
- Supersedes: the driver registration in ADR-0003 (manual client as default)

## Context

ADR-0003 registered a manual client (`'++++'`) and activated it while REAPER was active, following stagehand's
findings for a background app. Inside REAPER this crashed 3DconnexionHelper 1.4.2 five times (2026-10-01,
docs/feasibility.md), always at the same place (`-[__NSArrayM insertObject:atIndex:]: object cannot be nil` in a
notification observer, reached from an input report): twice 0.4 s after `RegisterConnexionClient` was called while
REAPER was still loading its extensions, twice right after the helper started while the development REAPER was the
active app. The same manual registration from stagehand's command line probe works. Tim then added both REAPERs
(development and Ultraschall) as applications in the 3DxWare settings.

The usual way for an application (Blender, for example) is the wildcard signature `'****'` with its executable name
as a Pascal string, in takeover mode: the driver itself delivers data only while that application is frontmost.

## Decision

- Default registration (`driver_registration=app`): `RegisterConnexionClient('****', "\pREAPER", takeover,
  all axes)` plus all buttons; no activation calls.
- The manual registration stays available (`driver_registration=manual`) with activation while REAPER is active.
- Registration happens 2 s after the input starts, never inside `ReaperPluginEntry`.

## Consequences

- Verified 2026-10-01 (helper 1.4.2, REAPER listed in the 3DxWare settings): client 4096, device added, no crash;
  scrolling and zooming work; data only while REAPER is frontmost; about 60 events per second while deflected,
  all-zero state on release. With the 3DxWare speed slider in the middle it feels like the native path.
- No setup step in 3DxWare is needed: 3DxWare lost Tim's application entries after its settings were reopened
  (apparently a 3DxWare bug), and the registration plus cap movement and buttons with REAPER frontmost worked without
  them and without a crash (2026-10-01). So the application registration and/or the delay stopped the crashes.
- The driver's axis values are pre-scaled by its speed slider (peaks up to 2640 at the middle position, native ±350);
  `full_scale` 350 saturates early, so the slider only helps below the middle. Open.

## Rules

- Never register inside `ReaperPluginEntry`; wait until REAPER has launched.
- With the application registration, do not call '3dac'/'3ddc'; the driver follows the frontmost app.
- Unregister and clean up on unload (unchanged from ADR-0003).

## Enforced and verified by

- `SpaceMouseKit/DriverSpaceMouse.swift` (`Registration`, `registrationDelay`), setting `driver_registration`.
- Verified 2026-10-01 without application entries in 3DxWare: works, no crash.
- Open checks: which of the two changes (application registration, delay) is the one that matters; Ultraschall;
  what the driver's speed slider does to the values.
