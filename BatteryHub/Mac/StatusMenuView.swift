import AppKit
import SwiftUI

enum StatusWindowPreferences {
    static let showMenuBarBatteryKey = "BatteryHub.showMenuBarBattery"
    static let didChangeNotification = Notification.Name("BatteryHub.statusWindowPreferencesDidChange")

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

enum StatusMenuSizing {
    static let width: CGFloat = 386
    static let contentMaxHeight: CGFloat = 620

    static func preferredContentSize(
        dashboardItemCount: Int,
        visibleScreenHeight: CGFloat
    ) -> CGSize {
        let panelVerticalPadding: CGFloat = 28
        let headerHeight: CGFloat = 58
        let rowHeight: CGFloat = 58
        let rowSpacing: CGFloat = dashboardItemCount > 1 ? CGFloat(dashboardItemCount - 1) * 8 : 0
        let listVerticalPadding: CGFloat = dashboardItemCount == 0 ? 0 : 18
        let emptyHeight: CGFloat = 82
        let contentHeight = dashboardItemCount == 0
            ? emptyHeight
            : listVerticalPadding + CGFloat(dashboardItemCount) * rowHeight + rowSpacing
        let desiredHeight = panelVerticalPadding
            + headerHeight
            + contentHeight
        let minimumHeight: CGFloat
        if dashboardItemCount == 0 {
            minimumHeight = 260
        } else {
            minimumHeight = 248
        }
        let screenCappedHeight = max(240, visibleScreenHeight - 46)
        return CGSize(width: width, height: min(max(desiredHeight, minimumHeight), screenCappedHeight))
    }
}

// MARK: - StatusMenuView

struct StatusMenuView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let isRefreshing: Bool
    let isPreviewingData: Bool
    let configuration: StatusWindowConfiguration
    let onRefresh: () -> Void
    let onOpenSettings: (SettingsPane, String?) -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayPreferences = DeviceDisplayPreferences.load()

