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
            if let existing = snapshotsByID[snapshot.deviceID], existing.updatedAt > snapshot.updatedAt {
                continue
            }
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
}

private extension DeviceKind {
    var sortOrder: Int {
        switch self {
        case .macBook: return 0
        case .iPhone: return 1
        case .appleWatch: return 2
        case .keyboard: return 3
        case .bluetoothPeripheral: return 4
        }
    }
}
