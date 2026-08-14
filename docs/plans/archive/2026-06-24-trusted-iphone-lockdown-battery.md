# Trusted iPhone Lockdown Battery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AirBuddy/AirBattery-style trusted iPhone battery reading without an iPhone companion app and without admitting random BLE iPhone rows.

**Architecture:** Add a local trusted iPhone registry keyed by iOS UDID, add an iOS lockdown provider backed by external `idevice_id` and `ideviceinfo` commands, wire the provider into the existing refresh pipeline, and surface enrollment/diagnostics in Settings. Keep Bluetooth input devices on the existing path, but explicitly block BLE iPhone candidates from snapshot creation.

**Tech Stack:** Swift 6, SwiftUI, UserDefaults, XCTest, XcodeGen, external libimobiledevice command-line tools (`idevice_id`, `ideviceinfo`).

---

## File Structure

- Create: `Beacon/Mac/TrustedIPhoneRegistry.swift`
  - Owns the Beacon-local iPhone allowlist stored in UserDefaults.
- Create: `Beacon/Mac/IPhoneLockdownBatteryProvider.swift`
  - Discovers command-line tools, lists USB/network lockdown devices, reads battery payloads, and converts allowlisted devices into `BluetoothBatteryCandidate` values.
- Modify: `Beacon/Mac/BluetoothBatteryResolver.swift`
  - Adds `.lockdownNetwork` transport, blocks BLE iPhones in report creation, and gives trusted iPhones UDID-based IDs.
- Modify: `Beacon/Mac/BluetoothDeviceScanner.swift`
  - Calls the lockdown provider and merges only trusted iPhone candidates.
- Modify: `Beacon/Shared/BatterySnapshotStore.swift`
  - Adds removal by device ID so Forget removes stale trusted iPhone snapshots immediately.
- Modify: `Beacon/Mac/BeaconMacApp.swift`
  - Publishes trusted iPhone registry state and enrollment result from the model.
- Modify: `Beacon/Mac/BeaconSettingsWindowController.swift`
  - Passes trusted iPhone state, diagnostics, and enrollment callbacks to Settings.
- Modify: `Beacon/Mac/BeaconSettingsView.swift`
  - Adds iPhone setup and diagnostics UI in the Devices pane.
- Modify: `Beacon/Mac/BeaconSettingsSupportViews.swift`
  - Adds reusable trusted iPhone setup/status views.
- Modify: `Beacon/Mac/DeviceBatteryRow.swift`
  - Labels `.ideviceInfo` as `Trusted iPhone`.
- Modify: `BeaconTests/BluetoothBatteryResolverTests.swift`
  - Tests provider parsing, allowlist filtering, missing command diagnostics, BLE iPhone suppression, and UDID-based IDs.
- Modify: `BeaconTests/BatterySnapshotStoreTests.swift`
  - Tests removal by device ID.
- Modify: `BeaconTests/DeviceListPresentationTests.swift`
  - Tests label and Settings rendering.
- Inspect: `project.yml`
  - Existing source directories already include `Beacon/Mac` and `BeaconTests`, so no target changes are required.
- Modify: `Beacon.xcodeproj/project.pbxproj`
  - Regenerate with `xcodegen generate` after creating new source files.

## Task 1: Trusted iPhone Registry and Store Removal

**Files:**
- Create: `Beacon/Mac/TrustedIPhoneRegistry.swift`
- Modify: `Beacon/Shared/BatterySnapshotStore.swift`
- Test: `BeaconTests/BluetoothBatteryResolverTests.swift`
- Test: `BeaconTests/BatterySnapshotStoreTests.swift`

- [ ] **Step 1: Write failing registry tests**

Append these tests to `BeaconTests/BluetoothBatteryResolverTests.swift`:

```swift
func testTrustedIPhoneRegistryPersistsAllowlistedUDIDs() throws {
    let suiteName = "BeaconTests.TrustedIPhoneRegistry.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let trustedAt = Date(timeIntervalSince1970: 100)
    let registry = TrustedIPhoneRegistry().trusting(
        TrustedIPhone(
            udid: "00008110-001234567890801E",
            displayName: "Isaac's iPhone",
            trustedAt: trustedAt
        )
    )
    registry.save(to: defaults)

    let loaded = TrustedIPhoneRegistry.load(from: defaults)
    XCTAssertTrue(loaded.isTrusted(udid: "00008110-001234567890801E"))
    XCTAssertEqual(loaded.displayName(for: "00008110-001234567890801E"), "Isaac's iPhone")
    XCTAssertEqual(loaded.devices.first?.trustedAt, trustedAt)
}

func testTrustedIPhoneRegistryUpdatesExistingUDIDWithoutDuplicating() {
    let first = TrustedIPhone(
        udid: "00008110-001234567890801E",
        displayName: "Old Name",
        trustedAt: Date(timeIntervalSince1970: 100)
    )
    let second = TrustedIPhone(
        udid: "00008110-001234567890801E",
        displayName: "Isaac's iPhone",
        trustedAt: Date(timeIntervalSince1970: 200)
    )

    let registry = TrustedIPhoneRegistry()
        .trusting(first)
        .trusting(second)

    XCTAssertEqual(registry.devices.count, 1)
    XCTAssertEqual(registry.devices[0].displayName, "Isaac's iPhone")
    XCTAssertEqual(registry.devices[0].trustedAt, Date(timeIntervalSince1970: 200))
}
```

Append this test to `BeaconTests/BatterySnapshotStoreTests.swift`:

```swift
func testRemoveDeviceIDsDropsTrustedIPhoneSnapshot() {
    var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 500) })
    store.merge([
        BatterySnapshot(
            deviceID: "trusted-iphone-00008110-001234567890801E",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 80,
            chargeState: .unknown,
            source: .ideviceInfo,
            updatedAt: Date(timeIntervalSince1970: 400)
        ),
        BatterySnapshot(
            deviceID: "bluetooth-keyboard",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 77,
            chargeState: .unknown,
            source: .ioRegistry,
            updatedAt: Date(timeIntervalSince1970: 400)
        )
    ])

    store.removeDeviceIDs(["trusted-iphone-00008110-001234567890801E"])

    XCTAssertEqual(store.snapshots.map(\.deviceID), ["bluetooth-keyboard"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/BluetoothBatteryResolverTests -only-testing:BeaconTests/BatterySnapshotStoreTests
```

