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
    case ioRegistry
    case coreBluetooth
    case ioBluetooth
    case systemProfiler
    case bluetoothUnsupported
    case ideviceInfo
}

public enum BatteryProvider: String, Codable, Sendable {
    case macPowerSource
    case ioRegistry
    case coreBluetoothBatteryService
    case ioBluetooth
    case systemProfiler
    case bluetoothUnsupported
    case ideviceInfo
}

public enum BatteryReadStatus: String, Codable, Sendable {
    case reported
    case noReport
    case unavailable
    case timedOut
    case unauthorized
    case commandMissing
}

public enum BatteryReadConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
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
    public let provider: BatteryProvider
    public let readStatus: BatteryReadStatus
    public let confidence: BatteryReadConfidence
    public let updatedAt: Date

    public init(
        deviceID: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState,
        connectionState: ConnectionState = .connected,
        source: BatterySource,
        provider: BatteryProvider? = nil,
        readStatus: BatteryReadStatus? = nil,
        confidence: BatteryReadConfidence? = nil,
        updatedAt: Date
    ) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.kind = kind
        self.percent = percent
        self.chargeState = chargeState
        self.connectionState = connectionState
        self.source = source
        self.provider = provider ?? BatteryProvider.defaultProvider(for: source)
        self.readStatus = readStatus ?? BatteryReadStatus.defaultStatus(percent: percent, source: source)
        self.confidence = confidence ?? BatteryReadConfidence.defaultConfidence(percent: percent, source: source)
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
        case provider
        case readStatus
        case confidence
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
        provider = try container.decodeIfPresent(BatteryProvider.self, forKey: .provider) ?? BatteryProvider.defaultProvider(for: source)
        readStatus = try container.decodeIfPresent(BatteryReadStatus.self, forKey: .readStatus) ?? BatteryReadStatus.defaultStatus(percent: percent, source: source)
        confidence = try container.decodeIfPresent(BatteryReadConfidence.self, forKey: .confidence) ?? BatteryReadConfidence.defaultConfidence(percent: percent, source: source)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public extension BatteryProvider {
    static func defaultProvider(for source: BatterySource) -> BatteryProvider {
        switch source {
        case .macPowerSource: return .macPowerSource
        case .ioRegistry: return .ioRegistry
        case .coreBluetooth: return .coreBluetoothBatteryService
        case .ioBluetooth: return .ioBluetooth
        case .systemProfiler: return .systemProfiler
        case .bluetoothUnsupported: return .bluetoothUnsupported
        case .ideviceInfo: return .ideviceInfo
        }
    }
}

public extension BatteryReadStatus {
    static func defaultStatus(percent: Int?, source: BatterySource) -> BatteryReadStatus {
        if percent != nil { return .reported }
        switch source {
        case .bluetoothUnsupported:
            return .noReport
        default:
            return .unavailable
        }
    }
}

public extension BatteryReadConfidence {
    static func defaultConfidence(percent: Int?, source: BatterySource) -> BatteryReadConfidence {
        guard percent != nil else { return .low }
        switch source {
        case .macPowerSource, .ioRegistry, .systemProfiler, .ideviceInfo:
            return .high
        case .coreBluetooth, .ioBluetooth:
            return .medium
        case .bluetoothUnsupported:
            return .low
        }
    }
}

public struct DecoratedBatterySnapshot: Equatable, Identifiable, Sendable {
    public var id: String { snapshot.id }
    public let snapshot: BatterySnapshot
    public let freshness: Freshness
}

public struct BatteryProviderAttempt: Codable, Equatable, Sendable {
    public let provider: BatteryProvider
    public let status: BatteryReadStatus
    public let candidateCount: Int
    public let message: String
    public let attemptedAt: Date

    public init(
        provider: BatteryProvider,
        status: BatteryReadStatus,
        candidateCount: Int,
        message: String,
        attemptedAt: Date
    ) {
        self.provider = provider
        self.status = status
        self.candidateCount = candidateCount
        self.message = message
        self.attemptedAt = attemptedAt
    }
}

public struct BatteryRefreshDiagnostics: Codable, Equatable, Sendable {
    public let attempts: [BatteryProviderAttempt]
    public let refreshedAt: Date
    public let snapshotCount: Int

    public init(
        attempts: [BatteryProviderAttempt] = [],
        refreshedAt: Date = Date(),
        snapshotCount: Int = 0
    ) {
        self.attempts = attempts
        self.refreshedAt = refreshedAt
        self.snapshotCount = snapshotCount
    }
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
