import AppKit
import SwiftUI

enum StatusWindowPreferences {
    static let showMenuBarBatteryKey = "Beacon.showMenuBarBattery"
    static let didChangeNotification = Notification.Name("Beacon.statusWindowPreferencesDidChange")

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

struct StatusWindowConfiguration: Equatable {
    var showsMenuBarBattery: Bool

    static func load(from defaults: UserDefaults = .standard) -> StatusWindowConfiguration {
        return StatusWindowConfiguration(
            showsMenuBarBattery: boolPreference(
                StatusWindowPreferences.showMenuBarBatteryKey,
                defaultValue: false,
                defaults: defaults
            )
        )
    }

    private static func boolPreference(
        _ key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}

/// Metrics of the system Bluetooth menu (measured from a macOS 26 capture):
/// 32pt rows, a bold title row, inset separators and a "… Settings" footer row.
enum StatusMenuSizing {
    static let width: CGFloat = 386
    static let headerHeight: CGFloat = 42
    static let rowHeight: CGFloat = 32
    static let listVerticalPadding: CGFloat = 6
    static let footerHeight: CGFloat = 34
    static let bottomPadding: CGFloat = 6
    static let separatorHeight: CGFloat = 1
    static let contentMaxHeight: CGFloat = 620

    static func preferredContentSize(
        dashboardItemCount: Int,
        visibleScreenHeight: CGFloat,
        supplementalHeight: CGFloat = 0
    ) -> CGSize {
        // Header, separator, footer row and bottom inset are always present;
        // the device list adds its own separator, padding and rows.
        let chrome = headerHeight + separatorHeight + footerHeight + bottomPadding
        let list = dashboardItemCount == 0
            ? 0
            : separatorHeight + listVerticalPadding * 2 + CGFloat(dashboardItemCount) * rowHeight
        let desiredHeight = chrome + list + supplementalHeight
        let screenCappedHeight = max(240, visibleScreenHeight - 46)
        return CGSize(width: width, height: min(desiredHeight, screenCappedHeight))
    }
}

// MARK: - StatusMenuView

struct StatusMenuView: View {
    @ObservedObject var connections: BluetoothConnectionController
    let snapshots: [DecoratedBatterySnapshot]
    let isRefreshing: Bool
    let isPreviewingData: Bool
    let configuration: StatusWindowConfiguration
    let refreshDiagnostics: BatteryRefreshDiagnostics
    let onSetUpDevice: (() -> Void)?
    let otherDevicesExpanded: Bool
    let onToggleOtherDevices: () -> Void
    let onRefresh: () -> Void
    let onOpenSettings: (SettingsPane, String?) -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayPreferences = DeviceDisplayPreferences.load()

    init(
        snapshots: [DecoratedBatterySnapshot],
        connections: BluetoothConnectionController = BluetoothConnectionController(),
        isRefreshing: Bool = false,
        isPreviewingData: Bool = false,
        configuration: StatusWindowConfiguration = .load(),
        refreshDiagnostics: BatteryRefreshDiagnostics = BatteryRefreshDiagnostics(),
        onSetUpDevice: (() -> Void)? = nil,
        otherDevicesExpanded: Bool = false,
        onToggleOtherDevices: @escaping () -> Void = {},
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping (SettingsPane, String?) -> Void = { _, _ in },
        initialDisplayPreferences: DeviceDisplayPreferences = .load()
    ) {
        self.snapshots = snapshots
        self.connections = connections
        self.isRefreshing = isRefreshing
        self.isPreviewingData = isPreviewingData
        self.configuration = configuration
        self.refreshDiagnostics = refreshDiagnostics
        self.onSetUpDevice = onSetUpDevice
        self.otherDevicesExpanded = otherDevicesExpanded
        self.onToggleOtherDevices = onToggleOtherDevices
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        _displayPreferences = State(initialValue: initialDisplayPreferences)
    }

    var body: some View {
        nativeBody
    }

