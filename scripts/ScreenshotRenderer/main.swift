import AppKit
import SwiftUI

/// Simulates the clipped onboarding layout before the #18 fix (480pt window).
private struct OnboardingClippedSnapshotView: View {
    var body: some View {
        OnboardingView(isTranslocated: false, onOpenSettings: {}, onQuit: {})
            .frame(width: 430, height: 480, alignment: .top)
            .clipped()
    }
}

@main
struct ScreenshotRenderer {
    static func main() {
        guard let config = parseArguments(CommandLine.arguments) else {
            printUsage()
            exit(1)
        }

        let view: AnyView
        switch config.mode {
        case .menu:
            let model = StatusMenuViewModel(
                isDisabled: false,
                onToggleDisabled: { _ in },
                onSetKey: { _, _ in },
                onSetMouseMove: { _ in },
                onSetRightClickResize: { _ in },
                onReset: {}
            )
            view = AnyView(
                StatusMenuView(model: model, onQuit: {}, versionOverride: config.version)
            )
        case .onboarding:
            view = AnyView(
                OnboardingView(isTranslocated: false, onOpenSettings: {}, onQuit: {})
            )
        case .onboardingBefore:
            view = AnyView(OnboardingClippedSnapshotView())
        }

        do {
            try render(view, to: config.outputPath)
            print("Wrote \(config.outputPath)")
        } catch {
            fputs("Failed to render screenshot: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func printUsage() {
        fputs(
            """
            Usage: ScreenshotRenderer [--version <x.y.z>] <output.png> <menu|onboarding|onboarding-before>

            Renders SwiftUI views to PNG for docs/ and site/ screenshots.
            --version defaults to CFBundleShortVersionString from the renderer bundle, then VERSION file.
            """,
            stderr
        )
    }

    private struct Config {
        enum Mode: String {
            case menu
            case onboarding
            case onboardingBefore = "onboarding-before"
        }

        var version: String?
        var outputPath: String
        var mode: Mode
    }

    private static func parseArguments(_ args: [String]) -> Config? {
        var version: String?
        var positional: [String] = []
        var index = 1
        while index < args.count {
            let arg = args[index]
            if arg == "--version" {
                guard index + 1 < args.count else { return nil }
                version = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("--") {
                return nil
            }
            positional.append(arg)
            index += 1
        }
        guard positional.count == 2, let mode = Config.Mode(rawValue: positional[1]) else {
            return nil
        }
        if version == nil {
            version = resolvedVersion()
        }
        return Config(version: version, outputPath: positional[0], mode: mode)
    }

    private static func resolvedVersion() -> String? {
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        let versionURL = URL(fileURLWithPath: "VERSION")
        guard let raw = try? String(contentsOf: versionURL, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func render(_ view: AnyView, to path: String) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()

        let fitSize = hosting.fittingSize
        guard fitSize.width > 0, fitSize.height > 0 else {
            throw RenderError.invalidSize
        }
        hosting.setFrameSize(fitSize)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw RenderError.bitmapFailed
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let image = NSImage(size: fitSize)
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.encodeFailed
        }
        try png.write(to: URL(fileURLWithPath: path))
    }

    private enum RenderError: Error {
        case invalidSize
        case bitmapFailed
        case encodeFailed
    }
}
