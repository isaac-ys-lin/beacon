import XCTest
@testable import Beacon

extension DeviceListPresentationTests {
    func testReportPresentationDistinguishesCurrentCachedMissingAndDeniedValues() {
        let current = DeviceBatteryPresentation(percent: 40, freshness: .fresh)
        XCTAssertEqual(current.state, .current)
        XCTAssertEqual(current.valueText, "40%")
        for freshness in [Freshness.stale, .expired] {
            let report = DeviceBatteryPresentation(percent: 40, freshness: freshness)
            XCTAssertEqual(report.valueText, "Last known: 40%")
            XCTAssertNotEqual(report.state, .current)
        }
        XCTAssertEqual(DeviceBatteryPresentation(percent: 40, freshness: .fresh, connectionState: .disconnected).state, .disconnected)
        XCTAssertEqual(DeviceBatteryPresentation(percent: 40, freshness: .fresh, connectionState: .unknown).state, .unconfirmed)
        XCTAssertEqual(DeviceBatteryPresentation(percent: 40, freshness: .fresh, readStatus: .timedOut).state, .unavailable)
        let denied = DeviceBatteryPresentation(percent: 40, freshness: .fresh, readStatus: .unauthorized)
        XCTAssertEqual(denied.state, .permission)
        XCTAssertNil(denied.percent)
        XCTAssertNil(DeviceBatteryPresentation(percent: 40, freshness: .fresh, readStatus: .noReport).percent)
        XCTAssertNil(DeviceBatteryPresentation(percent: 101, freshness: .fresh).percent)
        XCTAssertEqual(DeviceBatteryPresentation(percent: nil, freshness: .fresh).state, .noReport)
    }

    func testRefreshFailuresUseExactIdentityAndCannotOverwriteNewerReport() {
        let now = Date(timeIntervalSince1970: 1_000)
        func report(_ id: String, date: Date = Date(timeIntervalSince1970: 1_000)) -> DecoratedBatterySnapshot {
            .init(snapshot: BatterySnapshot(deviceID: id, displayName: "Same Name", kind: .keyboard,
                percent: 40, chargeState: .unplugged, source: .coreBluetooth, identityStrength: .strong, updatedAt: date), freshness: .fresh)
        }
        let snapshots = [report("first"), report("second")]
        let failure = BatteryProviderAttempt(provider: .coreBluetoothBatteryService, status: .unauthorized,
            candidateCount: 0, message: "fixture", attemptedAt: now, affectedDeviceIDs: ["second"])
        let annotated = batterySnapshotsWithKnownFailures(snapshots, diagnostics: .init(attempts: [failure]))
        XCTAssertEqual(annotated[0], snapshots[0])
        XCTAssertEqual(DeviceBatteryPresentation(item: .device(annotated[1])).state, .permission)
        XCTAssertEqual(annotated[1].snapshot.updatedAt, snapshots[1].snapshot.updatedAt)
        XCTAssertEqual(annotated[1].snapshot.percent, 40, "The cached report is retained, not rewritten into an invented value.")
        let newer = report("second", date: now.addingTimeInterval(10))
        XCTAssertEqual(batterySnapshotsWithKnownFailures([newer], diagnostics: .init(attempts: [failure])), [newer])
        let unknown = BatteryProviderAttempt(provider: .coreBluetoothBatteryService, status: .timedOut,
            candidateCount: 0, message: "Same Name", attemptedAt: now)
        XCTAssertEqual(batterySnapshotsWithKnownFailures(snapshots, diagnostics: .init(attempts: [unknown])), snapshots)
    }

    func testCachedChargingReportsDoNotContributeCurrentChargingOrLowAlerts() {
        let now = Date()
        let snapshot = BatterySnapshot(deviceID: "cached", displayName: "Headphones", kind: .bluetoothPeripheral,
            percent: 10, chargeState: .charging, source: .coreBluetooth, updatedAt: now)
        let sections = [DeviceSection(items: [.device(.init(snapshot: snapshot, freshness: .stale))])]
        let summary = batteryOverviewSummary(for: sections, lowBatteryThreshold: 20)
        XCTAssertEqual(summary.chargingItemCount, 0)
        XCTAssertEqual(summary.lowBatteryItemCount, 0)
        XCTAssertEqual(summary.staleItemCount, 1)
        let row = DashboardBatteryDevice(item: sections[0].items[0])
        XCTAssertEqual(row.reportState, .stale)
    }

