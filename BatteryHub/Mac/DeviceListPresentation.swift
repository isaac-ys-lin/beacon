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

    public var displayName: String {
        switch self {
        case .device(let decorated): return decorated.snapshot.displayName
        case .airPods(let name, _, _): return name
        }
    }

    public var kind: DeviceKind {
        switch self {
        case .device(let decorated): return decorated.snapshot.kind
        case .airPods: return .airPods
        }
    }

    public var connectionState: ConnectionState {
        switch self {
        case .device(let decorated):
            return decorated.snapshot.connectionState
        case .airPods:
            return .connected
        }
    }
}

// MARK: - Device Section

public struct DeviceSection: Equatable, Sendable {
    public let items: [DeviceListItem]
}

public struct BatteryOverviewSummary: Equatable, Sendable {
    public let reportedItemCount: Int
    public let lowestPercent: Int?
    public let lowBatteryItemCount: Int
    public let chargingItemCount: Int
    public let staleItemCount: Int
}

public struct BatteryOverviewDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: DeviceKind
    public let percent: Int
    public let chargeState: ChargeState
    public let freshness: Freshness
}

public enum DeviceControlQuickAction: Equatable, Sendable {
    case connectNearby
    case disconnectLowest
}

public struct DeviceControlQuickActionTarget: Equatable, Sendable {
    public let item: DeviceListItem
    public let action: DeviceContextMenuAction
}

public struct DeviceDisplayPreferences: Equatable, Sendable {
    public static let pinnedDeviceIDsKey = "BatteryHub.pinnedDeviceIDs"
    public static let hiddenDeviceIDsKey = "BatteryHub.hiddenDeviceIDs"

    public let pinnedDeviceIDs: Set<String>
    public let hiddenDeviceIDs: Set<String>

    public init(pinnedDeviceIDs: Set<String> = [], hiddenDeviceIDs: Set<String> = []) {
        self.pinnedDeviceIDs = pinnedDeviceIDs
        self.hiddenDeviceIDs = hiddenDeviceIDs
    }

    public static func load(from defaults: UserDefaults = .standard) -> DeviceDisplayPreferences {
        DeviceDisplayPreferences(
            pinnedDeviceIDs: Set(defaults.stringArray(forKey: pinnedDeviceIDsKey) ?? []),
            hiddenDeviceIDs: Set(defaults.stringArray(forKey: hiddenDeviceIDsKey) ?? [])
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(pinnedDeviceIDs.sorted(), forKey: Self.pinnedDeviceIDsKey)
        defaults.set(hiddenDeviceIDs.sorted(), forKey: Self.hiddenDeviceIDsKey)
    }

    public func isPinned(_ item: DeviceListItem) -> Bool {
        pinnedDeviceIDs.contains(item.id)
    }

    public func isHidden(_ item: DeviceListItem) -> Bool {
        hiddenDeviceIDs.contains(item.id)
    }

    public func togglingPin(for item: DeviceListItem) -> DeviceDisplayPreferences {
        var nextPinned = pinnedDeviceIDs
        if nextPinned.contains(item.id) {
            nextPinned.remove(item.id)
        } else {
            nextPinned.insert(item.id)
        }
        return DeviceDisplayPreferences(
            pinnedDeviceIDs: nextPinned,
            hiddenDeviceIDs: hiddenDeviceIDs
        )
    }

    public func settingPinned(_ isPinned: Bool, for item: DeviceListItem) -> DeviceDisplayPreferences {
        var nextPinned = pinnedDeviceIDs
        if isPinned {
            nextPinned.insert(item.id)
        } else {
            nextPinned.remove(item.id)
        }
        return DeviceDisplayPreferences(
            pinnedDeviceIDs: nextPinned,
            hiddenDeviceIDs: hiddenDeviceIDs
        )
    }

    public func hiding(_ item: DeviceListItem) -> DeviceDisplayPreferences {
        DeviceDisplayPreferences(
            pinnedDeviceIDs: pinnedDeviceIDs.subtracting([item.id]),
            hiddenDeviceIDs: hiddenDeviceIDs.union([item.id])
        )
    }

    public func restoring(_ item: DeviceListItem) -> DeviceDisplayPreferences {
        DeviceDisplayPreferences(
            pinnedDeviceIDs: pinnedDeviceIDs,
            hiddenDeviceIDs: hiddenDeviceIDs.subtracting([item.id])
        )
    }

    public func restoringAllHidden() -> DeviceDisplayPreferences {
        DeviceDisplayPreferences(
            pinnedDeviceIDs: pinnedDeviceIDs,
            hiddenDeviceIDs: []
        )
    }
}

public struct DeviceInspectorItem: Equatable, Identifiable, Sendable {
    public let item: DeviceListItem
    public let isPinned: Bool
    public let isUserHidden: Bool
    public let isUnavailable: Bool

