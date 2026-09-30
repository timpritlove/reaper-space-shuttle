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
- Unclear which change stopped the crashes: the application registration, the delay, or the application entry in the
  3DxWare settings. If users must add REAPER to the 3DxWare settings, that is a setup step to document.
- The driver's axis values are pre-scaled by its speed slider (peaks up to 2640 at the middle position, native ±350);
  `full_scale` 350 saturates early, so the slider only helps below the middle. Open.

## Rules

- Never register inside `ReaperPluginEntry`; wait until REAPER has launched.
- With the application registration, do not call '3dac'/'3ddc'; the driver follows the frontmost app.
- Unregister and clean up on unload (unchanged from ADR-0003).

## Enforced and verified by

- `SpaceMouseKit/DriverSpaceMouse.swift` (`Registration`, `registrationDelay`), setting `driver_registration`.
- Open checks: registration without the application entry in the 3DxWare settings (does the helper crash?); Ultraschall;
  what the driver's speed slider does to the values.
