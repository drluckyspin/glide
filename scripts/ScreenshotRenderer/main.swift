import AppKit
import SwiftUI

/// Static onboarding layout for PR screenshots (avoids @State / xcodebuild).
private struct OnboardingSnapshotView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.05, blue: 0.10),
                    Color(red: 0.18, green: 0.10, blue: 0.28),
                    Color(red: 0.07, green: 0.06, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                Spacer(minLength: 18)
                Image(systemName: "app.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 1.0))
                    .padding(.bottom, 14)
                Text("Welcome to Glide")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)
                Text("Move and resize windows effortlessly with your mouse.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)
                Spacer()
                VStack(spacing: 10) {
                    Text("Open System Settings")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 123 / 255, green: 109 / 255, blue: 143 / 255))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Quit")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 123 / 255, green: 109 / 255, blue: 143 / 255))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
            }
            .padding(18)
        }
        .frame(width: 430, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

/// Simulates the clipped onboarding layout before the #18 fix (480pt window).
private struct OnboardingClippedSnapshotView: View {
    var body: some View {
        OnboardingSnapshotView()
            .frame(width: 430, height: 480, alignment: .top)
            .clipped()
    }
}

@main
struct ScreenshotRenderer {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            fputs("Usage: ScreenshotRenderer <output.png> <menu|onboarding>\n", stderr)
            exit(1)
        }
        let path = args[1]
        let mode = args[2]

        let view: AnyView
        let size: NSSize
        switch mode {
        case "menu":
            let model = StatusMenuViewModel(
                isDisabled: false,
                onToggleDisabled: { _ in },
                onSetKey: { _, _ in },
                onSetMouseMove: { _ in },
                onReset: {}
            )
            view = AnyView(StatusMenuView(model: model, onQuit: {}))
            size = NSSize(width: 232, height: 380)
        case "onboarding":
            view = AnyView(OnboardingSnapshotView())
            size = NSSize(width: 430, height: 520)
        case "onboarding-before":
            view = AnyView(OnboardingClippedSnapshotView())
            size = NSSize(width: 430, height: 480)
        default:
            fputs("Unknown mode: \(mode)\n", stderr)
            exit(1)
        }

        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(origin: .zero, size: size)
        hosting.view.layoutSubtreeIfNeeded()

        guard let rep = hosting.view.bitmapImageRepForCachingDisplay(in: hosting.view.bounds) else {
            fputs("Failed to create bitmap rep\n", stderr)
            exit(1)
        }
        hosting.view.cacheDisplay(in: hosting.view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("Failed to encode PNG\n", stderr)
            exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }
}
