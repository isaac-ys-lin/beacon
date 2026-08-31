import Foundation

public enum IPhoneLockdownConnection: Equatable, Sendable {
    case usb
    case network
}

public struct IPhoneLockdownCommandSet: Equatable, Sendable {
    public let ideviceIDURL: URL
    public let ideviceInfoURL: URL

    public init(ideviceIDURL: URL, ideviceInfoURL: URL) {
        self.ideviceIDURL = ideviceIDURL
        self.ideviceInfoURL = ideviceInfoURL
    }
}

public struct IPhoneLockdownCommandResult: Equatable, Sendable {
    public let exitStatus: Int32
    public let output: String
    public let errorOutput: String
    public let timedOut: Bool

    public init(exitStatus: Int32, output: String, errorOutput: String = "", timedOut: Bool = false) {
        self.exitStatus = exitStatus
        self.output = output
        self.errorOutput = errorOutput
        self.timedOut = timedOut
    }
}

public protocol IPhoneLockdownCommandRunning: Sendable {
    func run(commandURL: URL, arguments: [String], timeout: TimeInterval) async -> IPhoneLockdownCommandResult
}

public struct IPhoneLockdownBatteryReport: Equatable, Sendable {
    public let candidates: [BluetoothBatteryCandidate]
    public let attempts: [BatteryProviderAttempt]
    public var attempt: BatteryProviderAttempt? { attempts.first }

    public init(candidates: [BluetoothBatteryCandidate], attempts: [BatteryProviderAttempt]) {
        self.candidates = candidates
        self.attempts = attempts
    }
}

public struct IPhoneLockdownDiscoveryReport: Equatable, Sendable {
    public let devices: [TrustedIPhone]
    public let status: BatteryReadStatus
    public let message: String
    public let attempts: [BatteryProviderAttempt]

    public init(
        devices: [TrustedIPhone],
        status: BatteryReadStatus,
        message: String,
        attempts: [BatteryProviderAttempt] = []
    ) {
        self.devices = devices
        self.status = status
        self.message = message
        self.attempts = attempts
    }
}

public struct ProcessIPhoneLockdownCommandRunner: IPhoneLockdownCommandRunning {
    public init() {}

    public func run(commandURL: URL, arguments: [String], timeout: TimeInterval) async -> IPhoneLockdownCommandResult {
        do {
            let result = try await BatteryProviderRunner().run(
                executableURL: commandURL,
                arguments: arguments,
                timeout: .milliseconds(Int64(timeout * 1_000))
            )
            return IPhoneLockdownCommandResult(
                exitStatus: result.terminationStatus,
                output: String(data: result.output, encoding: .utf8) ?? "",
                errorOutput: String(data: result.errorOutput, encoding: .utf8) ?? "",
                timedOut: result.timedOut || result.wasCancelled
            )
        } catch {
            return IPhoneLockdownCommandResult(
                exitStatus: -1,
                output: "",
                errorOutput: error.localizedDescription
            )
        }
    }
}

public struct IPhoneLockdownCommandLocator {
    public static let defaultSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    public let searchPaths: [String]
    private let fileManager: FileManager

    public init(searchPaths: [String] = Self.defaultSearchPaths, fileManager: FileManager = .default) {
        self.searchPaths = searchPaths
        self.fileManager = fileManager
    }

    public func locate() -> IPhoneLockdownCommandSet? {
        guard let ideviceIDURL = executableURL(named: "idevice_id"),
              let ideviceInfoURL = executableURL(named: "ideviceinfo")
        else {
            return nil
        }
        return IPhoneLockdownCommandSet(ideviceIDURL: ideviceIDURL, ideviceInfoURL: ideviceInfoURL)
    }

