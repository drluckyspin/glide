import Cocoa
import SwiftUI

private let kMoveFilterInterval   = 2
private let kResizeFilterInterval = 4

// CGEventMaskBit was removed in Xcode 26 SDK. Replace with bit shift.
private func eventMaskBit(_ type: CGEventType) -> CGEventMask {
    CGEventMask(1) << CGEventMask(type.rawValue)
}

// MARK: - Event Tap Callback
// Must be a free function — Swift closures that capture context cannot be
// used as C function pointers. `refcon` carries an unretained AppDelegate.
// Note: In Xcode 26 SDK, proxy and event are non-optional.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    return delegate.handleCGEvent(type: type, event: event)
}

// MARK: -

@objc(AppDelegate) @objcMembers
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    // Popover-based replacement for the legacy NSMenu UI.
    private let statusPopover = NSPopover()
    private var statusMenuViewModel: StatusMenuViewModel?
    // Click monitors are installed only while the popover is visible
    // so outside clicks close it like a native menu.
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    // Runtime-resolved shortcut mask built from user preferences.
    private var keyModifierFlags: CGEventFlags = []
    private var onboardingWindowController: OnboardingWindowController?
    private var accessibilityCheckTimer: Timer?
    // Protects event-tap setup from accidental double-initialization.
    private var didStartMainFlow = false
    // Cached disabled state for the SwiftUI popover model.
    private var isDisabled = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // If AX permission is already granted, we can immediately start handling events.
        // Otherwise, route through onboarding and poll until permission appears.
        if hasAccessibilityPermission() {
            startMainFlow()
        } else {
            showOnboarding()
            startAccessibilityCheckTimer()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // We use an NSPopover for richer UI, so we intentionally do not attach NSMenu here.
        statusItem.menu = nil
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
            button.target = self
            button.action = #selector(toggleStatusPopover)
        }
        configureStatusPopover()
    }

    // MARK: - Event Handling (called from C callback)

    func handleCGEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // `passthrough` means "do not consume this event".
        let passthrough = Unmanaged.passUnretained(event)

        if keyModifierFlags.isEmpty {
            // Defensive fallback: if preferences resolve to no modifiers, disable behavior.
            return passthrough
        }

        let moveResize = WindowGlide.shared

        // Re-enable the tap if macOS disabled it (e.g. slow window operation).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = moveResize.globalEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("Glide: Re-enabling event tap...")
            }
            return passthrough
        }

        // Bail if the required modifier keys aren't all held down.
        let flags = event.flags
        guard flags.contains(keyModifierFlags) else {
            // User released required modifiers mid-drag; stop tracking gesture state.
            if moveResize.dragEventCount > 0 { moveResize.dragEventCount = 0 }
            return passthrough
        }

        // Bail if extra modifier keys are also held (e.g. Cmd+Ctrl+Alt should be ignored).
        let allModifiers: CGEventFlags = [.maskShift, .maskCommand, .maskAlphaShift, .maskAlternate, .maskControl]
        let ignoredMask = allModifiers.subtracting(keyModifierFlags)
        if !flags.intersection(ignoredMask).isEmpty {
            return passthrough
        }

        let useMouseMove = Preferences.shared.useMouseMove

        // ── Initial tracking: find the window under the cursor ────────────────
        if (useMouseMove && type == .mouseMoved && moveResize.dragEventCount == 0)
            || type == .leftMouseDown
            || type == .rightMouseDown {

            let mouseLocation = event.location
            // `1` indicates an active gesture has started; increments on each drag event.
            moveResize.dragEventCount = 1

            let systemWide = AXUIElementCreateSystemWide()
            var clickedWindow: AXUIElement?
            var element: AXUIElement?

            if AXUIElementCopyElementAtPosition(
                systemWide,
                Float(mouseLocation.x),
                Float(mouseLocation.y),
                &element
            ) == .success, let element {
                // Check if the element itself is a window.
                var roleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    element,
                    NSAccessibility.Attribute.role.rawValue as CFString,
                    &roleRef
                ) == .success,
                   (roleRef as? String) == NSAccessibility.Role.window.rawValue {
                    clickedWindow = element
                }
                // Otherwise get the window that contains this element.
                var windowRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    element,
                    NSAccessibility.Attribute.window.rawValue as CFString,
                    &windowRef
                ) == .success, let windowRef {
                    clickedWindow = (windowRef as! AXUIElement)
                }
            }

            if let win = clickedWindow {
                var posRef: CFTypeRef?
                var position = CGPoint.zero
                if AXUIElementCopyAttributeValue(
                    win,
                    NSAccessibility.Attribute.position.rawValue as CFString,
                    &posRef
                ) == .success, let posRef {
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
                }
                // Snap to integer coordinates (matches original behaviour).
                position.x = CGFloat(Int(position.x))
                position.y = CGFloat(Int(position.y))
                moveResize.trackedWindowOrigin = position
                moveResize.trackedWindow = win
            } else {
                // No AX window at cursor position (desktop/menu bar/etc.).
                moveResize.trackedWindow = nil
            }
        }

        // ── Move window ────────────────────────────────────────────────────────
        if (useMouseMove && type == .mouseMoved && moveResize.dragEventCount > 0)
            || (type == .leftMouseDragged && moveResize.dragEventCount > 0) {

            moveResize.dragEventCount += 1
            guard let win = moveResize.trackedWindow else { return nil }

            let deltaX = event.getDoubleValueField(.mouseEventDeltaX)
            let deltaY = event.getDoubleValueField(.mouseEventDeltaY)
            var newPos = moveResize.trackedWindowOrigin
            newPos.x += deltaX
            newPos.y += deltaY
            moveResize.trackedWindowOrigin = newPos

            // Only flush every kMoveFilterInterval events — AX calls are expensive.
            if moveResize.dragEventCount % kMoveFilterInterval == 0 {
                var pt = newPos
                if let axPos = AXValueCreate(.cgPoint, &pt) {
                    AXUIElementSetAttributeValue(
                        win,
                        NSAccessibility.Attribute.position.rawValue as CFString,
                        axPos
                    )
                }
            }
        }

        // ── Determine resize direction on right-click ─────────────────────────
        if type == .rightMouseDown {
            moveResize.dragEventCount = 1
            guard let win = moveResize.trackedWindow else { return nil }

            let clickPoint = event.location
            let origin = moveResize.trackedWindowOrigin
            let localX = clickPoint.x - origin.x
            let localY = clickPoint.y - origin.y

            var sizeRef: CFTypeRef?
            var windowSize = CGSize.zero
            guard AXUIElementCopyAttributeValue(
                win,
                NSAccessibility.Attribute.size.rawValue as CFString,
                &sizeRef
            ) == .success, let sizeRef else {
                NSLog("Glide: ERROR — could not get window size")
                return nil
            }
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &windowSize)

            var resizeGrip = WindowResizeGrip()
            // Divide the window into a 3x3 grid and infer edge/corner direction
            // from the right-click location.
            if localX < windowSize.width / 3 {
                resizeGrip.horizontalDirection = .left
            } else if localX > 2 * windowSize.width / 3 {
                resizeGrip.horizontalDirection = .right
            } else {
                resizeGrip.horizontalDirection = .none
            }
            if localY < windowSize.height / 3 {
                resizeGrip.verticalDirection = .bottom
            } else if localY > 2 * windowSize.height / 3 {
                resizeGrip.verticalDirection = .top
            } else {
                resizeGrip.verticalDirection = .none
            }

            moveResize.trackedWindowSize = windowSize
            moveResize.currentResizeGrip = resizeGrip
        }

        // ── Resize window on right-drag ────────────────────────────────────────
        if type == .rightMouseDragged && moveResize.dragEventCount > 0 {
            moveResize.dragEventCount += 1
            guard let win = moveResize.trackedWindow else { return nil }

            let resizeGrip = moveResize.currentResizeGrip
            let deltaX = event.getDoubleValueField(.mouseEventDeltaX)
            let deltaY = event.getDoubleValueField(.mouseEventDeltaY)

            var pos  = moveResize.trackedWindowOrigin
            var size = moveResize.trackedWindowSize

            // Horizontal resize math.
            switch resizeGrip.horizontalDirection {
            case .right: size.width += deltaX
            case .left:  size.width -= deltaX; pos.x += deltaX
            case .none:  break
            }

            // Vertical resize math.
            switch resizeGrip.verticalDirection {
            case .top:    size.height += deltaY
            case .bottom: size.height -= deltaY; pos.y += deltaY
            case .none:  break
            }

            moveResize.trackedWindowOrigin = pos
            moveResize.trackedWindowSize = size

            // Only flush every kResizeFilterInterval events.
            if moveResize.dragEventCount % kResizeFilterInterval == 0 {
                // If resizing from left/bottom edges, update position first so the
                // anchored edge visually stays under the cursor.
                if resizeGrip.horizontalDirection == .left || resizeGrip.verticalDirection == .bottom {
                    var p = pos
                    if let axPos = AXValueCreate(.cgPoint, &p) {
                        AXUIElementSetAttributeValue(
                            win,
                            NSAccessibility.Attribute.position.rawValue as CFString,
                            axPos
                        )
                    }
                }
                var s = size
                if let axSize = AXValueCreate(.cgSize, &s) {
                    AXUIElementSetAttributeValue(
                        win,
                        NSAccessibility.Attribute.size.rawValue as CFString,
                        axSize
                    )
                }
            }
        }

        // ── Stop tracking on mouse-up ──────────────────────────────────────────
        if type == .leftMouseUp || type == .rightMouseUp {
            moveResize.dragEventCount = 0
        }

        // We handled this event — don't pass it downstream.
        return nil
    }

    // MARK: - Event Tap Lifecycle

    private func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func startMainFlow() {
        guard !didStartMainFlow else { return }
        didStartMainFlow = true

        // Initialize UI from persisted prefs, then compute runtime mask.
        keyModifierFlags = Preferences.shared.modifierFlags

        // Mouse events we intercept globally to implement move/resize gestures.
        let eventMask: CGEventMask =
            eventMaskBit(.leftMouseDown)    |
            eventMaskBit(.leftMouseDragged) |
            eventMaskBit(.rightMouseDown)   |
            eventMaskBit(.rightMouseDragged) |
            eventMaskBit(.leftMouseUp)      |
            eventMaskBit(.mouseMoved)       |
            eventMaskBit(.rightMouseUp)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Glide: Couldn't create event tap!")
            exit(1)
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let moveResize = WindowGlide.shared
        moveResize.globalEventTap = tap
        moveResize.eventTapRunLoopSource = source
        enableEventTap(moveResize)
    }

    private func showOnboarding() {
        // let debugText = "AX trusted: \(hasAccessibilityPermission())\nBundle: \(Bundle.main.bundlePath)"
        let controller = OnboardingWindowController(
            onOpenSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            debugText: nil
        )
        onboardingWindowController = controller
        // Ensure onboarding opens after app startup settles.
        DispatchQueue.main.async {
            controller.showWindow()
        }
    }

    private func startAccessibilityCheckTimer() {
        accessibilityCheckTimer?.invalidate()
        // Poll because AX permission changes are driven by System Settings
        // and there is no direct callback for this app to observe.
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.hasAccessibilityPermission() else { return }
            self.accessibilityCheckTimer?.invalidate()
            self.accessibilityCheckTimer = nil
            self.onboardingWindowController?.close()
            self.onboardingWindowController = nil
            self.startMainFlow()
        }
    }

    private func enableEventTap(_ moveResize: WindowGlide) {
        guard let source = moveResize.eventTapRunLoopSource else { return }
        // Attach source to main run loop and ensure tap is enabled.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        if let tap = moveResize.globalEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func disableEventTap(_ moveResize: WindowGlide) {
        // Disable first, then detach source from run loop.
        if let tap = moveResize.globalEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = moveResize.eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Menu Setup

    private func configureStatusPopover() {
        // ViewModel bridges SwiftUI controls to existing AppDelegate behaviors.
        let viewModel = StatusMenuViewModel(
            isDisabled: isDisabled,
            onToggleDisabled: { [weak self] disabled in
                self?.setDisabled(disabled)
            },
            onSetKey: { [weak self] key, enabled in
                self?.setModifierKey(key, enabled: enabled)
            },
            onSetMouseMove: { [weak self] enabled in
                self?.setUseMouseMove(enabled)
            },
            onReset: { [weak self] in
                self?.resetToDefaults()
            }
        )
        statusMenuViewModel = viewModel
        let hostingController = NSHostingController(
            rootView: StatusMenuView(
                model: viewModel,
                onQuit: { NSApp.terminate(nil) }
            )
        )
        statusPopover.contentViewController = hostingController
        statusPopover.contentSize = NSSize(width: 220, height: 320)
        statusPopover.behavior = .transient
        statusPopover.animates = true
    }

    @objc private func toggleStatusPopover() {
        guard let button = statusItem.button else { return }
        if statusPopover.isShown {
            statusPopover.performClose(nil)
            removeClickMonitors()
        } else {
            // Refresh UI state from persisted prefs each time before showing.
            statusMenuViewModel?.syncFromPreferences()
            // Anchor just below the status-bar icon.
            let anchorRect = NSRect(x: 0, y: button.bounds.height - 1, width: button.bounds.width, height: 1)
            statusPopover.show(relativeTo: anchorRect, of: button, preferredEdge: .maxY)
            // Defer window adjustment to avoid layout recursion warnings.
            DispatchQueue.main.async { [weak self] in
                self?.nudgePopoverDown()
            }
            installClickMonitors()
        }
    }

    private func nudgePopoverDown() {
        guard let window = statusPopover.contentViewController?.view.window else { return }
        var frame = window.frame
        frame.origin.y -= 30
        window.setFrame(frame, display: false)
    }

    private func installClickMonitors() {
        removeClickMonitors()
        // Global monitor catches clicks outside app; local monitor catches clicks in-app.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            if self.isClickInsidePopover(event: event) { return }
            self.statusPopover.performClose(nil)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.isClickInsidePopover(event: event) { return event }
            self.statusPopover.performClose(nil)
            return event
        }
    }

    private func isClickInsidePopover(event: NSEvent) -> Bool {
        guard let window = statusPopover.contentViewController?.view.window else { return false }
        if event.window === window {
            return window.contentView?.bounds.contains(event.locationInWindow) ?? false
        }
        let screenPoint: NSPoint
        if let eventWindow = event.window {
            let rect = eventWindow.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero))
            screenPoint = rect.origin
        } else {
            screenPoint = event.locationInWindow
        }
        return window.frame.contains(screenPoint)
    }

    private func removeClickMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    private func setModifierKey(_ key: ModifierKey, enabled: Bool) {
        Preferences.shared.setKey(key, enabled: enabled)
        keyModifierFlags = Preferences.shared.modifierFlags
    }

    private func setUseMouseMove(_ enabled: Bool) {
        Preferences.shared.useMouseMove = enabled
    }

    private func setDisabled(_ disabled: Bool) {
        isDisabled = disabled
        let moveResize = WindowGlide.shared
        // Keep event-tap lifecycle tied to disabled state.
        if disabled {
            disableEventTap(moveResize)
        } else {
            enableEventTap(moveResize)
        }
    }

    private func resetToDefaults() {
        Preferences.shared.resetToDefaults()
        keyModifierFlags = Preferences.shared.modifierFlags
        // Reset UI + behavior state to an enabled baseline.
        isDisabled = false
        let moveResize = WindowGlide.shared
        enableEventTap(moveResize)
    }

    // MARK: - IBActions (legacy NSMenu removed)
}