Expected: FAIL with missing `TrustedIPhone`, missing `TrustedIPhoneRegistry`, and missing `removeDeviceIDs`.

- [ ] **Step 3: Add registry implementation**

Create `Beacon/Mac/TrustedIPhoneRegistry.swift`:

```swift
import Foundation

public struct TrustedIPhone: Codable, Equatable, Identifiable, Sendable {
    public var id: String { udid }
    public let udid: String
    public let displayName: String
    public let trustedAt: Date

    public init(udid: String, displayName: String, trustedAt: Date) {
        self.udid = udid
        self.displayName = displayName
        self.trustedAt = trustedAt
    }
}

public struct TrustedIPhoneRegistry: Equatable, Sendable {
    public static let defaultsKey = "Beacon.trustedIPhones"

    public let devices: [TrustedIPhone]

    public init(devices: [TrustedIPhone] = []) {
        self.devices = devices.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> TrustedIPhoneRegistry {
        guard let data = defaults.data(forKey: defaultsKey),
              let devices = try? JSONDecoder().decode([TrustedIPhone].self, from: data)
        else {
            return TrustedIPhoneRegistry()
        }
        return TrustedIPhoneRegistry(devices: devices)
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    public func isTrusted(udid: String) -> Bool {
        devices.contains { $0.udid == udid }
    }

    public func displayName(for udid: String) -> String? {
        devices.first { $0.udid == udid }?.displayName
    }

    public func trusting(_ device: TrustedIPhone) -> TrustedIPhoneRegistry {
        var next = devices.filter { $0.udid != device.udid }
        next.append(device)
        return TrustedIPhoneRegistry(devices: next)
    }

    public func forgetting(udid: String) -> TrustedIPhoneRegistry {
        TrustedIPhoneRegistry(devices: devices.filter { $0.udid != udid })
    }
}
```

Modify `Beacon/Shared/BatterySnapshotStore.swift` by adding this method after `merge(_:)`:

```swift
public mutating func removeDeviceIDs(_ deviceIDs: Set<String>) {
    snapshotsByID = snapshotsByID.filter { id, _ in
        !deviceIDs.contains(id)
    }
}
```

- [ ] **Step 4: Regenerate project**

Run:

```bash
xcodegen generate
```

Expected: `Beacon.xcodeproj/project.pbxproj` includes `TrustedIPhoneRegistry.swift`.

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/BluetoothBatteryResolverTests -only-testing:BeaconTests/BatterySnapshotStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Beacon/Mac/TrustedIPhoneRegistry.swift Beacon/Shared/BatterySnapshotStore.swift BeaconTests/BluetoothBatteryResolverTests.swift BeaconTests/BatterySnapshotStoreTests.swift Beacon.xcodeproj/project.pbxproj
git commit -m "feat: add trusted iPhone registry"
```

## Task 2: Lockdown Provider With Allowlist Filtering

**Files:**
- Create: `Beacon/Mac/IPhoneLockdownBatteryProvider.swift`
- Test: `BeaconTests/BluetoothBatteryResolverTests.swift`

- [ ] **Step 1: Write failing provider tests**

Append these helpers and tests to `BeaconTests/BluetoothBatteryResolverTests.swift`:

```swift
private struct FakeIPhoneLockdownRunner: IPhoneLockdownCommandRunning {
    let outputs: [String: IPhoneLockdownCommandResult]

    func run(commandURL: URL, arguments: [String], timeout: TimeInterval) -> IPhoneLockdownCommandResult {
        let key = ([commandURL.lastPathComponent] + arguments).joined(separator: " ")
        return outputs[key] ?? IPhoneLockdownCommandResult(status: 1, output: "", timedOut: false)
    }
}

func testIPhoneLockdownProviderReadsOnlyAllowlistedDevices() async throws {
    let commandSet = IPhoneLockdownCommandSet(
        ideviceID: URL(fileURLWithPath: "/usr/local/bin/idevice_id"),
        ideviceInfo: URL(fileURLWithPath: "/usr/local/bin/ideviceinfo")
    )
    let registry = TrustedIPhoneRegistry(devices: [
        TrustedIPhone(
            udid: "00008110-001234567890801E",
            displayName: "Isaac's iPhone",
            trustedAt: Date(timeIntervalSince1970: 10)
        )
    ])
    let runner = FakeIPhoneLockdownRunner(outputs: [
        "idevice_id -l": .init(status: 0, output: "00008110-001234567890801E\n00008120-00BADBADBADBAD00\n", timedOut: false),
        "idevice_id -n": .init(status: 0, output: "", timedOut: false),
        "ideviceinfo -u 00008110-001234567890801E -k DeviceName": .init(status: 0, output: "Isaac's iPhone\n", timedOut: false),
        "ideviceinfo -u 00008110-001234567890801E -q com.apple.mobile.battery": .init(status: 0, output: "BatteryCurrentCapacity: 82\nBatteryIsCharging: false\n", timedOut: false)
    ])

    let report = await IPhoneLockdownBatteryProvider.readCandidates(
        registry: registry,
        commandSet: commandSet,
        runner: runner,
        now: Date(timeIntervalSince1970: 50)
    )

    XCTAssertEqual(report.candidates.count, 1)
    XCTAssertEqual(report.candidates[0].deviceID, "00008110-001234567890801E")
    XCTAssertEqual(report.candidates[0].displayName, "Isaac's iPhone")
    XCTAssertEqual(report.candidates[0].transport, .usb)
    XCTAssertEqual(report.candidates[0].batteryPercent, 82)
    XCTAssertEqual(report.attempt.status, .reported)
    XCTAssertEqual(report.attempt.candidateCount, 1)
}

