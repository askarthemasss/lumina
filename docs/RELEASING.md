# Releasing Lumina

Lumina ships directly, outside the Mac App Store. A release needs three things:

1. A **Developer ID Application** certificate from an Apple Developer account.
2. A signed `.app` and `.dmg`.
3. A notarization ticket from Apple, stapled to the disk image.

The app is intentionally unsandboxed. See [Why isn't Lumina sandboxed?](../README.md#why-isnt-lumina-sandboxed) for the trade-off.

---

## Prerequisites

- An active [Apple Developer Program](https://developer.apple.com/programs/enroll/) membership. Individual enrollment costs $99 per year and usually takes one to two days to approve.
- Admin access to the GitHub repository, so you can add Actions secrets.
- A **Developer ID Application** certificate. This is separate from an Apple Development certificate and is only available after enrollment is approved.

If you have not enrolled yet, do that first. Nothing else here can produce a distributable build without it.

## One-time setup

### 1. Create and export the certificate

These steps work without a full Xcode installation:

1. Open **Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority**.
2. Enter your email and a common name, choose **Saved to disk**, and save the certificate signing request (`.certSigningRequest`).
3. Sign in to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list) and choose **Certificates → + → Developer ID Application**.
4. Upload the signing request, download the resulting `.cer`, and double-click it to install it in your login keychain.
5. Confirm that **Keychain Access → My Certificates** shows *Developer ID Application: …* with its private key attached.
6. Right-click the certificate, choose **Export**, select `.p12`, and set a password. This file and password go to CI; never commit them.

Copy the ten-character **Team ID** from [Membership Details](https://developer.apple.com/account/#/membership/).

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

The helper prompts for the `.p12`, its password, the signing identity, and the notary credentials, then stores all seven secrets through `gh`:

```bash
./scripts/configure_release_secrets.sh
```

It sends values over standard input, so they do not appear in shell history or process arguments. If you prefer to add them by hand, use **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64 of the `.p12` file (`base64 -i DeveloperID.p12`) |
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