    private var nativeBody: some View {
        VStack(spacing: 0) {
            nativeHeader

            let recovery = DeviceSetupRecoveryState.resolve(
                visibleCount: visibleItemCount, isRefreshing: isRefreshing, diagnostics: refreshDiagnostics
            )
            if recovery != .ready {
                menuSeparator
                DeviceSetupRecoveryCard(
                    state: recovery, isRefreshing: isRefreshing,
                    onSetUp: { if let onSetUpDevice { onSetUpDevice() } else { onOpenSettings(.devices, nil) } },
                    onRefresh: onRefresh,
                    surfaced: false
                ).padding(.horizontal, 14).padding(.vertical, 10)
            }
            if refreshDiagnostics.attempts.contains(where: { $0.status != .reported && $0.status != .noReport }) {
                Button {
                    let affectedID = refreshDiagnostics.attempts.flatMap { $0.affectedDeviceIDs ?? [] }.first
                    onOpenSettings(.devices, affectedID)
                } label: {
                    Label("Refresh needs attention", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.borderless).font(.caption)
                .accessibilityIdentifier("status.refresh-problems")
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            if !sections.isEmpty {
                menuSeparator
                nativeDeviceList
            }

            menuSeparator
            settingsFooter
        }
        .padding(.bottom, StatusMenuSizing.bottomPadding)
        .frame(width: statusWindowWidth)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status.menu")
        .beaconPopoverSurface(
            cornerRadius: NativeMacStyle.popoverCornerRadius,
            colorScheme: appearanceTheme.colorSchemeOverride ?? colorScheme
        )
        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
    }

    private var nativeHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Beacon")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .help(nativeHeaderSubtitle)
                .accessibilityValue(Text(nativeHeaderSubtitle))

            if isPreviewingData {
                Text("Preview")
                    .font(DesignTokens.Typography.caption2Emphasis)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule(style: .continuous).fill(theme.hover))
                    .help("Sample devices, not live Bluetooth.")
                    .accessibilityIdentifier("status.preview-badge")
            }

            Spacer()

            BeaconHeaderControls(
                theme: theme,
                onOpenSettings: nil,
                onRefresh: onRefresh,
                isRefreshing: isRefreshing
            )
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: StatusMenuSizing.headerHeight)
    }

