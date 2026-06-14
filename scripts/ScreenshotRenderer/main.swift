import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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
        let args = CommandLine.arguments
        guard args.count > 1 else {
            printUsage()
            exit(1)
        }

        if args[1] == "composite" {
            runComposite(args: args)
            return
        }

        runRender(args: args)
    }

    private static func runComposite(args: [String]) {
        guard args.count == 7 else {
            printUsage()
            exit(1)
        }
        let basePath = args[2]
        let overlayPath = args[3]
        guard let x = Int(args[4]), let y = Int(args[5]) else {
            fputs("composite x and y must be integers\n", stderr)
            exit(1)
        }
        let outputPath = args[6]

        do {
            try composite(base: basePath, overlay: overlayPath, x: x, y: y, to: outputPath)
            print("Wrote \(outputPath)")
        } catch {
            fputs("Failed to composite images: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runRender(args: [String]) {
        guard let config = parseRenderArguments(args) else {
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
            Usage:
              ScreenshotRenderer [--version <x.y.z>] <output.png> <menu|onboarding|onboarding-before>
              ScreenshotRenderer composite <base.png> <overlay.png> <x> <y> <output.png>

            Renders SwiftUI views to PNG for docs/ and site/ screenshots.
            composite pastes overlay onto base at top-left (x, y) in PNG coordinates.
            --version defaults to the VERSION file in the repo root (then bundle version).
            """,
            stderr
        )
    }

    private struct RenderConfig {
        enum Mode: String {
            case menu
            case onboarding
            case onboardingBefore = "onboarding-before"
        }

        var version: String?
        var outputPath: String
        var mode: Mode
    }

    private static func parseRenderArguments(_ args: [String]) -> RenderConfig? {
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
        guard positional.count == 2, let mode = RenderConfig.Mode(rawValue: positional[1]) else {
            return nil
        }
        if version == nil {
            version = resolvedVersion()
        }
        return RenderConfig(version: version, outputPath: positional[0], mode: mode)
    }

    private static func resolvedVersion() -> String? {
        if let versionFromFile = readVersionFile() {
            return versionFromFile
        }
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        return nil
    }

    private static func readVersionFile() -> String? {
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

    private static func composite(base basePath: String, overlay overlayPath: String, x: Int, y: Int, to outputPath: String) throws {
        let baseURL = URL(fileURLWithPath: basePath)
        let overlayURL = URL(fileURLWithPath: overlayPath)

        guard let baseSource = CGImageSourceCreateWithURL(baseURL as CFURL, nil),
              let baseImage = CGImageSourceCreateImageAtIndex(baseSource, 0, nil) else {
            throw CompositeError.loadFailed(basePath)
        }
        guard let overlaySource = CGImageSourceCreateWithURL(overlayURL as CFURL, nil),
              let overlayImage = CGImageSourceCreateImageAtIndex(overlaySource, 0, nil) else {
            throw CompositeError.loadFailed(overlayPath)
        }

        let width = baseImage.width
        let height = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw CompositeError.contextFailed
        }

        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let overlayHeight = overlayImage.height
        let destY = height - y - overlayHeight
        let destRect = CGRect(x: x, y: destY, width: overlayImage.width, height: overlayHeight)

        if let overlayBitmap = NSBitmapImageRep(cgImage: overlayImage),
           let cardColor = overlayBitmap.colorAt(x: 8, y: 32) {
            context.setFillColor(
                red: cardColor.redComponent,
                green: cardColor.greenComponent,
                blue: cardColor.blueComponent,
                alpha: 1
            )
            context.fill(destRect)
        }

        context.draw(overlayImage, in: destRect)

        guard let result = context.makeImage() else {
            throw CompositeError.encodeFailed
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CompositeError.encodeFailed
        }
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CompositeError.encodeFailed
        }
    }

    private enum RenderError: Error {
        case invalidSize
        case bitmapFailed
        case encodeFailed
    }

    private enum CompositeError: Error, CustomStringConvertible {
        case loadFailed(String)
        case contextFailed
        case encodeFailed

        var description: String {
            switch self {
            case .loadFailed(let path):
                return "could not load image at \(path)"
            case .contextFailed:
                return "could not create graphics context"
            case .encodeFailed:
                return "could not encode PNG"
            }
        }
    }
}
