#!/bin/bash
# Builds Lumina with SwiftPM and assembles a runnable .app bundle in dist/.
# XcodeGen remains the canonical project generator; this script supports local
# smoke tests and release packaging without a full Xcode installation.
#
# Set SIGN_IDENTITY to a Developer ID Application identity for distribution:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/package_app.sh
# With no identity, the app is ad-hoc signed for local use only.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Lumina"
BUNDLE_ID="com.lumina.app"
APP="dist/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp AppResources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

sed -e "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    AppResources/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Build a .icns from the same generated app icon set the asset catalog uses.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
cp AppResources/Assets.xcassets/AppIcon.appiconset/*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

ENTITLEMENTS="AppResources/Lumina.entitlements"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Ad-hoc signing keeps Gatekeeper and macOS privacy prompts coherent for a
    # local build. Distribution builds need a Developer ID identity.
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP" >/dev/null
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP (signed with $SIGN_IDENTITY)"
