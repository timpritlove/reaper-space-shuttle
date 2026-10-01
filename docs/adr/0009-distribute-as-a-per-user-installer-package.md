# ADR-0009: Distribute as a signed, notarized per-user installer package

- Status: accepted
- Date: 2026-10-01

## Context

REAPER loads extensions from `UserPlugins` in its resource folder, by default
`~/Library/Application Support/REAPER/UserPlugins` (also Ultraschall's). The folder is hidden in the Finder
(`~/Library`), so "copy this file there" is a poor instruction. Replacing a library that a running REAPER has loaded
can crash it (ADR-0002). The REAPER community also uses ReaPack, REAPER's own package manager (SWS, js_ReaScriptAPI),
which installs and updates from within REAPER. Tim has a Developer ID Application certificate, a notary profile
(`stagehand-notary`) and, since 2026-10-01, a Developer ID Installer certificate.

## Decision

- Releases are a standard macOS installer package, `dist/SpaceShuttle-<version>.pkg`, built only by
  `Scripts/release.sh` (`make release`), which refuses uncommitted changes.
- The package installs **for the current user only** (`enable_currentUserHome`), into
  `~/Library/Application Support/REAPER/UserPlugins/reaper_spaceshuttle.dylib`; no choices, no scripts.
- An installation check refuses while REAPER (bundle ID `com.cockos.reaper`, which Ultraschall shares) is running.
- The dylib is universal (arm64 + x86_64, macOS 14+), signed with Developer ID Application, hardened runtime and a
  secure timestamp; the package is signed with Developer ID Installer, notarized and stapled.
- Installer texts in German and English (`Packaging/Resources/<lang>.lproj`).
- Version in `VERSION`; package identifier `me.metaebene.reaper-space-shuttle` (renamed by ADR-0013).
- ReaPack is a later, additional channel (updates), not a replacement.

## Consequences

- One double click installs it; Gatekeeper accepts it without warnings.
- Portable REAPER installations or other resource folders are not covered by the package.
- No uninstaller: removing means deleting the one file (to be documented).

## Rules

- Hand out only packages built by `Scripts/release.sh`; raise `VERSION` before a release.
- The package never installs outside the user's REAPER `UserPlugins` folder and never runs scripts.

## Enforced and verified by

- `Scripts/release.sh`, `Packaging/distribution.xml`, `Packaging/Resources`.
- Verified 2026-10-01: package signed (Developer ID Installer), notarization accepted, stapled, `spctl` "Notarized
  Developer ID"; payload is the universal, signed dylib.
- Verified 2026-10-01 (release 0.1 installed by Tim): `reaper_spacemouse.dylib` lands in
  `~/Library/Application Support/REAPER/UserPlugins`, owned by the user despite `auth="root"`; Ultraschall loads it
  and navigation works through the 3DxWare driver.
- Open checks: no admin prompt, refusal while REAPER runs, texts in both languages.
