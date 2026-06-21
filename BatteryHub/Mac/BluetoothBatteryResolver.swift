import Foundation

public enum BluetoothTransport: Sendable {
    case hid
    case ble
    case classic
    case systemProfiler
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

public struct BluetoothBatteryResolver {
    public init() {}

    public func read(now: Date = Date()) async -> [BatterySnapshot] {
        await BluetoothDeviceScanner().connectedCandidates().map {
            Self.snapshot(from: $0, now: now)
        }
    }

    static func snapshot(from candidate: BluetoothBatteryCandidate, now: Date) -> BatterySnapshot {
        let percent = candidate.batteryPercent.map { Swift.max(0, Swift.min(100, $0)) }

        return BatterySnapshot(
            deviceID: "bluetooth-\(candidate.deviceID)",
            displayName: candidate.displayName,
            kind: kind(for: candidate),
            percent: percent,
            chargeState: .unknown,
            connectionState: candidate.connectionState,
            source: source(for: candidate),
            updatedAt: now
        )
    }

    private static func source(for candidate: BluetoothBatteryCandidate) -> BatterySource {
        if candidate.batteryPercent == nil { return .bluetoothUnsupported }
        switch candidate.transport {
        case .hid: return .ioRegistry
        case .ble: return .coreBluetooth
        case .classic: return .ioBluetooth
        case .systemProfiler: return .systemProfiler
        case .unknown: return .bluetoothUnsupported
        }
    }

    private static func kind(for candidate: BluetoothBatteryCandidate) -> DeviceKind {
        if let kindHint = candidate.kindHint {
            return kindHint
        }

        let name = candidate.displayName.lowercased()
        if name.contains("airpods") || name.contains("air pods") { return .airPods }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse") { return .mouse }
        if name.contains("trackpad") { return .trackpad }
        return .bluetoothPeripheral
    }
}
