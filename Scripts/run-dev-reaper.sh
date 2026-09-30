#!/bin/zsh
# Quits a running development REAPER cleanly (Scripts/quit-dev-reaper.sh), installs the current build and starts it again with diagnostics in the
# console (SPACEMOUSE_DIAGNOSTICS=1). Only ever touches the portable REAPER in .dev/reaper (ADR-0007).
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/.dev/reaper/REAPER.app"
[[ -d "$APP" ]] || "$ROOT/Scripts/setup-dev-reaper.sh"
"$ROOT/Scripts/install-extension.sh"

"$ROOT/Scripts/quit-dev-reaper.sh"

LOG="$ROOT/.dev/reaper.log"
export SPACEMOUSE_LOG="${SPACEMOUSE_LOG:-$ROOT/.dev/spacemouse.log}"
# Launch through LaunchServices like a user would (not by executing the binary): the 3Dconnexion helper crashed on
# the registration of a client from a REAPER started directly (2026-10-01, docs/feasibility.md).
open -n -a "$APP" --env SPACEMOUSE_DIAGNOSTICS="${SPACEMOUSE_DIAGNOSTICS:-1}" --env SPACEMOUSE_LOG="$SPACEMOUSE_LOG" \
  --stdout "$LOG" --stderr "$LOG"
echo "Development REAPER started (log: $LOG, extension log: $SPACEMOUSE_LOG)"
