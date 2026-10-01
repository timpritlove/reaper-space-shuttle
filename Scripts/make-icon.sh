#!/bin/zsh
# Rebuilds the icon (ADR-0016): draws the layers of Packaging/AppIcon.icon, renders it with Icon Composer's ictool
# and writes the installer window images (light and dark, 1x and 2x) and docs/icon.png. Needs Xcode 26 and
# ImageMagick; the results are committed, so a release does not need either.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
ICTOOL="${ICTOOL:-/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift Scripts/make-icon-layers.swift Packaging/AppIcon.icon/Assets

render() { # rendition size output
  "$ICTOOL" Packaging/AppIcon.icon --export-image --output-file "$3" --platform macOS --rendition "$1" \
    --width "$2" --height "$2" --scale 1 >/dev/null
}

render Default 512 "$WORK/icon.png"
magick "$WORK/icon.png" -depth 8 docs/icon.png

# The installer draws its background bottom left, unscaled: a 128 pt icon with a 16 pt margin.
for rendition suffix in Default "" Dark "-dark"; do
  render "$rendition" 128 "$WORK/icon.png"
  render "$rendition" 256 "$WORK/icon@2x.png"
  magick -size 160x160 xc:none "$WORK/icon.png" -geometry +16+16 -composite -depth 8 -density 72 -units PixelsPerInch \
    "$WORK/background.png"
  magick -size 320x320 xc:none "$WORK/icon@2x.png" -geometry +32+32 -composite -depth 8 -density 144 -units PixelsPerInch \
    "$WORK/background@2x.png"
  tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
    -out "Packaging/Resources/background$suffix.tiff" 2>/dev/null
done
echo "Icon: Packaging/AppIcon.icon, Packaging/Resources/background*.tiff, docs/icon.png"
