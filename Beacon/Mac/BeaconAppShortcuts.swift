import AppIntents
import Foundation

@MainActor
final class BeaconIntentBridge {
    static let shared = BeaconIntentBridge()

    private var actionHandler: ((BeaconQuickAction) -> Bool)?
    private var snapshotProvider: (() -> [DecoratedBatterySnapshot])?

    private init() {}

    func register(
        handler: @escaping (BeaconQuickAction) -> Bool,
        snapshotProvider: (() -> [DecoratedBatterySnapshot])? = nil
    ) {
        actionHandler = handler
        self.snapshotProvider = snapshotProvider
    }

    @discardableResult
    func perform(_ action: BeaconQuickAction) -> Bool {
        guard action.isSupported, let actionHandler else {
            return false
        }
        return actionHandler(action)
    }

    func snapshots() -> [DecoratedBatterySnapshot] {
        snapshotProvider?() ?? []
    }
}

struct BeaconShortcutSummary: Equatable {
    let reportedDeviceCount: Int
    let lowestBatteryLine: String?
    let lowBatteryLines: [String]
    let chargingLines: [String]
    let staleDeviceCount: Int

    var summaryText: String {
        var lines: [String] = []
        lines.append(
            BeaconL10n.format(
                "Beacon: %d reporting device%@.",
                reportedDeviceCount,
                reportedDeviceCount == 1 ? "" : "s"
            )
        )

        if let lowestBatteryLine {
            lines.append(BeaconL10n.format("Lowest: %@.", lowestBatteryLine))
        } else {
            lines.append(BeaconL10n.string("Lowest: no reported battery levels."))
        }

        if lowBatteryLines.isEmpty {
            lines.append(BeaconL10n.string("Low battery: none."))
        } else {
            lines.append(
                BeaconL10n.format(
                    "Low battery: %@.",
                    lowBatteryLines.joined(separator: ", ")
                )
            )
        }

        if !chargingLines.isEmpty {
            lines.append(
                BeaconL10n.format(
                    "Charging: %@.",
                    chargingLines.joined(separator: ", ")
                )
            )
        }

        if staleDeviceCount > 0 {
            lines.append(BeaconL10n.format("Stale reports: %d.", staleDeviceCount))
        }

        return lines.joined(separator: " ")
    }
}

enum BeaconShortcutSnapshotFormatter {
    static func summary(
        for snapshots: [DecoratedBatterySnapshot],
        lowBatteryThreshold: Int = LowBatteryNotifier.threshold
    ) -> BeaconShortcutSummary {
        let reported = snapshots
            .filter { $0.freshness != .expired }
            .compactMap { lineItem(for: $0) }

        let sortedByBattery = reported.sorted { lhs, rhs in
            if lhs.percent != rhs.percent {
                return lhs.percent < rhs.percent
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let lowBatteryLines = sortedByBattery
            .filter { item in
                item.percent <= lowBatteryThreshold
                    && item.chargeState != .charging
                    && item.chargeState != .full
            }
            .map(\.displayLine)

        let chargingLines = reported
            .filter { $0.chargeState == .charging || $0.chargeState == .full }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.displayLine)

        return BeaconShortcutSummary(
            reportedDeviceCount: reported.count,
            lowestBatteryLine: sortedByBattery.first?.displayLine,
            lowBatteryLines: lowBatteryLines,
            chargingLines: chargingLines,
            staleDeviceCount: snapshots.filter { $0.freshness == .stale }.count
        )
    }

    static func lowestBatteryText(for snapshots: [DecoratedBatterySnapshot]) -> String {
        summary(for: snapshots).lowestBatteryLine
            ?? BeaconL10n.string("No reported battery levels.")
    }

    static func lowBatteryText(
        for snapshots: [DecoratedBatterySnapshot],
        lowBatteryThreshold: Int = LowBatteryNotifier.threshold
    ) -> String {
        let lines = summary(
            for: snapshots,
            lowBatteryThreshold: lowBatteryThreshold
        ).lowBatteryLines
        return lines.isEmpty
            ? BeaconL10n.string("No low battery devices.")
            : lines.joined(separator: ", ")
    }

    static func batteryTrendText(
        for snapshots: [DecoratedBatterySnapshot],
        defaults: UserDefaults = .standard
    ) -> String {
        let lines = snapshots
            .filter { $0.freshness != .expired }
            .compactMap { decorated -> String? in
                guard let summary = BatteryHistoryStore.summary(
                    for: decorated.snapshot.deviceID,
                    defaults: defaults
                ) else {
                    return nil
                }
                return BeaconL10n.format(
                    "%1$@: %2$@, range %3$d%%-%4$d%% across %5$d reports.",
                    decorated.snapshot.displayName,
                    summary.trendDescription,
                    summary.minimumPercent,
                    summary.maximumPercent,
                    summary.samples.count
                )
            }

        return lines.isEmpty
            ? BeaconL10n.string("No battery trends yet. Beacon builds trends as reports arrive.")
            : lines.joined(separator: " ")
    }

    private static func lineItem(for decorated: DecoratedBatterySnapshot) -> ShortcutBatteryLineItem? {
        guard let percent = decorated.snapshot.percent else { return nil }
        return ShortcutBatteryLineItem(
            name: decorated.snapshot.displayName,
            percent: percent,
            chargeState: decorated.snapshot.chargeState
        )
    }
}

private struct ShortcutBatteryLineItem: Equatable {
    let name: String
    let percent: Int
    let chargeState: ChargeState

