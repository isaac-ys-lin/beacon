import XCTest
@testable import Beacon

extension DeviceListPresentationTests {
    func testSetupDistinguishesEmptyFailureAndPermissionWithoutHidingOtherDevices() {
        func diagnostics(_ status: BatteryReadStatus, provider: BatteryProvider = .coreBluetoothBatteryService) -> BatteryRefreshDiagnostics {
            BatteryRefreshDiagnostics(attempts: [BatteryProviderAttempt(
                provider: provider, status: status, candidateCount: 0, message: "fixture", attemptedAt: Date()
            )])
        }
        XCTAssertEqual(DeviceSetupRecoveryState.resolve(visibleCount: 0, isRefreshing: false, diagnostics: .init()), .checking)
        XCTAssertEqual(DeviceSetupRecoveryState.resolve(visibleCount: 0, isRefreshing: false, diagnostics: diagnostics(.noReport)), .empty)
        XCTAssertEqual(DeviceSetupRecoveryState.resolve(visibleCount: 0, isRefreshing: false, diagnostics: diagnostics(.timedOut)), .failed)
        XCTAssertEqual(DeviceSetupRecoveryState.resolve(visibleCount: 1, isRefreshing: false, diagnostics: diagnostics(.unauthorized)), .permission)
        XCTAssertEqual(DeviceSetupRecoveryState.resolve(visibleCount: 1, isRefreshing: false, diagnostics: diagnostics(.reported)), .ready)
        // An iPhone trust problem must not be described as a Bluetooth privacy denial.
        XCTAssertNotEqual(DeviceSetupRecoveryState.resolve(visibleCount: 0, isRefreshing: false, diagnostics: diagnostics(.unauthorized, provider: .ideviceInfo)), .permission)
    }

    func testSetupIntroductionPreservesExistingPreferencesAndOnlyAppearsOnce() throws {
        let suite = "Beacon.SetupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(BeaconSetupIntroduction.shouldPresent(defaults: defaults))
        defaults.set(true, forKey: BeaconSetupIntroduction.presentedKey)
        XCTAssertFalse(BeaconSetupIntroduction.shouldPresent(defaults: defaults))
        defaults.removeObject(forKey: BeaconSetupIntroduction.presentedKey)
        defaults.set(["refreshBatteries"], forKey: "Beacon.quickActions.enabledActionIDs")
        let before = defaults.persistentDomain(forName: suite)
        XCTAssertFalse(BeaconSetupIntroduction.shouldPresent(defaults: defaults))
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, before as NSDictionary?)
    }
}
