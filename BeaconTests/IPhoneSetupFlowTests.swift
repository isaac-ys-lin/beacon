import XCTest
@testable import Beacon

extension BluetoothBatteryResolverTests {
    func testIPhonePreflightRequiresBothExecutableToolsWithoutRunningThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let locator = IPhoneLockdownCommandLocator(searchPaths: [directory.path])
        XCTAssertEqual(locator.missingCommandNames, ["idevice_id", "ideviceinfo"])
        for name in ["idevice_id", "ideviceinfo"] {
            let path = directory.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 99\n".utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
            if name == "idevice_id" { XCTAssertEqual(locator.missingCommandNames, ["ideviceinfo"]) }
        }
        XCTAssertTrue(IPhoneToolAvailability.inspect(locator: locator).isAvailable)
        XCTAssertNotNil(locator.locate())
    }

    func testIPhoneEnrollmentDenialIsNotGenericConnectionFailure() async {
        let report = await IPhoneLockdownBatteryProvider(
            registry: TrustedIPhoneRegistry(), commandSet: setupCommands,
            commandRunner: SetupIPhoneRunner(denied: true, noBattery: false)
        ).discoverUSBDevicesForEnrollment()
        XCTAssertEqual(report.status, .unauthorized)
        XCTAssertTrue(report.devices.isEmpty)
        XCTAssertEqual(IPhoneLockdownFailureStatus.classify(.init(exitStatus: 1, output: "", errorOutput: "ERROR: Could not connect to lockdownd, error code -3")), .unavailable)
    }

    func testIPhoneEnrollmentAndFreshBatteryAreSeparateResults() async {
        let phone = TrustedIPhone(udid: "fixture-iphone", displayName: "Test iPhone", trustedAt: Date())
        let registry = TrustedIPhoneRegistry(devices: [phone])
        let provider = IPhoneLockdownBatteryProvider(registry: registry, commandSet: setupCommands,
            commandRunner: SetupIPhoneRunner(denied: false, noBattery: true))
        let enrollment = await provider.discoverUSBDevicesForEnrollment()
        let noBattery = await provider.readReport()
        XCTAssertEqual(enrollment.status, .reported)
        XCTAssertTrue(noBattery.candidates.isEmpty)
        XCTAssertEqual(noBattery.attempt?.status, .noReport)
        XCTAssertEqual(IPhoneSetupStage.resolve(tools: .init(missingCommands: []), isChecking: false,
            enrollment: enrollment, hasCurrentReading: false), .noBattery)
        let read = await IPhoneLockdownBatteryProvider(registry: registry, commandSet: setupCommands,
            commandRunner: SetupIPhoneRunner(denied: false, noBattery: false)).readReport()
        XCTAssertEqual(read.candidates.first?.batteryPercent, 87)
        XCTAssertEqual(read.candidates.first?.deviceID, phone.udid)
    }

    private var setupCommands: IPhoneLockdownCommandSet {
        .init(ideviceIDURL: URL(fileURLWithPath: "/fixture/idevice_id"), ideviceInfoURL: URL(fileURLWithPath: "/fixture/ideviceinfo"))
    }
}

private struct SetupIPhoneRunner: IPhoneLockdownCommandRunning {
    let denied: Bool
    let noBattery: Bool

    func run(commandURL: URL, arguments: [String], timeout: TimeInterval) async -> IPhoneLockdownCommandResult {
        if commandURL.lastPathComponent == "idevice_id" {
            return .init(exitStatus: 0, output: arguments == ["-l"] ? "fixture-iphone\n" : "")
        }
        if denied { return .init(exitStatus: 1, output: "", errorOutput: "ERROR: Could not connect to lockdownd: PairingDialogResponsePending (-19)") }
        if arguments.contains("DeviceName") { return .init(exitStatus: 0, output: "Test iPhone\n") }
        return .init(exitStatus: 0, output: noBattery ? "" : "BatteryCurrentCapacity: 87\nBatteryIsCharging: true\n")
    }
}
