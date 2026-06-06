import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case macBook
    case iPhone
    case appleWatch
    case keyboard
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

public enum Freshness: String, Codable, Sendable {
    case fresh
    case stale
    case expired
}

public struct BatterySnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { deviceID }
    public let deviceID: String
    public let displayName: String
    public let kind: DeviceKind
    public let percent: Int?
    public let chargeState: ChargeState
    public let source: BatterySource
    public let updatedAt: Date

    public init(
        deviceID: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState,
        source: BatterySource,
        updatedAt: Date
    ) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.kind = kind
        self.percent = percent
        self.chargeState = chargeState
        self.source = source
        self.updatedAt = updatedAt
    }
}

public struct DecoratedBatterySnapshot: Equatable, Identifiable, Sendable {
    public var id: String { snapshot.id }
    public let snapshot: BatterySnapshot
    public let freshness: Freshness
}
