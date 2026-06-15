# AGENTS.md — Glide

Guidance for coding agents working in this repository.

## What Glide Is

Glide is a **macOS menu-bar utility** that adds simple, reliable window **move** and **resize** via modifier keys + mouse drag. It deliberately avoids the feature bloat of full window managers — one job, done well.

**Repository:** [github.com/drluckyspin/glide](https://github.com/drluckyspin/glide)  
**License:** MIT  
**Current version:** see `VERSION` (synced to `Glide/Glide-Info.plist` via `make bump-version`)

### Product Goals

- **Focused scope:** move and resize windows only — no tiling, snapping, multi-monitor layouts, etc.
- **Low friction:** defaults should work out of the box (`Cmd + Shift` + drag).
- **Native feel:** menu-bar app (`LSUIElement`), SwiftUI status dropdown, minimal onboarding for Accessibility permission.
- **Trustworthy distribution:** signed, notarized Developer ID builds; users install from a DMG copied to `/Applications`.
- **No third-party dependencies:** Apple frameworks only (`Cocoa`, `SwiftUI`, Accessibility APIs).

### Roadmap (not yet implemented)

- Launch at login
- User-selectable color scheme
- About dialog with version
- Check for updates

When implementing roadmap items, keep the same minimal scope — do not turn Glide into a general window manager.

---

## User-Facing Features

### Window actions (defaults)

| Action | Input | Behavior |
| ------ | ----- | -------- |
| **Move** | Hold required modifiers + **left-drag** (or hover-move; see below) | Moves the window under the cursor |
| **Resize** | Hold required modifiers + **right-drag** | Resizes from the edge/corner nearest the right-click (3×3 grid heuristic) |
| **Hover move** | Modifiers held + **mouse move** (no click) | Moves the app under the cursor without clicking the title bar |

### Menu bar dropdown (`StatusMenuView`)

Accessible from the menu-bar icon. All selected modifier keys must be held **simultaneously**.

- **Disabled** — globally turns Glide off (event tap disabled)
- **Activation keys** — toggle `Option`, `Command`, `Control`, `Shift` (stored as comma-separated string in `UserDefaults`)
- **Glide** — toggle hover-move mode (`useMouseMove`)
- **Resize** — toggle right-click resize (`useRightClickResize`)
- **Reset to defaults** — `Cmd + Shift`, hover move on, resize on, Glide enabled
- **Quit** — terminates the app

Defaults: `Cmd + Shift`, hover move **on**, right-click resize **on**.

### Onboarding

Shown on first launch when Accessibility permission is missing. Guides the user to **System Settings → Privacy & Security → Accessibility**.

- Running from a translocated path (e.g. directly from DMG) shows a warning banner — users must copy to `/Applications` first.
- Test flags: `-force-onboarding`, `-translocation` (see `make run-onboarding`).

### Permissions

Glide **requires Accessibility** (`AXIsProcessTrusted`) to read/write window position and size via `AXUIElement`. Without it, the app shows onboarding and polls until permission is granted.

---

## Architecture

```
main.swift
  └── NSApplicationMain → AppDelegate

AppDelegate.swift          ← lifecycle, CGEvent tap, menu panel, onboarding
  ├── Preferences.swift    ← UserDefaults persistence
  ├── WindowGlide.swift    ← shared gesture state (tracked window, resize grip)
  ├── StatusMenuView.swift ← SwiftUI menu + StatusMenuViewModel
  └── OnboardingView.swift ← first-run permission UI

GlideTests/                ← unit tests (Preferences, WindowGlide, launch smoke)
site/                      ← static landing page (Vercel deploy on merge to main)
scripts/                   ← log.bash (Makefile logging), ScreenshotRenderer
```

### Event handling (core mechanism)

1. `AppDelegate` creates a **head-insert CGEvent tap** on mouse events (`leftMouseDown/Dragged/Up`, `rightMouseDown/Dragged/Up`, `mouseMoved`).
2. The tap callback is a **free C function** (`eventTapCallback`) — not a closure — because Swift closures cannot be C function pointers.
3. When required modifiers are held (and no *extra* modifiers), events are handled in `handleCGEvent`:
   - Resolve window under cursor via `AXUIElementCopyElementAtPosition`
   - **Move:** update `AXPosition` (throttled every 2 events)
   - **Resize:** infer grip from right-click location in a 3×3 grid; update `AXSize` / `AXPosition` (throttled every 4 events)
4. Handled events return `nil` (consumed); otherwise events pass through.
5. When **Disabled**, the event tap is detached from the run loop.

### UI pattern

The status menu uses a custom **`StatusMenuPanel`** (borderless `NSPanel` at `.popUpMenu` level) instead of `NSPopover`, with global/local click monitors to dismiss on outside click — mimicking a native menu.

### Persistence

`Preferences` stores settings in `UserDefaults.standard`:

| Key | Default | Purpose |
| --- | ------- | ------- |
| `ModifierFlags` | `"CMD,SHIFT"` | Comma-separated `ModifierKey` raw values |
| `UseMouseMove` | `true` | Hover-move without click |
| `UseRightClickResize` | `true` | Right-drag resize |

---

## Tech Stack & Requirements

| Item | Value |
| ---- | ----- |
| Language | Swift 5.0 |
| UI | SwiftUI (menu, onboarding) + AppKit (app shell, event tap) |
| Deployment target | macOS 13.0 (Ventura) |
| Xcode | `LastUpgradeCheck` 2630; SDK notes reference Xcode 26 APIs (e.g. `CGEventMask` bit shift) |
| Packages | **None** — no SwiftPM, CocoaPods, or Carthage |
| Build system | Xcode project (`Glide.xcodeproj`) + `Makefile` wrappers |
| External tools | Homebrew `create-dmg` (for packaging) |

---

## Development Commands

Run from repo root. Use `make help` for the full list.

```bash
make check          # Verify Xcode, brew, create-dmg
make open           # Open Glide.xcodeproj in Xcode
make build          # Release build → build/Build/Products/Release/Glide.app
make build-debug    # Debug build
make run            # Build (Release) and launch
make run-debug      # Build (Debug) and launch
make run-onboarding # Debug build with -force-onboarding -translocation
make test           # xcodebuild test (Debug)
make clean          # Remove build/ and DMG artifacts
make install        # Build and copy to /Applications (prompts if exists)
make dev-package    # Unsigned DMG tagged "dev" for local testing
make site           # Open site/index.html in browser
```

First-time Xcode setup: `xcodebuild -runFirstLaunch`

Build output lives under `build/` (gitignored).

---

## Testing

```bash
make test
```

**What is tested** (`GlideTests/GlideTests.swift`):

- `Preferences` — default modifier flags, round-trip, reset
- `WindowGlide` — singleton and initial state
- `testLaunchOnboardingWithBanner` — launches the built app with onboarding flags (requires prior `make build`; skips if app not found)

Prefer extending tests for **pure logic** (preferences parsing, resize-grip math if extracted). Event-tap and AX integration are hard to unit-test — manual verification on macOS is expected.

---

## Release Process

Full details: [`RELEASE.md`](RELEASE.md). Summary for agents:

### Version sources

| File | Role |
| ---- | ---- |
| `VERSION` | Single source of truth for the next release (plain text, e.g. `1.3.0`) |
| `Glide/Glide-Info.plist` | `CFBundleShortVersionString` + `CFBundleVersion` — synced by `make bump-version` |
| `site/index.html` | Download URL + `data-vmtrc-version` — synced by `make bump-version` |

**Always run `make bump-version` after editing `VERSION`.** Bumping the plist alone does not update the website download link.

### Standard release (CI — preferred)

1. Set version: `echo "1.2.5" > VERSION && make bump-version`
2. Commit `VERSION`, `Glide/Glide-Info.plist`, and `site/index.html`
3. Merge to `main` (site deploys to production via **Vercel** automatically)
4. Push tag: `git tag v1.2.5 && git push origin v1.2.5`
5. GitHub Actions (`.github/workflows/release.yaml`) builds, signs, notarizes, creates DMG, zips it, and publishes a GitHub Release

**Triggers:** push of `v*` tag, or manual workflow dispatch (uses `VERSION` file).

**Release artifact:** `Glide-{version}.zip` (DMG inside a zip — preserves custom DMG icon through GitHub's upload).

**Download URL pattern:**

```
https://github.com/drluckyspin/glide/releases/download/v{version}/Glide-{version}.zip
```

### Local release (developer machine)

For testing signed builds without publishing:

```bash
echo "1.2.5" > VERSION
make bump-version
make release    # archive → codesign → notarize app → DMG → notarize DMG
```

- Output: `Glide-{version}.dmg` in repo root (gitignored)
- Uses **login keychain** Developer ID cert + `secrets/secrets.env` for notarization
- Does **not** create a GitHub release or `.zip` wrapper
- Override signing identity: `make release SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"`

### Secrets — do not commit

| Location | Purpose |
| -------- | ------- |
| `secrets/` (gitignored) | Local certs, `.p8` keys, `secrets.env` |
| GitHub Actions secrets | `APPLE_SIGNING_P12`, `APPLE_SIGNING_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_B64` |

Never commit, log, or embed signing credentials in source. The `secrets/` directory is in `.gitignore`.

---

## Landing Site (`site/`)

Static HTML landing page (`site/index.html`) with Tailwind CDN, custom CSS, and Vemetric analytics.

- **Deploy:** merging to `main` deploys `site/` to production (Vercel)
- **Download button:** must point at the GitHub release zip (updated by `make bump-version`)
- **Assets:** screenshots and icons live alongside `index.html` (`site/*.png`)
- **Docs mirror:** `docs/` holds README screenshots; keep marketing copy aligned when UI changes

Preview locally: `make site`

---

## Agent Guidelines

### Do

- Keep changes **minimal and focused** — match existing style in each file
- Use **`make build`** / **`make test`** to verify Swift changes
- Update **`VERSION` + `make bump-version`** when preparing a release (include `site/index.html`)
- Preserve the **no-dependency** policy — Apple frameworks only
- Respect **Accessibility** as a hard requirement; do not add workarounds that bypass user consent
- Use **`make run-onboarding`** to manually test onboarding UI changes
- Follow existing patterns: free-function event tap callback, `WindowGlide.shared` for gesture state, `Preferences.shared` for settings

### Do not

- Commit files under `secrets/`, `build/`, or `*.dmg`
- Add SwiftPM/CocoaPods dependencies without explicit approval
- Expand scope into full window management (tiling, spaces, rules engines, etc.)
- Change signing/notarization flow without updating both `Makefile` and `.github/workflows/release.yaml`
- Run `make release` or push tags unless the user explicitly asks
- Create git commits or PRs unless requested
- Create branches outside `feature/`, `fix/`, or `chore/`

### Common edit locations

| Task | Files |
| ---- | ----- |
| Move/resize behavior | `AppDelegate.swift`, `WindowGlide.swift` |
| Menu UI / toggles | `StatusMenuView.swift`, `AppDelegate.swift` (wiring) |
| Defaults / prefs | `Preferences.swift` |
| Onboarding copy/UI | `OnboardingView.swift`, `OnboardingWindowController.swift` |
| App metadata | `Glide/Glide-Info.plist`, `VERSION` |
| Release/version bump | `VERSION`, `Makefile` (`bump-version`), `site/index.html` |
| CI release | `.github/workflows/release.yaml` |
| Marketing page | `site/index.html`, `site/*.png` |

### SDK notes

The codebase targets modern Xcode/macOS SDKs. Notable patterns:

- `CGEventMaskBit` removed in Xcode 26 SDK — use `CGEventMask(1) << CGEventMask(type.rawValue)` (see `eventMaskBit` in `AppDelegate.swift`)
- Event tap callback parameters are non-optional in newer SDKs

---

## Contributing Workflow

1. Open an issue for bugs or feature ideas (especially before large changes)
2. Fork → branch → pull request
3. Small PRs welcome for early feedback
4. Ensure `make test` passes before requesting review

### Branch names

Use **only** these prefixes:

| Prefix | Use for |
| ------ | ------- |
| `feature/` | New functionality or user-facing improvements |
| `fix/` | Bug fixes |
| `chore/` | Docs, tooling, refactors, version bumps, CI — no product behavior change |

Format: `{prefix}/{short-kebab-description}` (e.g. `feature/add-agents-md`, `fix/status-menu-dismiss`, `chore/bump-version`).

Do not use other prefixes (`cursor/`, `dev/`, personal names, etc.).

---

## Quick Reference

```bash
# Daily dev loop
make run-debug

# Before a release PR
echo "X.Y.Z" > VERSION && make bump-version
make test && make build

# Tag release (after merge)
git tag vX.Y.Z && git push origin vX.Y.Z

# Local signed DMG (optional)
make release
```

For release troubleshooting, signing chain setup, and GitHub secret configuration, see [`RELEASE.md`](RELEASE.md) and [`README.md`](README.md).
