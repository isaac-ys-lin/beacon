import Foundation

public enum BluetoothTransport: Sendable {
    case hid
    case ble
    case classic
    case systemProfiler
    case usb
    case unknown
}

public struct BluetoothBatteryCandidate: Sendable {
    public let deviceID: String
    public let displayName: String
    public let transport: BluetoothTransport
    public let batteryPercent: Int?
    public let kindHint: DeviceKind?
    public let connectionState: ConnectionState

    public init(
        deviceID: String,
        displayName: String,
        transport: BluetoothTransport,
        batteryPercent: Int?,
        kindHint: DeviceKind? = nil,
        connectionState: ConnectionState = .connected
    ) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.transport = transport
        self.batteryPercent = batteryPercent
        self.kindHint = kindHint
        self.connectionState = connectionState
    }
}

public struct BluetoothCandidateScanReport: Sendable {
    public let candidates: [BluetoothBatteryCandidate]
    public let attempts: [BatteryProviderAttempt]

    public init(candidates: [BluetoothBatteryCandidate], attempts: [BatteryProviderAttempt]) {
        self.candidates = candidates
        self.attempts = attempts
    }
}

public struct BluetoothBatteryReadReport: Sendable {
    public let snapshots: [BatterySnapshot]
    public let diagnostics: BatteryRefreshDiagnostics
}

public struct BluetoothBatteryResolver {
    public init() {}

    public func read(now: Date = Date()) async -> [BatterySnapshot] {
        await readReport(now: now).snapshots
    }

    public func readReport(now: Date = Date()) async -> BluetoothBatteryReadReport {
        await Self.report(
            from: BluetoothDeviceScanner().connectedCandidateReport(now: now),
            now: now
        )
    }

