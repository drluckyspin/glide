# ![Icon](docs/app-icon.png) Glide

Assistive macOS menu-bar utility for simple, reliable window **move** and **resize** — modifier keys + your mouse.

## Description

**Glide** helps when title bars and resize edges are hard to reach. It stays focused on one job: move and resize windows
with minimal effort. No tiling, no rules engine, no window-manager bloat.

**Defaults (`Cmd + Shift`):**

- **Move (Glide):** hold your keys and **move the mouse** over a window — it follows the cursor. No title bar, no click.
- **Resize:** hold your keys and **right-click** anywhere in a window, then pull. The edge or corner nearest your click
  sets the direction (for example, top-right grows from the top-right corner).

You can turn off hover-move and use left-click drag instead, or change which modifier keys are required, from the menu
bar dropdown.

### Customization

Open the menu-bar icon to adjust settings. **All** selected modifier keys must be held **at the same time** for move or
resize to activate.

![Drop Down](docs/drop-down.png)

- `Disabled` — turns Glide off globally (when disabled, move/resize actions are ignored)
- `Option`, `Command`, `Control`, `Shift` — toggle required modifier keys (all selected keys must be held)
- `Glide` — hover to move without clicking the title bar (tooltip: “Hover to move”)
- `Resize` — right-click to resize (tooltip: “Right-click drag”)
- `Reset to defaults` — restores defaults (`Cmd + Shift`, hover move on, resize on, Glide enabled)
- `Quit` — quits Glide

## Installation

Glide is distributed as a **signed, notarized DMG** via
[GitHub Releases](https://github.com/drluckyspin/glide/releases). The
[landing site](https://github.com/drluckyspin/glide/tree/main/site) download button points at the same release zip.

- Download the latest `Glide-{version}.zip` from the [Releases page](https://github.com/drluckyspin/glide/releases)
- Unzip `Glide-{version}.zip`, then open the extracted DMG and **drag Glide to Applications** (do not run directly from
  the disk image)
- Launch Glide from Applications
- Enable Privacy Settings during onboarding

  ![Onboarding](docs/onboarding.png)

- Click the menu icon for the dropdown to change hot keys

  ![Drop Down](docs/drop-down.png)

## Developing

### Quick start

- Clone the repo, then open the project with `make open` (or open `Glide.xcodeproj` in Xcode)
- First-time Xcode setup: `xcodebuild -runFirstLaunch` (or `make check`, which runs this idempotently)
- **Daily dev:** `make run-debug` — Debug build (ad-hoc signed, no Developer ID cert required)
- **Release-like local build:** `make build` / `make run` / `make install` — Release build (Developer ID signed; cert
  must be in your login keychain)
- Run tests with `make test`
- Clean local build output with `make clean`
- Regenerate README/site screenshots after a version bump with `make screenshots` (macOS only)
- Install your current Release build into `/Applications`: `make install`
- Package an unsigned DMG for local testing: `make dev-package`
- Build a signed + notarized DMG for distribution: `make release` (see notes below)

`make build`, `make clean`, and `make test` pipe xcodebuild output through indented dim logging (`-quiet` by default).
Pass `VERBOSE=true` for the full log, e.g. `VERBOSE=true make build`.

To bump the version before a release: `echo "1.3.2" > VERSION && make bump-version` (reads `VERSION`; does not take the
version as a make argument).

Full details of the [Release Process](RELEASE.md).

#### Releasing locally

`make release` codesigns and notarizes a distributable DMG. It signs with the Developer ID Application identity in your
**login keychain** and notarizes using credentials from `secrets/secrets.env` — it does not create or switch keychains,
so it won't disturb your macOS session.

> **Note:** Your Developer ID Application certificate must be installed in your login keychain. If it isn't,
> `make release` fails with a clear message — import it once by double-clicking `secrets/DevIDCertificates.p12`, then
> retry. Override the identity with `make release SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` if
> needed.

Tagged releases (pushing a `v*` tag) are built and published automatically by GitHub Actions, which signs independently
of this Makefile target.

### Xcode and dependency requirements

- Xcode with macOS SDK support (project `LastUpgradeCheck` is `2630`)
- macOS deployment target is `13.0`
- Swift language version is `5.0`
- Uses Apple frameworks only (`Cocoa`, `SwiftUI`, `XCTest`) and Accessibility APIs
- No third-party package dependencies (no SwiftPM/CocoaPods/Carthage required)
- **Brew tools** (for `make dev-package` / `make release`): `create-dmg` — install with `brew install create-dmg`
- Run `make check` to verify all dependencies (Xcode, brew, create-dmg)
- **Code signing:** Release builds use **Developer ID Application** (manual signing in the Xcode project; sandbox off —
  required for Accessibility). Debug builds are **ad-hoc** (`CODE_SIGN_IDENTITY = -`) so local dev does not need a
  distribution cert. CI release still archives unsigned and re-signs in GitHub Actions (unchanged).

## Roadmap

- Add support for registering to start automatically at startup
- Enable users to select their own color scheme
- ~~Add an About dialog with version~~
- Add "check for updates" functionality

## Contributing

Contributions are welcome and appreciated.

- Open an issue first for bugs or feature ideas (details help).
- For code changes, use the standard fork -> branch -> pull request workflow.
- Small or WIP pull requests are great for early feedback.
