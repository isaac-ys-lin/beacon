import Foundation

public enum BluetoothTransport: Equatable, Sendable {
    case hid
    case ble
    case classic
    case systemProfiler
    case usb
    case lockdownNetwork
    case unknown
}

public struct BluetoothBatteryCandidate: Equatable, Sendable {
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
        let snapshots = scanReport.candidates.filter {
            !Self.shouldDropFromReport($0)
        }.map {
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
            return "trusted-iphone-\(candidate.deviceID)"
        }
        if kind == .iPhone, candidate.transport == .lockdownNetwork {
            return "trusted-iphone-\(candidate.deviceID)"
        }
        return "bluetooth-\(candidate.deviceID)"
    }

    private static func shouldDropFromReport(_ candidate: BluetoothBatteryCandidate) -> Bool {
        kind(for: candidate) == .iPhone && candidate.transport == .ble
    }

    private static func source(for candidate: BluetoothBatteryCandidate) -> BatterySource {
        if candidate.batteryPercent == nil { return .bluetoothUnsupported }
        switch candidate.transport {
        case .hid: return .ioRegistry
        case .ble: return .coreBluetooth
        case .classic: return .ioBluetooth
        case .systemProfiler: return .systemProfiler
        case .usb, .lockdownNetwork: return .ideviceInfo
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