    static func report(from scanReport: BluetoothCandidateScanReport, now: Date) -> BluetoothBatteryReadReport {
        let snapshots = scanReport.candidates.map {
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

    static func snapshot(from candidate: BluetoothBatteryCandidate, now: Date) -> BatterySnapshot {
        let percent = candidate.batteryPercent.map { Swift.max(0, Swift.min(100, $0)) }
        let kind = kind(for: candidate)
        let source = source(for: candidate)

        return BatterySnapshot(
            deviceID: stableDeviceID(for: candidate, kind: kind),
            displayName: candidate.displayName,
            kind: kind,
            percent: percent,
            chargeState: .unknown,
            connectionState: candidate.connectionState,
            source: source,
            updatedAt: now
        )
    }

    private static func stableDeviceID(for candidate: BluetoothBatteryCandidate, kind: DeviceKind) -> String {
        if kind == .iPhone, candidate.transport == .ble {
            return "bluetooth-iphone-\(candidate.displayName.stableBluetoothIdentitySlug)"
        }
        if kind == .iPhone, candidate.transport == .usb {
            return "usb-iphone-\(candidate.displayName.stableBluetoothIdentitySlug)"
        }
        return "bluetooth-\(candidate.deviceID)"
    }

    private static func source(for candidate: BluetoothBatteryCandidate) -> BatterySource {
        if candidate.batteryPercent == nil { return .bluetoothUnsupported }
        switch candidate.transport {
        case .hid: return .ioRegistry
        case .ble: return .coreBluetooth
        case .classic: return .ioBluetooth
        case .systemProfiler: return .systemProfiler
        case .usb: return .ideviceInfo
        case .unknown: return .bluetoothUnsupported
        }
    }

    private static func kind(for candidate: BluetoothBatteryCandidate) -> DeviceKind {
        if let kindHint = candidate.kindHint {
            return kindHint
        }

        let name = candidate.displayName.lowercased()
        if name.contains("iphone") || name.contains("ios") { return .iPhone }
        if name.contains("airpods") || name.contains("air pods") { return .airPods }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse") { return .mouse }
        if name.contains("trackpad") { return .trackpad }
        return .bluetoothPeripheral
    }
}

public struct IPhoneUSBBatteryReading: Equatable, Sendable {
    public let percent: Int
    public let displayName: String

    public init(percent: Int, displayName: String) {
        self.percent = percent
        self.displayName = displayName
    }
}

enum IPhoneUSBBatteryProvider {
    private static let commandPaths = [
        "/opt/homebrew/bin/ideviceinfo",
        "/usr/local/bin/ideviceinfo",
        "/usr/bin/ideviceinfo"
    ]
    private static let timeout: TimeInterval = 3

    static func candidate(from reading: IPhoneUSBBatteryReading) -> BluetoothBatteryCandidate? {
        BluetoothBatteryCandidate(
            deviceID: "usb-\(reading.displayName.stableBluetoothIdentitySlug)",
            displayName: reading.displayName,
            transport: .usb,
            batteryPercent: reading.percent,
            kindHint: .iPhone,
            connectionState: .connected
        )
    }

    static func parse(_ output: String, fallbackDisplayName: String = "iPhone") -> IPhoneUSBBatteryReading? {
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

        return IPhoneUSBBatteryReading(
            percent: max(0, min(100, percent)),
            displayName: displayName
        )
    }

    static func readCandidate(now: Date = Date()) async -> (candidate: BluetoothBatteryCandidate?, attempt: BatteryProviderAttempt) {
        await Task.detached(priority: .utility) {
            guard let commandURL = availableCommandURL() else {
                return (
                    nil,
                    BatteryProviderAttempt(
                        provider: .ideviceInfo,
                        status: .commandMissing,
                        candidateCount: 0,
                        message: "ideviceinfo command not found",
                        attemptedAt: now
                    )
                )
            }

            // Try USB first, fall back to Wi-Fi lockdown (established after one USB trust pairing)
            var batteryResult = run(commandURL: commandURL, arguments: ["-q", "com.apple.mobile.battery"])
            var networkMode = false
            if batteryResult.status != 0 {
                batteryResult = run(commandURL: commandURL, arguments: ["-n", "-q", "com.apple.mobile.battery"])
                networkMode = true
            }
            guard batteryResult.status == 0 else {
                return (
                    nil,
                    BatteryProviderAttempt(
                        provider: .ideviceInfo,
                        status: batteryResult.timedOut ? .timedOut : .unavailable,
                        candidateCount: 0,
                        message: batteryResult.timedOut
                            ? "ideviceinfo timed out while reading iPhone battery"
                            : "ideviceinfo returned status \(batteryResult.status)",
                        attemptedAt: now
                    )
                )
            }

            let nameArgs = networkMode ? ["-n", "-k", "DeviceName"] : ["-k", "DeviceName"]
            let deviceName = run(commandURL: commandURL, arguments: nameArgs)
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = deviceName.isEmpty ? "iPhone" : deviceName
            guard let reading = parse(batteryResult.output, fallbackDisplayName: fallbackName),
                  let candidate = candidate(from: reading)
            else {
                return (
                    nil,
                    BatteryProviderAttempt(
                        provider: .ideviceInfo,
                        status: .noReport,
                        candidateCount: 0,
                        message: "ideviceinfo did not return an iPhone battery percentage",
                        attemptedAt: now
                    )
                )
            }

            return (
                candidate,
                BatteryProviderAttempt(
                    provider: .ideviceInfo,
                    status: .reported,
                    candidateCount: 1,
                    message: "ideviceinfo returned 1 iPhone battery candidate (\(networkMode ? "Wi-Fi" : "USB"))",
                    attemptedAt: now
                )
            )
        }.value
    }

    private static func availableCommandURL(fileManager: FileManager = .default) -> URL? {
        commandPaths
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
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
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "%").union(.whitespacesAndNewlines))
        return Int(trimmed)
    }

    private static func run(commandURL: URL, arguments: [String]) -> (status: Int32, output: String, timedOut: Bool) {
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
            return (-1, "", false)
        }

        timeoutWorkItem.cancel()
        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, output, didTimeOut)
    }
}

private extension String {
    var stableBluetoothIdentitySlug: String {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "device" : collapsed.lowercased()
    }
}
