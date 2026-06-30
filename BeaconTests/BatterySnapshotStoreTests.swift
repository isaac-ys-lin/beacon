import XCTest
@testable import Beacon

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
            source: .coreBluetooth,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let new = BatterySnapshot(
            deviceID: "iphone",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 43,
            chargeState: .charging,
            source: .coreBluetooth,
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
            source: .coreBluetooth,
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

    func testMergeDeduplicatesSameIPhoneAcrossBLEAndUSBSources() {
        let bleReport = BatterySnapshot(
            deviceID: "bluetooth-iphone-yisungiphone",
            displayName: "YiSungiPhone",
            kind: .iPhone,
            percent: 80,
            chargeState: .unknown,
            source: .coreBluetooth,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let usbReport = BatterySnapshot(
            deviceID: "usb-iphone-yisungiphone",
            displayName: "YiSungiPhone",
            kind: .iPhone,
            percent: 77,
            chargeState: .unknown,
            source: .ideviceInfo,
            updatedAt: Date(timeIntervalSince1970: 120)
        )

        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 140) })
        store.merge([bleReport])
        store.merge([usbReport])

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["usb-iphone-yisungiphone"])
        XCTAssertEqual(store.snapshots.map(\.source), [.ideviceInfo])
        XCTAssertEqual(store.snapshots.map(\.percent), [77])
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

    func testMobileRowsRemainOrdinaryExternalSnapshots() {
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
            source: .coreBluetooth,
            updatedAt: now
        )
        var store = BatterySnapshotStore(now: { now })
        store.merge([keyboard, iphone])

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["iphone", "keyboard"])
        XCTAssertEqual(store.externalBatterySnapshots.map(\.deviceID), ["iphone", "keyboard"])
    }

    func testReconcileRemovesDeviceMissingFromLiveRead() {
        let now = Date(timeIntervalSince1970: 100)
        let keyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 88,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now
        )
        let iphone = BatterySnapshot(
            deviceID: "usb-iphone-yisungiphone",
            displayName: "YiSungiPhone",
            kind: .iPhone,
            percent: 52,
            chargeState: .unplugged,
            source: .ideviceInfo,
            updatedAt: now
        )

        var store = BatterySnapshotStore(now: { now.addingTimeInterval(20) })
        store.merge([keyboard, iphone])

        // Next live read only sees the keyboard (iPhone disconnected/removed).
        let keyboardNext = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 87,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now.addingTimeInterval(45)
        )
        store.reconcile(with: [keyboardNext])

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["keyboard"])
    }

    func testReconcileRemovesStaleIPhoneEvenWhenNameDiffersFromLiveRead() {
        let now = Date(timeIntervalSince1970: 100)
        // Stale connected iPhone captured earlier under the iOS DeviceName.
        let staleUSBIPhone = BatterySnapshot(
            deviceID: "usb-iphone-yisung-s-iphone",
            displayName: "YiSung's iPhone",
            kind: .iPhone,
            percent: 60,
            chargeState: .charging,
            source: .ideviceInfo,
            updatedAt: now
        )
        let keyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 88,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now
        )

        var store = BatterySnapshotStore(now: { now.addingTimeInterval(20) })
        store.merge([staleUSBIPhone, keyboard])

        // iPhone now only visible over Bluetooth as disconnected, under its
        // Bluetooth name (different normalized name than the USB DeviceName).
        let liveKeyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 87,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now.addingTimeInterval(45)
        )
        store.reconcile(with: [liveKeyboard])

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["keyboard"])
    }

    func testReconcileSkipsPruneWhenLiveReadHasNoBluetoothDevices() {
        let now = Date(timeIntervalSince1970: 100)
        let keyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 88,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now
        )
        var store = BatterySnapshotStore(now: { now.addingTimeInterval(20) })
        store.merge([keyboard])

        // A failed/empty scan must not wipe the existing list.
        store.reconcile(with: [])

        XCTAssertEqual(store.snapshots.map(\.deviceID), ["keyboard"])
    }

    func testReconcilePreservesMacPowerSourceDevice() {
        let now = Date(timeIntervalSince1970: 100)
        let mac = BatterySnapshot(
            deviceID: "mac",
            displayName: "MacBook",
            kind: .macBook,
            percent: 80,
            chargeState: .charging,
            source: .macPowerSource,
            updatedAt: now
        )
        let keyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 88,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now
        )
        var store = BatterySnapshotStore(now: { now.addingTimeInterval(20) })
        store.merge([mac, keyboard])

        // Live Bluetooth read does not include the Mac power source — it must survive.
        store.reconcile(with: [keyboard])

        XCTAssertEqual(Set(store.snapshots.map(\.deviceID)), ["mac", "keyboard"])
    }

    func testIsChargingByTrendDetectsRecentRise() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = [
            BatteryHistorySample(deviceID: "kbd", percent: 80, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-120)),
            BatteryHistorySample(deviceID: "kbd", percent: 83, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-30)),
        ]
        XCTAssertTrue(BatteryHistoryStore.isChargingByTrend(samples: samples, now: now))
    }

    func testIsChargingByTrendRejectsFallingBattery() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = [
            BatteryHistorySample(deviceID: "kbd", percent: 83, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-120)),
            BatteryHistorySample(deviceID: "kbd", percent: 80, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-30)),
        ]
        XCTAssertFalse(BatteryHistoryStore.isChargingByTrend(samples: samples, now: now))
    }

    func testIsChargingByTrendRejectsStaleRise() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = [
            BatteryHistorySample(deviceID: "kbd", percent: 80, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-2_000)),
            BatteryHistorySample(deviceID: "kbd", percent: 83, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-1_200)),
        ]
        XCTAssertFalse(BatteryHistoryStore.isChargingByTrend(samples: samples, now: now))
    }

    // Regression: a flat device left overnight read 82% before sleep and 83%
    // on the first post-wake poll. The latest reading is fresh, but it straddles
    // a ~12h gap, so the +1% is recalibration/jitter — not active charging.
    // Previously this lit up the Keychron as "charging" right after wake.
    func testIsChargingByTrendRejectsRiseAcrossSleepGap() {
        let now = Date(timeIntervalSince1970: 100_000)
        let samples = [
            BatteryHistorySample(deviceID: "kbd", percent: 82, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-43_200)),
            BatteryHistorySample(deviceID: "kbd", percent: 83, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-30)),
        ]
        XCTAssertFalse(BatteryHistoryStore.isChargingByTrend(samples: samples, now: now))
    }

    // A rise measured across a normal poll interval is still detected as charging.
    func testIsChargingByTrendDetectsRiseWithinPollInterval() {
        let now = Date(timeIntervalSince1970: 100_000)
        let samples = [
            BatteryHistorySample(deviceID: "kbd", percent: 82, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-200)),
            BatteryHistorySample(deviceID: "kbd", percent: 83, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-30)),
        ]
        XCTAssertTrue(BatteryHistoryStore.isChargingByTrend(samples: samples, now: now))
    }

    func testIsChargingByTrendNeedsTwoSamples() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = [
            BatteryHistorySample(deviceID: "kbd", percent: 83, chargeState: .unknown, source: .coreBluetooth, recordedAt: now.addingTimeInterval(-30)),
        ]
        XCTAssertFalse(BatteryHistoryStore.isChargingByTrend(samples: samples, now: now))
    }

    func testApplyInferredChargeStatesOnlyOverridesUnknown() {
        let now = Date(timeIntervalSince1970: 100)
        let blePeripheral = BatterySnapshot(
            deviceID: "kbd",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 83,
            chargeState: .unknown,
            source: .coreBluetooth,
            updatedAt: now
        )
        let usbIPhone = BatterySnapshot(
            deviceID: "usb-iphone",
            displayName: "iPhone",
            kind: .iPhone,
            percent: 50,
            chargeState: .unplugged,
            source: .ideviceInfo,
            updatedAt: now
        )
        var store = BatterySnapshotStore(now: { now.addingTimeInterval(10) })
        store.merge([blePeripheral, usbIPhone])

        store.applyInferredChargeStates { snapshot in
            snapshot.chargeState == .unknown ? .charging : snapshot.chargeState
        }

        let byID = Dictionary(uniqueKeysWithValues: store.snapshots.map { ($0.deviceID, $0) })
        XCTAssertEqual(byID["kbd"]?.chargeState, .charging)        // inferred
        XCTAssertEqual(byID["usb-iphone"]?.chargeState, .unplugged) // real reading preserved
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
                source: .coreBluetooth,
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
