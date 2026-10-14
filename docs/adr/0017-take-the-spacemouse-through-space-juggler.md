# ADR-0017: Take the SpaceMouse through Space Juggler

- Status: proposed (2026-10-14); takes effect when Space Shuttle moves to Space Juggler (spacemousekit `docs/plan.md`,
  step 6, the first client); then supersedes the native input of ADR-0003 and ADR-0015
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

To be written when built. Checks then in REAPER: scroll and zoom with a Compact and a SpaceMouse Pro; Kugelblitz or
Stagehand get the device when REAPER is in the background.
