import CoreBluetooth
import XCTest
@testable import BatteryHub

final class BluetoothBatteryResolverTests: XCTestCase {
    private static func lockdownCommandSet() -> IPhoneLockdownCommandSet {
        IPhoneLockdownCommandSet(
            ideviceIDURL: URL(fileURLWithPath: "/tmp/idevice_id"),
            ideviceInfoURL: URL(fileURLWithPath: "/tmp/ideviceinfo")
        )
    }

    private func isolatedDefaults(name: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "BluetoothBatteryResolverTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testIORegistryBatteryPercentCreatesKeyboardSnapshot() {
        let device = BluetoothBatteryCandidate(
            deviceID: "apple-keyboard",
            displayName: "Magic Keyboard",
            transport: .hid,
            batteryPercent: 64
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.displayName, "Magic Keyboard")
        XCTAssertEqual(snapshot.kind, .keyboard)
        XCTAssertEqual(snapshot.percent, 64)
        XCTAssertEqual(snapshot.source, .ioRegistry)
    }

    func testDeviceWithoutBatteryIsVisibleAsUnsupported() {
        let device = BluetoothBatteryCandidate(
            deviceID: "speaker",
            displayName: "Kitchen Speaker",
            transport: .unknown,
            batteryPercent: nil
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.percent, nil)
        XCTAssertEqual(snapshot.source, .bluetoothUnsupported)
    }

    func testDisconnectedPairedDeviceKeepsConnectionState() {
        let device = BluetoothBatteryCandidate(
            deviceID: "20-C1-9B-AA-BB-CC",
            displayName: "Magic Mouse",
            transport: .classic,
            batteryPercent: nil,
            kindHint: .mouse,
            connectionState: .disconnected
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.deviceID, "bluetooth-20-C1-9B-AA-BB-CC")
        XCTAssertEqual(snapshot.kind, .mouse)
        XCTAssertNil(snapshot.percent)
        XCTAssertEqual(snapshot.connectionState, .disconnected)
        XCTAssertEqual(snapshot.source, .bluetoothUnsupported)
    }

    func testBLEBatteryServiceClassifiesIPhoneWithProviderMetadata() {
        let device = BluetoothBatteryCandidate(
            deviceID: "16AE09F1-3309-CF7D-793F-80F1EE3B4933",
            displayName: "YiSungiPhone",
            transport: .ble,
            batteryPercent: 80
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.deviceID, "bluetooth-iphone-yisungiphone")
        XCTAssertEqual(snapshot.displayName, "YiSungiPhone")
        XCTAssertEqual(snapshot.kind, .iPhone)
        XCTAssertEqual(snapshot.percent, 80)
        XCTAssertEqual(snapshot.source, .coreBluetooth)
        XCTAssertEqual(snapshot.provider, .coreBluetoothBatteryService)
        XCTAssertEqual(snapshot.readStatus, .reported)
        XCTAssertEqual(snapshot.confidence, .medium)
    }

    func testBLEIPhoneUUIDChurnKeepsStableSnapshotIdentity() {
        let first = BluetoothBatteryResolver.snapshot(
            from: BluetoothBatteryCandidate(
                deviceID: "16AE09F1-3309-CF7D-793F-80F1EE3B4933",
                displayName: "YiSungiPhone",
                transport: .ble,
                batteryPercent: 80
            ),
            now: Date(timeIntervalSince1970: 50)
        )
        let second = BluetoothBatteryResolver.snapshot(
            from: BluetoothBatteryCandidate(
                deviceID: "E845C788-1D87-AE9D-C050-44E65C6807E1",
                displayName: "YiSungiPhone",
                transport: .ble,
                batteryPercent: 79
            ),
            now: Date(timeIntervalSince1970: 70)
        )

        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertEqual(second.deviceID, "bluetooth-iphone-yisungiphone")
    }

