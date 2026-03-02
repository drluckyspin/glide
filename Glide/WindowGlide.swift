import Cocoa

// MARK: - Resize direction enums

/// Horizontal edge or corner involved in a window resize (left, right, or neither).
enum HorizontalResizeDirection {
    case left
    case right
    case none
}

/// Vertical edge or corner involved in a window resize (top, bottom, or neither).
enum VerticalResizeDirection {
    case top
    case bottom
    case none
}

/// Describes which edge or corner of the window is being resized,
/// derived from where the user right-clicked (e.g. top-left, bottom-right).
struct WindowResizeGrip {
    var horizontalDirection: HorizontalResizeDirection = .none
    var verticalDirection: VerticalResizeDirection = .none
}

// MARK: - WindowGlide

/// Shared state for an in-progress move or resize operation.
/// Tracks the target window, its position/size, and the resize grip (which edge is being dragged).
/// Used by the global event tap callback to apply move/resize via the Accessibility API.
final class WindowGlide {

    static let shared = WindowGlide()
    private init() {}

    /// The global event tap (CGEvent tap) used to intercept mouse events for move/resize.
    var globalEventTap: CFMachPort?

    /// Run-loop source that delivers events from `globalEventTap` to the main run loop.
    var eventTapRunLoopSource: CFRunLoopSource?

    /// Which edge or corner of the window is being resized (set on right-click, used during right-drag).
    var currentResizeGrip = WindowResizeGrip()

    /// Number of drag events processed in the current gesture; used for throttling AX updates and to detect active drag.
    var dragEventCount: Int = 0

    /// Last known origin (top-left) of the window being moved or resized.
    var trackedWindowOrigin: CGPoint = .zero

    /// Last known size of the window being resized.
    var trackedWindowSize: CGSize = .zero

    /// The accessibility element for the window currently being moved or resized, if any.
    var trackedWindow: AXUIElement?
}
