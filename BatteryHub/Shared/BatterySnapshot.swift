import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case macBook
    case iPhone
    case appleWatch
    case airPods
    case keyboard
    case mouse
    case trackpad
    case bluetoothPeripheral
}

public enum ChargeState: String, Codable, Sendable {
    case unknown
    case unplugged
    case charging
    case full
}

public enum BatterySource: String, Codable, Sendable {
    case macPowerSource
    case iCloud
    case watchConnectivity
    case ioRegistry
    case coreBluetooth
    case ioBluetooth
    case systemProfiler
    case bluetoothUnsupported
}

public extension BatterySource {
    var isCompanionSync: Bool {
        self == .iCloud || self == .watchConnectivity
    }
}

public enum Freshness: String, Codable, Sendable {
    case fresh
    case stale
    case expired
}

public enum ConnectionState: String, Codable, Sendable {
    case unknown
    case connected
    case disconnected
}

public struct BatterySnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { deviceID }
    public let deviceID: String
    public let displayName: String
    public let kind: DeviceKind
    public let percent: Int?
    public let chargeState: ChargeState
    public let connectionState: ConnectionState
    public let source: BatterySource
    public let updatedAt: Date

    public init(
        deviceID: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState,
        connectionState: ConnectionState = .connected,
        source: BatterySource,
        updatedAt: Date
    ) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.kind = kind
        self.percent = percent
        self.chargeState = chargeState
        self.connectionState = connectionState
        self.source = source
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case displayName
        case kind
        case percent
        case chargeState
        case connectionState
        case source
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        displayName = try container.decode(String.self, forKey: .displayName)
        kind = try container.decode(DeviceKind.self, forKey: .kind)
        percent = try container.decodeIfPresent(Int.self, forKey: .percent)
        chargeState = try container.decode(ChargeState.self, forKey: .chargeState)
        connectionState = try container.decodeIfPresent(ConnectionState.self, forKey: .connectionState) ?? .connected
        source = try container.decode(BatterySource.self, forKey: .source)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct DecoratedBatterySnapshot: Equatable, Identifiable, Sendable {
    public var id: String { snapshot.id }
    public let snapshot: BatterySnapshot
    public let freshness: Freshness
}

public struct BatteryHistorySample: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(deviceID)-\(Int(recordedAt.timeIntervalSince1970))-\(percent)" }
    public let deviceID: String
    public let percent: Int
    public let chargeState: ChargeState
    public let source: BatterySource
    public let recordedAt: Date

    public init(
        deviceID: String,
        percent: Int,
        chargeState: ChargeState,
        source: BatterySource,
        recordedAt: Date
    ) {
        self.deviceID = deviceID
        self.percent = percent
        self.chargeState = chargeState
        self.source = source
        self.recordedAt = recordedAt
    }
}

public struct BatteryHistorySummary: Equatable, Sendable {
    public let samples: [BatteryHistorySample]
    public let latestPercent: Int
    public let delta: Int
    public let minimumPercent: Int
    public let maximumPercent: Int

    public var trendDescription: String {
        if delta > 0 { return "+\(delta)% trend" }
        if delta < 0 { return "\(delta)% trend" }
        return "Stable"
    }
}
