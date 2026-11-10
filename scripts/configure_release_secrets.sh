#!/bin/bash
# Stores the GitHub Actions secrets used by .github/workflows/release.yml.
#
# Run this after creating and exporting a Developer ID Application
# certificate. Values are sent to GitHub over gh's stdin, so they do not land
# in shell history, process arguments, or the repository.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI not found. Install it with: brew install gh" >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    exit 1
fi

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "Configuring release secrets for $REPO."
echo

read -r -p "Path to the exported Developer ID .p12: " P12
P12="${P12/#\~/$HOME}"
if [[ ! -f "$P12" ]]; then
    echo "No file at $P12" >&2
    exit 1
fi

read -r -s -p "Password used to export the .p12: " P12_PASSWORD
echo
if [[ -z "$P12_PASSWORD" ]]; then
    echo "The .p12 password cannot be empty." >&2
    exit 1
fi

read -r -p "Developer ID identity (Developer ID Application: Name (TEAMID)): " IDENTITY
if [[ "$IDENTITY" != "Developer ID Application:"* ]]; then
    echo "The identity must start with 'Developer ID Application:'." >&2
    exit 1
fi

read -r -p "Apple ID email: " APPLE_ID
read -r -p "Apple Team ID (ten characters): " TEAM_ID
read -r -s -p "App-specific password for notarization: " APPLE_APP_PASSWORD
echo

if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APPLE_APP_PASSWORD" ]]; then
    echo "Apple ID, Team ID, and app-specific password are all required." >&2
    exit 1
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "Found the signing identity in this Mac's keychain."
else
    echo "Note: this identity is not installed locally; CI will import it from the .p12."
fi

echo
echo "Uploading secrets..."

set_secret() {
    printf '%s' "$2" | gh secret set "$1" --repo "$REPO" >/dev/null
    echo "  set $1"
}

base64 -i "$P12" | gh secret set MACOS_CERTIFICATE --repo "$REPO" >/dev/null
echo "  set MACOS_CERTIFICATE"
set_secret MACOS_CERTIFICATE_PASSWORD "$P12_PASSWORD"
set_secret MACOS_SIGNING_IDENTITY "$IDENTITY"
set_secret KEYCHAIN_PASSWORD "$(openssl rand -base64 32)"
set_secret APPLE_ID "$APPLE_ID"
set_secret APPLE_TEAM_ID "$TEAM_ID"
set_secret APPLE_APP_PASSWORD "$APPLE_APP_PASSWORD"

echo
gh secret list --repo "$REPO"
echo
echo "Done. Push a v* tag, or run the Release workflow manually, to publish."
