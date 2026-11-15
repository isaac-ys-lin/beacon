import Carbon
import XCTest
@testable import Beacon

final class QuickActionShortcutTests: XCTestCase {
    func testCustomShortcutRoundTripsAndOverridesDefault() {
        let defaults = makeDefaults()
        let custom = BeaconQuickActionShortcut(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | shiftKey),
            keyLabel: "D"
        )

        let preferences = BeaconQuickActionPreferences()
            .settingShortcut(custom, for: .showDashboard)
        preferences.save(to: defaults)
        let restored = BeaconQuickActionPreferences.load(from: defaults)

        XCTAssertEqual(restored.shortcut(for: .showDashboard), custom)
        XCTAssertEqual(restored.shortcut(for: .showDashboard)?.displayText, "⌃⇧D")
        XCTAssertEqual(restored.shortcut(for: .refreshBatteries)?.displayText, "⌥⌘R")
    }

    func testClearedShortcutStaysClearedAfterReload() {
        let defaults = makeDefaults()
        BeaconQuickActionPreferences()
            .settingShortcut(nil, for: .refreshBatteries)
            .save(to: defaults)

        XCTAssertNil(BeaconQuickActionPreferences.load(from: defaults).shortcut(for: .refreshBatteries))
    }

    func testDisplayTextUsesAppleModifierOrder() {
        let shortcut = BeaconQuickActionShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
            keyLabel: "k"
        )
        XCTAssertEqual(shortcut.displayText, "⌃⌥⇧⌘K")
    }

    func testShortcutWithoutCommandControlOrOptionIsRejectedUnlessFunctionKey() {
        XCTAssertFalse(BeaconQuickActionShortcut(
            keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(shiftKey), keyLabel: "A"
        ).isValidGlobalShortcut)
        XCTAssertTrue(BeaconQuickActionShortcut(
            keyCode: UInt32(kVK_F5), modifiers: 0, keyLabel: "F5"
        ).isValidGlobalShortcut)
        XCTAssertTrue(BeaconQuickActionShortcut(
            keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey), keyLabel: "A"
        ).isValidGlobalShortcut)
    }

    func testConflictingActionIsReportedWithinBeacon() {
        let preferences = BeaconQuickActionPreferences()
        let taken = BeaconQuickAction.refreshBatteries.defaultShortcut!

        XCTAssertEqual(preferences.action(using: taken, excluding: .showDashboard), .refreshBatteries)
        XCTAssertNil(preferences.action(using: taken, excluding: .refreshBatteries))
    }

    @MainActor
    func testFailedRegistrationIsReportedPerAction() {
        let controller = BeaconShortcutController(registrar: { _, _, hotKeyID in
            hotKeyID == BeaconQuickAction.refreshBatteries.hotKeyID ? OSStatus(eventHotKeyExistsErr) : noErr
        })

        let failures = controller.registerEnabledShortcuts(preferences: BeaconQuickActionPreferences()) { _ in }

        XCTAssertEqual(failures, [.refreshBatteries])
        XCTAssertEqual(controller.registrationFailures, [.refreshBatteries])
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "QuickActionShortcutTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }
}