    /// Inset hairline between menu groups, as in the system menus.
    private var menuSeparator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: StatusMenuSizing.separatorHeight)
            .padding(.horizontal, 14)
    }

    /// "Bluetooth Settings…" in the system menu; here it opens Beacon's settings.
    private var settingsFooter: some View {
        Button { onOpenSettings(.devices, nil) } label: {
            Text("Beacon Settings…")
                .font(.body)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .frame(height: StatusMenuSizing.footerHeight - 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuItemButtonStyle(theme: theme))
        .padding(.horizontal, 5)
        .padding(.top, 6)
        .accessibilityLabel("Open Beacon Settings")
        .help("Open Beacon Settings")
    }

    private var nativeHeaderSubtitle: String {
        statusMenuHeaderSubtitle(
            isRefreshing: isRefreshing,
            isPreviewingData: isPreviewingData,
            visibleItemCount: visibleItemCount,
            latestUpdatedAt: latestStatusMenuUpdateDate(for: nativeItems)
        )
    }

    private var appearanceTheme: BeaconAppearanceTheme {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
    }

    private var theme: BeaconThemePalette {
        appearanceTheme.palette(resolvedSystemScheme: colorScheme)
    }

    private var nativeDeviceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                deviceRows(primaryItems)
                if !otherItems.isEmpty {
                    Button(action: onToggleOtherDevices) {
                        HStack(spacing: 6) {
                            Text("Other devices")
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Text("\(otherItems.count)").foregroundStyle(theme.textMuted)
                            Image(systemName: otherDevicesExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textMuted)
                                .accessibilityHidden(true)
                        }
                        .font(.body)
                        .padding(.horizontal, 9)
                        .frame(height: StatusMenuSizing.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MenuItemButtonStyle(theme: theme))
                    .accessibilityIdentifier("status.other-devices")
                    .accessibilityLabel(Text(BeaconL10n.format("Other devices, %d", otherItems.count)))
                    .accessibilityValue(Text(otherDevicesExpanded ? "Expanded" : "Collapsed"))
                    .padding(.horizontal, 5)
                    if otherDevicesExpanded { deviceRows(otherItems) }
                }
            }
            .padding(.vertical, StatusMenuSizing.listVerticalPadding)
        }
        .frame(maxHeight: contentMaxHeight)
    }

    private func deviceRows(_ items: [DeviceListItem]) -> some View {
        ForEach(items, id: \.id) { item in
            DashboardBatteryDeviceRow(
                device: DashboardBatteryDevice(
                    item: item,
                    isPinned: displayPreferences.isPinned(item)
                ),
                lowBatteryThreshold: clampedLowBatteryThreshold
            )
            .contextMenu {
                deviceContextMenu(for: item, displayName: item.displayName)
            }
            // The context-menu wrapper is the exposed AX element on macOS.
            // This wrapper exposes AXLabel, but not AXValue.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.displayName + ", " + dashboardBatteryAccessibilityValue(
                for: DashboardBatteryDevice(item: item, isPinned: displayPreferences.isPinned(item)),
                statusText: DeviceBatteryPresentation(item: item).state.title))
            .accessibilityIdentifier("device.row.\(item.id)")
            .help(item.displayName)
            if connections.device(for: item.id) != nil || connections.operation(for: item.id) != nil {
                BluetoothConnectionControls(item: item, controller: connections, compact: true)
                    .padding(.leading, 50).padding(.trailing, 14).padding(.bottom, 8)
            }
        }
    }

    private var primaryItems: [DeviceListItem] {
        nativeItems.filter { connections.isPrimaryMenuItem($0, preferences: displayPreferences) }
    }

    private var otherItems: [DeviceListItem] {
        nativeItems.filter { !connections.isPrimaryMenuItem($0, preferences: displayPreferences) }
    }

    // MARK: - Computed sections

    private var sections: [DeviceSection] {
        let presented = connections.snapshots(including: snapshots)
        return statusMenuDeviceSections(presented, preferences: displayPreferences,
            pairedDeviceIDs: connections.pairedPresentationIDs(in: presented))
    }

    private var nativeItems: [DeviceListItem] {
        sections.flatMap(\.items)
    }

    private var visibleItemCount: Int {
        sections.reduce(0) { partial, section in partial + section.items.count }
    }

    private var statusWindowWidth: CGFloat {
        StatusMenuSizing.width
    }

    private var contentMaxHeight: CGFloat {
        StatusMenuSizing.contentMaxHeight
    }

    // MARK: - Helpers

    private var clampedLowBatteryThreshold: Int {
        Swift.max(5, Swift.min(50, lowBatteryThreshold))
    }

    private func handleDeviceContextAction(_ action: DeviceContextMenuAction, item: DeviceListItem) {
        switch action {
        case .batteryAlerts, .audioControls, .options:
            onOpenSettings(.devices, item.id)
        case .refresh:
            onRefresh()
        case .connect:
            connections.perform(.connect, deviceID: item.id, displayName: item.displayName)
        case .pin, .unpin:
            setDisplayPreferences(displayPreferences.togglingPin(for: item))
        case .remove:
            setDisplayPreferences(displayPreferences.hiding(item))
        case .disconnect:
            connections.perform(.disconnect, deviceID: item.id, displayName: item.displayName)
        }
    }

    private func setDisplayPreferences(_ preferences: DeviceDisplayPreferences) {
        displayPreferences = preferences
        preferences.save()
    }

    @ViewBuilder
    private func deviceContextMenu(for item: DeviceListItem, displayName: String) -> some View {
        ForEach(deviceContextMenuActions(for: item, preferences: displayPreferences)) { action in
            if action == .pin || action == .unpin || action == .remove {
                Divider()
            }

            Button {
                handleDeviceContextAction(action, item: item)
            } label: {
                Label(action.title(for: displayName), systemImage: BeaconSymbols.resolved(action.systemImage))
            }
            .disabled(!action.isEnabled(for: item) || ((action == .connect || action == .disconnect)
                && (connections.device(for: item.id) == nil || connections.operation(for: item.id)?.phase.isInProgress == true)))
        }
    }

}

