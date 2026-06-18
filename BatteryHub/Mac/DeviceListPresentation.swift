import Foundation

// MARK: - AirPods Component

public struct AirPodsComponent: Equatable, Sendable {
    public enum Slot: String, Equatable, Sendable {
        case `case`
        case left
        case right
    }

    public let slot: Slot
    public let percent: Int?
    public let chargeState: ChargeState
    public let freshness: Freshness
}

// MARK: - Device List Item

public enum DeviceListItem: Equatable, Sendable {
    case device(DecoratedBatterySnapshot)
    case airPods(name: String, id: String, components: [AirPodsComponent])

    public var id: String {
        switch self {
        case .device(let d): return d.id
        case .airPods(_, let id, _): return id
        }
    }
}

// MARK: - Device Section

public struct DeviceSection: Equatable, Sendable {
    public let items: [DeviceListItem]
}

// MARK: - Grouping logic

/// Pure function — no SwiftUI, safe for unit tests.
/// Returns at most two sections (Mac+peripherals, then mobile+audio),
/// empty sections omitted, order within each section preserved from input
/// (caller is responsible for pre-sorting via BatterySnapshotStore).
public func groupedDeviceItems(_ snapshots: [DecoratedBatterySnapshot]) -> [DeviceSection] {
    // 1. Aggregate AirPods components by address prefix.
    let items = aggregateAirPods(snapshots)

    // 2. Split into two ordered buckets.
    var macItems: [DeviceListItem] = []
    var mobileItems: [DeviceListItem] = []

    for item in items {
        switch item {
        case .device(let d):
            switch d.snapshot.kind {
            case .macBook, .keyboard, .mouse, .trackpad:
                macItems.append(item)
            case .iPhone, .appleWatch, .airPods, .bluetoothPeripheral:
                mobileItems.append(item)
            }
        case .airPods:
            // Aggregated AirPods always belong to mobile+audio section.
            mobileItems.append(item)
        }
    }

    return [macItems, mobileItems]
        .filter { !$0.isEmpty }
        .map { DeviceSection(items: $0) }
}

// MARK: - AirPods aggregation (internal, exposed for tests)

/// Groups `.airPods` snapshots by address prefix (strips `-case`/`-left`/`-right` suffix).
/// Non-AirPods snapshots pass through as `.device` items unchanged.
/// Groups with a single component fall back to `.device`.
func aggregateAirPods(_ snapshots: [DecoratedBatterySnapshot]) -> [DeviceListItem] {
    // Separate AirPods from everything else, preserving original order for non-AirPods.
    var nonAirPods: [(index: Int, item: DeviceListItem)] = []
    var airPodsGroups: [String: [DecoratedBatterySnapshot]] = [:] // prefix -> snapshots
    var airPodsFirstIndex: [String: Int] = [:]                    // prefix -> insertion index

    for (index, decorated) in snapshots.enumerated() {
        if decorated.snapshot.kind == .airPods {
            let prefix = airPodsPrefix(for: decorated.snapshot.deviceID)
            if airPodsGroups[prefix] == nil {
                airPodsFirstIndex[prefix] = index
                airPodsGroups[prefix] = []
            }
            airPodsGroups[prefix]!.append(decorated)
        } else {
            nonAirPods.append((index, .device(decorated)))
        }
    }

    // Build aggregated items with a stable sort-key (first-seen index in the original list).
    var result: [(index: Int, item: DeviceListItem)] = nonAirPods

    for (prefix, group) in airPodsGroups {
        let firstIndex = airPodsFirstIndex[prefix] ?? 0

        if group.count == 1 {
            // Single-component → fall back to regular device row.
            result.append((firstIndex, .device(group[0])))
        } else {
            // Aggregate name: strip the component word from the first snapshot's displayName.
            let aggregatedName = strippedAirPodsName(group[0].snapshot.displayName)

            // Build components in canonical slot order (case < left < right < unknown).
            let components: [AirPodsComponent] = group.compactMap { decorated in
                guard let slot = airPodsSlot(for: decorated.snapshot.deviceID) else { return nil }
                return AirPodsComponent(
                    slot: slot,
                    percent: decorated.snapshot.percent,
                    chargeState: decorated.snapshot.chargeState,
                    freshness: decorated.freshness
                )
            }.sorted { slotOrder($0.slot) < slotOrder($1.slot) }

            result.append((firstIndex, .airPods(name: aggregatedName, id: prefix, components: components)))
        }
    }

    // Restore original order.
    return result.sorted { $0.index < $1.index }.map { $0.item }
}

// MARK: - Helpers

/// Returns the address prefix by stripping known component suffixes.
/// IMPORTANT: Bluetooth addresses already contain dashes (e.g. "20-C1-9B-xx-xx-xx"),
/// so we cannot split on "-". Instead use hasSuffix to detect and strip exactly.
func airPodsPrefix(for deviceID: String) -> String {
    for suffix in ["-case", "-left", "-right", "-main", "-battery"] {
        if deviceID.hasSuffix(suffix) {
            return String(deviceID.dropLast(suffix.count))
        }
    }
    return deviceID
}

/// Parses the slot from the deviceID suffix.
func airPodsSlot(for deviceID: String) -> AirPodsComponent.Slot? {
    if deviceID.hasSuffix("-case") { return .case }
    if deviceID.hasSuffix("-left") { return .left }
    if deviceID.hasSuffix("-right") { return .right }
    return nil
}

/// Strips trailing component word (space-delimited) from an AirPods displayName.
/// "John's AirPods Pro Case" → "John's AirPods Pro"
func strippedAirPodsName(_ displayName: String) -> String {
    let lowered = displayName.lowercased()
    for suffix in [" case", " left", " right"] {
        if lowered.hasSuffix(suffix) {
            return String(displayName.dropLast(suffix.count))
        }
    }
    return displayName
}

private func slotOrder(_ slot: AirPodsComponent.Slot) -> Int {
    switch slot {
    case .case: return 0
    case .left: return 1
    case .right: return 2
    }
}
