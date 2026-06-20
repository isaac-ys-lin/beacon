import XCTest
@testable import BatteryHub

final class BatterySnapshotStoreTests: XCTestCase {
    private func isolatedDefaults(name: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "BatteryHistoryStoreTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testMergeKeepsNewestSnapshotPerDevice() {
        let old = BatterySnapshot(
            deviceID: "iphone",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 42,
            chargeState: .unplugged,
            source: .iCloud,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let new = BatterySnapshot(
            deviceID: "iphone",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 43,
            chargeState: .charging,
            source: .iCloud,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 300) })
        store.merge([old])
        store.merge([new])

        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots[0].percent, 43)
        XCTAssertEqual(store.snapshots[0].chargeState, .charging)
    }

    func testFreshnessBucketsUseConfiguredThresholds() {
        let snapshot = BatterySnapshot(
            deviceID: "watch",
            displayName: "Apple Watch",
            kind: .appleWatch,
            percent: 88,
            chargeState: .unplugged,
            source: .watchConnectivity,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 700) })
        store.merge([snapshot])

        XCTAssertEqual(store.decoratedSnapshots[0].freshness, .stale)
    }

    func testUnsupportedBluetoothDeviceStaysVisibleWithoutPercent() {
        let snapshot = BatterySnapshot(
            deviceID: "bt-keyboard",
            displayName: "Keychron K2",
            kind: .bluetoothPeripheral,
            percent: nil,
            chargeState: .unknown,
            source: .bluetoothUnsupported,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 120) })
        store.merge([snapshot])

        XCTAssertNil(store.snapshots[0].percent)
        XCTAssertEqual(store.snapshots[0].source, .bluetoothUnsupported)
    }

    func testExternalBatterySnapshotsHideMacBookAndMissingReports() {
        let mac = BatterySnapshot(
            deviceID: "mac",
            displayName: "MacBook",
            kind: .macBook,
            percent: 80,
            chargeState: .unplugged,
            source: .macPowerSource,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let unsupportedKeyboard = BatterySnapshot(
            deviceID: "keyboard-unknown",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: nil,
            chargeState: .unknown,
            source: .bluetoothUnsupported,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let keyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 42,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 120) })
        store.merge([mac, unsupportedKeyboard, keyboard])

        XCTAssertEqual(store.externalBatterySnapshots.map(\.deviceID), ["keyboard"])
        XCTAssertEqual(store.decoratedExternalBatterySnapshots.map(\.snapshot.deviceID), ["keyboard"])
    }

    func testMergeDeduplicatesSameNamedBluetoothDeviceAcrossSources() {
        let oldUnsupported = BatterySnapshot(
            deviceID: "bluetooth-AA-BB-CC",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: nil,
            chargeState: .unknown,
            source: .bluetoothUnsupported,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerBatteryReport = BatterySnapshot(
            deviceID: "bluetooth-hid-keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 82,
            chargeState: .unplugged,
            source: .ioRegistry,
            updatedAt: Date(timeIntervalSince1970: 120)
        )

        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 140) })
        store.merge([oldUnsupported])
        store.merge([newerBatteryReport])

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["bluetooth-hid-keyboard"])
        XCTAssertEqual(store.snapshots.map(\.percent), [82])
    }

    func testMergeKeepsBatteryReportWhenSameRefreshAlsoHasUnsupportedBluetoothDuplicate() {
        let now = Date(timeIntervalSince1970: 120)
        let batteryReport = BatterySnapshot(
            deviceID: "bluetooth-hid-keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 82,
            chargeState: .unknown,
            source: .ioRegistry,
            updatedAt: now
        )
        let unsupportedDuplicate = BatterySnapshot(
            deviceID: "bluetooth-AA-BB-CC",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: nil,
            chargeState: .unknown,
            source: .bluetoothUnsupported,
            updatedAt: now
        )

        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 140) })
        store.merge([batteryReport, unsupportedDuplicate])

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["bluetooth-hid-keyboard"])
        XCTAssertEqual(store.snapshots.map(\.percent), [82])
    }

    func testRemoveCompanionSyncSnapshotsKeepsBluetoothDevices() {
        let now = Date(timeIntervalSince1970: 100)
        let keyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 88,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now
        )
        let iphone = BatterySnapshot(
            deviceID: "iphone",
            displayName: "YiSungiPhone",
            kind: .iPhone,
            percent: 52,
            chargeState: .unplugged,
            source: .iCloud,
            updatedAt: now
        )
        let watch = BatterySnapshot(
            deviceID: "watch",
            displayName: "Yi Sung Apple Watch",
            kind: .appleWatch,
            percent: 42,
            chargeState: .charging,
            source: .watchConnectivity,
            updatedAt: now
        )

        var store = BatterySnapshotStore(now: { now })
        store.merge([keyboard, iphone, watch])
        store.removeCompanionSyncSnapshots()

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["keyboard"])
        XCTAssertEqual(store.externalBatterySnapshots.map(\.deviceID), ["keyboard"])
    }

    func testBatteryHistoryStoreRecordsAndSummarizesPercentTrend() {
        let defaults = isolatedDefaults()
        let base = Date(timeIntervalSince1970: 1_000)

        BatteryHistoryStore.record(
            [
                BatterySnapshot(
                    deviceID: "mouse",
                    displayName: "Magic Mouse",
                    kind: .mouse,
                    percent: 42,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: base
                ),
                BatterySnapshot(
                    deviceID: "mouse",
                    displayName: "Magic Mouse",
                    kind: .mouse,
                    percent: 38,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: base.addingTimeInterval(3_600)
                ),
            ],
            now: base.addingTimeInterval(3_600),
            defaults: defaults
        )

        let samples = BatteryHistoryStore.samples(for: "mouse", defaults: defaults)
        let summary = BatteryHistoryStore.summary(for: "mouse", defaults: defaults)

        XCTAssertEqual(samples.map(\.percent), [42, 38])
        XCTAssertEqual(summary?.latestPercent, 38)
        XCTAssertEqual(summary?.delta, -4)
        XCTAssertEqual(summary?.minimumPercent, 38)
        XCTAssertEqual(summary?.maximumPercent, 42)
    }

    func testBatteryHistoryStoreSkipsDuplicateStableReports() {
        let defaults = isolatedDefaults()
        let base = Date(timeIntervalSince1970: 1_000)
        let snapshot = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 82,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: base
        )

        BatteryHistoryStore.record([snapshot], now: base, defaults: defaults)
        BatteryHistoryStore.record([snapshot], now: base.addingTimeInterval(60), defaults: defaults)

        XCTAssertEqual(BatteryHistoryStore.samples(for: "keyboard", defaults: defaults).count, 1)
    }

    func testBatteryHistoryStorePrunesOldAndExcessSamples() {
        let defaults = isolatedDefaults()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshots = (0..<(BatteryHistoryStore.maximumSamplesPerDevice + 8)).map { index in
            BatterySnapshot(
                deviceID: "watch",
                displayName: "Apple Watch",
                kind: .appleWatch,
                percent: 100 - (index % 50),
                chargeState: .unplugged,
                source: .watchConnectivity,
                updatedAt: now
                    .addingTimeInterval(-BatteryHistoryStore.retentionInterval)
                    .addingTimeInterval(Double(index * 600))
            )
        }

        BatteryHistoryStore.record(snapshots, now: now, defaults: defaults)

        let samples = BatteryHistoryStore.samples(for: "watch", defaults: defaults)
        XCTAssertLessThanOrEqual(samples.count, BatteryHistoryStore.maximumSamplesPerDevice)
        XCTAssertTrue(samples.allSatisfy { $0.recordedAt >= now.addingTimeInterval(-BatteryHistoryStore.retentionInterval) })
    }
}