func statusMenuHeaderSubtitle(
    isRefreshing: Bool,
    isPreviewingData: Bool,
    visibleItemCount: Int,
    latestUpdatedAt: Date?,
    now: Date = Date()
) -> String {
    if isRefreshing {
        return BeaconL10n.string("Scanning nearby")
    }
    if visibleItemCount == 0 {
        return BeaconL10n.string("No reporting devices")
    }

    let countLabel = statusMenuDeviceCountLabel(visibleItemCount)
    if isPreviewingData {
        return BeaconL10n.format("Preview data · %@", countLabel)
    }
    guard let latestUpdatedAt else {
        return countLabel
    }

    return BeaconL10n.format(
        "%1$@ · Updated %2$@",
        countLabel,
        statusMenuCompactAgeText(updatedAt: latestUpdatedAt, now: now)
    )
}

func latestStatusMenuUpdateDate(for items: [DeviceListItem]) -> Date? {
    items.compactMap { item -> Date? in
        switch item {
        case .device(let decorated):
            return decorated.snapshot.updatedAt
        case .airPods(_, _, let components):
            return activeAirPodsComponents(components).map(\.updatedAt).max()
        }
    }
    .max()
}

private func statusMenuDeviceCountLabel(_ count: Int) -> String {
    BeaconL10n.format(count == 1 ? "%d device" : "%d devices", count)
}

private func statusMenuCompactAgeText(updatedAt: Date, now: Date) -> String {
    let elapsedSeconds = max(0, Int(now.timeIntervalSince(updatedAt)))
    if elapsedSeconds < 60 {
        return BeaconL10n.string("now")
    }

    let elapsedMinutes = elapsedSeconds / 60
    if elapsedMinutes < 60 {
        return BeaconL10n.format("%dm ago", elapsedMinutes)
    }

    let elapsedHours = elapsedMinutes / 60
    if elapsedHours < 24 {
        return BeaconL10n.format("%dh ago", elapsedHours)
    }

    let elapsedDays = elapsedHours / 24
    return BeaconL10n.format("%dd ago", elapsedDays)
}

// MARK: - Settings preview

struct StatusWindowPreview: View {
    let showsMenuBarBattery: Bool
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview")
                    .font(DesignTokens.Typography.captionEmphasis)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Spacer()

