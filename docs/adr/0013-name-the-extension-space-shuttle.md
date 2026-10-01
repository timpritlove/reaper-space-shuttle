# ADR-0013: Name the extension Space Shuttle and retire reaper_spacemouse.dylib

- Status: accepted
- Date: 2026-10-01

## Context

The project ran under the working title "reaper-spacemouse" and released 0.1 and 0.2 as `reaper_spacemouse.dylib`.
Tim (2026-10-01) named it **Space Shuttle**, after a jog shuttle: the cap is a shuttle wheel for the arrange view,
with the speed following the deflection. "SpaceMouse" stays the name of the device (3Dconnexion's), so types that
model the device (`SpaceMouseKit`, `DriverSpaceMouse`, `SpaceMouseAxes`, …) keep it.

REAPER loads every `reaper_*.dylib` in `UserPlugins`. An installed 0.x extension next to the renamed one would read
the SpaceMouse a second time (the driver delivers to both, so the view moves twice; natively, only one can open the
device). The installer must not run scripts (ADR-0009), so it cannot remove the old file. Users of 0.x have settings
in the extension state section `spacemouse` and may have shortcuts on the old action IDs.

## Decision

- Product name "Space Shuttle"; GitHub repository and folder `reaper-space-shuttle`; Swift package `SpaceShuttle`,
  extension target `SpaceShuttleExtension`, dylib `reaper_spaceshuttle.dylib`.
- Package `dist/SpaceShuttle-<version>.pkg`, identifier `me.metaebene.reaper-space-shuttle`, installer title
  "Space Shuttle for REAPER" / "Space Shuttle für REAPER".
- Actions `SPACESHUTTLE_TOGGLE`, `SPACESHUTTLE_DIAGNOSTICS`, `SPACESHUTTLE_RELOAD`, `SPACESHUTTLE_SETTINGS`, titled
  "Space Shuttle: …"; console prefix and window title "Space Shuttle"; development variables `SPACESHUTTLE_DIAGNOSTICS`
  and `SPACESHUTTLE_LOG` (`.dev/spaceshuttle.log`).
- Settings live in the extension state section `spaceshuttle`; a key missing there is read from `spacemouse`. Writes
  go only to `spaceshuttle`.
- On load, the extension looks for `reaper_spacemouse.dylib` next to itself. If it is there, it moves it to the Trash,
  reports that (ADR-0011) and starts without input until REAPER restarts; the old copy REAPER already loaded keeps
  navigating for this session.

## Consequences

- Updating from 0.x needs no manual step: the first start after installing retires the old file, the second runs
  Space Shuttle alone with the old settings.
- Shortcuts or toolbar buttons bound to the old `SPACEMOUSE_*` actions are lost and must be assigned again.
- The old section `spacemouse` stays in `reaper-extstate.ini` until removed by hand.

## Rules

- "SpaceMouse" names only the device; the product, its files, actions and settings use Space Shuttle.
- Never run Space Shuttle's input in a REAPER that also loaded `reaper_spacemouse.dylib`.
- Move the old file only to the Trash, never delete it, and only from the folder this library was loaded from.

## Enforced and verified by

- `Package.swift`, `Scripts/`, `Packaging/`, `Extension.predecessor()`/`retire` in `PluginEntry.swift`,
  `Navigator.hold(because:)` and `Navigator.readSettings`.
- Verified 2026-10-01 in the development REAPER 7.81 (log only): with the old dylib next to it, the extension moved
  it to the Trash and held; after a restart it alone connected through the 3DxWare driver.
- Open checks: moving the view at the device after the update, the settings from `spacemouse` taking effect, the
  window title, the installer's new title, the update in Ultraschall.