func testIPhoneLockdownProviderReadsNetworkAllowlistedDevice() async throws {
    let commandSet = IPhoneLockdownCommandSet(
        ideviceID: URL(fileURLWithPath: "/usr/local/bin/idevice_id"),
        ideviceInfo: URL(fileURLWithPath: "/usr/local/bin/ideviceinfo")
    )
    let registry = TrustedIPhoneRegistry(devices: [
        TrustedIPhone(
            udid: "00008110-001234567890801E",
            displayName: "Isaac's iPhone",
            trustedAt: Date(timeIntervalSince1970: 10)
        )
    ])
    let runner = FakeIPhoneLockdownRunner(outputs: [
        "idevice_id -l": .init(status: 0, output: "", timedOut: false),
        "idevice_id -n": .init(status: 0, output: "00008110-001234567890801E\n", timedOut: false),
        "ideviceinfo -n -u 00008110-001234567890801E -k DeviceName": .init(status: 0, output: "Isaac's iPhone\n", timedOut: false),
        "ideviceinfo -n -u 00008110-001234567890801E -q com.apple.mobile.battery": .init(status: 0, output: "BatteryCurrentCapacity: 65\nBatteryIsCharging: true\n", timedOut: false)
    ])

    let report = await IPhoneLockdownBatteryProvider.readCandidates(
        registry: registry,
        commandSet: commandSet,
        runner: runner,
        now: Date(timeIntervalSince1970: 50)
    )

    XCTAssertEqual(report.candidates.map(\.transport), [.lockdownNetwork])
    XCTAssertEqual(report.candidates.map(\.batteryPercent), [65])
}

func testIPhoneLockdownProviderReportsMissingCommands() async {
    let report = await IPhoneLockdownBatteryProvider.readCandidates(
        registry: TrustedIPhoneRegistry(),
        commandSet: nil,
        runner: FakeIPhoneLockdownRunner(outputs: [:]),
        now: Date(timeIntervalSince1970: 50)
    )

    XCTAssertTrue(report.candidates.isEmpty)
    XCTAssertEqual(report.attempt.provider, .ideviceInfo)
    XCTAssertEqual(report.attempt.status, .commandMissing)
    XCTAssertEqual(report.attempt.message, "idevice_id or ideviceinfo command not found")
}

func testIPhoneLockdownDiscoveryListsUSBDevicesForEnrollment() async throws {
    let commandSet = IPhoneLockdownCommandSet(
        ideviceID: URL(fileURLWithPath: "/usr/local/bin/idevice_id"),
        ideviceInfo: URL(fileURLWithPath: "/usr/local/bin/ideviceinfo")
    )
    let runner = FakeIPhoneLockdownRunner(outputs: [
        "idevice_id -l": .init(status: 0, output: "00008110-001234567890801E\n", timedOut: false),
        "ideviceinfo -u 00008110-001234567890801E -k DeviceName": .init(status: 0, output: "Isaac's iPhone\n", timedOut: false)
    ])

    let result = await IPhoneLockdownBatteryProvider.discoverUSBTrustedDevices(
        commandSet: commandSet,
        runner: runner,
        now: Date(timeIntervalSince1970: 50)
    )

    XCTAssertEqual(result.devices, [
        TrustedIPhone(
            udid: "00008110-001234567890801E",
            displayName: "Isaac's iPhone",
            trustedAt: Date(timeIntervalSince1970: 50)
        )
    ])
    XCTAssertEqual(result.status, .reported)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/BluetoothBatteryResolverTests
```

Expected: FAIL with missing lockdown provider types and missing `.lockdownNetwork`.

- [ ] **Step 3: Add lockdown provider**

Create `Beacon/Mac/IPhoneLockdownBatteryProvider.swift`:

```swift
import Foundation

public enum IPhoneLockdownConnection: String, Equatable, Sendable {
    case usb
    case network
}

public struct IPhoneLockdownCommandSet: Equatable, Sendable {
    public let ideviceID: URL
    public let ideviceInfo: URL

    public init(ideviceID: URL, ideviceInfo: URL) {
        self.ideviceID = ideviceID
        self.ideviceInfo = ideviceInfo
    }
}

public struct IPhoneLockdownCommandResult: Equatable, Sendable {
    public let status: Int32
    public let output: String
    public let timedOut: Bool

    public init(status: Int32, output: String, timedOut: Bool) {
        self.status = status
        self.output = output
        self.timedOut = timedOut
    }
}

public protocol IPhoneLockdownCommandRunning: Sendable {
    func run(commandURL: URL, arguments: [String], timeout: TimeInterval) -> IPhoneLockdownCommandResult
}

public struct IPhoneLockdownBatteryReport: Sendable {
    public let candidates: [BluetoothBatteryCandidate]
    public let attempt: BatteryProviderAttempt
}

public struct IPhoneLockdownDiscoveryReport: Sendable {
    public let devices: [TrustedIPhone]
    public let status: BatteryReadStatus
    public let message: String
}

public struct ProcessIPhoneLockdownCommandRunner: IPhoneLockdownCommandRunning {
    public init() {}

    public func run(commandURL: URL, arguments: [String], timeout: TimeInterval) -> IPhoneLockdownCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = commandURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        var didTimeOut = false
        let timeoutWorkItem = DispatchWorkItem {
            guard process.isRunning else { return }
            didTimeOut = true
            process.terminate()
        }

        do {
            try process.run()
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWorkItem
            )
            process.waitUntilExit()
        } catch {
            timeoutWorkItem.cancel()
            return IPhoneLockdownCommandResult(status: -1, output: "", timedOut: false)
        }

        timeoutWorkItem.cancel()
        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return IPhoneLockdownCommandResult(
            status: process.terminationStatus,
            output: output,
            timedOut: didTimeOut
        )
    }
}