    init(
        snapshots: [DecoratedBatterySnapshot],
        isRefreshing: Bool = false,
        isPreviewingData: Bool = false,
        configuration: StatusWindowConfiguration = .load(),
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping (SettingsPane, String?) -> Void = { _, _ in },
        initialDisplayPreferences: DeviceDisplayPreferences = .load()
    ) {
        self.snapshots = snapshots
        self.isRefreshing = isRefreshing
        self.isPreviewingData = isPreviewingData
        self.configuration = configuration
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

            if isPreviewingData {
                nativePreviewNotice
            }

            if sections.isEmpty {
                nativeEmptyState
            } else {
                nativeDeviceList
            }

        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: statusWindowWidth)
        .beaconPopoverSurface(cornerRadius: NativeMacStyle.popoverCornerRadius, theme: theme)
        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
    }

    private var nativeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            BatteryHubLogoMark(size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("BatteryHub")
                    .font(DesignTokens.Typography.nativePopoverTitle)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Text(nativeHeaderSubtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer()

            BatteryHubHeaderControls(
                theme: theme,
                onOpenSettings: { onOpenSettings(.devices, nil) }
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var nativeHeaderSubtitle: String {
        if isRefreshing {
            return "Scanning nearby"
        }
        if visibleItemCount == 0 {
            return "No reporting devices"
        }
        let deviceLabel = visibleItemCount == 1 ? "device" : "devices"
        return "\(visibleItemCount) \(deviceLabel)"
    }

    private var appearanceTheme: BatteryHubAppearanceTheme {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
    }

    private var theme: BeaconThemePalette {
        appearanceTheme.palette(resolvedSystemScheme: colorScheme)
    }

    private var nativePreviewNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: resolveSymbol("eye", fallback: "info.circle"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.statusLow)

            Text("Preview data")
                .font(DesignTokens.Typography.captionEmphasis)
                .foregroundStyle(theme.textPrimary)

            Text("Sample devices, not live Bluetooth.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nativeDeviceList: some View {
        ScrollView(showsIndicators: nativeItems.count > 8) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(nativeItems.indices, id: \.self) { index in
                    let item = nativeItems[index]

                    DashboardBatteryDeviceRow(
                        device: DashboardBatteryDevice(
                            item: item,
                            isPinned: displayPreferences.isPinned(item)
                        ),
                        lowBatteryThreshold: clampedLowBatteryThreshold,
                        iconSize: 30,
                        horizontalPadding: 10,
                        verticalPadding: 10,
                        statusWidth: 68
                    )
                    .contextMenu {
                        deviceContextMenu(for: item, displayName: item.displayName)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: contentMaxHeight)
    }

    private var nativeEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BatteryHubLogoMark(size: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.raised.opacity(0.72))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("No reporting devices")
                        .font(DesignTokens.Typography.nativePopoverRowTitle)
                        .foregroundStyle(theme.textPrimary)
                    Text(isRefreshing ? "Scanning nearby." : "No connected devices are reporting battery levels.")
                        .font(DesignTokens.Typography.nativePopoverRowSubtitle)
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Computed sections

    private var sections: [DeviceSection] {
        statusMenuDeviceSections(snapshots, preferences: displayPreferences)
    }

    private var nativeItems: [DeviceListItem] {
        sections.flatMap(\.items)
    }

    private var visibleItemCount: Int {
        sections.reduce(0) { partial, section in partial + section.items.count }
    }

    private var latestUpdateText: String {
        guard let latest = snapshots.map(\.snapshot.updatedAt).max() else { return "No devices" }
        let interval = abs(latest.timeIntervalSinceNow)
        if interval < 60 { return "Updated now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: latest, relativeTo: Date()))"
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
        case .batteryAlerts:
            onOpenSettings(.alerts, item.id)
        case .audioControls:
            onOpenSettings(.devices, item.id)
        case .options:
            onOpenSettings(.devices, item.id)
        case .refresh:
            onRefresh()
        case .connect:
            _ = BluetoothDeviceController.connect(deviceID: item.id)
            onRefresh()
        case .pin, .unpin:
            setDisplayPreferences(displayPreferences.togglingPin(for: item))
        case .remove:
            setDisplayPreferences(displayPreferences.hiding(item))
        case .disconnect:
            _ = BluetoothDeviceController.disconnect(deviceID: item.id)
            onRefresh()
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
                Label(action.title(for: displayName), systemImage: BatteryHubSymbols.resolved(action.systemImage))
            }
            .disabled(!action.isEnabled(for: item))
        }
    }

}

// MARK: - Settings preview

struct StatusWindowPreview: View {
    let showsMenuBarBattery: Bool
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
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

            VStack(spacing: 4) {
                previewHeader

                ForEach(0..<rowCount, id: \.self) { index in
                    previewRow(previewDevice(for: index))
                }
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
            BatteryHubLogoMark(size: 15)

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

    private var previewHeader: some View {
        HStack(spacing: 8) {
            BatteryHubLogoMark(size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("Batteries")
                    .font(DesignTokens.Typography.nativePopoverRowTitle)
                    .foregroundStyle(DesignTokens.Palette.text)
                Text("Updated now")
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            Spacer(minLength: 0)

            BatteryHubHeaderControls(
                theme: previewTheme,
                onOpenSettings: {},
                frameSize: 20,
                settingsGlyphSize: 11,
                spacing: 4
            )
            .allowsHitTesting(false)
        }
        .frame(height: 38)
    }

    private var previewTheme: BeaconThemePalette {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }

    private func previewRow(_ device: DashboardBatteryDevice) -> some View {
        DashboardBatteryDeviceRow(
            device: device,
            lowBatteryThreshold: 20,
            iconSize: 22,
            horizontalPadding: 8,
            verticalPadding: 7,
            statusWidth: 48
        )
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