    func testResolverReportCarriesProviderDiagnostics() {
        let scanReport = BluetoothCandidateScanReport(
            candidates: [
                BluetoothBatteryCandidate(
                    deviceID: "apple-keyboard",
                    displayName: "Magic Keyboard",
                    transport: .hid,
                    batteryPercent: 80,
                    kindHint: .keyboard
                )
            ],
            attempts: [
                BatteryProviderAttempt(
                    provider: .ioRegistry,
                    status: .reported,
                    candidateCount: 1,
                    message: "IORegistry returned 1 battery candidate",
                    attemptedAt: Date(timeIntervalSince1970: 40)
                )
            ]
        )

        let report = BluetoothBatteryResolver.report(from: scanReport, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(report.snapshots.map(\.deviceID), ["bluetooth-apple-keyboard"])
        XCTAssertEqual(report.diagnostics.snapshotCount, 1)
        XCTAssertEqual(report.diagnostics.attempts.count, 1)
        XCTAssertEqual(report.diagnostics.attempts[0].provider, .ioRegistry)
        XCTAssertEqual(report.diagnostics.attempts[0].status, .reported)
        XCTAssertEqual(report.diagnostics.attempts[0].candidateCount, 1)
    }

    func testResolverReportDropsBLEIPhoneCandidates() {
        let scanReport = BluetoothCandidateScanReport(
            candidates: [
                BluetoothBatteryCandidate(
                    deviceID: "16AE09F1-3309-CF7D-793F-80F1EE3B4933",
                    displayName: "YiSungiPhone",
                    transport: .ble,
                    batteryPercent: 80
                ),
                BluetoothBatteryCandidate(
                    deviceID: "apple-keyboard",
                    displayName: "Magic Keyboard",
                    transport: .hid,
                    batteryPercent: 64,
                    kindHint: .keyboard
                )
            ],
            attempts: [
                BatteryProviderAttempt(
                    provider: .coreBluetoothBatteryService,
                    status: .reported,
                    candidateCount: 1,
                    message: "Known BLE scan returned 1 battery candidate",
                    attemptedAt: Date(timeIntervalSince1970: 40)
                )
            ]
        )

        let report = BluetoothBatteryResolver.report(from: scanReport, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(report.snapshots.map(\.deviceID), ["bluetooth-apple-keyboard"])
        XCTAssertEqual(report.diagnostics.snapshotCount, 1)
    }

    func testTrustedIPhoneSnapshotUsesUDIDIdentity() {
        let usbSnapshot = BluetoothBatteryResolver.snapshot(
            from: BluetoothBatteryCandidate(
                deviceID: "00008030-001A",
                displayName: "YiSungiPhone",
                transport: .usb,
                batteryPercent: 77,
                kindHint: .iPhone
            ),
            now: Date(timeIntervalSince1970: 70)
        )
        let networkSnapshot = BluetoothBatteryResolver.snapshot(
            from: BluetoothBatteryCandidate(
                deviceID: "00008110-00BB",
                displayName: "YiSungiPhone",
                transport: .lockdownNetwork,
                batteryPercent: 72,
                kindHint: .iPhone
            ),
            now: Date(timeIntervalSince1970: 70)
        )

        XCTAssertEqual(usbSnapshot.deviceID, "trusted-iphone-00008030-001A")
        XCTAssertEqual(usbSnapshot.kind, .iPhone)
        XCTAssertEqual(usbSnapshot.percent, 77)
        XCTAssertEqual(usbSnapshot.source, .ideviceInfo)
        XCTAssertEqual(usbSnapshot.provider, .ideviceInfo)
        XCTAssertEqual(usbSnapshot.confidence, .high)
        XCTAssertEqual(networkSnapshot.deviceID, "trusted-iphone-00008110-00BB")
        XCTAssertEqual(networkSnapshot.source, .ideviceInfo)
    }

    func testIPhoneLockdownBatteryParserReadsCapacityAndDeviceName() {
        let reading = IPhoneLockdownBatteryProvider.parseBatteryReading(
            """
            BatteryCurrentCapacity: 77
            BatteryIsCharging: false
            DeviceName: YiSungiPhone
            """,
            fallbackDisplayName: "Fallback iPhone"
        )

        XCTAssertEqual(reading?.percent, 77)
        XCTAssertEqual(reading?.displayName, "YiSungiPhone")
    }

    func testIPhoneLockdownProviderReadsOnlyAllowlistedDevices() async throws {
        let trustedAt = Date(timeIntervalSince1970: 1_000)
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner(responses: [
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-l"]): .init(
                exitStatus: 0,
                output: "trusted-usb\nuntrusted-usb\n"
            ),
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-n"]): .init(
                exitStatus: 0,
                output: "trusted-usb\nuntrusted-network\n"
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "trusted-usb", "-k", "DeviceName"]): .init(
                exitStatus: 0,
                output: "Live iPhone\n"
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "trusted-usb", "-q", "com.apple.mobile.battery"]): .init(
                exitStatus: 0,
                output: "BatteryCurrentCapacity: 64\nDeviceName: Live iPhone\n"
            )
        ])
        let registry = TrustedIPhoneRegistry()
            .trusting(TrustedIPhone(udid: "trusted-usb", displayName: "Registry iPhone", trustedAt: trustedAt))
        let provider = IPhoneLockdownBatteryProvider(
            registry: registry,
            commandSet: commandSet,
            commandRunner: runner
        )

        let report = await provider.readReport(now: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(report.candidates.count, 1)
        let candidate = try XCTUnwrap(report.candidates.first)
        XCTAssertEqual(candidate.deviceID, "trusted-usb")
        XCTAssertEqual(candidate.displayName, "Live iPhone")
        XCTAssertEqual(candidate.transport, .usb)
        XCTAssertEqual(candidate.batteryPercent, 64)
        XCTAssertEqual(candidate.kindHint, .iPhone)
        XCTAssertEqual(report.attempts.first?.status, .reported)
        XCTAssertEqual(report.attempt?.status, .reported)
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("untrusted-usb") })
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("untrusted-network") })
    }

    func testIPhoneLockdownProviderReadsNetworkAllowlistedDevice() async throws {
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner(responses: [
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-l"]): .init(exitStatus: 0, output: ""),
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-n"]): .init(exitStatus: 0, output: "trusted-network\n"),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-n", "-u", "trusted-network", "-k", "DeviceName"]): .init(
                exitStatus: 0,
                output: ""
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-n", "-u", "trusted-network", "-q", "com.apple.mobile.battery"]): .init(
                exitStatus: 0,
                output: "BatteryCurrentCapacity: 52\n"
            )
        ])
        let registry = TrustedIPhoneRegistry(devices: [
            TrustedIPhone(
                udid: "trusted-network",
                displayName: "Registry Network iPhone",
                trustedAt: Date(timeIntervalSince1970: 1_000)
            )
        ])
        let provider = IPhoneLockdownBatteryProvider(
            registry: registry,
            commandSet: commandSet,
            commandRunner: runner
        )

        let report = await provider.readReport(now: Date(timeIntervalSince1970: 2_000))

        let candidate = try XCTUnwrap(report.candidates.first)
        XCTAssertEqual(candidate.deviceID, "trusted-network")
        XCTAssertEqual(candidate.displayName, "Registry Network iPhone")
        XCTAssertEqual(candidate.transport, .lockdownNetwork)
        XCTAssertEqual(candidate.batteryPercent, 52)

        let snapshot = BluetoothBatteryResolver.snapshot(from: candidate, now: Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(snapshot.deviceID, "trusted-iphone-trusted-network")
        XCTAssertEqual(snapshot.source, .ideviceInfo)
        XCTAssertEqual(snapshot.provider, .ideviceInfo)
    }

    func testIPhoneLockdownProviderSkipsCommandsWhenRegistryIsEmpty() async {
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner()
        let provider = IPhoneLockdownBatteryProvider(
            registry: TrustedIPhoneRegistry(),
            commandSet: commandSet,
            commandRunner: runner
        )

        let report = await provider.readReport(now: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(report.candidates.isEmpty)
        XCTAssertEqual(report.attempt?.status, .noReport)
        XCTAssertEqual(report.attempt?.candidateCount, 0)
        XCTAssertEqual(report.attempt?.message, "No trusted iPhones are allowlisted")
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testIPhoneLockdownProviderKeepsUSBCandidateWhenNetworkListingFails() async throws {
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner(responses: [
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-l"]): .init(
                exitStatus: 0,
                output: "trusted-usb\n"
            ),
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-n"]): .init(
                exitStatus: 255,
                output: "",
                errorOutput: "network unavailable"
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "trusted-usb", "-k", "DeviceName"]): .init(
                exitStatus: 0,
                output: "USB iPhone\n"
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "trusted-usb", "-q", "com.apple.mobile.battery"]): .init(
                exitStatus: 0,
                output: "BatteryCurrentCapacity: 66\n"
            )
        ])
        let registry = TrustedIPhoneRegistry(devices: [
            TrustedIPhone(udid: "trusted-usb", displayName: "Registry iPhone", trustedAt: Date(timeIntervalSince1970: 1_000))
        ])

        let report = await IPhoneLockdownBatteryProvider.readCandidates(
            registry: registry,
            commandSet: commandSet,
            runner: runner,
            now: Date(timeIntervalSince1970: 2_000)
        )

        let candidate = try XCTUnwrap(report.candidates.first)
        XCTAssertEqual(candidate.deviceID, "trusted-usb")
        XCTAssertEqual(candidate.transport, .usb)
        XCTAssertEqual(candidate.batteryPercent, 66)
        XCTAssertEqual(report.attempt?.status, .reported)
        XCTAssertEqual(report.attempt?.candidateCount, 1)
        XCTAssertTrue(report.attempt?.message.contains("idevice_id -n returned status 255") == true)
    }

    func testIPhoneLockdownProviderPrefersUSBWhenSameUDIDAppearsOnNetwork() async throws {
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner(responses: [
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-l"]): .init(exitStatus: 0, output: "same-udid\n"),
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-n"]): .init(exitStatus: 0, output: "same-udid\n"),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "same-udid", "-k", "DeviceName"]): .init(
                exitStatus: 0,
                output: "USB Preferred iPhone\n"
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "same-udid", "-q", "com.apple.mobile.battery"]): .init(
                exitStatus: 0,
                output: "BatteryCurrentCapacity: 71\n"
            )
        ])
        let registry = TrustedIPhoneRegistry(devices: [
            TrustedIPhone(udid: "same-udid", displayName: "Registry iPhone", trustedAt: Date(timeIntervalSince1970: 1_000))
        ])
        let provider = IPhoneLockdownBatteryProvider(
            registry: registry,
            commandSet: commandSet,
            commandRunner: runner
        )

        let report = await provider.readReport(now: Date(timeIntervalSince1970: 2_000))

        let candidate = try XCTUnwrap(report.candidates.first)
        XCTAssertEqual(candidate.transport, .usb)
        XCTAssertEqual(candidate.batteryPercent, 71)
        XCTAssertTrue(runner.invocations.contains {
            $0.arguments == ["-u", "same-udid", "-q", "com.apple.mobile.battery"]
        })
        XCTAssertFalse(runner.invocations.contains {
            $0.arguments == ["-n", "-u", "same-udid", "-q", "com.apple.mobile.battery"]
        })
    }

    func testIPhoneLockdownProviderReportsTimedOutWhenListingTimesOut() async {
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner(responses: [
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-l"]): .init(
                exitStatus: -1,
                output: "",
                timedOut: true
            )
        ])
        let provider = IPhoneLockdownBatteryProvider(
            registry: TrustedIPhoneRegistry(devices: [
                TrustedIPhone(udid: "trusted-usb", displayName: "Registry iPhone", trustedAt: Date(timeIntervalSince1970: 1_000))
            ]),
            commandSet: commandSet,
            commandRunner: runner
        )

        let report = await provider.readReport(now: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(report.candidates.isEmpty)
        XCTAssertEqual(report.attempts.first?.status, .timedOut)
        XCTAssertEqual(report.attempts.first?.candidateCount, 0)
    }

    func testIPhoneLockdownProviderReportsMissingCommands() async {
        let provider = IPhoneLockdownBatteryProvider(
            registry: TrustedIPhoneRegistry(devices: [
                TrustedIPhone(udid: "trusted-usb", displayName: "Registry iPhone", trustedAt: Date(timeIntervalSince1970: 1_000))
            ]),
            commandSet: nil,
            commandRunner: MockIPhoneLockdownCommandRunner()
        )

        let report = await provider.readReport(now: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(report.candidates.isEmpty)
        XCTAssertEqual(report.attempts.first?.status, .commandMissing)
        XCTAssertEqual(report.attempts.first?.candidateCount, 0)
    }

    func testIPhoneLockdownDiscoveryListsUSBDevicesForEnrollment() async {
        let now = Date(timeIntervalSince1970: 2_000)
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner(responses: [
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-l"]): .init(
                exitStatus: 0,
                output: "first-usb\nsecond-usb\n"
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "first-usb", "-k", "DeviceName"]): .init(
                exitStatus: 0,
                output: "First iPhone\n"
            ),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "second-usb", "-k", "DeviceName"]): .init(
                exitStatus: 0,
                output: "Second iPhone\n"
            )
        ])
        let report = await IPhoneLockdownBatteryProvider.discoverUSBTrustedDevices(
            commandSet: commandSet,
            runner: runner,
            now: now
        )

        XCTAssertEqual(report.devices, [
            TrustedIPhone(udid: "first-usb", displayName: "First iPhone", trustedAt: now),
            TrustedIPhone(udid: "second-usb", displayName: "Second iPhone", trustedAt: now)
        ])
        XCTAssertEqual(report.status, .reported)
        XCTAssertEqual(report.message, "ideviceinfo verified 2 USB iPhones for enrollment")
        XCTAssertEqual(report.attempts.first?.status, .reported)
        XCTAssertEqual(report.attempts.first?.candidateCount, 2)
    }

    func testIPhoneLockdownDiscoverySkipsUSBDeviceWhenTrustProofFails() async {
        let commandSet = Self.lockdownCommandSet()
        let runner = MockIPhoneLockdownCommandRunner(responses: [
            .init(commandURL: commandSet.ideviceIDURL, arguments: ["-l"]): .init(exitStatus: 0, output: "locked-usb\n"),
            .init(commandURL: commandSet.ideviceInfoURL, arguments: ["-u", "locked-usb", "-k", "DeviceName"]): .init(
                exitStatus: 255,
                output: ""
            )
        ])
        let provider = IPhoneLockdownBatteryProvider(commandSet: commandSet, commandRunner: runner)

        let report = await provider.discoverUSBDevicesForEnrollment(now: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(report.devices.isEmpty)
        XCTAssertEqual(report.status, .unavailable)
        XCTAssertEqual(report.message, "No trusted USB iPhone found. Unlock the iPhone, tap Trust, and reconnect by USB.")
        XCTAssertEqual(report.attempts.first?.status, .unavailable)
    }

    func testIPhoneLockdownBatteryParserReadsAndClampsCapacity() {
        let reading = IPhoneLockdownBatteryProvider.parseBatteryReading(
            "BatteryCurrentCapacity: 155\nDeviceName: YiSungiPhone\n",
            fallbackDisplayName: "Fallback iPhone"
        )

        XCTAssertEqual(reading?.percent, 100)
        XCTAssertEqual(reading?.displayName, "YiSungiPhone")
    }

    func testTrustedIPhoneRegistryPersistsAllowlistedUDIDs() {
        let defaults = isolatedDefaults()
        let firstTrustedAt = Date(timeIntervalSince1970: 1_000)
        let secondTrustedAt = Date(timeIntervalSince1970: 2_000)
        let registry = TrustedIPhoneRegistry()
            .trusting(TrustedIPhone(udid: "00008030-001A", displayName: "YiSungiPhone", trustedAt: firstTrustedAt))
            .trusting(TrustedIPhone(udid: "00008110-00BB", displayName: "Work iPhone", trustedAt: secondTrustedAt))

        registry.save(to: defaults)
        let loaded = TrustedIPhoneRegistry.load(from: defaults)

        XCTAssertTrue(loaded.isTrusted(udid: "00008030-001A"))
        XCTAssertEqual(loaded.displayName(for: "00008110-00BB"), "Work iPhone")
        XCTAssertEqual(loaded.devices.first { $0.udid == "00008030-001A" }?.trustedAt, firstTrustedAt)
        XCTAssertEqual(loaded.devices.first { $0.udid == "00008110-00BB" }?.trustedAt, secondTrustedAt)
        XCTAssertEqual(loaded.devices, registry.devices)
    }

    func testTrustedIPhoneRegistryUpdatesExistingUDIDWithoutDuplicate() {
        let oldTrustedAt = Date(timeIntervalSince1970: 1_000)
        let newTrustedAt = Date(timeIntervalSince1970: 2_000)
        let registry = TrustedIPhoneRegistry()
            .trusting(TrustedIPhone(udid: "00008030-001A", displayName: "Old Name", trustedAt: oldTrustedAt))
            .trusting(TrustedIPhone(udid: "00008030-001A", displayName: "YiSungiPhone", trustedAt: newTrustedAt))

        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.displayName(for: "00008030-001A"), "YiSungiPhone")
        XCTAssertEqual(registry.devices.first?.trustedAt, newTrustedAt)
    }

    func testTrustedIPhoneRegistryRemovesUDID() {
        let trustedAt = Date(timeIntervalSince1970: 1_000)
        let registry = TrustedIPhoneRegistry()
            .trusting(TrustedIPhone(udid: "00008030-001A", displayName: "YiSungiPhone", trustedAt: trustedAt))
            .trusting(TrustedIPhone(udid: "00008110-00BB", displayName: "Work iPhone", trustedAt: trustedAt))
            .removing(udid: "00008030-001A")

        XCTAssertFalse(registry.isTrusted(udid: "00008030-001A"))
        XCTAssertTrue(registry.isTrusted(udid: "00008110-00BB"))
        XCTAssertEqual(registry.devices.map(\.udid), ["00008110-00BB"])
    }

    func testTrustedIPhoneRegistryLoadsEmptyFromCorruptData() {
        let defaults = isolatedDefaults()
        defaults.set(Data("not-json".utf8), forKey: TrustedIPhoneRegistry.storageKey)

        let registry = TrustedIPhoneRegistry.load(from: defaults)

        XCTAssertTrue(registry.devices.isEmpty)
    }

    func testBluetoothHIDUsageClassifiesKeychronAsKeyboard() {
        let hint = BluetoothDeviceScanner.hidKindHint(
            name: "Keychron K3 Max",
            transport: "Bluetooth Low Energy",
            primaryUsagePage: 1,
            primaryUsage: 6
        )

        XCTAssertEqual(hint, .keyboard)
    }

    func testUSBKeyboardBacklightDoesNotBecomeBatteryHubCandidate() {
        let hint = BluetoothDeviceScanner.hidKindHint(
            name: "Keyboard Backlight",
            transport: "USB",
            primaryUsagePage: 65280,
            primaryUsage: 15
        )

        XCTAssertEqual(hint, .keyboard)
        XCTAssertFalse(
            BluetoothDeviceScanner.shouldIncludeHIDCandidate(
                batteryPercent: nil,
                transport: "USB",
                kindHint: hint
            )
        )
    }

    func testAppleDeviceManagementBatteryPercentCreatesMagicKeyboardCandidate() throws {
        let candidate = try XCTUnwrap(
            BluetoothDeviceScanner.appleDeviceManagementCandidate(
                from: [
                    "Product": "吳郁庭 Fendy 的 Magic Keyboard",
                    "Transport": "Bluetooth Low Energy",
                    "DeviceAddress": "AA:BB:CC:DD:EE:FF",
                    "BatteryPercent": 89,
                    "PrimaryUsagePage": 1,
                    "PrimaryUsage": 6
                ]
            )
        )

        XCTAssertEqual(candidate.deviceID, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(candidate.displayName, "吳郁庭 Fendy 的 Magic Keyboard")
        XCTAssertEqual(candidate.batteryPercent, 89)
        XCTAssertEqual(candidate.kindHint, .keyboard)

        let snapshot = BluetoothBatteryResolver.snapshot(
            from: candidate,
            now: Date(timeIntervalSince1970: 50)
        )
        XCTAssertEqual(snapshot.percent, 89)
        XCTAssertEqual(snapshot.kind, .keyboard)
        XCTAssertEqual(snapshot.source, .ioRegistry)
    }

    func testAppleDeviceManagementFindsNestedBatteryPercent() throws {
        let candidate = try XCTUnwrap(
            BluetoothDeviceScanner.appleDeviceManagementCandidate(
                from: [
                    "Product": "吳郁庭 Fendy 的 Magic Trackpad",
                    "Transport": "Bluetooth",
                    "SerialNumber": "trackpad-serial",
                    "PrimaryUsagePage": 1,
                    "PrimaryUsage": 5,
                    "HIDEventServiceProperties": [
                        "DeviceManagement": [
                            "BatteryLevel": "88%"
                        ]
                    ]
                ]
            )
        )

        XCTAssertEqual(candidate.displayName, "吳郁庭 Fendy 的 Magic Trackpad")
        XCTAssertEqual(candidate.batteryPercent, 88)
        XCTAssertEqual(candidate.kindHint, .trackpad)
    }

    func testAppleDeviceManagementIgnoresDescriptorBatteryLevelMetadata() throws {
        let candidate = try XCTUnwrap(
            BluetoothDeviceScanner.appleDeviceManagementCandidate(
                from: [
                    "Product": "吳郁庭 Fendy 的 Magic Keyboard",
                    "Transport": "Bluetooth Low Energy",
                    "DeviceAddress": "AA:BB:CC:DD:EE:FF",
                    "PrimaryUsagePage": 1,
                    "PrimaryUsage": 6,
                    "Elements": [
                        [
                            "Name": "Battery Strength",
                            "BatteryLevel": 6
                        ]
                    ]
                ]
            )
        )

        XCTAssertNil(candidate.batteryPercent)
        XCTAssertEqual(candidate.kindHint, .keyboard)
    }

    func testAppleDeviceManagementSkipsBuiltInKeyboardTrackpad() {
        let candidate = BluetoothDeviceScanner.appleDeviceManagementCandidate(
            from: [
                "Product": "Apple Internal Keyboard / Trackpad",
                "Transport": "FIFO",
                "Built-In": true,
                "BatteryPercent": 100,
                "PrimaryUsagePage": 65280,
                "PrimaryUsage": 11
            ]
        )

        XCTAssertNil(candidate)
    }

    func testBLEBatteryReadPolicyScansKnownPeripheralsWhenPoweredOn() {
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .unknown), .wait)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .resetting), .wait)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .poweredOn), .scanKnownPeripherals)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .poweredOff), .finish)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .unauthorized), .finish)
    }

    func testBLEKnownDeviceFilterAcceptsKnownDeviceIDWithGenericPeripheralName() {
        let filter = BLEKnownDeviceFilter(
            knownCandidates: [
                BluetoothBatteryCandidate(
                    deviceID: "9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
                    displayName: "Keychron K3 Max",
                    transport: .hid,
                    batteryPercent: nil,
                    kindHint: .keyboard
                )
            ]
        )

        XCTAssertTrue(
            filter.contains(
                deviceID: "9d520bec-a95a-d7f0-1f4e-fdbad0d5d0f0",
                displayName: "Bluetooth Device"
            )
        )
    }

    func testBLEKnownDeviceFilterRejectsUnknownGenericPeripheralName() {
        let filter = BLEKnownDeviceFilter(
            knownCandidates: [
                BluetoothBatteryCandidate(
                    deviceID: "9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
                    displayName: "Keychron K3 Max",
                    transport: .hid,
                    batteryPercent: nil,
                    kindHint: .keyboard
                )
            ]
        )

        XCTAssertFalse(
            filter.contains(
                deviceID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                displayName: "Bluetooth Device"
            )
        )
    }

    func testBLEKnownDeviceFilterAcceptsKnownNonGenericName() {
        let filter = BLEKnownDeviceFilter(
            knownCandidates: [
                BluetoothBatteryCandidate(
                    deviceID: "9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
                    displayName: "Keychron K3 Max",
                    transport: .hid,
                    batteryPercent: nil,
                    kindHint: .keyboard
                )
            ]
        )

        XCTAssertTrue(
            filter.contains(
                deviceID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                displayName: "Keychron K3 Max"
            )
        )
    }

    func testBLEBatteryMergePreservesHIDDisplayNameForGenericPeripheralName() {
        let hidCandidate = BluetoothBatteryCandidate(
            deviceID: "9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
            displayName: "Keychron K3 Max",
            transport: .hid,
            batteryPercent: nil,
            kindHint: .keyboard
        )
        let bleCandidate = BluetoothBatteryCandidate(
            deviceID: "9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
            displayName: "Bluetooth Device",
            transport: .ble,
            batteryPercent: 95
        )

        let merged = BluetoothDeviceScanner.mergedCandidate(existing: hidCandidate, with: bleCandidate)

        XCTAssertEqual(merged.displayName, "Keychron K3 Max")
        XCTAssertEqual(merged.kindHint, .keyboard)
        XCTAssertEqual(merged.batteryPercent, 95)
        XCTAssertEqual(merged.transport, .ble)
    }

    func testSystemProfilerParserKeepsOnlyConnectedBatteryDevices() throws {
        let json = """
        {
          "SPBluetoothDataType" : [
            {
              "device_connected" : [
                {
                  "Keychron K3 Max" : {
                    "device_address" : "D1:B3:88:E2:67:CB",
                    "device_batteryLevelMain" : "100%",
                    "device_minorType" : "Keyboard"
                  }
                },
                {
                  "Kitchen" : {
                    "device_address" : "40:ED:CF:4E:B5:6A"
                  }
                }
              ],
              "device_not_connected" : [
                {
                  "Yi Sung’s AirPods Pro" : {
                    "device_address" : "7C:F3:4D:74:56:78",
                    "device_batteryLevelLeft" : "100%",
                    "device_batteryLevelRight" : "92%"
                  }
                }
              ]
            }
          ]
        }
        """

        let candidates = BluetoothDeviceScanner.parseSystemProfilerBluetoothData(Data(json.utf8))

        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.displayName, "Keychron K3 Max")
        XCTAssertEqual(candidate.batteryPercent, 100)

        let snapshot = BluetoothBatteryResolver.snapshot(
            from: candidate,
            now: Date(timeIntervalSince1970: 50)
        )
        XCTAssertEqual(snapshot.kind, .keyboard)
        XCTAssertEqual(snapshot.source, .systemProfiler)
    }

    func testSystemProfilerParserSplitsConnectedAirPodsBatteryComponents() {
        let json = """
        {
          "SPBluetoothDataType" : [
            {
              "device_connected" : [
                {
                  "Yi Sung’s AirPods Pro" : {
                    "device_address" : "7C:F3:4D:74:56:78",
                    "device_batteryLevelCase" : "70%",
                    "device_batteryLevelLeft" : "100%",
                    "device_batteryLevelRight" : "92%",
                    "device_minorType" : "Headphones"
                  }
                }
              ],
              "device_not_connected" : [
                {
                  "Old AirPods" : {
                    "device_address" : "AA:BB:CC:DD:EE:FF",
                    "device_batteryLevelCase" : "10%",
                    "device_batteryLevelLeft" : "11%",
                    "device_batteryLevelRight" : "12%",
                    "device_minorType" : "Headphones"
                  }
                }
              ]
            }
          ]
        }
        """

        let candidates = BluetoothDeviceScanner.parseSystemProfilerBluetoothData(Data(json.utf8))

        XCTAssertEqual(candidates.map(\.displayName), [
            "Yi Sung’s AirPods Pro Case",
            "Yi Sung’s AirPods Pro Left",
            "Yi Sung’s AirPods Pro Right"
        ])
        XCTAssertEqual(candidates.map(\.batteryPercent), [70, 100, 92])
        XCTAssertEqual(
            candidates.map { String(describing: BluetoothBatteryResolver.snapshot(from: $0, now: Date(timeIntervalSince1970: 50)).kind) },
            ["airPods", "airPods", "airPods"]
        )
    }

    func testSystemProfilerParserClassifiesMagicMouseTrackpadAndKeyboard() {
        let json = """
        {
          "SPBluetoothDataType" : [
            {
              "device_connected" : [
                {
                  "Magic Mouse" : {
                    "device_address" : "11:22:33:44:55:66",
                    "device_batteryLevelMain" : "50%",
                    "device_minorType" : "Mouse"
                  }
                },
                {
                  "Magic Trackpad" : {
                    "device_address" : "22:33:44:55:66:77",
                    "device_batteryLevelMain" : "90%",
                    "device_minorType" : "Trackpad"
                  }
                },
                {
                  "Magic Keyboard" : {
                    "device_address" : "33:44:55:66:77:88",
                    "device_batteryLevelMain" : "42%",
                    "device_minorType" : "Keyboard"
                  }
                }
              ]
            }
          ]
        }
        """

        let candidates = BluetoothDeviceScanner.parseSystemProfilerBluetoothData(Data(json.utf8))
        let kinds = candidates.map {
            String(describing: BluetoothBatteryResolver.snapshot(from: $0, now: Date(timeIntervalSince1970: 50)).kind)
        }

        XCTAssertEqual(candidates.map(\.displayName), ["Magic Mouse", "Magic Trackpad", "Magic Keyboard"])
        XCTAssertEqual(kinds, ["mouse", "trackpad", "keyboard"])
    }
}

private struct IPhoneLockdownInvocation: Hashable, Sendable {
    let commandURL: URL
    let arguments: [String]
}

private final class MockIPhoneLockdownCommandRunner: IPhoneLockdownCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [IPhoneLockdownInvocation: IPhoneLockdownCommandResult]
    private var recordedInvocations: [IPhoneLockdownInvocation] = []

    var invocations: [IPhoneLockdownInvocation] {
        lock.withLock { recordedInvocations }
    }

    init(responses: [IPhoneLockdownInvocation: IPhoneLockdownCommandResult] = [:]) {
        self.responses = responses
    }

    func run(commandURL: URL, arguments: [String], timeout: TimeInterval) async -> IPhoneLockdownCommandResult {
        let invocation = IPhoneLockdownInvocation(commandURL: commandURL, arguments: arguments)
        lock.withLock {
            recordedInvocations.append(invocation)
        }
        return responses[invocation] ?? IPhoneLockdownCommandResult(
            exitStatus: 1,
            output: "",
            errorOutput: "No mock response for \(commandURL.path) \(arguments.joined(separator: " "))"
        )
    }
}