    var displayLine: String {
        "\(name) \(percent)%"
    }
}

struct ShowBeaconDashboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Battery Dashboard"
    static let description = IntentDescription("Show or hide the Beacon menu bar dashboard.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BeaconIntentBridge.shared.perform(.showDashboard)
        return .result()
    }
}

struct RefreshBeaconBatteriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Batteries"
    static let description = IntentDescription("Refresh battery reports from locally connected devices.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BeaconIntentBridge.shared.perform(.refreshBatteries)
        return .result()
    }
}

struct OpenBeaconSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Beacon Settings"
    static let description = IntentDescription("Open the Beacon settings window.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BeaconIntentBridge.shared.perform(.openSettings)
        return .result()
    }
}

struct AddBeaconDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Up a Battery Device"
    static let description = IntentDescription("Open Beacon's guide for pairing or connecting a supported device.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BeaconIntentBridge.shared.perform(.addDevice)
        return .result()
    }
}

struct OpenBeaconBluetoothSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Bluetooth Settings"
    static let description = IntentDescription("Open macOS Bluetooth Settings for pairing nearby battery devices.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BeaconIntentBridge.shared.perform(.openBluetoothSettings)
        return .result()
    }
}

struct ConnectBeaconNearbyDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect Prioritized Device"
    static let description = IntentDescription("Connect a visible disconnected paired Bluetooth device, prioritizing the lowest reported battery.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let didPerform = BeaconIntentBridge.shared.perform(.connectNearbyDevice)
        return .result(
            value: didPerform
                ? BeaconL10n.string("Beacon requested a connection for the prioritized paired Bluetooth device.")
                : BeaconL10n.string("Beacon could not find or connect an eligible paired Bluetooth device.")
        )
    }
}

struct DisconnectBeaconLowestDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnect Lowest Battery Device"
    static let description = IntentDescription("Disconnect the visible connected Bluetooth device with the lowest reported battery.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let didPerform = BeaconIntentBridge.shared.perform(.disconnectLowestDevice)
        return .result(
            value: didPerform
                ? BeaconL10n.string("Beacon requested a disconnect for the lowest battery Bluetooth device.")
                : BeaconL10n.string("Beacon could not find or disconnect an eligible Bluetooth device.")
        )
    }
}

struct GetBeaconSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Summary"
    static let description = IntentDescription("Get a text summary of current Beacon device battery levels.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = BeaconShortcutSnapshotFormatter.summary(
            for: BeaconIntentBridge.shared.snapshots()
        )
        return .result(value: summary.summaryText)
    }
}

struct GetBeaconLowestBatteryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Lowest Battery"
    static let description = IntentDescription("Get the device with the lowest currently reported battery level.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(
            value: BeaconShortcutSnapshotFormatter.lowestBatteryText(
                for: BeaconIntentBridge.shared.snapshots()
            )
        )
    }
}

struct GetBeaconLowBatteryDevicesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Low Battery Devices"
    static let description = IntentDescription("Get a comma-separated list of devices below the current Beacon alert threshold.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(
            value: BeaconShortcutSnapshotFormatter.lowBatteryText(
                for: BeaconIntentBridge.shared.snapshots()
            )
        )
    }
}

struct GetBeaconBatteryTrendsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Trends"
    static let description = IntentDescription("Get local Beacon battery trend summaries for currently reporting devices.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(
            value: BeaconShortcutSnapshotFormatter.batteryTrendText(
                for: BeaconIntentBridge.shared.snapshots()
            )
        )
    }
}

struct BeaconAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowBeaconDashboardIntent(),
            phrases: [
                "Show \(.applicationName)",
                "Show battery dashboard in \(.applicationName)"
            ],
            shortTitle: "Show Dashboard",
            systemImageName: "macwindow"
        )

        AppShortcut(
            intent: RefreshBeaconBatteriesIntent(),
            phrases: [
                "Refresh \(.applicationName)",
                "Refresh batteries in \(.applicationName)"
            ],
            shortTitle: "Refresh Batteries",
            systemImageName: "arrow.clockwise"
        )

        AppShortcut(
            intent: OpenBeaconSettingsIntent(),
            phrases: [
                "Open \(.applicationName) settings",
                "Show settings in \(.applicationName)"
            ],
            shortTitle: "Open Settings",
            systemImageName: "gearshape.2.fill"
        )

        AppShortcut(
            intent: AddBeaconDeviceIntent(),
            phrases: [
                "Set up a device in \(.applicationName)",
                "Show device setup in \(.applicationName)"
            ],
            shortTitle: "Set Up Device",
            systemImageName: "plus"
        )

        AppShortcut(
            intent: ConnectBeaconNearbyDeviceIntent(),
            phrases: [
                "Connect prioritized device with \(.applicationName)",
                "Connect paired device in \(.applicationName)"
            ],
            shortTitle: "Connect Device",
            systemImageName: "dot.radiowaves.left.and.right"
        )

        AppShortcut(
            intent: DisconnectBeaconLowestDeviceIntent(),
            phrases: [
                "Disconnect lowest battery device with \(.applicationName)",
                "Disconnect lowest device in \(.applicationName)"
            ],
            shortTitle: "Disconnect Device",
            systemImageName: "bolt.horizontal.circle"
        )

        AppShortcut(
            intent: GetBeaconSummaryIntent(),
            phrases: [
                "Get battery summary from \(.applicationName)",
                "Check batteries with \(.applicationName)"
            ],
            shortTitle: "Battery Summary",
            systemImageName: "list.bullet.rectangle"
        )

        AppShortcut(
            intent: GetBeaconLowestBatteryIntent(),
            phrases: [
                "Get lowest battery from \(.applicationName)",
                "Find lowest battery in \(.applicationName)"
            ],
            shortTitle: "Lowest Battery",
            systemImageName: "battery.25"
        )

        AppShortcut(
            intent: GetBeaconLowBatteryDevicesIntent(),
            phrases: [
                "Get low battery devices from \(.applicationName)",
                "List low batteries in \(.applicationName)"
            ],
            shortTitle: "Low Batteries",
            systemImageName: "exclamationmark.triangle"
        )

        AppShortcut(
            intent: GetBeaconBatteryTrendsIntent(),
            phrases: [
                "Get battery trends from \(.applicationName)",
                "Check battery trends with \(.applicationName)"
            ],
            shortTitle: "Battery Trends",
            systemImageName: "chart.xyaxis.line"
        )

    }
}
