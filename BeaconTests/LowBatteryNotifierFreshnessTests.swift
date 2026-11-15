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

    func testFailedSystemNotificationDoesNotRepeatAlertOnEveryPoll() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let low = DecoratedBatterySnapshot(snapshot: snapshot(percent: 10), freshness: .fresh)
        let failingPost: LowBatteryNotifier.NotificationPoster = { _, completion in
            completion("Notifications are not allowed")
        }

        let first = LowBatteryNotifier.notifyIfNeeded(for: [low], defaults: defaults, post: failingPost)
        let second = LowBatteryNotifier.notifyIfNeeded(for: [low], defaults: defaults, post: failingPost)

        XCTAssertEqual(first.map(\.kind), [.lowBattery])
        XCTAssertTrue(second.isEmpty, "A HUD-surfaced alert must latch even when the system notification fails")
    }

    func testFailedNotificationIsRetriedWhenTheHUDWillNotShowIt() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set(false, forKey: BatteryHUDPreferences.showActionHUDKey)
        let low = DecoratedBatterySnapshot(snapshot: snapshot(percent: 10), freshness: .fresh)
        let failingPost: LowBatteryNotifier.NotificationPoster = { _, completion in completion("denied") }
        let succeedingPost: LowBatteryNotifier.NotificationPoster = { _, completion in completion(nil) }

        XCTAssertEqual(LowBatteryNotifier.notifyIfNeeded(for: [low], defaults: defaults, post: failingPost).count, 1)
        XCTAssertEqual(
            LowBatteryNotifier.notifyIfNeeded(for: [low], defaults: defaults, post: succeedingPost).count, 1,
            "With the HUD off, a refused notification was shown nowhere and must be retried"
        )
        XCTAssertTrue(LowBatteryNotifier.notifyIfNeeded(for: [low], defaults: defaults, post: succeedingPost).isEmpty)
    }

    func testNotifyIfNeededReportsDeliveryFailure() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let low = DecoratedBatterySnapshot(snapshot: snapshot(percent: 10), freshness: .fresh)
        let reported = expectation(description: "delivery reported")

        _ = LowBatteryNotifier.notifyIfNeeded(
            for: [low],
            defaults: defaults,
            post: { _, completion in completion("denied") },
            deliveryHandler: { result in
                if result.state == .failed { reported.fulfill() }
            }
        )
        wait(for: [reported], timeout: 1)
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
