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

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var altMenu: NSMenuItem!
    @IBOutlet weak var cmdMenu: NSMenuItem!
    @IBOutlet weak var ctrlMenu: NSMenuItem!
    @IBOutlet weak var shiftMenu: NSMenuItem!
    @IBOutlet weak var disabledMenu: NSMenuItem!
    @IBOutlet weak var useMouseMoveMenu: NSMenuItem!

    private var statusItem: NSStatusItem!
    private let statusPopover = NSPopover()
    private var statusMenuViewModel: StatusMenuViewModel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyModifierFlags: CGEventFlags = []
    private var onboardingWindowController: OnboardingWindowController?
    private var accessibilityCheckTimer: Timer?
    private var didStartMainFlow = false
    private var isDisabled = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        statusItem.menu = nil
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
            button.target = self
            button.action = #selector(toggleStatusPopover)
        }
        statusMenu.autoenablesItems = false
        statusMenu.item(at: 0)?.isEnabled = false
        configureStatusPopover()
    }

    // MARK: - Event Handling (called from C callback)

    func handleCGEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        if keyModifierFlags.isEmpty {
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
            if moveResize.dragEventCount > 0 { moveResize.dragEventCount = 0 }
            return passthrough
        }

        // Bail if extra modifier keys are also held (e.g. Cmd+Ctrl+Alt should be ignored).
        let allModifiers: CGEventFlags = [.maskShift, .maskCommand, .maskAlphaShift, .maskAlternate, .maskControl]
        let ignoredMask = allModifiers.subtracting(keyModifierFlags)
        if !flags.intersection(ignoredMask).isEmpty {
            return passthrough
        }

        let useMouseMove = useMouseMoveMenu.state == .on

        // ── Initial tracking: find the window under the cursor ────────────────
        if (useMouseMove && type == .mouseMoved && moveResize.dragEventCount == 0)
            || type == .leftMouseDown
            || type == .rightMouseDown {

            let mouseLocation = event.location
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

            switch resizeGrip.horizontalDirection {
            case .right: size.width += deltaX
            case .left:  size.width -= deltaX; pos.x += deltaX
            case .none:  break
            }

            switch resizeGrip.verticalDirection {
            case .top:    size.height += deltaY
            case .bottom: size.height -= deltaY; pos.y += deltaY
            case .none:  break
            }

            moveResize.trackedWindowOrigin = pos
            moveResize.trackedWindowSize = size

            // Only flush every kResizeFilterInterval events.
            if moveResize.dragEventCount % kResizeFilterInterval == 0 {
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

        initModifierMenuItems()
        keyModifierFlags = Preferences.shared.modifierFlags

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
        DispatchQueue.main.async {
            controller.showWindow()
        }
    }

    private func startAccessibilityCheckTimer() {
        accessibilityCheckTimer?.invalidate()
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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        if let tap = moveResize.globalEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func disableEventTap(_ moveResize: WindowGlide) {
        if let tap = moveResize.globalEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = moveResize.eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Menu Setup

    private func initModifierMenuItems() {
        let enabled = Preferences.shared.enabledKeys
        altMenu.state   = enabled.contains(.alt)  ? .on : .off
        cmdMenu.state   = enabled.contains(.cmd)  ? .on : .off
        ctrlMenu.state  = enabled.contains(.ctrl) ? .on : .off
        shiftMenu.state = enabled.contains(.shift) ? .on : .off
        disabledMenu.state   = .off
        useMouseMoveMenu.state = Preferences.shared.useMouseMove ? .on : .off
    }

    private func configureStatusPopover() {
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
            statusMenuViewModel?.syncFromPreferences()
            let anchorRect = NSRect(x: 0, y: button.bounds.height - 1, width: button.bounds.width, height: 1)
            statusPopover.show(relativeTo: anchorRect, of: button, preferredEdge: .maxY)
            nudgePopoverDown()
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
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.statusPopover.performClose(nil)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.statusPopover.performClose(nil)
            return event
        }
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
        if disabled {
            disableEventTap(moveResize)
        } else {
            enableEventTap(moveResize)
        }
    }

    private func resetToDefaults() {
        Preferences.shared.resetToDefaults()
        keyModifierFlags = Preferences.shared.modifierFlags
        isDisabled = false
        let moveResize = WindowGlide.shared
        enableEventTap(moveResize)
    }

    private func setMenusEnabled(_ enabled: Bool) {
        altMenu.isEnabled   = enabled
        cmdMenu.isEnabled   = enabled
        ctrlMenu.isEnabled  = enabled
        shiftMenu.isEnabled = enabled
    }

    // MARK: - IBActions

    @IBAction func modifierToggle(_ sender: NSMenuItem) {
        let newState: NSControl.StateValue = sender.state == .on ? .off : .on
        sender.state = newState
        // Menu item titles ("Alt", "Cmd", "Ctrl", "Shift") uppercase to ModifierKey raw values.
        if let key = ModifierKey(rawValue: sender.title.uppercased()) {
            Preferences.shared.setKey(key, enabled: newState == .on)
            keyModifierFlags = Preferences.shared.modifierFlags
        }
    }

    @IBAction func useMouseMoveToggle(_ sender: NSMenuItem) {
        let newState: NSControl.StateValue = sender.state == .on ? .off : .on
        sender.state = newState
        Preferences.shared.useMouseMove = newState == .on
    }

    @IBAction func resetModifiersToDefaults(_ sender: Any) {
        Preferences.shared.resetToDefaults()
        initModifierMenuItems()
        keyModifierFlags = Preferences.shared.modifierFlags
    }

    @IBAction func toggleDisabled(_ sender: Any) {
        let moveResize = WindowGlide.shared
        if disabledMenu.state == .off {
            disabledMenu.state = .on
            setMenusEnabled(false)
            disableEventTap(moveResize)
        } else {
            disabledMenu.state = .off
            setMenusEnabled(true)
            enableEventTap(moveResize)
        }
    }
}
