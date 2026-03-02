import XCTest
@testable import Glide

final class GlideTests: XCTestCase {

    // MARK: - Preferences: modifier flag parsing

    func testDefaultModifierFlags() {
        // With no stored prefs the default should be Cmd + Shift.
        UserDefaults.standard.removeObject(forKey: "ModifierFlags")
        let flags = Preferences.shared.modifierFlags
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
    }

    func testModifierFlagsRoundTrip() {
        UserDefaults.standard.removeObject(forKey: "ModifierFlags")
        Preferences.shared.setKey(.alt, enabled: true)
        Preferences.shared.setKey(.cmd, enabled: false)
        Preferences.shared.setKey(.ctrl, enabled: false)

        let flags = Preferences.shared.modifierFlags
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertFalse(flags.contains(.maskCommand))
        XCTAssertFalse(flags.contains(.maskControl))

        // Clean up.
        Preferences.shared.resetToDefaults()
    }

    func testEnabledKeysDefaultsSet() {
        UserDefaults.standard.removeObject(forKey: "ModifierFlags")
        let keys = Preferences.shared.enabledKeys
        XCTAssertTrue(keys.contains(.cmd))
        XCTAssertTrue(keys.contains(.shift))
    }

    func testResetToDefaults() {
        Preferences.shared.setKey(.ctrl, enabled: true)
        Preferences.shared.resetToDefaults()
        let keys = Preferences.shared.enabledKeys
        XCTAssertTrue(keys.contains(.cmd))
        XCTAssertTrue(keys.contains(.shift))
        XCTAssertFalse(keys.contains(.ctrl))
    }

    // MARK: - WindowGlide: singleton

    func testWindowGlideSharedIsSingleton() {
        XCTAssertTrue(WindowGlide.shared === WindowGlide.shared)
    }

    func testWindowGlideInitialState() {
        let mr = WindowGlide.shared
        XCTAssertNil(mr.trackedWindow)
        XCTAssertEqual(mr.dragEventCount, 0)
    }
}