    private func executableURL(named commandName: String) -> URL? {
        searchPaths
            .map { URL(fileURLWithPath: $0).appendingPathComponent(commandName) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

private struct IPhoneLockdownListResult: Sendable {
    let connection: IPhoneLockdownConnection
    let udids: [String]
    let result: IPhoneLockdownCommandResult

    var timedOut: Bool { result.timedOut }

    var isAvailable: Bool {
        !result.timedOut && result.exitStatus == 0
    }

    var status: BatteryReadStatus {
        if result.timedOut {
            return .timedOut
        }
        if result.exitStatus == 0 {
            return .reported
        }
        return .unavailable
    }

    var failureMessage: String? {
        guard !isAvailable else { return nil }
        switch connection {
        case .usb:
            return result.timedOut
                ? "idevice_id timed out while listing USB iPhones"
                : "idevice_id -l returned status \(result.exitStatus)"
        case .network:
            return result.timedOut
                ? "idevice_id -n timed out while listing network iPhones"
                : "idevice_id -n returned status \(result.exitStatus)"
        }
    }
}

public struct IPhoneLockdownBatteryProvider: Sendable {
    private let registry: TrustedIPhoneRegistry
    private let commandSet: IPhoneLockdownCommandSet?
    private let commandRunner: any IPhoneLockdownCommandRunning
    private let timeout: TimeInterval

    public init(
        registry: TrustedIPhoneRegistry = TrustedIPhoneRegistry.load(),
        commandSet: IPhoneLockdownCommandSet? = IPhoneLockdownCommandLocator().locate(),
        commandRunner: any IPhoneLockdownCommandRunning = ProcessIPhoneLockdownCommandRunner(),
        timeout: TimeInterval = 3
    ) {
        self.registry = registry
        self.commandSet = commandSet
        self.commandRunner = commandRunner
        self.timeout = timeout
    }

    public static func readCandidates(
        registry: TrustedIPhoneRegistry,
        commandSet: IPhoneLockdownCommandSet? = IPhoneLockdownCommandLocator().locate(),
        runner: any IPhoneLockdownCommandRunning = ProcessIPhoneLockdownCommandRunner(),
        now: Date = Date()
    ) async -> IPhoneLockdownBatteryReport {
        await IPhoneLockdownBatteryProvider(
            registry: registry,
            commandSet: commandSet,
            commandRunner: runner
        ).readReport(now: now)
    }

    public static func discoverUSBTrustedDevices(
        commandSet: IPhoneLockdownCommandSet? = IPhoneLockdownCommandLocator().locate(),
        runner: any IPhoneLockdownCommandRunning = ProcessIPhoneLockdownCommandRunner(),
        now: Date = Date()
    ) async -> IPhoneLockdownDiscoveryReport {
        await IPhoneLockdownBatteryProvider(
            commandSet: commandSet,
            commandRunner: runner
        ).discoverUSBDevicesForEnrollment(now: now)
    }

    public func readReport(now: Date = Date()) async -> IPhoneLockdownBatteryReport {
        guard !registry.devices.isEmpty else {
            return IPhoneLockdownBatteryReport(
                candidates: [],
                attempts: [
                    attempt(
                        status: .noReport,
                        candidateCount: 0,
                        message: "No trusted iPhones are allowlisted",
                        now: now
                    )
                ]
            )
        }

        guard let commandSet else {
            return IPhoneLockdownBatteryReport(
                candidates: [],
                attempts: [
                    attempt(
                        status: .commandMissing,
                        candidateCount: 0,
                        message: "idevice_id or ideviceinfo command not found",
                        now: now
                    )
                ]
            )
        }

        let usbList = await listUDIDs(connection: .usb, commandSet: commandSet)
        let networkList = await listUDIDs(connection: .network, commandSet: commandSet)

        let listFailures = [usbList.failureMessage, networkList.failureMessage].compactMap { $0 }
        if !usbList.isAvailable && !networkList.isAvailable {
            let status: BatteryReadStatus = usbList.status == .timedOut || networkList.status == .timedOut
                ? .timedOut
                : .unavailable
            return IPhoneLockdownBatteryReport(
                candidates: [],
                attempts: [
                    attempt(
                        status: status,
                        candidateCount: 0,
                        message: listFailures.joined(separator: "; "),
                        now: now
                    )
                ]
            )
        }

        let devices = mergedDevices(
            usbUDIDs: usbList.isAvailable ? usbList.udids : [],
            networkUDIDs: networkList.isAvailable ? networkList.udids : []
        )
            .filter { registry.isTrusted(udid: $0.udid) }
        var candidates: [BluetoothBatteryCandidate] = []
        var readStatuses: [BatteryReadStatus] = []

        for device in devices {
            let read = await readCandidate(
                udid: device.udid,
                connection: device.connection,
                commandSet: commandSet
            )
            readStatuses.append(read.status)
            if let candidate = read.candidate {
                candidates.append(candidate)
            }
        }
        var status = batteryAttemptStatus(candidates: candidates, readStatuses: readStatuses)
        if candidates.isEmpty,
           readStatuses.isEmpty,
           let firstListFailure = [usbList, networkList].first(where: { !$0.isAvailable }) {
            status = firstListFailure.status
        }
        var message = "ideviceinfo returned \(candidates.count) trusted iPhone battery candidates"
        if !listFailures.isEmpty {
            message += "; " + listFailures.joined(separator: "; ")
        }

        return IPhoneLockdownBatteryReport(
            candidates: candidates,
            attempts: [
                attempt(
                    status: status,
                    candidateCount: candidates.count,
                    message: message,
                    now: now
                )
            ]
        )
    }

    public func discoverUSBDevicesForEnrollment(now: Date = Date()) async -> IPhoneLockdownDiscoveryReport {
        guard let commandSet else {
            let message = "idevice_id or ideviceinfo command not found"
            return IPhoneLockdownDiscoveryReport(
                devices: [],
                status: .commandMissing,
                message: message,
                attempts: [
                    attempt(
                        status: .commandMissing,
                        candidateCount: 0,
                        message: message,
                        now: now
                    )
                ]
            )
        }

        async let usbListRead = listUDIDs(connection: .usb, commandSet: commandSet)
        async let networkListRead = listUDIDs(connection: .network, commandSet: commandSet)
        let (usbList, networkList) = await (usbListRead, networkListRead)

        let listFailures = [usbList.failureMessage, networkList.failureMessage].compactMap { $0 }
        if !usbList.isAvailable && !networkList.isAvailable {
            let status: BatteryReadStatus = usbList.timedOut || networkList.timedOut
                ? .timedOut
                : .unavailable
            let message = listFailures.joined(separator: "; ")
            return IPhoneLockdownDiscoveryReport(
                devices: [],
                status: status,
                message: message,
                attempts: [
                    attempt(
                        status: status,
                        candidateCount: 0,
                        message: message,
                        now: now
                    )
                ]
            )
        }

        let devices = mergedDevices(
            usbUDIDs: usbList.isAvailable ? usbList.udids : [],
            networkUDIDs: networkList.isAvailable ? networkList.udids : []
        )
        var trustedDevices: [TrustedIPhone] = []
        var trustProofStatuses: [BatteryReadStatus] = []
        for device in devices {
            let nameResult = await readDeviceName(
                udid: device.udid,
                connection: device.connection,
                commandSet: commandSet
            )
            guard !nameResult.timedOut else {
                trustProofStatuses.append(.timedOut)
                continue
            }
            guard nameResult.exitStatus == 0 else {
                trustProofStatuses.append(.unavailable)
                continue
            }
            let displayName = nameResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else {
                trustProofStatuses.append(.unavailable)
                continue
            }
            trustProofStatuses.append(.reported)
            trustedDevices.append(TrustedIPhone(udid: device.udid, displayName: displayName, trustedAt: now))
        }

        let status: BatteryReadStatus
        var message: String
        if trustedDevices.isEmpty,
           !devices.isEmpty,
           trustProofStatuses.contains(.timedOut) {
            status = .timedOut
            message = "Timed out verifying paired iPhone trust. Unlock the iPhone and keep it reachable by USB or Wi-Fi."
        } else if trustedDevices.isEmpty,
                  !devices.isEmpty,
                  trustProofStatuses.contains(.unavailable) {
            status = .unavailable
            message = "No paired iPhone could be verified. Unlock the iPhone and keep it reachable by USB or Wi-Fi."
        } else {
            status = trustedDevices.isEmpty ? .noReport : .reported
            let connectionLabel = networkList.udids.isEmpty ? "USB" : "paired"
            message = "ideviceinfo verified \(trustedDevices.count) \(connectionLabel) iPhones for enrollment"
        }
        if !listFailures.isEmpty {
            message += "; " + listFailures.joined(separator: "; ")
        }
        return IPhoneLockdownDiscoveryReport(
            devices: trustedDevices,
            status: status,
            message: message,
            attempts: [
                attempt(
                    status: status,
                    candidateCount: trustedDevices.count,
                    message: message,
                    now: now
                )
            ]
        )
    }

    static func parseBatteryReading(
        _ output: String,
        fallbackDisplayName: String
    ) -> (percent: Int, displayName: String, chargeState: ChargeState)? {
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

        guard let percent else { return nil }

        let displayName = [
            "devicename",
            "device name",
            "name",
            "productname"
        ]
        .compactMap { values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? fallbackDisplayName

        return (
            Swift.max(0, Swift.min(100, percent)),
            displayName,
            chargeState(from: values)
        )
    }

    private func listUDIDs(
        connection: IPhoneLockdownConnection,
        commandSet: IPhoneLockdownCommandSet
    ) async -> IPhoneLockdownListResult {
        let result = await commandRunner.run(
            commandURL: commandSet.ideviceIDURL,
            arguments: connection == .network ? ["-n"] : ["-l"],
            timeout: timeout
        )
        return IPhoneLockdownListResult(
            connection: connection,
            udids: Self.parseUDIDs(result.output),
            result: result
        )
    }

    private func readCandidate(
        udid: String,
        connection: IPhoneLockdownConnection,
        commandSet: IPhoneLockdownCommandSet
    ) async -> (candidate: BluetoothBatteryCandidate?, status: BatteryReadStatus) {
        let nameResult = await readDeviceName(udid: udid, connection: connection, commandSet: commandSet)
        let registryDisplayName = registry.displayName(for: udid) ?? "iPhone"
        let liveDisplayName = nameResult.exitStatus == 0 && !nameResult.timedOut
            ? nameResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let fallbackDisplayName = liveDisplayName.isEmpty ? registryDisplayName : liveDisplayName

        let batteryResult = await commandRunner.run(
            commandURL: commandSet.ideviceInfoURL,
            arguments: infoArguments(udid: udid, connection: connection, query: "com.apple.mobile.battery"),
            timeout: timeout
        )
        guard !batteryResult.timedOut else {
            return (nil, .timedOut)
        }
        guard batteryResult.exitStatus == 0 else {
            return (nil, .unavailable)
        }
        guard let reading = Self.parseBatteryReading(
                batteryResult.output,
                fallbackDisplayName: fallbackDisplayName
              )
        else {
            return (nil, .noReport)
        }

        return (BluetoothBatteryCandidate(
            deviceID: udid,
            displayName: reading.displayName.isEmpty ? fallbackDisplayName : reading.displayName,
            transport: connection == .network ? .lockdownNetwork : .usb,
            batteryPercent: reading.percent,
            kindHint: .iPhone,
            connectionState: .connected,
            chargeState: reading.chargeState,
            identityEvidence: .serialNumber
        ), .reported)
    }

    private func readDeviceName(
        udid: String,
        connection: IPhoneLockdownConnection,
        commandSet: IPhoneLockdownCommandSet
    ) async -> IPhoneLockdownCommandResult {
        await commandRunner.run(
            commandURL: commandSet.ideviceInfoURL,
            arguments: infoArguments(udid: udid, connection: connection, key: "DeviceName"),
            timeout: timeout
        )
    }

    private func infoArguments(
        udid: String,
        connection: IPhoneLockdownConnection,
        query: String? = nil,
        key: String? = nil
    ) -> [String] {
        var arguments: [String] = []
        if connection == .network {
            arguments.append("-n")
        }
        arguments.append(contentsOf: ["-u", udid])
        if let query {
            arguments.append(contentsOf: ["-q", query])
        }
        if let key {
            arguments.append(contentsOf: ["-k", key])
        }
        return arguments
    }

    private func mergedDevices(
        usbUDIDs: [String],
        networkUDIDs: [String]
    ) -> [(udid: String, connection: IPhoneLockdownConnection)] {
        var seen = Set<String>()
        var devices: [(udid: String, connection: IPhoneLockdownConnection)] = []
        for udid in usbUDIDs where seen.insert(udid).inserted {
            devices.append((udid, .usb))
        }
        for udid in networkUDIDs where seen.insert(udid).inserted {
            devices.append((udid, .network))
        }
        return devices
    }

    private func batteryAttemptStatus(
        candidates: [BluetoothBatteryCandidate],
        readStatuses: [BatteryReadStatus]
    ) -> BatteryReadStatus {
        if !candidates.isEmpty {
            return .reported
        }
        if readStatuses.contains(.timedOut) {
            return .timedOut
        }
        if readStatuses.contains(.unavailable) {
            return .unavailable
        }
        return .noReport
    }

    private func attempt(
        status: BatteryReadStatus,
        candidateCount: Int,
        message: String,
        now: Date
    ) -> BatteryProviderAttempt {
        BatteryProviderAttempt(
            provider: .ideviceInfo,
            status: status,
            candidateCount: candidateCount,
            message: message,
            attemptedAt: now
        )
    }

    private static func parseUDIDs(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    private static func chargeState(from values: [String: String]) -> ChargeState {
        let fullyCharged = boolValue(values["fullycharged"])
        let isCharging = boolValue(values["batteryischarging"])
        let externalConnected = boolValue(values["externalconnected"])

        if fullyCharged == true { return .full }
        if isCharging == true || externalConnected == true { return .charging }
        if isCharging == false || externalConnected == false { return .unplugged }
        return .unknown
    }

    private static func boolValue(_ value: String?) -> Bool? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        switch value {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }
}
