import XCTest
@testable import BatteryHub

final class BatterySnapshotStoreTests: XCTestCase {
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
}
