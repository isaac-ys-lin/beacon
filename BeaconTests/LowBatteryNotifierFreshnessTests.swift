import XCTest
@testable import Beacon

final class LowBatteryNotifierFreshnessTests: XCTestCase {
    func testStaleRecoveryDoesNotResetLowBatteryLatch() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let low = snapshot(percent: 10)
        let recovered = snapshot(percent: 80)

        XCTAssertEqual(
            LowBatteryNotifier.pendingAlertEvents(
                for: [DecoratedBatterySnapshot(snapshot: low, freshness: .fresh)],
                defaults: defaults
            ).map(\.kind),
            [.lowBattery]
        )
        XCTAssertTrue(
            LowBatteryNotifier.pendingAlertEvents(
                for: [DecoratedBatterySnapshot(snapshot: recovered, freshness: .stale)],
                defaults: defaults
            ).isEmpty
        )
        XCTAssertTrue(
            LowBatteryNotifier.pendingAlertEvents(
                for: [DecoratedBatterySnapshot(snapshot: low, freshness: .fresh)],
                defaults: defaults
            ).isEmpty
        )

        _ = LowBatteryNotifier.pendingAlertEvents(
            for: [DecoratedBatterySnapshot(snapshot: recovered, freshness: .fresh)],
            defaults: defaults
        )
        XCTAssertEqual(
            LowBatteryNotifier.pendingAlertEvents(
                for: [DecoratedBatterySnapshot(snapshot: low, freshness: .fresh)],
                defaults: defaults
            ).map(\.kind),
            [.lowBattery]
        )
    }

    func testExpiredChargedSnapshotDoesNotCreateNameAlias() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        LowBatteryNotifier.setChargedAlertEnabled(true, forDeviceID: "old-id", defaults: defaults)
        let charged = snapshot(deviceID: "old-id", displayName: "Studio Headphones", percent: 100, chargeState: .full)

        XCTAssertTrue(
            LowBatteryNotifier.pendingAlertEvents(
                for: [DecoratedBatterySnapshot(snapshot: charged, freshness: .expired)],
                defaults: defaults
            ).isEmpty
        )
        XCTAssertFalse(
            LowBatteryNotifier.isChargedAlertEnabled(
                forDeviceID: "new-id",
                displayName: "Studio Headphones",
                defaults: defaults
            )
        )
    }

    func testDisconnectedFreshSnapshotDoesNotNotify() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let disconnected = snapshot(percent: 10, connectionState: .disconnected)

        XCTAssertTrue(
            LowBatteryNotifier.pendingAlertEvents(
                for: [DecoratedBatterySnapshot(snapshot: disconnected, freshness: .fresh)],
                defaults: defaults
            ).isEmpty
        )
    }

    private func snapshot(
        deviceID: String = "keyboard",
        displayName: String = "Magic Keyboard",
        percent: Int,
        chargeState: ChargeState = .unplugged,
        connectionState: ConnectionState = .connected
    ) -> BatterySnapshot {
        BatterySnapshot(
            deviceID: deviceID,
            displayName: displayName,
            kind: .keyboard,
            percent: percent,
            chargeState: chargeState,
            connectionState: connectionState,
            source: .ioRegistry,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "LowBatteryNotifierFreshnessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(20, forKey: LowBatteryNotifier.thresholdDefaultsKey)
        return defaults
    }

    private func clear(_ defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }
}
