#!/bin/bash
# Submits a signed DMG to Apple's notary service and staples the ticket.
#
# Prefer a local notarytool keychain profile:
#   xcrun notarytool store-credentials "lumina-notary" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#   NOTARYTOOL_PROFILE=lumina-notary ./scripts/notarize.sh dist/Lumina-1.0.0.dmg
#
# CI can provide APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD instead.
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="${1:-}"
if [[ -z "$DMG" || ! -f "$DMG" ]]; then
    echo "Usage: $0 path/to/Lumina.dmg" >&2
    exit 1
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARYTOOL_PROFILE" \
        --wait
else
    : "${APPLE_ID:?Set NOTARYTOOL_PROFILE or APPLE_ID}"
    : "${APPLE_TEAM_ID:?Set NOTARYTOOL_PROFILE or APPLE_TEAM_ID}"
    : "${APPLE_APP_PASSWORD:?Set NOTARYTOOL_PROFILE or APPLE_APP_PASSWORD}"
    xcrun notarytool submit "$DMG" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait
fi

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarized and stapled $DMG"
