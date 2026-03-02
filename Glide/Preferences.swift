import Foundation
import CoreGraphics

private let modifierFlagsKey = "ModifierFlags"
private let useMouseMoveKey = "UseMouseMove"

enum ModifierKey: String, CaseIterable {
    case ctrl  = "CTRL"
    case shift = "SHIFT"
    case caps  = "CAPS"
    case alt   = "ALT"
    case cmd   = "CMD"

    var eventFlag: CGEventFlags {
        switch self {
        case .ctrl:  return .maskControl
        case .shift: return .maskShift
        case .caps:  return .maskAlphaShift
        case .alt:   return .maskAlternate
        case .cmd:   return .maskCommand
        }
    }
}

final class Preferences {
    static let shared = Preferences()
    private init() {
        registerDefaultsIfNeeded()
    }

    private var defaults: UserDefaults { .standard }

    var modifierFlags: CGEventFlags {
        flags(from: defaults.string(forKey: modifierFlagsKey) ?? "CMD,SHIFT")
    }

    var useMouseMove: Bool {
        get { defaults.bool(forKey: useMouseMoveKey) }
        set { defaults.set(newValue, forKey: useMouseMoveKey) }
    }

    var enabledKeys: Set<ModifierKey> {
        keySet(from: defaults.string(forKey: modifierFlagsKey) ?? "CMD,SHIFT")
    }

    func setKey(_ key: ModifierKey, enabled: Bool) {
        var current = enabledKeys
        if enabled {
            current.insert(key)
        } else {
            current.remove(key)
        }
        let str = current.map(\.rawValue).joined(separator: ",")
        defaults.set(str, forKey: modifierFlagsKey)
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: modifierFlagsKey)
        defaults.removeObject(forKey: useMouseMoveKey)
    }

    // MARK: - Private

    private func keySet(from str: String) -> Set<ModifierKey> {
        let normalized = str.uppercased().replacingOccurrences(of: " ", with: "")
        return Set(normalized.split(separator: ",").compactMap { ModifierKey(rawValue: String($0)) })
    }

    private func flags(from str: String) -> CGEventFlags {
        keySet(from: str).reduce(into: CGEventFlags()) { $0.insert($1.eventFlag) }
    }

    private func registerDefaultsIfNeeded() {
        defaults.register(defaults: [
            modifierFlagsKey: "CMD,SHIFT",
            useMouseMoveKey: true
        ])
    }
}
