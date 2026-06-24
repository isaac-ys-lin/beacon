import Foundation

public struct BatterySnapshotStore: Sendable {
    private var snapshotsByID: [String: BatterySnapshot] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public var snapshots: [BatterySnapshot] {
        snapshotsByID.values.sorted { left, right in
            if left.kind.sortOrder != right.kind.sortOrder {
                return left.kind.sortOrder < right.kind.sortOrder
            }
            return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
        }
    }

    public var decoratedSnapshots: [DecoratedBatterySnapshot] {
        snapshots.map { snapshot in
            DecoratedBatterySnapshot(
                snapshot: snapshot,
                freshness: Self.freshness(for: snapshot, now: now())
            )
        }
    }

    public var externalBatterySnapshots: [BatterySnapshot] {
        snapshots.filter(Self.isVisibleExternalBattery)
    }

    public var decoratedExternalBatterySnapshots: [DecoratedBatterySnapshot] {
        externalBatterySnapshots.map { snapshot in
            DecoratedBatterySnapshot(
                snapshot: snapshot,
                freshness: Self.freshness(for: snapshot, now: now())
            )
        }
    }

    public mutating func merge(_ incoming: [BatterySnapshot]) {
        for snapshot in incoming {
            if hasNewerDuplicateBluetoothSnapshot(matching: snapshot) {
                continue
            }
            if hasBetterDuplicateBluetoothSnapshot(matching: snapshot) {
                continue
            }
            if let existing = snapshotsByID[snapshot.deviceID], existing.updatedAt > snapshot.updatedAt {
                continue
            }
            removeDuplicateBluetoothSnapshots(matching: snapshot)
            snapshotsByID[snapshot.deviceID] = snapshot
        }
    }

    public static func freshness(for snapshot: BatterySnapshot, now: Date) -> Freshness {
        let age = now.timeIntervalSince(snapshot.updatedAt)
        if age >= 1_800 { return .expired }
        if age >= 600 { return .stale }
        return .fresh
    }

    public static func isVisibleExternalBattery(_ snapshot: BatterySnapshot) -> Bool {
        snapshot.kind != .macBook && snapshot.percent != nil
    }

    private func hasNewerDuplicateBluetoothSnapshot(matching snapshot: BatterySnapshot) -> Bool {
        guard snapshot.source.isBluetoothRelated else { return false }

        let normalizedName = snapshot.displayName.normalizedDeviceName
        return snapshotsByID.contains { id, existing in
            id != snapshot.deviceID
                && existing.source.isBluetoothRelated
                && existing.kind == snapshot.kind
                && existing.displayName.normalizedDeviceName == normalizedName
                && existing.updatedAt > snapshot.updatedAt
        }
    }

    private func hasBetterDuplicateBluetoothSnapshot(matching snapshot: BatterySnapshot) -> Bool {
        guard snapshot.source.isBluetoothRelated,
              snapshot.percent == nil
        else {
            return false
        }

        let normalizedName = snapshot.displayName.normalizedDeviceName
        return snapshotsByID.contains { id, existing in
            id != snapshot.deviceID
                && existing.source.isBluetoothRelated
                && existing.kind == snapshot.kind
                && existing.displayName.normalizedDeviceName == normalizedName
                && existing.percent != nil
                && existing.updatedAt >= snapshot.updatedAt
        }
    }

    private mutating func removeDuplicateBluetoothSnapshots(matching snapshot: BatterySnapshot) {
        guard snapshot.source.isBluetoothRelated else { return }

        let normalizedName = snapshot.displayName.normalizedDeviceName
        snapshotsByID = snapshotsByID.filter { id, existing in
            id == snapshot.deviceID
                || !existing.source.isBluetoothRelated
                || existing.kind != snapshot.kind
                || existing.displayName.normalizedDeviceName != normalizedName
        }
    }
}

private extension DeviceKind {
    var sortOrder: Int {
        switch self {
        case .macBook: return 0
        case .iPhone: return 1
        case .appleWatch: return 2
        case .airPods: return 3
        case .keyboard: return 4
        case .mouse: return 5
        case .trackpad: return 6
        case .bluetoothPeripheral: return 7
        }
    }
}

private extension BatterySource {
    var isBluetoothRelated: Bool {
        switch self {
        case .ioRegistry, .coreBluetooth, .ioBluetooth, .systemProfiler, .bluetoothUnsupported, .ideviceInfo:
            return true
        case .macPowerSource:
            return false
        }
    }
}

private extension String {
    var normalizedDeviceName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