    public var isHidden: Bool {
        isUserHidden || isUnavailable
    }

    public var id: String { item.id }
    public var displayName: String { item.displayName }
    public var kind: DeviceKind { item.kind }
}

public enum AirPodsListeningModePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case noiseCancellation
    case transparency
    case off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .noiseCancellation: return "Noise Cancellation"
        case .transparency: return "Transparency"
        case .off: return "Off"
        }
    }

    public var shortTitle: String {
        switch self {
        case .automatic: return "Auto"
        case .noiseCancellation: return "Noise"
        case .transparency: return "Trans"
        case .off: return "Off"
        }
    }

    public var systemImage: String {
        switch self {
        case .automatic: return "sparkles"
        case .noiseCancellation: return "ear.badge.waveform"
        case .transparency: return "waveform"
        case .off: return "ear"
        }
    }
}

public enum AirPodsMicrophonePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case left
    case right

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .left: return "Always Left"
        case .right: return "Always Right"
        }
    }

    public var shortTitle: String {
        switch self {
        case .automatic: return "Auto"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

public struct AirPodsAudioPreferences: Equatable, Sendable {
    public static let listeningModePrefix = "BatteryHub.airPodsAudio.listeningMode."
    public static let microphonePrefix = "BatteryHub.airPodsAudio.microphone."

    public let listeningMode: AirPodsListeningModePreference
    public let microphone: AirPodsMicrophonePreference

    public init(
        listeningMode: AirPodsListeningModePreference = .automatic,
        microphone: AirPodsMicrophonePreference = .automatic
    ) {
        self.listeningMode = listeningMode
        self.microphone = microphone
    }

    public static func load(
        for deviceID: String,
        defaults: UserDefaults = .standard
    ) -> AirPodsAudioPreferences {
        let listeningMode = defaults.string(forKey: listeningModeKey(for: deviceID))
            .flatMap(AirPodsListeningModePreference.init(rawValue:)) ?? .automatic
        let microphone = defaults.string(forKey: microphoneKey(for: deviceID))
            .flatMap(AirPodsMicrophonePreference.init(rawValue:)) ?? .automatic
        return AirPodsAudioPreferences(listeningMode: listeningMode, microphone: microphone)
    }

    public func save(
        for deviceID: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(listeningMode.rawValue, forKey: Self.listeningModeKey(for: deviceID))
        defaults.set(microphone.rawValue, forKey: Self.microphoneKey(for: deviceID))
    }

    public func settingListeningMode(
        _ listeningMode: AirPodsListeningModePreference
    ) -> AirPodsAudioPreferences {
        AirPodsAudioPreferences(listeningMode: listeningMode, microphone: microphone)
    }

    public func settingMicrophone(
        _ microphone: AirPodsMicrophonePreference
    ) -> AirPodsAudioPreferences {
        AirPodsAudioPreferences(listeningMode: listeningMode, microphone: microphone)
    }

    public static func reset(for deviceID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: listeningModeKey(for: deviceID))
        defaults.removeObject(forKey: microphoneKey(for: deviceID))
    }

    public static func listeningModeKey(for deviceID: String) -> String {
        listeningModePrefix + deviceID
    }

    public static func microphoneKey(for deviceID: String) -> String {
        microphonePrefix + deviceID
    }
}

public enum DeviceContextMenuAction: String, CaseIterable, Identifiable, Equatable, Sendable {
    case batteryAlerts
    case audioControls
    case options
    case refresh
    case connect
    case pin
    case unpin
    case disconnect
    case remove

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .batteryAlerts: return "bell.badge"
        case .audioControls: return "waveform"
        case .options: return "slider.horizontal.3"
        case .refresh: return "arrow.clockwise"
        case .connect: return "dot.radiowaves.left.and.right"
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        case .disconnect: return "bolt.horizontal.circle"
        case .remove: return "minus.circle"
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .batteryAlerts, .options, .refresh, .pin, .unpin, .remove:
            return true
        case .audioControls, .connect, .disconnect:
            return false
        }
    }

    public func isEnabled(for item: DeviceListItem) -> Bool {
        switch self {
        case .audioControls:
            return item.kind == .airPods
        case .connect:
            return BluetoothDeviceControlSupport.canConnect(item)
        case .disconnect:
            return BluetoothDeviceControlSupport.canDisconnect(item)
        default:
            return isEnabled
        }
    }

    public func title(for displayName: String) -> String {
        switch self {
        case .batteryAlerts: return "Battery Alerts..."
        case .audioControls: return "Audio Controls..."
        case .options: return "Options"
        case .refresh: return "Refresh Battery"
        case .connect: return "Connect"
        case .pin: return "Pin \(displayName)"
        case .unpin: return "Unpin \(displayName)"
        case .disconnect: return "Disconnect"
        case .remove: return "Remove from BatteryHub"
        }
    }
}