    func testCachedCompositeAccessibilityExplicitlyMarksLastKnownReadings() {
        let snapshots = ["left", "right"].map { slot in
            DecoratedBatterySnapshot(snapshot: BatterySnapshot(deviceID: "headset-\(slot)",
                displayName: "Headset", kind: .airPods, percent: 40, chargeState: .charging,
                connectionState: .disconnected, source: .systemProfiler, updatedAt: Date()), freshness: .fresh)
        }
        let item = groupedDeviceItems(snapshots).flatMap(\.items).first!
        let device = DashboardBatteryDevice(item: item)
        let value = dashboardBatteryAccessibilityValue(for: device, statusText: device.reportState.title)
        XCTAssertTrue(value.contains("Last known: 40%"), value)
        XCTAssertTrue(value.contains("Disconnected"), value)
        XCTAssertFalse(value.contains("charging"), value)
        let absent = DashboardBatteryDevice(item: .device(.init(snapshot: BatterySnapshot(
            deviceID: "none", displayName: "None", kind: .keyboard, percent: nil,
            chargeState: .unknown, source: .coreBluetooth, readStatus: .noReport, updatedAt: Date()), freshness: .fresh)))
        let missing = dashboardBatteryAccessibilityValue(for: absent, statusText: absent.reportState.title)
        XCTAssertTrue(missing.contains("No report"), missing)
        XCTAssertTrue(missing.contains("No battery report"), missing)
    }

    func testOldDiagnosticsDecodeWithoutAnAffectedDeviceClaim() throws {
        let old = Data(#"{"provider":"systemProfiler","status":"timedOut","candidateCount":0,"message":"old","attemptedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(BatteryProviderAttempt.self, from: old)
        XCTAssertNil(decoded.affectedDeviceIDs)
    }
}

extension LowBatteryNotifierFreshnessTests {
    func testFailedReadDoesNotCreateAlertsOrResetExistingLatch() throws {
        let suite = "Beacon.ReadFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(20, forKey: LowBatteryNotifier.thresholdDefaultsKey)
        func report(_ percent: Int, _ status: BatteryReadStatus) -> DecoratedBatterySnapshot {
            .init(snapshot: BatterySnapshot(deviceID: "test-keyboard", displayName: "Test", kind: .keyboard,
                percent: percent, chargeState: .unplugged, source: .ioRegistry, readStatus: status, updatedAt: Date()), freshness: .fresh)
        }
        XCTAssertTrue(LowBatteryNotifier.pendingAlertEvents(for: [report(10, .unauthorized)], defaults: defaults).isEmpty)
        XCTAssertEqual(LowBatteryNotifier.pendingAlertEvents(for: [report(10, .reported)], defaults: defaults).map(\.kind), [.lowBattery])
        XCTAssertTrue(LowBatteryNotifier.pendingAlertEvents(for: [report(90, .timedOut)], defaults: defaults).isEmpty)
        XCTAssertTrue(LowBatteryNotifier.pendingAlertEvents(for: [report(10, .reported)], defaults: defaults).isEmpty)
    }
}

extension BluetoothBatteryResolverTests {
    func testPartialIPhoneReadIdentifiesOnlyTheFailedDevice() async {
        let registry = TrustedIPhoneRegistry(devices: [
            TrustedIPhone(udid: "good", displayName: "Same Name", trustedAt: Date()),
            TrustedIPhone(udid: "denied", displayName: "Same Name", trustedAt: Date())
        ])
        let report = await IPhoneLockdownBatteryProvider(registry: registry,
            commandSet: .init(ideviceIDURL: URL(fileURLWithPath: "/fixture/idevice_id"), ideviceInfoURL: URL(fileURLWithPath: "/fixture/ideviceinfo")),
            commandRunner: PartiallyFailingIPhoneRunner()).readReport()
        XCTAssertEqual(report.candidates.map(\.deviceID), ["good"])
        let failures = report.attempts.filter { $0.affectedDeviceIDs != nil }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.affectedDeviceIDs, ["trusted-iphone-denied"])
        XCTAssertEqual(failures.first?.status, .unauthorized)
    }
}

private struct PartiallyFailingIPhoneRunner: IPhoneLockdownCommandRunning {
    func run(commandURL: URL, arguments: [String], timeout: TimeInterval) async -> IPhoneLockdownCommandResult {
        if commandURL.lastPathComponent == "idevice_id" {
            return .init(exitStatus: 0, output: arguments == ["-l"] ? "good\ndenied\n" : "")
        }
        if arguments.contains("denied") {
            return .init(exitStatus: 1, output: "", errorOutput: "ERROR: Could not connect to lockdownd: UserDeniedPairing (-18)")
        }
        if arguments.contains("DeviceName") { return .init(exitStatus: 0, output: "Same Name\n") }
        return .init(exitStatus: 0, output: "BatteryCurrentCapacity: 87\nBatteryIsCharging: true\n")
    }
}
