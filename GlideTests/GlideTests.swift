import AppKit
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

    // MARK: - Onboarding: launch with banner for UI testing

    /// Launches Glide with -force-onboarding -translocation so the onboarding dialog and
    /// translocation banner are visible. Use `make run-onboarding` for the same effect.
    func testLaunchOnboardingWithBanner() throws {
        let testBundlePath = Bundle(for: type(of: self)).bundlePath
        let appPath: String
        if testBundlePath.contains("PlugIns") {
            // Test runs inside app bundle: .../Glide.app/Contents/PlugIns/GlideTests.xctest
            let plugInsDir = (testBundlePath as NSString).deletingLastPathComponent
            let contentsDir = (plugInsDir as NSString).deletingLastPathComponent
            appPath = (contentsDir as NSString).deletingLastPathComponent
        } else {
            // Test runs as sibling: .../Build/Products/Debug/GlideTests.xctest
            let buildDir = (testBundlePath as NSString).deletingLastPathComponent
            appPath = (buildDir as NSString).appendingPathComponent("Glide.app")
        }
        let appURL = URL(fileURLWithPath: appPath)

        guard FileManager.default.fileExists(atPath: appPath) else {
            throw XCTSkip("Glide.app not found at \(appPath). Run 'make build' first.")
        }

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["-force-onboarding", "-translocation"]
        config.activates = true

        let exp = expectation(description: "App launched")
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            XCTAssertNil(error, "Failed to launch: \(String(describing: error))")
            XCTAssertNotNil(app)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }
}
