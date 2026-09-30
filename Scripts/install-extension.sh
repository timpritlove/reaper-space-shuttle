#!/bin/zsh
# Builds the extension and installs it into the portable development REAPER (.dev/reaper/UserPlugins, ADR-0007).
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-debug}"
TARGET_DIR="${TARGET_DIR:-$ROOT/.dev/reaper/UserPlugins}"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product reaper_spacemouse
mkdir -p "$TARGET_DIR"
# REAPER only loads extensions named reaper_*.dylib.
# Copy next to the target and rename: overwriting a dylib that a running REAPER has loaded invalidates its code
# signature in memory and can crash REAPER; a rename leaves the loaded file intact until REAPER restarts.
cp "$(swift build -c "$CONFIGURATION" --show-bin-path)/libreaper_spacemouse.dylib" "$TARGET_DIR/reaper_spacemouse.dylib.new"
mv -f "$TARGET_DIR/reaper_spacemouse.dylib.new" "$TARGET_DIR/reaper_spacemouse.dylib"
echo "Installed to $TARGET_DIR/reaper_spacemouse.dylib"