public enum IPhoneLockdownCommandLocator {
    private static let directories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    public static func locate(fileManager: FileManager = .default) -> IPhoneLockdownCommandSet? {
        guard let ideviceID = executable(named: "idevice_id", fileManager: fileManager),
              let ideviceInfo = executable(named: "ideviceinfo", fileManager: fileManager)
        else {
            return nil
        }
        return IPhoneLockdownCommandSet(ideviceID: ideviceID, ideviceInfo: ideviceInfo)
    }

    private static func executable(named name: String, fileManager: FileManager) -> URL? {
        directories
            .map { "\($0)/\(name)" }
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }
}

public enum IPhoneLockdownBatteryProvider {
    private static let timeout: TimeInterval = 3

    public static func readCandidates(
        registry: TrustedIPhoneRegistry = .load(),
        commandSet: IPhoneLockdownCommandSet? = IPhoneLockdownCommandLocator.locate(),
        runner: IPhoneLockdownCommandRunning = ProcessIPhoneLockdownCommandRunner(),
        now: Date = Date()
    ) async -> IPhoneLockdownBatteryReport {
        guard let commandSet else {
            return IPhoneLockdownBatteryReport(
                candidates: [],
                attempt: BatteryProviderAttempt(
                    provider: .ideviceInfo,
                    status: .commandMissing,
                    candidateCount: 0,
                    message: "idevice_id or ideviceinfo command not found",
                    attemptedAt: now
                )
            )
        }

        return await Task.detached(priority: .utility) {
            let listed = listedDevices(commandSet: commandSet, runner: runner)
            let trusted = listed.filter { registry.isTrusted(udid: $0.udid) }
            let candidates = trusted.compactMap { listedDevice -> BluetoothBatteryCandidate? in
                guard let percent = batteryPercent(
                    udid: listedDevice.udid,
                    connection: listedDevice.connection,
                    commandSet: commandSet,
                    runner: runner
                ) else {
                    return nil
                }
                let displayName = deviceName(
                    udid: listedDevice.udid,
                    connection: listedDevice.connection,
                    commandSet: commandSet,
                    runner: runner
                ) ?? registry.displayName(for: listedDevice.udid) ?? "iPhone"

                return BluetoothBatteryCandidate(
                    deviceID: listedDevice.udid,
                    displayName: displayName,
                    transport: listedDevice.connection == .network ? .lockdownNetwork : .usb,
                    batteryPercent: percent,
                    kindHint: .iPhone,
                    connectionState: .connected
                )
            }

            let status: BatteryReadStatus
            if candidates.isEmpty {
                status = listed.isEmpty ? .noReport : .noReport
            } else {
                status = .reported
            }

            return IPhoneLockdownBatteryReport(
                candidates: candidates,
                attempt: BatteryProviderAttempt(
                    provider: .ideviceInfo,
                    status: status,
                    candidateCount: candidates.count,
                    message: "iOS lockdown listed \(listed.count) devices, \(trusted.count) trusted, \(candidates.count) battery reports",
                    attemptedAt: now
                )
            )
        }.value
    }

    public static func discoverUSBTrustedDevices(
        commandSet: IPhoneLockdownCommandSet? = IPhoneLockdownCommandLocator.locate(),
        runner: IPhoneLockdownCommandRunning = ProcessIPhoneLockdownCommandRunner(),
        now: Date = Date()
    ) async -> IPhoneLockdownDiscoveryReport {
        guard let commandSet else {
            return IPhoneLockdownDiscoveryReport(
                devices: [],
                status: .commandMissing,
                message: "idevice_id or ideviceinfo command not found"
            )
        }

        return await Task.detached(priority: .utility) {
            let usbDevices = listUDIDs(
                connection: .usb,
                commandSet: commandSet,
                runner: runner
            )
            let devices = usbDevices.map { udid in
                TrustedIPhone(
                    udid: udid,
                    displayName: deviceName(
                        udid: udid,
                        connection: .usb,
                        commandSet: commandSet,
                        runner: runner
                    ) ?? "iPhone",
                    trustedAt: now
                )
            }

            return IPhoneLockdownDiscoveryReport(
                devices: devices,
                status: devices.isEmpty ? .noReport : .reported,
                message: devices.isEmpty
                    ? "No trusted USB iPhone found"
                    : "Added \(devices.count) trusted iPhone devices"
            )
        }.value
    }

    private struct ListedDevice: Sendable {
        let udid: String
        let connection: IPhoneLockdownConnection
    }

    private static func listedDevices(
        commandSet: IPhoneLockdownCommandSet,
        runner: IPhoneLockdownCommandRunning
    ) -> [ListedDevice] {
        let usb = listUDIDs(connection: .usb, commandSet: commandSet, runner: runner)
            .map { ListedDevice(udid: $0, connection: .usb) }
        let network = listUDIDs(connection: .network, commandSet: commandSet, runner: runner)
            .filter { networkUDID in !usb.contains { $0.udid == networkUDID } }
            .map { ListedDevice(udid: $0, connection: .network) }
        return usb + network
    }