                if showsMenuBarBattery {
                    previewMenuBarItem
                }
            }

            VStack(spacing: 0) {
                previewHeader
                previewSeparator
                ForEach(0..<rowCount, id: \.self) { index in
                    previewRow(previewDevice(for: index))
                }
                .padding(.vertical, 3)
                previewSeparator
                previewFooter
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(0.72))
        )
    }

    private var rowCount: Int {
        2
    }

    private var previewMenuBarItem: some View {
        HStack(spacing: 5) {
            BeaconLogoMark(size: 15)

            if showsMenuBarBattery {
                Text("42%")
                    .font(DesignTokens.Typography.caption2Emphasis)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.text)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            Capsule(style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
    }

    /// The panel's own anatomy: title row, separator, device rows, separator,
    /// settings row.
    private var previewHeader: some View {
        HStack(spacing: 8) {
            Text("Beacon")
                .font(.headline)
                .foregroundStyle(previewTheme.textPrimary)
            Spacer(minLength: 0)
            BeaconHeaderControls(
                theme: previewTheme,
                onOpenSettings: nil,
                onRefresh: {},
                frameSize: 22,
                refreshGlyphSize: 11
            )
            .allowsHitTesting(false)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 36)
    }

    private var previewSeparator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var previewFooter: some View {
        Text("Beacon Settings…")
            .font(.body)
            .foregroundStyle(previewTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 30)
    }

    private var previewTheme: BeaconThemePalette {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }

    private func previewRow(_ device: DashboardBatteryDevice) -> some View {
        DashboardBatteryDeviceRow(device: device, lowBatteryThreshold: 20)
    }

    private func previewDevice(for index: Int) -> DashboardBatteryDevice {
        switch index {
        case 0:
            return DashboardBatteryDevice(
                id: "preview-keyboard",
                displayName: "Keyboard",
                kind: .keyboard,
                percent: 82,
                chargeState: .unplugged,
                freshness: .fresh
            )
        case 1:
            return DashboardBatteryDevice(
                id: "preview-mouse",
                displayName: "Mouse",
                kind: .mouse,
                percent: 42,
                chargeState: .unplugged,
                freshness: .fresh
            )
        default:
            return DashboardBatteryDevice(
                id: "preview-airpods",
                displayName: "AirPods",
                kind: .airPods,
                percent: 18,
                chargeState: .unplugged,
                freshness: .fresh
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
private func mockDecorated(
    id: String = UUID().uuidString,
    name: String,
    kind: DeviceKind,
    percent: Int?,
    chargeState: ChargeState = .unplugged,
    freshness: Freshness = .fresh
) -> DecoratedBatterySnapshot {
    DecoratedBatterySnapshot(
        snapshot: BatterySnapshot(
            deviceID: id,
            displayName: name,
            kind: kind,
            percent: percent,
            chargeState: chargeState,
            source: .coreBluetooth,
            updatedAt: Date()
        ),
        freshness: freshness
    )
}

private let previewSnapshots: [DecoratedBatterySnapshot] = [
    // Mac section
    mockDecorated(id: "mac1", name: "Mac mini",         kind: .macBook,   percent: nil),
    mockDecorated(id: "kbd1", name: "Magic Keyboard",   kind: .keyboard,  percent: 95),
    mockDecorated(id: "mse1", name: "Magic Mouse",      kind: .mouse,     percent: 62),
    // Audio section
    mockDecorated(id: "hp1",  name: "AirPods Max",      kind: .airPods, percent: 42, chargeState: .charging),
    // AirPods 3-component
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-case",  name: "John's AirPods Pro Case",  kind: .airPods, percent: 90),
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-left",  name: "John's AirPods Pro Left",  kind: .airPods, percent: 75),
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-right", name: "John's AirPods Pro Right", kind: .airPods, percent: 80),
]

private let previewSnapshotsEdge: [DecoratedBatterySnapshot] = [
    // Critical battery
    mockDecorated(id: "mse2", name: "Low Magic Mouse",  kind: .mouse,    percent: 8),
    // Stale data
    mockDecorated(id: "bt1",  name: "BT Speaker",       kind: .bluetoothPeripheral, percent: 30, freshness: .stale),
    // AirPods with nil case + low buds
    mockDecorated(id: "11-22-33-44-55-66-case",  name: "AirPods Case",  kind: .airPods, percent: nil),
    mockDecorated(id: "11-22-33-44-55-66-left",  name: "AirPods Left",  kind: .airPods, percent: 12),
    mockDecorated(id: "11-22-33-44-55-66-right", name: "AirPods Right", kind: .airPods, percent: 15, freshness: .stale),
]

#Preview("StatusMenuView — full (light)") {
    StatusMenuView(snapshots: previewSnapshots, onRefresh: {})
}

#Preview("StatusMenuView — full (dark)") {
    StatusMenuView(snapshots: previewSnapshots, onRefresh: {})
        .preferredColorScheme(.dark)
}

#Preview("StatusMenuView — edge cases (light)") {
    StatusMenuView(snapshots: previewSnapshotsEdge, onRefresh: {})
}

#Preview("StatusMenuView — edge cases (dark)") {
    StatusMenuView(snapshots: previewSnapshotsEdge, onRefresh: {})
        .preferredColorScheme(.dark)
}

#Preview("StatusMenuView — empty") {
    StatusMenuView(snapshots: [], onRefresh: {})
}
#endif