public enum BluetoothDeviceControlSupport {
    public static func canConnect(_ item: DeviceListItem) -> Bool {
        isAddressBackedControllableDevice(item) && item.connectionState == .disconnected
    }

    public static func canDisconnect(_ item: DeviceListItem) -> Bool {
        isAddressBackedControllableDevice(item) && item.connectionState == .connected
    }

    private static func isAddressBackedControllableDevice(_ item: DeviceListItem) -> Bool {
        guard normalizedAddress(from: item.id) != nil else { return false }
        switch item.kind {
        case .airPods, .keyboard, .mouse, .trackpad, .bluetoothPeripheral:
            return true
        case .macBook, .iPhone, .appleWatch:
            return false
        }
    }

    public static func normalizedAddress(from deviceID: String) -> String? {
        let unprefixedID = deviceID.hasPrefix("bluetooth-")
            ? String(deviceID.dropFirst("bluetooth-".count))
            : deviceID
        let baseID = airPodsPrefix(for: unprefixedID)
        let separator: Character
        if baseID.contains("-") {
            separator = "-"
        } else if baseID.contains(":") {
            separator = ":"
        } else {
            return nil
        }

        let parts = baseID.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 6,
              parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) })
        else {
            return nil
        }

        return parts.map { $0.lowercased() }.joined(separator: ":")
    }
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

