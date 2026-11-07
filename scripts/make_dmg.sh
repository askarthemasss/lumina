#!/bin/bash
# Packages dist/Lumina.app into a compressed DMG with an Applications shortcut.
# Set SIGN_IDENTITY to sign the disk image for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Lumina.app"
if [[ ! -d "$APP" ]]; then
    echo "Missing $APP. Run ./scripts/package_app.sh first." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/Lumina-${VERSION}.dmg"
STAGING_ROOT="$(mktemp -d)"
STAGING="$STAGING_ROOT/Lumina"
trap 'rm -rf "$STAGING_ROOT"' EXIT

mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/Lumina.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -quiet \
    -volname "Lumina ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --strict --verbose=2 "$DMG"
fi

echo "$DMG"
