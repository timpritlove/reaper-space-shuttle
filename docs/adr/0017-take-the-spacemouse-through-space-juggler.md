# ADR-0017: Take the SpaceMouse through Space Juggler

- Status: accepted (2026-10-14; checked at the device with all four apps, with and without 3DxWare); supersedes ADR-0003 (driver first, native fallback;
  the driver case goes to Space Juggler, spacemousekit ADR-0004), ADR-0015 and ADR-0008's registration (no own
  registration any more), and the input setting
- Date: 2026-10-14
- Related: spacemousekit ADR-0001 … 0004 (`~/src/timpritlove/spacemousekit`)

## Context

- Space Shuttle reads only the SpaceMouse Compact natively (0x256F/0xC635 in `NativeSpaceMouse`); other models are
  not even found.
- Only one program can seize a SpaceMouse; Stagehand holds it permanently, and the others take turns (ADR-0015).
- Space Juggler, a broker shipped with each of these programs, owns every SpaceMouse and gives it to one client at a
  time: a claim naming the frontmost app beats background claims (spacemousekit ADR-0001). With the classic
  3Dconnexion helper it tells clients to use the driver themselves (spacemousekit ADR-0004), which Space Shuttle
  already does as an application client.

## Decision

- Space Shuttle becomes a client of Space Juggler from inside REAPER. Claim: REAPER's bundle ID
  (`com.cockos.reaper`), no background.
- Its `SpaceMouseKit` target goes; it uses the spacemousekit package. `DriverSpaceMouse` stays for the driver case and
  runs only when Space Juggler says `driver`.
- The installer puts Space Juggler.app next to the extension; the extension starts it through Launch Services.
- The `input` setting goes: Space Juggler decides.

## Consequences

- Space Shuttle gets every SpaceMouse model of the package.
- No more native retries on app switches (`SeizeClaim`); REAPER in front simply wins.
- The extension links the package's client library into REAPER's process (connection on the main run loop, no work in
  `ReaperPluginEntry`).

## Rules

- Space Shuttle must not open a SpaceMouse's HID interface while this ADR is in effect.
- Nothing about Space Juggler happens in `ReaperPluginEntry`.

## Enforced and verified by

- `Navigator.startInput` (claim = REAPER's bundle ID, launcher = `Space Juggler.app` next to the dylib, found with
  `dladdr`), `Navigator.handle` (`heldTwoButtons`: the Pro's MENU and FIT as left and right), `setLEDs` for the LED
  pattern; `Scripts/space-juggler.sh`, `install-extension.sh`, `release.sh` (bundle not relocatable).
- `swift test` (63 tests) after removing the own `SpaceMouseKit` copy, `SeizeClaim` and the input setting.
- At the device with all four apps (Tim, 2026-10-14, spacemousekit `docs/spike.md` run 4): each app gets the
  SpaceMouse while in front, Stagehand otherwise; Kugelblitz kept it in the background ahead of Stagehand. The open
  checks below are what that run did not single out.
- Through 3DxWare 10.8.13 (helper running) with all four apps, each in front (Tim, 2026-10-14, run 6).
- Open checks in REAPER: scroll and zoom with the SpaceNavigator and the SpaceMouse Pro (MENU = autoscroll, FIT =
  start/stop); Kugelblitz or Stagehand get the device when REAPER is in the background; LED pattern; the release
  package installs both files and leaves other apps' Space Juggler alone.
