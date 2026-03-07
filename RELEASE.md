# Glide Release Guide

This document describes the release process used by `.github/workflows/release.yaml`. Use it as a reference if you forget the steps or need to set up secrets.

## Triggers

- **Tag push**: Push a tag matching `v*` (e.g. `v1.2.0`) to trigger a release.
- **Manual**: Use "Run workflow" in the Actions tab (uses version from `VERSION` file).

## Required Secrets (GitHub Repository Settings → Secrets and variables → Actions)

| Secret | Description | How to obtain |
|--------|-------------|---------------|
| `APPLE_SIGNING_P12` | Base64-encoded Developer ID Application certificate (.p12) | Export from Keychain Access, then `base64 -i YourCert.p12 \| pbcopy` |
| `APPLE_SIGNING_P12_PASSWORD` | Password for the .p12 file | Set when exporting the .p12 |
| `ASC_KEY_ID` | App Store Connect API key ID (10 chars) | [App Store Connect → Users and Access → Keys](https://appstoreconnect.apple.com/access/api) |
| `ASC_ISSUER_ID` | App Store Connect issuer ID (UUID) | Same page as ASC_KEY_ID |
| `ASC_PRIVATE_KEY_B64` | Base64-encoded .p8 private key | Download .p8 when creating the key, then `base64 -i AuthKey_XXX.p8 \| pbcopy` |
| `GITHUB_TOKEN` | Auto-provided by GitHub Actions | No setup needed |

---

## Release Steps (in order)

### 1. Checkout code

Standard `actions/checkout@v4`.

### 2. Get Version

- **Tag push**: Extract from `GITHUB_REF` (e.g. `refs/tags/v1.2.0` → `1.2.0`). Leading `v` is stripped.
- **Manual**: Read from `VERSION` file, or fallback to `CFBundleShortVersionString` in `Glide/Glide-Info.plist`.

### 3. Build (unsigned)

```bash
xcodebuild archive \
  -project Glide.xcodeproj \
  -scheme Glide \
  -configuration Release \
  -archivePath ./build/Glide.xcarchive \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

### 4. Prepare App Artifact

Copy the built app from the archive to `./build/dist/Glide.app`.

### 5. Setup Signing Keychain (Apple-specific)

Creates an ephemeral keychain and imports everything needed for codesigning:

1. **Create keychain** at `$RUNNER_TEMP/build.keychain-db` (empty password).
2. **Import .p12** (Developer ID Application cert + private key) from `APPLE_SIGNING_P12`.
3. **Import intermediate certs** (required for chain validation):
   - `DeveloperIDG2CA.cer` from apple.com/certificateauthority
   - `DeveloperIDCA.cer` from apple.com/certificateauthority
   - Downloaded with `curl -sfL`, imported only on success.
4. **Set key partition list** so `codesign` can access the key non-interactively (`-S apple-tool:,apple:`).

### 6. Codesign App

- Find the first codesigning identity in the keychain (SHA-1 hash).
- Sign with: `codesign --force --options runtime --timestamp --sign <identity> --keychain <path> Glide.app`
- **Hardened runtime** (`--options runtime`) is required for notarization.
- Verify with `codesign -vvv --deep --strict`.

### 7. Prepare App Store Connect API Key

Decode `ASC_PRIVATE_KEY_B64` to `AuthKey.p8`, chmod 600. Used by `notarytool` for notarization.

### 8. Notarize App (zip + staple)

1. **Zip the app**: `ditto -c -k --sequesterRsrc --keepParent Glide.app Glide.zip`
2. **Submit to Apple**: `xcrun notarytool submit Glide.zip --key AuthKey.p8 --key-id <ASC_KEY_ID> --issuer <ASC_ISSUER_ID> --wait`
3. **Staple** the notarization ticket to the app: `xcrun stapler staple Glide.app`
4. **Validate**: `xcrun stapler validate Glide.app`

Notarizing the app first gives fast feedback if something is wrong before building the DMG.

### 9. Build DMG

1. **Install create-dmg**: `brew install create-dmg`
2. **Create DMG** with `create-dmg`:
   - Volume name: "Glide {version}"
   - Volume icon from `AppIcon.icns`
   - Window 600×400, app icon at (175,120), drop link at (425,120)
3. **Embed custom icon on DMG file** (so it shows in Finder when unmounted):
   - `sips -i` on the .icns
   - `DeRez -only icns` to extract resource
   - `Rez -append` to add to DMG
   - `SetFile -a C` to set custom icon flag

### 10. Notarize DMG and Staple

Same as app: submit DMG to notarytool, wait, staple, validate.

### 11. Create Release Zip

`ditto -c -k --sequesterRsrc Glide-{version}.dmg Glide-{version}.zip`

**Why zip?** GitHub uploads strip resource forks. The DMG's custom icon lives in a resource fork. Zipping preserves it; when users download and extract, they get the DMG with the icon intact.

### 12. Verify Gatekeeper (optional)

`spctl -a -vvv --type exec Glide.app` — sanity check that Gatekeeper accepts the app.

### 13. Create GitHub Release

- **Tag**: `v{version}` (created if it doesn't exist for manual runs)
- **File**: `Glide-{version}.zip` (not the raw DMG, so the icon survives download)
- **Release notes**: Auto-generated

---

## Local Release (Makefile)

For local signing and notarization, use `make release` or `make sign`. Requires `secrets/secrets.env` with the same variables as the table above. Run `make bump-version` first to sync `VERSION` into the plist.

---

## Apple Developer Prerequisites

1. **Developer ID Application certificate**: Create in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list). Export as .p12.
2. **App Store Connect API key**: Create in [Users and Access → Keys](https://appstoreconnect.apple.com/access/api). Download the .p8 file once (it can't be re-downloaded).
3. **Notarization**: Requires an Apple Developer Program membership. Notarytool uses the App Store Connect API key for authentication.
