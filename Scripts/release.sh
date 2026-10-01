#!/bin/zsh
# Builds the release installer (ADR-0009): universal dylib signed with Developer ID Application, a per-user .pkg
# signed with Developer ID Installer, notarized and stapled → dist/SpaceShuttle-<version>.pkg.
# Without the installer certificate it stops after building an unsigned package for local tests.
# Options: --allow-dirty (skip the clean-tree check, for trying the script).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION="$(<VERSION)"
IDENTIFIER="me.metaebene.reaper-space-shuttle"
APP_IDENTITY="${APP_IDENTITY:-Developer ID Application: Tim Francis Pritlove (MZ2D45J5VM)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer: Tim Francis Pritlove (MZ2D45J5VM)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-stagehand-notary}"
BUILD="$ROOT/.build/release-pkg"
OUTPUT="$ROOT/dist/SpaceShuttle-$VERSION.pkg"

if [[ "${1:-}" != "--allow-dirty" && -n "$(git status --porcelain)" ]]; then
  echo "Uncommitted changes; commit first (or --allow-dirty to try the script)." >&2
  exit 1
fi

echo "== Tests"
swift test >/dev/null

echo "== Universal build $VERSION"
swift build -c release --arch arm64 --arch x86_64 --product reaper_spaceshuttle >/dev/null
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$BUILD"
mkdir -p "$BUILD/root" "$ROOT/dist"
# REAPER only loads extensions named reaper_*.dylib.
cp "$BIN/libreaper_spaceshuttle.dylib" "$BUILD/root/reaper_spaceshuttle.dylib"

echo "== Signing the extension"
codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" "$BUILD/root/reaper_spaceshuttle.dylib"
codesign --verify --strict "$BUILD/root/reaper_spaceshuttle.dylib"

echo "== Package"
# With the currentUserHome domain the install location is relative to the user's home folder.
pkgbuild --root "$BUILD/root" --identifier "$IDENTIFIER" --version "$VERSION" \
  --install-location "/Library/Application Support/REAPER/UserPlugins" "$BUILD/component.pkg" >/dev/null
sed "s/VERSION/$VERSION/" Packaging/distribution.xml > "$BUILD/distribution.xml"
productbuild --distribution "$BUILD/distribution.xml" --resources Packaging/Resources \
  --package-path "$BUILD" "$BUILD/unsigned.pkg" >/dev/null

if ! security find-identity -v | grep -qF "$INSTALLER_IDENTITY"; then
  echo "No \"$INSTALLER_IDENTITY\" in the keychain: cannot sign or notarize the installer." >&2
  echo "Create it in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Installer." >&2
  echo "Unsigned package for local tests: $BUILD/unsigned.pkg" >&2
  exit 2
fi

echo "== Signing the package"
productsign --timestamp --sign "$INSTALLER_IDENTITY" "$BUILD/unsigned.pkg" "$OUTPUT" >/dev/null

echo "== Notarizing"
xcrun notarytool submit "$OUTPUT" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUTPUT"
spctl --assess --type install -v "$OUTPUT"
echo "Release: $OUTPUT"
