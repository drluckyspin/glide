# AGENTS.md — Glide

Guidance for coding agents working in this repository.

## What Glide Is

Glide is **assistive macOS software** — a menu-bar utility that adds simple, reliable window **move** and **resize** via
modifier keys + mouse drag. It helps users who find standard title bars and resize edges difficult (limited dexterity,
pain, tremor, fatigue, etc.). It deliberately avoids the feature bloat of full window managers — one job, done well.

**Repository:** [github.com/drluckyspin/glide](https://github.com/drluckyspin/glide)\
**License:** MIT\
**Current version:** see `VERSION` (synced to `Glide/Glide-Info.plist` via `make bump-version`)

### Distribution (direct download only)

Glide is **not** distributed via the Mac App Store. Releases are:

1. **Built and published** as signed, notarized DMG inside `Glide-{version}.zip` on
   [GitHub Releases](https://github.com/drluckyspin/glide/releases) (CI: push a `v*` tag).
2. **Linked from the landing site** (`site/index.html` download button → GitHub release zip URL, updated by
   `make bump-version`).

Do not add App Store download links, MAS-specific copy, or assumptions that Glide is (or will be) on the Mac App Store.
App Store Connect API keys in release docs/secrets are used **only for Apple notarization** (`notarytool`), not for
store submission.

### Product Goals

- **Focused scope:** move and resize windows only — no tiling, snapping, multi-monitor layouts, etc.
- **Low friction:** defaults should work out of the box (`Cmd + Shift` + drag).
- **Native feel:** menu-bar app (`LSUIElement`), SwiftUI status dropdown, minimal onboarding for Accessibility
  permission.
- **Trustworthy distribution:** Developer ID signed + notarized builds; users download from the site/GitHub, open the
  DMG, and copy to `/Applications`.
- **No app dependencies:** Apple frameworks only in the Glide target (`Cocoa`, `SwiftUI`, Accessibility APIs).

### Roadmap (not yet implemented)

- Launch at login
- User-selectable color scheme
- About dialog with version
- Check for updates

When implementing roadmap items, keep the same minimal scope — do not turn Glide into a general window manager.

---

## User-Facing Features

### Window actions (defaults)

| Action         | Input                                                              | Behavior                                                                  |
| -------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| **Move**       | Hold required modifiers + **left-drag** (or hover-move; see below) | Moves the window under the cursor                                         |
| **Resize**     | Hold required modifiers + **right-drag**                           | Resizes from the edge/corner nearest the right-click (3×3 grid heuristic) |
| **Hover move** | Modifiers held + **mouse move** (no click)                         | Moves the app under the cursor without clicking the title bar             |

### Menu bar dropdown (`StatusMenuView`)

Accessible from the menu-bar icon. All selected modifier keys must be held **simultaneously**.

- **Disabled** — globally turns Glide off (event tap disabled)
- **Activation keys** — toggle `Option`, `Command`, `Control`, `Shift` (stored as comma-separated string in
  `UserDefaults`)
- **Glide** — toggle hover-move mode (`useMouseMove`); tooltip: "Hover to move"
- **Resize** — toggle right-click resize (`useRightClickResize`); tooltip: "Right-click drag"
- **Reset to defaults** — `Cmd + Shift`, hover move on, resize on, Glide enabled
- **Quit** — terminates the app

Defaults: `Cmd + Shift`, hover move **on**, right-click resize **on**.

### Onboarding

Shown on first launch when Accessibility permission is missing. Guides the user to **System Settings → Privacy &
Security → Accessibility**.

- Running from a translocated path (e.g. directly from DMG) shows a warning banner — users must copy to `/Applications`
  first.
- Test flags: `-force-onboarding`, `-translocation` (see `make run-onboarding`).

### Permissions

Glide **requires Accessibility** (`AXIsProcessTrusted`) to read/write window position and size via `AXUIElement`.
Without it, the app shows onboarding and polls until permission is granted. `NSAccessibilityUsageDescription` in
`Glide-Info.plist` frames this as assistive window control — keep that framing in related copy.

---

## Architecture

```sh
main.swift
  └── NSApplicationMain → AppDelegate

AppDelegate.swift          ← lifecycle, CGEvent tap, menu panel, onboarding, --screenshot mode
  ├── Preferences.swift    ← UserDefaults persistence
  ├── WindowGlide.swift    ← shared gesture state (tracked window, resize grip)
  ├── StatusMenuView.swift ← SwiftUI menu + StatusMenuViewModel
  ├── OnboardingView.swift ← first-run permission UI
  └── OnboardingWindowController.swift

GlideTests/                ← unit tests (Preferences, WindowGlide, launch smoke)
site/                      ← static landing page (Vercel deploy on merge to main)
scripts/                   ← render-screenshots.sh, screenshot-layout.json, log.bash,
                             patch-screenshot-version.py, prepare-menubar-base.py
.github/workflows/         ← release.yaml (signed DMG), screenshots.yaml (PNG refresh CI)
```

### Event handling (core mechanism)

1. `AppDelegate` creates a **head-insert CGEvent tap** on mouse events (`leftMouseDown/Dragged/Up`,
   `rightMouseDown/Dragged/Up`, `mouseMoved`).
2. The tap callback is a **free C function** (`eventTapCallback`) — not a closure — because Swift closures cannot be C
   function pointers.
3. When required modifiers are held (and no _extra_ modifiers), events are handled in `handleCGEvent`:
   - Resolve window under cursor via `AXUIElementCopyElementAtPosition`
   - **Move:** update `AXPosition` (throttled every 2 events)
   - **Resize:** infer grip from right-click location in a 3×3 grid; update `AXSize` / `AXPosition` (throttled every 4
     events)
4. Handled events return `nil` (consumed); otherwise events pass through.
5. When **Disabled**, the event tap is detached from the run loop.

### `--screenshot` headless render mode

Used by `make screenshots` and CI to regenerate marketing PNGs from real SwiftUI views:

```bash
Glide --screenshot [--menu <out.png>] [--onboarding <out.png>] [--version x.y.z]
```

- Skips status item, event tap, and normal onboarding flow (`awakeFromNib` early-returns in screenshot mode).
- Renders with SwiftUI **`ImageRenderer` at `scale = 1.0`** (1× pixels). Avoids Retina 2× drift from `NSHostingView` +
  `bitmapImageRepForCachingDisplay`.
- Menu screenshot uses `omitDropShadow: true` on `StatusMenuView` (no card shadow or header icon glow — live menu
  unchanged).
- Output size follows each view's natural layout (dropdown **240×419**, onboarding **430×471**). When dimensions change,
  update `scripts/screenshot-layout.json` **and** matching `aspect-ratio` rules in `site/index.html`.

### UI pattern

The status menu uses a custom **`StatusMenuPanel`** (borderless `NSPanel` at `.popUpMenu` level) instead of `NSPopover`,
with global/local click monitors to dismiss on outside click — mimicking a native menu.

### Persistence

`Preferences` stores settings in `UserDefaults.standard`:

| Key                   | Default       | Purpose                                  |
| --------------------- | ------------- | ---------------------------------------- |
| `ModifierFlags`       | `"CMD,SHIFT"` | Comma-separated `ModifierKey` raw values |
| `UseMouseMove`        | `true`        | Hover-move without click                 |
| `UseRightClickResize` | `true`        | Right-drag resize                        |

---

## Tech Stack & Requirements

| Item                      | Value                                                                                                     |
| ------------------------- | --------------------------------------------------------------------------------------------------------- |
| Language                  | Swift 5.0                                                                                                 |
| UI                        | SwiftUI (menu, onboarding) + AppKit (app shell, event tap)                                                |
| Deployment target         | macOS 13.0 (Ventura)                                                                                      |
| Xcode                     | `LastUpgradeCheck` 2630; SDK notes reference Xcode 26 APIs (e.g. `CGEventMask` bit shift)                 |
| App packages              | **None** — no SwiftPM, CocoaPods, or Carthage in the Glide target                                         |
| Build system              | Xcode project (`Glide.xcodeproj`) + `Makefile` wrappers                                                   |
| Code signing (local)      | **Release:** Developer ID Application, manual, sandbox **off**. **Debug:** ad-hoc (`-`), sandbox **off**. |
| Packaging tools           | Homebrew `create-dmg` (DMG creation)                                                                      |
| Dev tooling (not shipped) | Python 3 + Pillow (`patch-screenshot-version.py`, screenshot dimension verify in `render-screenshots.sh`) |
| Formatting                | [dprint](https://dprint.dev/) — config in `dprint.json`; `make fmt` / `make fmt-check`                    |

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
make fmt            # Format project sources with dprint
make fmt-check      # Check formatting (lists files that need fmt; exits 0)
make format         # Alias for make fmt
make clean          # Remove build/ and DMG artifacts
make install        # Build (Release) and copy to /Applications (prompts if exists)
make dev-package    # Unsigned DMG tagged "dev" for local testing
make screenshots    # Regenerate docs/ + site/ PNGs from VERSION (macOS + Xcode)
make site           # Open site/index.html in browser
```

`make build`, `make build-debug`, `make clean`, and `make test` pipe xcodebuild through indented dim logging (`-quiet`
by default). Use `VERBOSE=true make build` for the full xcodebuild log.

First-time Xcode setup: `xcodebuild -runFirstLaunch`

Build output lives under `build/` (gitignored).

---

## Formatting (dprint)

Project formatting is centralized in **`dprint.json`**. Run from repo root:

```bash
make fmt            # format supported files (per dprint.json)
make fmt-check      # report files that still need formatting
make format         # alias for make fmt
```

`make fmt-check` prints a friendly summary (file count + paths) and suggests `make fmt`. It exits **0** even when files
need formatting — treat the warning output as the signal, not the exit code.

### Plugins and file types

| Plugin         | Extensions              | Examples in this repo                           |
| -------------- | ----------------------- | ----------------------------------------------- |
| Swift (custom) | `**/*.swift`            | `Glide/`, `GlideTests/`                         |
| Markdown       | `**/*.md`               | `README.md`, `RELEASE.md`, `AGENTS.md`          |
| JSON           | `**/*.json`             | `dprint.json`, `scripts/screenshot-layout.json` |
| pretty_yaml    | `**/*.yaml`, `**/*.yml` | `.github/workflows/*.yaml`                      |

**Excluded** (do not add to `includes` without good reason):

- `site/` — hand-built HTML landing page
- `**/Images.xcassets/**` — Xcode asset catalog JSON (noisy diffs)
- `build/`, `DerivedData/`, `secrets/`

**Not formatted:** shell scripts, HTML, TOML (none in repo yet). Add plugins later only if the repo gains those files.

### Markdown rules

When editing `.md` files, use **aligned GFM pipe tables** (delimiter-row pipes align with header/body columns). Blank
lines before and after tables, headings, lists, and fenced code blocks. After editing markdown, run `make fmt` on the
file.

`lineWidth` is **120** for all plugins.

### Agent workflow

- After editing Swift, markdown, JSON, or workflow YAML, run **`make fmt`** on touched files (or the whole repo).
- Before opening a PR, run **`make fmt-check`** and fix anything it lists.
- When changing `dprint.json` (plugins, includes, excludes), run **`make fmt-check`** to confirm nothing breaks.

---

## Screenshots & Marketing Assets

When menu or onboarding UI changes, refresh screenshots and keep layout metadata in sync.

### Pipeline

```bash
make bump-version   # if VERSION changed
make screenshots    # macOS only
```

**What it does** (`scripts/render-screenshots.sh`):

1. Builds Glide with `xcodebuild` (`CODE_SIGNING_ALLOWED=NO`)
2. Runs `Glide --screenshot` to write `docs/drop-down.png` and `docs/onboarding.png` (1× via `ImageRenderer`)
3. Copies PNGs to `site/`
4. **`normalize_screenshot_sizes`** — downscales exact 2× outputs if a Retina fallback occurs
5. Composites `site/menubar.png` from `site/menubar-base.png` + dropdown (Pillow; auto-aligns under the Glide status
   icon at 1× — see `composite_menubar` in `patch-screenshot-version.py`)
6. Verifies all PNG dimensions against `scripts/screenshot-layout.json` (fails on drift)
7. Removes `default.profraw` if an instrumented build wrote one (gitignored)

**Linux/CI without Xcode:** falls back to `scripts/patch-screenshot-version.py` (`--skip-composite` on the fallback
path; patches version text in existing PNGs only).

### Canonical dimensions (`scripts/screenshot-layout.json`)

| Asset             | Size    | Site CSS                                         |
| ----------------- | ------- | ------------------------------------------------ |
| Dropdown          | 240×419 | (inline in composite)                            |
| Onboarding        | 430×471 | `.settings-section--onboarding .screenshot-card` |
| Menubar composite | 687×798 | `.settings-section .screenshot-card`             |

`menubar.card` in the JSON documents the **last composite** placement (auto-detected from `menubar-base.png`);
compositing does not read fixed `x`/`y` for paste position.

If a view layout change alters rendered PNG size: update the JSON, re-run `make screenshots`, and update the matching
`aspect-ratio` in `site/index.html`.

**Manual assets:**

- `site/glide-hero.png` — full-desktop capture (updated by hand when the hero scene changes)
- `site/menubar-source.png` → `python3 scripts/prepare-menubar-base.py` → `site/menubar-base.png` (clean menubar +
  wallpaper capture used as the compositing canvas)

### CI (`.github/workflows/screenshots.yaml`)

| Job          | When                               | Purpose                                                  |
| ------------ | ---------------------------------- | -------------------------------------------------------- |
| `render`     | PR + push to `main` (path filters) | Build, render, verify dimensions (read-only)             |
| `propose-pr` | push to `main` + manual dispatch   | Open a PR with refreshed PNGs (write; never runs on PRs) |

---

## Testing

```bash
make test
```

**What is tested** (`GlideTests/GlideTests.swift`):

- `Preferences` — default modifier flags, round-trip, reset
- `WindowGlide` — singleton and initial state
- `testLaunchOnboardingWithBanner` — launches the built app with onboarding flags (requires prior `make build`; skips if
  app not found)

Prefer extending tests for **pure logic** (preferences parsing, resize-grip math if extracted). Event-tap and AX
integration are hard to unit-test — manual verification on macOS is expected.

---

## Release Process

Full details: [`RELEASE.md`](RELEASE.md). Summary for agents:

### Version sources

| File                     | Role                                                                             |
| ------------------------ | -------------------------------------------------------------------------------- |
| `VERSION`                | Single source of truth for the next release (plain text, e.g. `1.3.0`)           |
| `Glide/Glide-Info.plist` | `CFBundleShortVersionString` + `CFBundleVersion` — synced by `make bump-version` |
| `site/index.html`        | Download URL + `data-vmtrc-version` — synced by `make bump-version`              |

**Always run `make bump-version` after editing `VERSION`.** It reads the plain-text `VERSION` file (does not accept the
version as a make argument). Bumping the plist alone does not update the website download link.

### Standard release (CI — preferred)

1. Set version: `echo "1.2.5" > VERSION && make bump-version`
2. Run `make screenshots` if UI changed; commit PNG updates with the release
3. Commit `VERSION`, `Glide/Glide-Info.plist`, and `site/index.html`
4. Merge to `main` (site deploys to production via **Vercel** automatically)
5. Push tag: `git tag v1.2.5 && git push origin v1.2.5`
6. GitHub Actions (`.github/workflows/release.yaml`) builds, signs, notarizes, creates DMG, zips it, and publishes a
   GitHub Release

**Triggers:** push of `v*` tag, or manual workflow dispatch (uses `VERSION` file).

**Release artifact:** `Glide-{version}.zip` (DMG inside a zip — preserves custom DMG icon through GitHub's upload).

**Download URL pattern** (used by the site download button):

```sh
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

### CI workflows

| Workflow           | Trigger                | Purpose                                    |
| ------------------ | ---------------------- | ------------------------------------------ |
| `release.yaml`     | `v*` tag / dispatch    | Sign, notarize, publish GitHub Release zip |
| `screenshots.yaml` | PR/push (path filters) | Render and validate marketing PNGs         |

### Secrets — do not commit

| Location                | Purpose                                                                                                 |
| ----------------------- | ------------------------------------------------------------------------------------------------------- |
| `secrets/` (gitignored) | Local certs, `.p8` keys, `secrets.env`                                                                  |
| GitHub Actions secrets  | `APPLE_SIGNING_P12`, `APPLE_SIGNING_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_B64` |

Never commit, log, or embed signing credentials in source. The `secrets/` directory is in `.gitignore`.

---

## Landing Site (`site/`)

Static HTML landing page (`site/index.html`) with Tailwind CDN, custom CSS, and Vemetric analytics.

- **Deploy:** merging to `main` deploys `site/` to production (Vercel)
- **Download button:** points at the GitHub release zip (updated by `make bump-version`) — this is the only public
  download path
- **Assets:** screenshots and icons live alongside `index.html` (`site/*.png`)
- **Docs mirror:** `docs/` holds README screenshots; keep marketing copy aligned when UI changes

Preview locally: `make site`

---

## Agent Guidelines

### Do

- Keep changes **minimal and focused** — match existing style in each file
- Use **`make build`** / **`make test`** to verify Swift changes
- Run **`make fmt`** after editing Swift, markdown, JSON, or workflow YAML; **`make fmt-check`** before PRs
- Update **`VERSION` + `make bump-version`** when preparing a release (include `site/index.html`)
- Run **`make screenshots`** after menu/onboarding UI changes; keep `screenshot-layout.json` and site `aspect-ratio` CSS
  in sync
- Preserve the **no-dependency** policy in the Glide app target — Apple frameworks only
- Respect **Accessibility** as a hard requirement; do not add workarounds that bypass user consent
- Use **`make run-onboarding`** to manually test onboarding UI changes
- Follow existing patterns: free-function event tap callback, `WindowGlide.shared` for gesture state,
  `Preferences.shared` for settings
- Frame Glide as **assistive software** in user-facing copy where accessibility purpose matters

### Do not

- Commit files under `secrets/`, `build/`, or `*.dmg`
- Add SwiftPM/CocoaPods dependencies without explicit approval
- Expand scope into full window management (tiling, spaces, rules engines, etc.)
- Add Mac App Store download links or copy implying MAS distribution
- Change signing/notarization flow without updating both `Makefile` and `.github/workflows/release.yaml`
- Run `make release` or push tags unless the user explicitly asks
- Create git commits or PRs unless requested
- Create branches outside `feature/`, `fix/`, or `chore/`

### Common edit locations

| Task                   | Files                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Move/resize behavior   | `AppDelegate.swift`, `WindowGlide.swift`                                                                                                    |
| Menu UI / toggles      | `StatusMenuView.swift`, `AppDelegate.swift` (wiring)                                                                                        |
| Defaults / prefs       | `Preferences.swift`                                                                                                                         |
| Onboarding copy/UI     | `OnboardingView.swift`, `OnboardingWindowController.swift`                                                                                  |
| Screenshot render mode | `AppDelegate.swift` (`--screenshot` extension)                                                                                              |
| Screenshot automation  | `scripts/render-screenshots.sh`, `scripts/screenshot-layout.json`, `scripts/patch-screenshot-version.py`, `scripts/prepare-menubar-base.py` |
| Makefile / logging     | `Makefile`, `scripts/log.bash` (`log_run_xcodebuild`, `VERBOSE=true`)                                                                       |
| Formatting config      | `dprint.json`                                                                                                                               |
| Screenshot CI          | `.github/workflows/screenshots.yaml`                                                                                                        |
| App metadata           | `Glide/Glide-Info.plist`, `VERSION`                                                                                                         |
| Release/version bump   | `VERSION`, `Makefile` (`bump-version`), `site/index.html`                                                                                   |
| CI release             | `.github/workflows/release.yaml`                                                                                                            |
| Marketing page         | `site/index.html`, `site/*.png`                                                                                                             |

### SDK notes

The codebase targets modern Xcode/macOS SDKs. Notable patterns:

- `CGEventMaskBit` removed in Xcode 26 SDK — use `CGEventMask(1) << CGEventMask(type.rawValue)` (see `eventMaskBit` in
  `AppDelegate.swift`)
- Event tap callback parameters are non-optional in newer SDKs

---

## Contributing Workflow

1. Open an issue for bugs or feature ideas (especially before large changes)
2. Fork → branch → pull request
3. Small PRs welcome for early feedback
4. Ensure `make test` passes before requesting review
5. Run `make fmt-check` and `make fmt` as needed so formatting stays consistent

### Branch names

Use **only** these prefixes:

| Prefix     | Use for                                                                  |
| ---------- | ------------------------------------------------------------------------ |
| `feature/` | New functionality or user-facing improvements                            |
| `fix/`     | Bug fixes                                                                |
| `chore/`   | Docs, tooling, refactors, version bumps, CI — no product behavior change |

Format: `{prefix}/{short-kebab-description}` (e.g. `feature/add-agents-md`, `fix/status-menu-dismiss`,
`chore/bump-version`).

Do not use other prefixes (`cursor/`, `dev/`, personal names, etc.).

---

## Quick Reference

```bash
# Daily dev loop
make run-debug

# After editing sources or docs
make fmt && make fmt-check

# After UI changes that affect marketing screenshots
make screenshots

# Before a release PR
echo "X.Y.Z" > VERSION && make bump-version
make test && make build

# Tag release (after merge) — publishes GitHub Release; site download link already bumped
git tag vX.Y.Z && git push origin vX.Y.Z

# Local signed DMG (optional)
make release
```

For release troubleshooting, signing chain setup, and GitHub secret configuration, see [`RELEASE.md`](RELEASE.md) and
[`README.md`](README.md).
