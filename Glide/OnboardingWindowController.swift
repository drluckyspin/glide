import Cocoa
import SwiftUI

final class OnboardingWindowController: NSWindowController {

    private static let minWindowWidth: CGFloat = 430

    convenience init(isTranslocated: Bool, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void, debugText: String?) {
        let hostingController = NSHostingController(
            rootView: OnboardingView(
                isTranslocated: isTranslocated,
                onOpenSettings: onOpenSettings,
                onQuit: onQuit,
                debugText: debugText
            )
        )

        let fittingHeight = hostingController.sizeThatFits(
            in: NSSize(width: Self.minWindowWidth, height: CGFloat.greatestFiniteMagnitude)
        ).height
        let windowHeight = ceil(max(fittingHeight, 480))

        let window = BorderlessKeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.minWindowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.center()

        self.init(window: window)
    }

    func showWindow() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
