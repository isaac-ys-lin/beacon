import XCTest
@testable import Beacon

final class MacPowerSourceReaderTests: XCTestCase {
    func testSnapshotFromPowerSourceDictionary() {
        let dictionary: [String: Any] = [
            "Name": "InternalBattery-0",
            "Current Capacity": 81,
            "Max Capacity": 100,
            "Is Charging": true
        ]

        let snapshot = MacPowerSourceReader.snapshot(from: dictionary, now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(snapshot?.kind, .macBook)
        XCTAssertEqual(snapshot?.percent, 81)
        XCTAssertEqual(snapshot?.chargeState, .charging)
        XCTAssertEqual(snapshot?.source, .macPowerSource)
    }

    @MainActor
    func testBeaconModelRefreshMergesMacPowerSourceSnapshotWithBluetoothReport() async {
        let now = Date(timeIntervalSince1970: 100)
        let mac = BatterySnapshot(
            deviceID: "macbook",
            displayName: "MacBook",
            kind: .macBook,
            percent: 81,
            chargeState: .charging,
            source: .macPowerSource,
            updatedAt: now
        )
        let keyboard = BatterySnapshot(
            deviceID: "keyboard",
            displayName: "Magic Keyboard",
            kind: .keyboard,
            percent: 64,
            chargeState: .unplugged,
            source: .coreBluetooth,
            updatedAt: now
        )
        let report = BluetoothBatteryReadReport(
            snapshots: [keyboard],
            diagnostics: BatteryRefreshDiagnostics(
                attempts: [
                    BatteryProviderAttempt(
                        provider: .coreBluetoothBatteryService,
                        status: .reported,
                        candidateCount: 1,
                        message: "Known BLE scan returned 1 battery candidate",
                        attemptedAt: now
                    )
                ],
                refreshedAt: now,
                snapshotCount: 1
            )
        )
        let model = BeaconModel(
            environment: [:],
            macPowerSourceReader: { [mac] },
            bluetoothReportReader: { report }
        )

        await model.refresh()

        XCTAssertEqual(Set(model.store.snapshots.map(\.deviceID)), ["macbook", "keyboard"])
        XCTAssertEqual(model.store.snapshots.first { $0.kind == .macBook }?.source, .macPowerSource)
        XCTAssertEqual(model.store.externalBatterySnapshots.map(\.deviceID), ["keyboard"])
    }
}
