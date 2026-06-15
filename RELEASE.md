# Glide Release Guide

This document describes the release process used by `.github/workflows/release.yaml`. Use it as a reference if you
forget the steps or need to set up secrets.

## Distribution

Glide is **not** on the Mac App Store. Public releases are:

1. **GitHub Releases** — CI publishes `Glide-{version}.zip` (signed, notarized DMG inside) when you push a `v*` tag.
2. **Landing site** — `site/index.html` download button links to that release zip (URL updated by `make bump-version`).

Secrets named `ASC_*` below are **App Store Connect API keys used only for Apple notarization** (`notarytool`). They are
not used for Mac App Store submission.

## Triggers

- **Tag push**: Push a tag matching `v*` (e.g. `v1.2.0`) to trigger a release.
- **Manual**: Use "Run workflow" in the Actions tab (uses version from `VERSION` file).

## Required Secrets (GitHub Repository Settings → Secrets and variables → Actions)

| Secret                       | Description                                                  | How to obtain                                                                               |
| ---------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `APPLE_SIGNING_P12`          | Base64-encoded Developer ID Application certificate (.p12)   | Export from Keychain Access, then `base64 -i YourCert.p12 \| pbcopy`                        |
| `APPLE_SIGNING_P12_PASSWORD` | Password for the .p12 file                                   | Set when exporting the .p12                                                                 |
| `ASC_KEY_ID`                 | Notarization API key ID (10 chars; App Store Connect → Keys) | [App Store Connect → Users and Access → Keys](https://appstoreconnect.apple.com/access/api) |
| `ASC_ISSUER_ID`              | Notarization issuer ID (UUID)                                | Same page as ASC_KEY_ID                                                                     |
| `ASC_PRIVATE_KEY_B64`        | Base64-encoded .p8 private key (notarization only)           | Download .p8 when creating the key, then `base64 -i AuthKey_XXX.p8 \| pbcopy`               |
| `GITHUB_TOKEN`               | Auto-provided by GitHub Actions                              | No setup needed                                                                             |

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
2. **Submit to Apple**:
   `xcrun notarytool submit Glide.zip --key AuthKey.p8 --key-id <ASC_KEY_ID> --issuer <ASC_ISSUER_ID> --wait`
3. **Staple** the notarization ticket to the app: `xcrun stapler staple Glide.app`
4. **Validate**: `xcrun stapler validate Glide.app`

Notarizing the app first gives fast feedback if something is wrong before building the DMG.

### 9. Build DMG

1. **Install create-dmg**: `brew install create-dmg`
2. **Create DMG** with `create-dmg`:
   - Volume name: "Glide {version}"
   - Volume icon from `AppIcon.icns`
   - Window position (200,120), size 600×400, icon size 100, app icon at (175,120), drop link at (425,120)
3. **Embed custom icon on DMG file** (so it shows in Finder when unmounted):
   - `sips -i` on the .icns
   - `DeRez -only icns` to extract resource
   - `Rez -append` to add to DMG
   - `SetFile -a C` to set custom icon flag

### 10. Notarize DMG and Staple

Same as app: submit DMG to notarytool, wait, staple, validate.

### 11. Create Release Zip

`ditto -c -k --sequesterRsrc Glide-{version}.dmg Glide-{version}.zip`

**Why zip?** GitHub uploads strip resource forks. The DMG's custom icon lives in a resource fork. Zipping preserves it;
when users download and extract, they get the DMG with the icon intact.

### 12. Verify Gatekeeper (optional)

`spctl -a -vvv --type exec Glide.app` — sanity check that Gatekeeper accepts the app.

### 13. Create GitHub Release

- **Tag**: `v{version}` (created if it doesn't exist for manual runs)
- **File**: `Glide-{version}.zip` (not the raw DMG, so the icon survives download)
- **Release notes**: Auto-generated

### 14. Update site download link

The landing page download button lives in `site/index.html`. It must point at the new GitHub release **after** the
release zip is published — otherwise visitors get a 404.

1. **Before tagging**: set `VERSION` and run `make bump-version`. This syncs the version into `Glide/Glide-Info.plist`
   and rewrites the download URL and `data-vmtrc-version` in `site/index.html` to:
   `https://github.com/drluckyspin/glide/releases/download/v{version}/Glide-{version}.zip`
2. **Refresh screenshots** (macOS only): run `make screenshots`. This rebuilds `docs/drop-down.png`,
   `docs/onboarding.png`, the matching `site/` copies, and `site/menubar.png` (the freshly rendered dropdown is scaled
   to the `card` footprint in `scripts/screenshot-layout.json` and stamped onto the clean menubar capture
   `site/menubar-base.png`, reusing its wallpaper, rounded corners, and drop shadow). `site/glide-hero.png` still needs
   a manual capture if you want that updated.
3. **After the GitHub release exists**: open the site locally (`make site`) and confirm the Download button resolves to
   the new `.zip` asset.
4. **Site deploy**: merging to `main` automatically deploys `site/` to production via Vercel. No manual deploy step —
   just ensure `site/index.html` and refreshed PNGs are committed in the release PR before merge (steps 1–2).

> Do not skip step 1 — bumping the app version alone does not update what users download from the website until
> `site/index.html` is committed and merged to `main`. Step 2 keeps README and site menu screenshots in sync with the
> release version.

The menu card is always the same rounded rectangle, so compositing just stamps the current dropdown over the card region
of `site/menubar-base.png`; the corners and shadow come from that base. If the dropdown moves or resizes, update the
`card` rectangle in `scripts/screenshot-layout.json`. To refresh the desktop/menubar background, drop a new clean
capture at `site/menubar-source.png` and run `python3 scripts/prepare-menubar-base.py` to regenerate
`site/menubar-base.png`.

---

## Local Release (Makefile)

For local signing and notarization, use `make release` (or `make sign`). The version comes from
`CFBundleShortVersionString` in `Glide/Glide-Info.plist`, so run `make bump-version` first to sync the `VERSION` file
into the plist.

```bash
echo "1.2.5" > VERSION   # set the version you want
make bump-version        # sync VERSION → plist + site download URL
make screenshots         # refresh docs/ and site/ PNGs (macOS only)
make release             # archive → codesign → notarize app → DMG → notarize DMG
```

Output is a signed, notarized, stapled `Glide-<version>.dmg` in the repo root. Local release does **not** create a
GitHub release or the `.zip` wrapper — those are CI-only steps (see above). Upload the DMG manually, or push a `v*` tag
to let the workflow build and publish its own copy.

### How local signing differs from CI

Unlike the GitHub Actions workflow, `make release` does **not** create an ephemeral keychain or change your
default/search-list keychains. It signs with the Developer ID Application identity already in your **login keychain**
and notarizes straight from `secrets/secrets.env`. This avoids disturbing your macOS session (no password prompts in
other apps, nothing to restore if a run is interrupted).

Requirements:

- `secrets/secrets.env` must exist with `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_B64` (used for
  notarization).
- Your Developer ID Application certificate must be installed in your login keychain.

> **Note:** Local signing uses the Developer ID Application certificate in your login keychain. If it isn't installed,
> `make release` fails fast with a clear message — import it once by double-clicking `secrets/DevIDCertificates.p12`,
> then retry.
>
> By default the target signs with the identity named `Developer ID Application`. If your keychain has more than one
> such identity (or you want to pin a specific one), override it with the full identity name:
>
> ```bash
> # List available identities:
> security find-identity -v -p codesigning
>
> # Then pass the one you want:
> make release SIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAMID>)"
> ```

---

## Apple Developer Prerequisites

1. **Developer ID Application certificate**: Create in
   [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list). Export as
   .p12.
2. **Notarization API key** (App Store Connect → Users and Access → Keys): download the `.p8` once for `notarytool`
   authentication. This is **not** Mac App Store distribution — only notarization.
3. **Notarization**: Requires an Apple Developer Program membership. Notarytool uses the API key above.