public func configuredDeviceSections(
    _ snapshots: [DecoratedBatterySnapshot],
    preferences: DeviceDisplayPreferences
) -> [DeviceSection] {
    groupedDeviceItems(snapshots)
        .compactMap { section in
            let visibleItems = section.items.enumerated()
                .filter { !preferences.isHidden($0.element) }
                .sorted { lhs, rhs in
                    let lhsPinned = preferences.isPinned(lhs.element)
                    let rhsPinned = preferences.isPinned(rhs.element)
                    if lhsPinned != rhsPinned {
                        return lhsPinned && !rhsPinned
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            guard !visibleItems.isEmpty else { return nil }
            return DeviceSection(items: visibleItems)
        }
}

public func dashboardDeviceSections(
    _ snapshots: [DecoratedBatterySnapshot],
    preferences: DeviceDisplayPreferences
) -> [DeviceSection] {
    configuredDeviceSections(snapshots, preferences: preferences)
        .compactMap { section in
            let dashboardItems = section.items.filter(isDashboardVisibleItem)
            guard !dashboardItems.isEmpty else { return nil }
            return DeviceSection(items: dashboardItems)
        }
}

public func isDashboardVisibleItem(_ item: DeviceListItem) -> Bool {
    switch item {
    case .device(let decorated):
        return decorated.snapshot.connectionState == .connected
            && decorated.snapshot.percent != nil
    case .airPods(_, _, let components):
        return components.contains { $0.percent != nil }
    }
}

public func deviceInspectorItems(
    _ snapshots: [DecoratedBatterySnapshot],
    preferences: DeviceDisplayPreferences
) -> [DeviceInspectorItem] {
    groupedDeviceItems(snapshots)
        .flatMap(\.items)
        .enumerated()
        .sorted { lhs, rhs in
            let lhsHidden = isInspectorHiddenItem(lhs.element, preferences: preferences)
            let rhsHidden = isInspectorHiddenItem(rhs.element, preferences: preferences)
            if lhsHidden != rhsHidden {
                return !lhsHidden && rhsHidden
            }

            let lhsPinned = preferences.isPinned(lhs.element)
            let rhsPinned = preferences.isPinned(rhs.element)
            if lhsPinned != rhsPinned {
                return lhsPinned && !rhsPinned
            }

            return lhs.offset < rhs.offset
        }
        .map { _, item in
            DeviceInspectorItem(
                item: item,
                isPinned: preferences.isPinned(item),
                isUserHidden: preferences.isHidden(item),
                isUnavailable: !isDashboardVisibleItem(item)
            )
        }
}

public func isInspectorHiddenItem(
    _ item: DeviceListItem,
    preferences: DeviceDisplayPreferences
) -> Bool {
    preferences.isHidden(item) || !isDashboardVisibleItem(item)
}

public func displayedDeviceInspectorItems(
    _ items: [DeviceInspectorItem],
    showHiddenUnavailable: Bool
) -> [DeviceInspectorItem] {
    if showHiddenUnavailable {
        return items
    }
    return items.filter { !$0.isHidden }
}

public func batteryOverviewSummary(
    for sections: [DeviceSection],
    lowBatteryThreshold threshold: Int
) -> BatteryOverviewSummary {
    var reportedItemCount = 0
    var lowestPercent: Int?
    var lowBatteryItemCount = 0
    var chargingItemCount = 0
    var staleItemCount = 0

    for section in sections {
        for item in section.items {
            switch item {
            case .device(let decorated):
                if let percent = decorated.snapshot.percent {
                    reportedItemCount += 1
                    lowestPercent = minPercent(lowestPercent, percent)
                    if percent <= threshold,
                       decorated.snapshot.chargeState != .charging,
                       decorated.snapshot.chargeState != .full {
                        lowBatteryItemCount += 1
                    }
                }

                if decorated.snapshot.chargeState == .charging {
                    chargingItemCount += 1
                }
                if decorated.freshness != .fresh {
                    staleItemCount += 1
                }

            case .airPods(_, _, let components):
                let percents = components.compactMap(\.percent)
                if let componentLowest = percents.min() {
                    reportedItemCount += 1
                    lowestPercent = minPercent(lowestPercent, componentLowest)
                }

                if components.contains(where: { component in
                    guard let percent = component.percent else { return false }
                    return percent <= threshold
                        && component.chargeState != .charging
                        && component.chargeState != .full
                }) {
                    lowBatteryItemCount += 1
                }
                if components.contains(where: { $0.chargeState == .charging }) {
                    chargingItemCount += 1
                }
                if components.contains(where: { $0.freshness != .fresh }) {
                    staleItemCount += 1
                }
            }
        }
    }

    return BatteryOverviewSummary(
        reportedItemCount: reportedItemCount,
        lowestPercent: lowestPercent,
        lowBatteryItemCount: lowBatteryItemCount,
        chargingItemCount: chargingItemCount,
        staleItemCount: staleItemCount
    )
}

public func batteryOverviewDevices(
    for sections: [DeviceSection],
    limit: Int = 4
) -> [BatteryOverviewDevice] {
    var devices: [BatteryOverviewDevice] = []

    for section in sections {
        for item in section.items {
            switch item {
            case .device(let decorated):
                guard let percent = decorated.snapshot.percent else { continue }
                devices.append(
                    BatteryOverviewDevice(
                        id: decorated.id,
                        displayName: decorated.snapshot.displayName,
                        kind: decorated.snapshot.kind,
                        percent: percent,
                        chargeState: decorated.snapshot.chargeState,
                        freshness: decorated.freshness
                    )
                )

            case .airPods(let name, let id, let components):
                let percents = components.compactMap(\.percent)
                guard let lowestPercent = percents.min() else { continue }
                let chargeState: ChargeState = components.contains { $0.chargeState == .charging || $0.chargeState == .full }
                    ? .charging
                    : .unplugged
                let freshness: Freshness = components.contains { $0.freshness == .expired }
                    ? .expired
                    : (components.contains { $0.freshness == .stale } ? .stale : .fresh)
                devices.append(
                    BatteryOverviewDevice(
                        id: id,
                        displayName: name,
                        kind: .airPods,
                        percent: lowestPercent,
                        chargeState: chargeState,
                        freshness: freshness
                    )
                )
            }
        }
    }

    return devices
        .sorted { lhs, rhs in
            if lhs.percent != rhs.percent {
                return lhs.percent < rhs.percent
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        .prefix(Swift.max(0, limit))
        .map { $0 }
}

public func deviceControlTarget(
    for action: DeviceControlQuickAction,
    snapshots: [DecoratedBatterySnapshot],
    preferences: DeviceDisplayPreferences = .load()
) -> DeviceControlQuickActionTarget? {
    let items = configuredDeviceSections(snapshots, preferences: preferences)
        .flatMap(\.items)

    switch action {
    case .connectNearby:
        return items
            .filter(BluetoothDeviceControlSupport.canConnect)
            .sorted(by: controlTargetSort)
            .first
            .map { DeviceControlQuickActionTarget(item: $0, action: .connect) }
    case .disconnectLowest:
        return items
            .filter(BluetoothDeviceControlSupport.canDisconnect)
            .sorted(by: controlTargetSort)
            .first
            .map { DeviceControlQuickActionTarget(item: $0, action: .disconnect) }
    }
}

public func deviceContextMenuActions(
    for item: DeviceListItem,
    preferences: DeviceDisplayPreferences = DeviceDisplayPreferences()
) -> [DeviceContextMenuAction] {
    let pinAction: DeviceContextMenuAction = preferences.isPinned(item) ? .unpin : .pin
    let connectionAction: DeviceContextMenuAction = item.connectionState == .disconnected ? .connect : .disconnect

    switch item {
    case .device(let decorated):
        switch decorated.snapshot.kind {
        case .airPods:
            return [.batteryAlerts, .audioControls, .options, .refresh, pinAction, connectionAction, .remove]
        case .keyboard, .mouse, .trackpad, .bluetoothPeripheral:
            return [.batteryAlerts, .options, .refresh, pinAction, connectionAction, .remove]
        case .macBook, .iPhone, .appleWatch:
            return [.batteryAlerts, .options, .refresh, pinAction, .remove]
        }
    case .airPods:
        return [.batteryAlerts, .audioControls, .options, .refresh, pinAction, connectionAction, .remove]
    }
}

private func controlTargetSort(_ lhs: DeviceListItem, _ rhs: DeviceListItem) -> Bool {
    let lhsPercent = controlSortPercent(lhs)
    let rhsPercent = controlSortPercent(rhs)
    if lhsPercent != rhsPercent {
        return lhsPercent < rhsPercent
    }
    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
}

private func controlSortPercent(_ item: DeviceListItem) -> Int {
    switch item {
    case .device(let decorated):
        return decorated.snapshot.percent ?? Int.max
    case .airPods(_, _, let components):
        return components.compactMap(\.percent).min() ?? Int.max
    }
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

private func minPercent(_ current: Int?, _ candidate: Int) -> Int {
    guard let current else { return candidate }
    return Swift.min(current, candidate)
}
