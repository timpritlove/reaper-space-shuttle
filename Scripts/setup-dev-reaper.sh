#!/bin/zsh
# Sets up a portable REAPER installation in .dev/reaper for development and tests.
# A portable install (reaper.ini next to REAPER.app) keeps its own resource path, so the
# production REAPER/Ultraschall configuration in ~/Library/Application Support/REAPER is never touched.
set -euo pipefail

REAPER_VERSION="${REAPER_VERSION:-781}"
ROOT="${0:A:h:h}"
DEV_DIR="$ROOT/.dev/reaper"
DMG="$ROOT/.dev/reaper${REAPER_VERSION}_universal.dmg"
LICENSE="$HOME/Library/Application Support/REAPER/reaper-license.rk"

mkdir -p "$DEV_DIR/UserPlugins"

if [[ ! -f "$DMG" ]]; then
  echo "Downloading REAPER ${REAPER_VERSION}…"
  curl -fL -o "$DMG" "https://www.reaper.fm/files/${REAPER_VERSION:0:1}.x/reaper${REAPER_VERSION}_universal.dmg"
fi

if [[ ! -d "$DEV_DIR/REAPER.app" ]]; then
  MOUNT="$(mktemp -d)"
  # The DMG shows a license agreement; answer it non-interactively.
  { yes || true; } | hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null 2>&1
  cp -R "$MOUNT/REAPER.app" "$DEV_DIR/"
  hdiutil detach "$MOUNT" >/dev/null
  xattr -dr com.apple.quarantine "$DEV_DIR/REAPER.app" 2>/dev/null || true
fi

# An existing reaper.ini next to the app switches REAPER into portable mode.
if [[ ! -f "$DEV_DIR/reaper.ini" ]]; then
  cat > "$DEV_DIR/reaper.ini" <<'INI'
[REAPER]
splashfast=1
showsplash=0
verchk=0
lastver=0
INI
fi

# Reuse the user's license (symlink, nothing is copied) so no evaluation dialog blocks automated runs.
if [[ -f "$LICENSE" && ! -e "$DEV_DIR/reaper-license.rk" ]]; then
  ln -s "$LICENSE" "$DEV_DIR/reaper-license.rk"
fi

defaults read "$DEV_DIR/REAPER.app/Contents/Info.plist" CFBundleShortVersionString
echo "Portable REAPER ready in $DEV_DIR"
