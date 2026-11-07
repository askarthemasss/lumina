# Releasing Lumina

Lumina ships directly, outside the Mac App Store. A release needs three things:

1. A **Developer ID Application** certificate from an Apple Developer account.
2. A signed `.app` and `.dmg`.
3. A notarization ticket from Apple, stapled to the disk image.

The app is intentionally unsandboxed. See [Why isn't Lumina sandboxed?](../README.md#why-isnt-lumina-sandboxed) for the trade-off.

---

## One-time setup

### 1. Export the certificate

In **Keychain Access → My Certificates**, find *Developer ID Application: …* and export it as a password-protected `.p12`.

For CI, base64-encode it:

```bash
base64 -i DeveloperID.p12 | pbcopy
```

### 2. Store notary credentials locally

Create an app-specific password at [appleid.apple.com](https://appleid.apple.com), then:

```bash
xcrun notarytool store-credentials "lumina-notary" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "app-specific-password"
```

The profile lives in your login keychain. Do not commit it.

### 3. Configure GitHub Actions secrets

Add these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64 of the `.p12` file |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `MACOS_SIGNING_IDENTITY` | Full identity name, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `KEYCHAIN_PASSWORD` | Any random password; used only for the temporary CI keychain |
| `APPLE_ID` | Apple account email |
| `APPLE_TEAM_ID` | Ten-character team identifier |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |

The release workflow imports the certificate into a temporary keychain and deletes the keychain afterward. The certificate and password never enter the repository.

---

## Build a release locally

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  CONFIGURATION=release ./scripts/package_app.sh

SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/make_dmg.sh
```

That produces `dist/Lumina-1.0.0.dmg`. Notarize it with the keychain profile:

```bash
NOTARYTOOL_PROFILE=lumina-notary ./scripts/notarize.sh dist/Lumina-1.0.0.dmg
```

Or provide the credentials directly:

```bash
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="YOURTEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
  ./scripts/notarize.sh dist/Lumina-1.0.0.dmg
```

`notarize.sh` submits the DMG with `--wait`, staples the ticket, and validates it.

### Verify the result

```bash
codesign --verify --deep --strict --verbose=2 dist/Lumina.app
codesign -dv --verbose=4 dist/Lumina.app
xcrun stapler validate dist/Lumina-1.0.0.dmg
```

---

## Publish a version

`project.yml` and `AppResources/Info.plist` both carry version fields. Update them together:

- `MARKETING_VERSION` in `project.yml` → new version, e.g. `1.1.0`
- `CFBundleShortVersionString` in `AppResources/Info.plist` → same version
- `CURRENT_PROJECT_VERSION` and `CFBundleVersion` → increment the build number
- `README.md` download table or release notes, if the version is mentioned

Then commit, tag, and push:

```bash
git add .
git commit -m "Release 1.1.0"
git tag -a v1.1.0 -m "Lumina 1.1.0"
git push origin main
git push origin v1.1.0
```

The tag starts `.github/workflows/release.yml`, which:

1. builds the signed app,
2. checks that the tag matches `CFBundleShortVersionString`,
3. creates and signs the DMG,
4. notarizes and staples it,
5. publishes a GitHub release with generated notes and the DMG attached.

You can also run the workflow manually with an existing tag from the **Actions** tab.

---

## Release checklist

- [ ] Tests pass: `./scripts/test.sh`
- [ ] Live runtime tests pass: `LUMINA_LIVE_OLLAMA=1 ./scripts/test.sh`
- [ ] `swift build` and `xcodebuild test` pass in CI
- [ ] Version fields match between `project.yml` and `Info.plist`
- [ ] `README.md` and screenshots still match the app
- [ ] The DMG opens, drags to Applications, and launches after quarantine
- [ ] The release artifact is signed with a Developer ID, not ad hoc
- [ ] The notarization ticket validates

Clean up local test data before publishing screenshots or recordings:

```bash
rm -rf "$HOME/Library/Application Support/Lumina"
defaults delete com.lumina.app
```
