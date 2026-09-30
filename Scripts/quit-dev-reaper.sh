#!/bin/zsh
# Quits the development REAPER (.dev/reaper) the way a user would, so the extension unloads and unregisters its
# 3DxWare client. Never kills it: a REAPER killed with a registered client left the 3Dconnexion helper with a stale
# client, and the helper crashed on the next device report (2026-10-01, docs/feasibility.md). Other REAPERs
# (Ultraschall) share the bundle ID, so the app is addressed by process ID only.
set -euo pipefail

ROOT="${0:A:h:h}"
BINARY="$ROOT/.dev/reaper/REAPER.app/Contents/MacOS/REAPER"
PID="$(pgrep -f "$BINARY" || true)"
[[ -z "$PID" ]] && exit 0

# In the background: while REAPER asks whether to save, the call can block until someone answers.
osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($PID).terminate" >/dev/null 2>&1 &
for _ in {1..150}; do
  kill -0 "$PID" 2>/dev/null || exit 0
  sleep 0.1
done
echo "Development REAPER (pid $PID) did not quit within 15 s — is a dialog open (unsaved project)? Not killing it." >&2
exit 1
