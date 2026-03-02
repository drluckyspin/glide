import Cocoa
import SwiftUI

final class OnboardingWindowController: NSWindowController {

    convenience init(onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void, debugText: String?) {
        let hostingController = NSHostingController(
            rootView: OnboardingView(
                onOpenSettings: onOpenSettings,
                onQuit: onQuit,
                debugText: debugText
            )
        )

        let window = BorderlessKeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 22
        window.contentView?.layer?.masksToBounds = true
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