    private static func listUDIDs(
        connection: IPhoneLockdownConnection,
        commandSet: IPhoneLockdownCommandSet,
        runner: IPhoneLockdownCommandRunning
    ) -> [String] {
        let arguments = connection == .network ? ["-n"] : ["-l"]
        let result = runner.run(commandURL: commandSet.ideviceID, arguments: arguments, timeout: timeout)
        guard result.status == 0, !result.timedOut else { return [] }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func deviceName(
        udid: String,
        connection: IPhoneLockdownConnection,
        commandSet: IPhoneLockdownCommandSet,
        runner: IPhoneLockdownCommandRunning
    ) -> String? {
        let result = runner.run(
            commandURL: commandSet.ideviceInfo,
            arguments: baseArguments(udid: udid, connection: connection) + ["-k", "DeviceName"],
            timeout: timeout
        )
        guard result.status == 0, !result.timedOut else { return nil }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func batteryPercent(
        udid: String,
        connection: IPhoneLockdownConnection,
        commandSet: IPhoneLockdownCommandSet,
        runner: IPhoneLockdownCommandRunning
    ) -> Int? {
        let result = runner.run(
            commandURL: commandSet.ideviceInfo,
            arguments: baseArguments(udid: udid, connection: connection) + ["-q", "com.apple.mobile.battery"],
            timeout: timeout
        )
        guard result.status == 0, !result.timedOut else { return nil }
        return parseBatteryPercent(result.output)
    }

    private static func baseArguments(udid: String, connection: IPhoneLockdownConnection) -> [String] {
        switch connection {
        case .usb:
            return ["-u", udid]
        case .network:
            return ["-n", "-u", udid]
        }
    }

    public static func parseBatteryPercent(_ output: String) -> Int? {
        let values = keyValuePairs(from: output)
        let percent = [
            "batterycurrentcapacity",
            "batterycurrentcapacitypercent",
            "batterypercent",
            "batterylevel",
            "battery level"
        ]
        .compactMap { values[$0].flatMap(percentValue) }
        .first
        return percent.map { max(0, min(100, $0)) }
    }

    private static func keyValuePairs(from output: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let separatorIndex = line.firstIndex(of: ":") ?? line.firstIndex(of: "=")
            guard let separatorIndex else { continue }
            let key = line[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }
        return values
    }

    private static func percentValue(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(
            in: CharacterSet(charactersIn: "%").union(.whitespacesAndNewlines)
        )
        return Int(trimmed)
    }
}
```

- [ ] **Step 4: Add network transport case**

Modify `Beacon/Mac/BluetoothBatteryResolver.swift`:

```swift
public enum BluetoothTransport: Equatable, Sendable {
    case hid
    case ble
    case classic
    case systemProfiler
    case usb
    case lockdownNetwork
    case unknown
}
```

In `source(for:)`, add:

```swift
case .usb, .lockdownNetwork: return .ideviceInfo
```

- [ ] **Step 5: Regenerate project**

Run:

```bash
xcodegen generate
```

Expected: `Beacon.xcodeproj/project.pbxproj` includes `IPhoneLockdownBatteryProvider.swift`.

- [ ] **Step 6: Run provider tests**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/BluetoothBatteryResolverTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Beacon/Mac/IPhoneLockdownBatteryProvider.swift Beacon/Mac/BluetoothBatteryResolver.swift BeaconTests/BluetoothBatteryResolverTests.swift Beacon.xcodeproj/project.pbxproj
git commit -m "feat: add iOS lockdown battery provider"
```

## Task 3: Wire Provider and Suppress BLE iPhones

**Files:**
- Modify: `Beacon/Mac/BluetoothBatteryResolver.swift`
- Modify: `Beacon/Mac/BluetoothDeviceScanner.swift`
- Test: `BeaconTests/BluetoothBatteryResolverTests.swift`

- [ ] **Step 1: Write failing resolver tests**

Append these tests to `BeaconTests/BluetoothBatteryResolverTests.swift`:

```swift
func testResolverReportDropsBLEIPhoneCandidates() {
    let report = BluetoothBatteryResolver.report(
        from: BluetoothCandidateScanReport(
            candidates: [
                BluetoothBatteryCandidate(
                    deviceID: "16AE09F1-3309-CF7D-793F-80F1EE3B4933",
                    displayName: "Stranger's iPhone",
                    transport: .ble,
                    batteryPercent: 91
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
        ),
        now: Date(timeIntervalSince1970: 50)
    )

    XCTAssertTrue(report.snapshots.isEmpty)
    XCTAssertEqual(report.diagnostics.snapshotCount, 0)
}

func testTrustedIPhoneSnapshotUsesUDIDIdentity() {
    let snapshot = BluetoothBatteryResolver.snapshot(
        from: BluetoothBatteryCandidate(
            deviceID: "00008110-001234567890801E",
            displayName: "Isaac's iPhone",
            transport: .lockdownNetwork,
            batteryPercent: 64,
            kindHint: .iPhone
        ),
        now: Date(timeIntervalSince1970: 50)
    )

    XCTAssertEqual(snapshot.deviceID, "trusted-iphone-00008110-001234567890801E")
    XCTAssertEqual(snapshot.kind, .iPhone)
    XCTAssertEqual(snapshot.source, .ideviceInfo)
    XCTAssertEqual(snapshot.provider, .ideviceInfo)
    XCTAssertEqual(snapshot.confidence, .high)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/BluetoothBatteryResolverTests
```

Expected: FAIL because BLE iPhones are still emitted or trusted iPhone IDs still use display-name identity.

- [ ] **Step 3: Filter BLE iPhones in resolver reports**

Modify `Beacon/Mac/BluetoothBatteryResolver.swift`:

```swift
static func report(from scanReport: BluetoothCandidateScanReport, now: Date) -> BluetoothBatteryReadReport {
    let snapshots = scanReport.candidates
        .filter { !isUnsupportedBLEIPhone($0) }
        .map {
            Self.snapshot(from: $0, now: now)
        }
    return BluetoothBatteryReadReport(
        snapshots: snapshots,
        diagnostics: BatteryRefreshDiagnostics(
            attempts: scanReport.attempts,
            refreshedAt: now,
            snapshotCount: snapshots.count
        )
    )
}

private static func isUnsupportedBLEIPhone(_ candidate: BluetoothBatteryCandidate) -> Bool {
    kind(for: candidate) == .iPhone && candidate.transport == .ble
}
```

Modify `stableDeviceID(for:kind:)` in the same file:

```swift
private static func stableDeviceID(for candidate: BluetoothBatteryCandidate, kind: DeviceKind) -> String {
    if kind == .iPhone,
       candidate.transport == .usb || candidate.transport == .lockdownNetwork {
        return "trusted-iphone-\(candidate.deviceID)"
    }
    if kind == .iPhone, candidate.transport == .ble {
        return "bluetooth-iphone-\(candidate.displayName.stableBluetoothIdentitySlug)"
    }
    return "bluetooth-\(candidate.deviceID)"
}
```

- [ ] **Step 4: Replace the old USB provider call**

In `Beacon/Mac/BluetoothDeviceScanner.swift`, replace:

```swift
let usb = await IPhoneUSBBatteryProvider.readCandidate(now: now)
Self.logger.info("USB iPhone read returned \(usb.attempt.candidateCount) battery candidates")
attempts.append(usb.attempt)
if let candidate = usb.candidate {
    candidates.upsert(candidate)
}
```

with:

```swift
let trustedIPhones = await IPhoneLockdownBatteryProvider.readCandidates(now: now)
Self.logger.info("Trusted iPhone read returned \(trustedIPhones.attempt.candidateCount) battery candidates")
attempts.append(trustedIPhones.attempt)
for candidate in trustedIPhones.candidates {
    candidates.upsert(candidate)
}
```

Remove `IPhoneUSBBatteryReading` and `IPhoneUSBBatteryProvider` from `Beacon/Mac/BluetoothBatteryResolver.swift`. Their parsing coverage is replaced by `IPhoneLockdownBatteryProvider.parseBatteryPercent(_:)` tests.

- [ ] **Step 5: Update existing USB tests**

In `BeaconTests/BluetoothBatteryResolverTests.swift`, remove `testIPhoneUSBBatteryParserReadsCapacityAndDeviceName` and `testIPhoneUSBBatteryCandidateCreatesUSBProviderSnapshot`.

Add:

```swift
func testIPhoneLockdownBatteryParserReadsCapacity() {
    let output = """
    BatteryCurrentCapacity: 77
    BatteryIsCharging: false
    """

    XCTAssertEqual(IPhoneLockdownBatteryProvider.parseBatteryPercent(output), 77)
}
```

- [ ] **Step 6: Run resolver tests**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/BluetoothBatteryResolverTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Beacon/Mac/BluetoothBatteryResolver.swift Beacon/Mac/BluetoothDeviceScanner.swift BeaconTests/BluetoothBatteryResolverTests.swift
git commit -m "fix: only show trusted iPhone battery reports"
```

## Task 4: Enrollment, Forget, and Diagnostics in Settings

**Files:**
- Modify: `Beacon/Mac/BeaconMacApp.swift`
- Modify: `Beacon/Mac/BeaconSettingsWindowController.swift`
- Modify: `Beacon/Mac/BeaconSettingsView.swift`
- Modify: `Beacon/Mac/BeaconSettingsSupportViews.swift`
- Test: `BeaconTests/DeviceListPresentationTests.swift`

- [ ] **Step 1: Write failing Settings tests**

Append these tests to `BeaconTests/DeviceListPresentationTests.swift`:

```swift
func testBatteryProviderLabelUsesTrustedIPhoneCopy() {
    XCTAssertEqual(
        batteryProviderLabel(source: .ideviceInfo, provider: .ideviceInfo),
        "Trusted iPhone"
    )
}

@MainActor
func testAddDeviceGuideRendersIPhoneSetupRow() throws {
    let view = AddDeviceGuideView(
        trustedIPhoneEnrollmentResult: nil,
        onTrustConnectedIPhone: {},
        onOpenBluetoothSettings: {},
        onDismiss: {}
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
    hostingView.layoutSubtreeIfNeeded()

    let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
    XCTAssertNotNil(bitmap)

    guard let bitmap else { return }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-add-device-guide-iphone-render.png")
    let pngData = bitmap.representation(using: .png, properties: [:])
    XCTAssertNotNil(pngData)

    try pngData?.write(to: outputURL, options: .atomic)
    XCTAssertGreaterThan((pngData ?? Data()).count, 20_000)
}

@MainActor
func testSettingsWindowRendersDiagnostics() throws {
    let view = BeaconSettingsView(
        snapshots: [],
        latestRefreshDiagnostics: BatteryRefreshDiagnostics(
            attempts: [
                BatteryProviderAttempt(
                    provider: .ideviceInfo,
                    status: .commandMissing,
                    candidateCount: 0,
                    message: "idevice_id or ideviceinfo command not found",
                    attemptedAt: Date(timeIntervalSince1970: 50)
                )
            ],
            refreshedAt: Date(timeIntervalSince1970: 50),
            snapshotCount: 0
        ),
        trustedIPhones: [],
        trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport(
            devices: [],
            status: .commandMissing,
            message: "idevice_id or ideviceinfo command not found"
        ),
        onRefresh: {}
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
    hostingView.layoutSubtreeIfNeeded()

    let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
    XCTAssertNotNil(bitmap)

    guard let bitmap else { return }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-settings-diagnostics-render.png")
    let pngData = bitmap.representation(using: .png, properties: [:])
    XCTAssertNotNil(pngData)

    try pngData?.write(to: outputURL, options: .atomic)
    XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/DeviceListPresentationTests
```

Expected: FAIL with missing initializer parameters and old provider label copy.

- [ ] **Step 3: Add model state and actions**

Modify `Beacon/Mac/BeaconMacApp.swift` inside `BeaconModel`:

```swift
@Published private(set) var trustedIPhoneRegistry = TrustedIPhoneRegistry.load()
@Published private(set) var trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport?
```

Add methods inside `BeaconModel`:

```swift
func trustConnectedIPhones() {
    Task { [weak self] in
        let result = await IPhoneLockdownBatteryProvider.discoverUSBTrustedDevices()
        await MainActor.run {
            guard let self else { return }
            trustedIPhoneEnrollmentResult = result
            guard !result.devices.isEmpty else { return }
            var next = trustedIPhoneRegistry
            for device in result.devices {
                next = next.trusting(device)
            }
            trustedIPhoneRegistry = next
            trustedIPhoneRegistry.save()
            Task { await self.refresh() }
        }
    }
}

func forgetTrustedIPhone(udid: String) {
    let next = trustedIPhoneRegistry.forgetting(udid: udid)
    trustedIPhoneRegistry = next
    next.save()
    store.removeDeviceIDs(["trusted-iphone-\(udid)"])
}
```

- [ ] **Step 4: Pass Settings dependencies**

Modify `Beacon/Mac/BeaconSettingsWindowController.swift` inside `updateContent()`:

```swift
latestRefreshDiagnostics: model.latestRefreshDiagnostics,
trustedIPhones: model.trustedIPhoneRegistry.devices,
trustedIPhoneEnrollmentResult: model.trustedIPhoneEnrollmentResult,
onTrustConnectedIPhone: { [weak model] in
    model?.trustConnectedIPhones()
},
onForgetTrustedIPhone: { [weak model] udid in
    model?.forgetTrustedIPhone(udid: udid)
},
```

Place those arguments after `latestNotificationDeliveryResult:` and before `onRefresh:`.

Modify `Beacon/Mac/BeaconStatusController.swift` so Settings refreshes when trust state changes:

```swift
private var trustedIPhoneObserver: AnyCancellable?
private var trustedIPhoneEnrollmentObserver: AnyCancellable?
```

Add in `init(model:)`:

```swift
trustedIPhoneObserver = model.$trustedIPhoneRegistry.sink { [weak self] _ in
    self?.settingsWindowController.updateContent()
    self?.updateStatusMenuContent()
    self?.updateDesktopWidget()
}
trustedIPhoneEnrollmentObserver = model.$trustedIPhoneEnrollmentResult.sink { [weak self] _ in
    self?.settingsWindowController.updateContent()
}
```

- [ ] **Step 5: Extend Settings view initializer**

Modify `Beacon/Mac/BeaconSettingsView.swift` properties:

```swift
let latestRefreshDiagnostics: BatteryRefreshDiagnostics
let trustedIPhones: [TrustedIPhone]
let trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport?
let onTrustConnectedIPhone: () -> Void
let onForgetTrustedIPhone: (String) -> Void
```

Modify the initializer signature:

```swift
latestRefreshDiagnostics: BatteryRefreshDiagnostics = BatteryRefreshDiagnostics(),
trustedIPhones: [TrustedIPhone] = [],
trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport? = nil,
onTrustConnectedIPhone: @escaping () -> Void = {},
onForgetTrustedIPhone: @escaping (String) -> Void = { _ in },
```

Assign each value in the initializer body.

Modify the Add Device sheet:

```swift
AddDeviceGuideView(
    trustedIPhoneEnrollmentResult: trustedIPhoneEnrollmentResult,
    onTrustConnectedIPhone: onTrustConnectedIPhone,
    onOpenBluetoothSettings: onOpenBluetoothSettings,
    onDismiss: { isShowingAddDeviceGuide = false }
)
```

In `devicesTab`, replace the selected-device `ScrollView` body:

```swift
ScrollView(showsIndicators: false) {
    deviceDetail(for: selectedDevice)
        .padding(1)
}
```

with:

```swift
ScrollView(showsIndicators: false) {
    VStack(alignment: .leading, spacing: 10) {
        TrustedIPhoneSettingsCard(
            trustedIPhones: trustedIPhones,
            enrollmentResult: trustedIPhoneEnrollmentResult,
            diagnostics: latestRefreshDiagnostics,
            onTrustConnectedIPhone: onTrustConnectedIPhone,
            onForgetTrustedIPhone: onForgetTrustedIPhone
        )

        deviceDetail(for: selectedDevice)
    }
    .padding(1)
}
```

- [ ] **Step 6: Add Settings support views**

Modify `Beacon/Mac/BeaconSettingsSupportViews.swift`:

```swift
struct TrustedIPhoneSettingsCard: View {
    let trustedIPhones: [TrustedIPhone]
    let enrollmentResult: IPhoneLockdownDiscoveryReport?
    let diagnostics: BatteryRefreshDiagnostics
    let onTrustConnectedIPhone: () -> Void
    let onForgetTrustedIPhone: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: resolveSymbol("iphone", fallback: "apps.iphone"))
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trusted iPhone")
                        .font(DesignTokens.Typography.captionEmphasis)
                    Text("Connect by USB, unlock, Trust this Mac, then add it to Beacon.")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                Button {
                    onTrustConnectedIPhone()
                } label: {
                    Label("Trust Connected iPhone", systemImage: "checkmark.shield")
                }
            }

            if let enrollmentResult {
                Label(enrollmentResult.message, systemImage: enrollmentResult.status == .reported ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(enrollmentResult.status == .reported ? DesignTokens.Palette.charging : DesignTokens.Palette.stale)
            }

            if trustedIPhones.isEmpty {
                Text(latestIPhoneDiagnosticText)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            } else {
                ForEach(trustedIPhones) { phone in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phone.displayName)
                                .font(DesignTokens.Typography.captionEmphasis)
                            Text(phone.udid)
                                .font(DesignTokens.Typography.caption2)
                                .foregroundStyle(DesignTokens.Palette.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            onForgetTrustedIPhone(phone.udid)
                        } label: {
                            Label("Forget", systemImage: "trash")
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                            .fill(DesignTokens.Palette.card)
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
                )
        )
    }

    private var latestIPhoneDiagnosticText: String {
        diagnostics.attempts
            .last { $0.provider == .ideviceInfo }
            .map(\.message)
            ?? "No trusted iPhone has been added to Beacon."
    }
}
```

Modify `AddDeviceGuideView` in the same file:

```swift
let trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport?
let onTrustConnectedIPhone: () -> Void
let onOpenBluetoothSettings: () -> Void
let onDismiss: () -> Void
```

Add this row above the AirPods row:

```swift
AddDeviceGuideRow(
    title: "iPhone or iPad",
    subtitle: trustedIPhoneEnrollmentResult?.message
        ?? "Connect by USB, unlock, Trust this Mac, then add it here.",
    systemImage: resolveSymbol("iphone", fallback: "apps.iphone"),
    actionTitle: "Trust",
    action: onTrustConnectedIPhone
)
```

- [ ] **Step 7: Update provider label**

Modify `batteryProviderLabel(source:provider:)` in `Beacon/Mac/DeviceBatteryRow.swift`:

```swift
case .ideviceInfo: return "Trusted iPhone"
```

- [ ] **Step 8: Run Settings tests**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/DeviceListPresentationTests
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Beacon/Mac/BeaconMacApp.swift Beacon/Mac/BeaconSettingsWindowController.swift Beacon/Mac/BeaconStatusController.swift Beacon/Mac/BeaconSettingsView.swift Beacon/Mac/BeaconSettingsSupportViews.swift Beacon/Mac/DeviceBatteryRow.swift BeaconTests/DeviceListPresentationTests.swift
git commit -m "feat: add trusted iPhone settings"
```

## Task 5: Full Verification and Installed App Proof

**Files:**
- Build/test/install only.

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests/BluetoothBatteryResolverTests -only-testing:BeaconTests/BatterySnapshotStoreTests -only-testing:BeaconTests/DeviceListPresentationTests
```

Expected: PASS.

- [ ] **Step 2: Run full unit suite**

Run:

```bash
xcodebuild test -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS' -only-testing:BeaconTests
```

Expected: PASS.

- [ ] **Step 3: Check formatting and generated project diff**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` has no output. `git status --short` shows only intended source, test, project, and docs changes.

- [ ] **Step 4: Verify local libimobiledevice availability**

Run:

```bash
command -v idevice_id
command -v ideviceinfo
idevice_id -l
```

Expected:

- If tools exist and the iPhone is trusted over USB, `idevice_id -l` prints the iPhone UDID.
- If tools are missing, Beacon still builds and Settings diagnostics show `idevice_id or ideviceinfo command not found`.

- [ ] **Step 5: Build and install to Applications**

First try the normal install path:

```bash
BATTERYHUB_DEVELOPMENT_TEAM=SM2Y9TGWH3 ./script/build_and_run.sh --install
```

If that fails with `No signing certificate "Mac Development" found`, use the known local fallback:

```bash
xcodebuild -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS,arch=arm64' -configuration Debug CODE_SIGNING_ALLOWED=NO build
APP_BUNDLE="$(xcodebuild -project Beacon.xcodeproj -scheme BeaconMac -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null | awk -F'= ' '$1 ~ /^[[:space:]]*BUILT_PRODUCTS_DIR[[:space:]]*$/ { dir=$2 } $1 ~ /^[[:space:]]*FULL_PRODUCT_NAME[[:space:]]*$/ { name=$2 } END { print dir "/" name }')"
STAGING="/Applications/.BeaconMac.app.installing.$$"
pkill -x BeaconMac || true
rm -rf "$STAGING"
ditto "$APP_BUNDLE" "$STAGING"
codesign --force --deep --sign "Apple Development: Yi-Sung Lin (SM2Y9TGWH3)" --entitlements Beacon/Mac/BeaconMac.entitlements "$STAGING"
codesign --verify --deep --strict "$STAGING"
rm -rf /Applications/BeaconMac.app
mv "$STAGING" /Applications/BeaconMac.app
open -n /Applications/BeaconMac.app
```

Expected: `/Applications/BeaconMac.app` launches.

- [ ] **Step 6: Prove the running app path**

Run:

```bash
PID="$(pgrep -x BeaconMac | head -1)"
ps -p "$PID" -o pid=,comm=
lsof -p "$PID" | rg '/Applications/BeaconMac.app/Contents/MacOS/BeaconMac'
codesign --verify --deep --strict /Applications/BeaconMac.app
codesign -d --entitlements :- /Applications/BeaconMac.app 2>/dev/null | rg 'com.apple.security.app-sandbox|com.apple.security.device.bluetooth'
```

Expected:

- `lsof` shows `/Applications/BeaconMac.app/Contents/MacOS/BeaconMac`.
- `codesign --verify --deep --strict` exits 0.
- Entitlements include sandbox and Bluetooth.

- [ ] **Step 7: Manual trusted iPhone acceptance test**

Run this with the user's iPhone connected by USB, unlocked, and trusted:

```bash
idevice_id -l
ideviceinfo -u <UDID_FROM_IDEVICE_ID> -k DeviceName
ideviceinfo -u <UDID_FROM_IDEVICE_ID> -q com.apple.mobile.battery
```

Then in `/Applications/BeaconMac.app`:

1. Open Settings.
2. Open Add Device.
3. Click `Trust Connected iPhone`.
4. Refresh.

Expected:

- The Settings trusted iPhone card lists the iPhone by name and UDID.
- The dashboard shows one iPhone row with source label `Trusted iPhone`.
- Removing the USB cable keeps the last reading visible until the existing stale/expired thresholds apply.
- A BLE-only iPhone does not create an iPhone row.

- [ ] **Step 8: Commit verification-ready implementation**

```bash
git status --short
```

If previous task commits already captured all source changes and `git status --short` is clean, skip this commit and record the clean state in the final response. If only documentation updates remain, run:

```bash
git add docs/superpowers/specs/2026-06-24-trusted-iphone-lockdown-battery-design.md docs/superpowers/plans/2026-06-24-trusted-iphone-lockdown-battery.md
git commit -m "docs: add trusted iPhone lockdown plan"
```

## Self-Review

- Spec coverage: The plan covers allowlist identity, no iPhone app, no BLE iPhone rows, external lockdown CLI, Settings enrollment, Settings diagnostics, forget behavior, unit tests, and installed app proof.
- Placeholder scan: No step depends on unspecified implementation details. Every code-changing step includes concrete Swift or shell content.
- Type consistency: The plan uses `TrustedIPhone`, `TrustedIPhoneRegistry`, `IPhoneLockdownBatteryProvider`, `IPhoneLockdownCommandSet`, `IPhoneLockdownCommandRunning`, `IPhoneLockdownDiscoveryReport`, and `.lockdownNetwork` consistently across tests and implementation steps.
