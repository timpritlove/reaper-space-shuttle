# ADR-0007: Develop and test against a portable REAPER in .dev, never against Ultraschall

- Status: accepted
- Date: 2026-10-01

## Context

Tim records podcasts with Ultraschall (REAPER 7.81 with its own resource folder in
`~/Library/Application Support/REAPER`). A development build that crashes or misbehaves must never touch that
installation. The Show Notes project uses a portable REAPER for the same reason.

## Decision

- `Scripts/setup-dev-reaper.sh` downloads REAPER (default 7.81) into `.dev/reaper` (git-ignored) and makes it portable
  (`reaper.ini` next to the app); the license is symlinked, not copied.
- `make install` installs into `.dev/reaper/UserPlugins`; `make run` installs, quits only the development instance
  (by path) and starts it with `SPACEMOUSE_DIAGNOSTICS=1`.

## Consequences

- The development REAPER has its own settings, actions and ext state; settings for the extension go into its
  `reaper-extstate.ini`, section `[spacemouse]`.
- Trying the extension in Ultraschall is a deliberate, manual step.

## Rules

- Scripts never write to `~/Library/Application Support/REAPER` or quit a REAPER they did not start by path.

## Enforced and verified by

- `Scripts/setup-dev-reaper.sh`, `install-extension.sh`, `run-dev-reaper.sh`.
- Verified 2026-10-01: portable REAPER 7.81 set up in `.dev/reaper`.
