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

    /// Merges the latest live read, then drops any Bluetooth-sourced device that
    /// no provider reported this cycle. Without this, a disconnected or removed
    /// device keeps its stale `.connected` snapshot (under a now-orphaned id)
    /// until the 30-minute freshness window expires — so it lingers in the menu.
    /// Matching is by (kind, normalized name) rather than raw deviceID so the
    /// prune survives the id churn between providers.
    ///
    /// Skips pruning when the live read produced no Bluetooth snapshots at all
    /// (a failed/empty scan) to avoid wiping the whole list on a transient miss.
    public mutating func reconcile(with liveSnapshots: [BatterySnapshot]) {
        merge(liveSnapshots)

        let liveBluetooth = liveSnapshots.filter { $0.source.isBluetoothRelated }
        guard !liveBluetooth.isEmpty else { return }

        let liveKeys = Set(liveBluetooth.map(Self.reconciliationKey))
        snapshotsByID = snapshotsByID.filter { _, existing in
            !existing.source.isBluetoothRelated || liveKeys.contains(Self.reconciliationKey(existing))
        }
    }

    private static func reconciliationKey(_ snapshot: BatterySnapshot) -> String {
        "\(snapshot.kind)|\(snapshot.displayName.normalizedDeviceName)"
    }

    /// Replaces each stored snapshot's charge state with `resolve(snapshot)`.
    /// Used to layer in heuristic (battery-trend) charging for devices that
    /// report no hardware charge signal, without touching recorded history.
    public mutating func applyInferredChargeStates(_ resolve: (BatterySnapshot) -> ChargeState) {
        snapshotsByID = snapshotsByID.mapValues { snapshot in
            let inferred = resolve(snapshot)
            return inferred == snapshot.chargeState ? snapshot : snapshot.withChargeState(inferred)
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
