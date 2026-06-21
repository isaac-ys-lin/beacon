import AppKit
import SwiftUI

private struct UtilityIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DesignTokens.Palette.secondaryText)
            .background(
                Circle()
                    .fill(configuration.isPressed ? DesignTokens.Palette.hover : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: DesignTokens.Motion.quick), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

enum StatusWindowStyle: String, CaseIterable, Identifiable {
    case native
    case large
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: return "Native"
        case .large: return "Large"
        case .compact: return "Compact"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .native: return "Simple dashboard"
        case .large: return "Detailed dashboard"
        case .compact: return "Compact dashboard"
        }
    }

    var symbolName: String {
        switch self {
        case .native:
            return resolveSymbol("rectangle.grid.2x2", fallback: "rectangle.grid.3x2")
        case .large:
            return resolveSymbol("rectangle.grid.3x2", fallback: "rectangle.grid.2x2")
        case .compact:
            return resolveSymbol("rectangle.grid.1x2", fallback: "rectangle")
        }
    }
}

enum StatusWindowPreferences {
    static let styleKey = "BatteryHub.statusWindowStyle"
    static let nativeDefaultMigrationKey = "BatteryHub.statusWindowStyle.nativeDefaultApplied"
    static let showAirPodsCardKey = "BatteryHub.showAirPodsStatusCard"
    static let showMenuBarBatteryKey = "BatteryHub.showMenuBarBattery"
    static let showBatteryOverviewKey = "BatteryHub.showBatteryOverview"
    static let didChangeNotification = Notification.Name("BatteryHub.statusWindowPreferencesDidChange")

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func applyNativeDefaultIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: styleKey) != nil else {
            defaults.set(StatusWindowStyle.native.rawValue, forKey: styleKey)
            defaults.set(true, forKey: nativeDefaultMigrationKey)
            return
        }
        guard !defaults.bool(forKey: nativeDefaultMigrationKey) else { return }
        defaults.set(StatusWindowStyle.native.rawValue, forKey: styleKey)
        defaults.set(true, forKey: nativeDefaultMigrationKey)
    }
}

struct StatusWindowConfiguration: Equatable {
    var style: StatusWindowStyle
    var showsAirPodsCard: Bool
    var showsMenuBarBattery: Bool
    var showsBatteryOverview: Bool

    static func load(from defaults: UserDefaults = .standard) -> StatusWindowConfiguration {
        let style = defaults.string(forKey: StatusWindowPreferences.styleKey)
            .flatMap(StatusWindowStyle.init(rawValue:)) ?? .native

        return StatusWindowConfiguration(
            style: style,
            showsAirPodsCard: boolPreference(
                StatusWindowPreferences.showAirPodsCardKey,
                defaultValue: true,
                defaults: defaults
            ),
            showsMenuBarBattery: boolPreference(
                StatusWindowPreferences.showMenuBarBatteryKey,
                defaultValue: false,
                defaults: defaults
            ),
            showsBatteryOverview: boolPreference(
                StatusWindowPreferences.showBatteryOverviewKey,
                defaultValue: true,
                defaults: defaults
            )
        )
    }

    var showsOverviewInDashboard: Bool {
        style != .native && showsBatteryOverview
    }

    func showsAirPodsCard(in sections: [DeviceSection]) -> Bool {
        style == .large
            && showsAirPodsCard
            && sections.contains { section in
                section.items.contains { item in
                    if case .airPods = item { return true }
                    return false
                }
            }
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
    static func width(for style: StatusWindowStyle) -> CGFloat {
        switch style {
        case .native: return 386
        case .large: return 430
        case .compact: return 386
        }
    }

    static func contentMaxHeight(for style: StatusWindowStyle) -> CGFloat {
        switch style {
        case .native: return 620
        case .large: return 760
        case .compact: return 620
        }
    }

    static func preferredContentSize(
        dashboardItemCount: Int,
        showsOverview: Bool,
        showsAirPodsCard: Bool,
        style: StatusWindowStyle,
        visibleScreenHeight: CGFloat
    ) -> CGSize {
        let width = width(for: style)
        let panelVerticalPadding: CGFloat = 28
        let headerHeight: CGFloat = 58
        let overviewHeight: CGFloat = showsOverview ? 48 : 0
        let rowHeight: CGFloat = style == .large ? 62 : 58
        let rowSpacing: CGFloat = dashboardItemCount > 1 ? CGFloat(dashboardItemCount - 1) * 8 : 0
        let listVerticalPadding: CGFloat = dashboardItemCount == 0 ? 0 : 18
        let emptyHeight: CGFloat = 82
        let contentHeight = dashboardItemCount == 0
            ? emptyHeight
            : listVerticalPadding + CGFloat(dashboardItemCount) * rowHeight + rowSpacing
        let desiredHeight = panelVerticalPadding
            + headerHeight
            + overviewHeight
            + contentHeight
        let minimumHeight: CGFloat
        if dashboardItemCount == 0 {
            minimumHeight = 260
        } else {
            minimumHeight = style == .large ? 340 : 248
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
    let bluetoothPowerState: BluetoothPowerState
    let onRefresh: () -> Void
    let onOpenSettings: (SettingsPane, String?) -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @State private var displayPreferences = DeviceDisplayPreferences.load()

    init(
        snapshots: [DecoratedBatterySnapshot],
        isRefreshing: Bool = false,
        isPreviewingData: Bool = false,
        configuration: StatusWindowConfiguration = .load(),
        bluetoothPowerState: BluetoothPowerState = .on,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping (SettingsPane, String?) -> Void = { _, _ in },
        initialDisplayPreferences: DeviceDisplayPreferences = .load()
    ) {
        self.snapshots = snapshots
        self.isRefreshing = isRefreshing
        self.isPreviewingData = isPreviewingData
        self.configuration = configuration
        self.bluetoothPowerState = bluetoothPowerState
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

            if configuration.showsOverviewInDashboard, !sections.isEmpty {
                nativeOverviewMetrics
            }

            if sections.isEmpty {
                nativeEmptyState
            } else {
                nativeDeviceList
            }

        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: statusWindowWidth)
        .nativeSystemSurface(cornerRadius: NativeMacStyle.popoverCornerRadius)
    }

    private var nativeOverviewMetrics: some View {
        HStack(spacing: 8) {
            nativeMetric(
                "\(visibleItemCount)",
                visibleItemCount == 1 ? "Device" : "Devices",
                color: DesignTokens.Palette.accent
            )

            nativeMetric(
                "\(lowBatteryItemCount)",
                "Low",
                color: lowBatteryItemCount > 0 ? DesignTokens.Palette.critical : DesignTokens.Palette.secondaryText
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func nativeMetric(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(DesignTokens.Typography.nativePopoverPercent)
                .monospacedDigit()
                .foregroundStyle(color)

            Text(label)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NativeMacStyle.rowCornerRadius, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
    }

    private var nativeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            BatteryHubLogoMark(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Batteries")
                    .font(DesignTokens.Typography.nativePopoverTitle)
                    .foregroundStyle(DesignTokens.Palette.text)
                    .lineLimit(1)

                Text(nativeHeaderSubtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer()

            nativeSettingsButton

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.62))
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(UtilityIconButtonStyle())
            .disabled(isRefreshing)
            .help(isRefreshing ? "Refreshing" : "Refresh")

            nativeLowestBatteryPill
            nativeBluetoothStatusButton
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var nativeSettingsButton: some View {
        Button {
            onOpenSettings(.devices, nil)
        } label: {
            Image(systemName: resolveSymbol("gearshape", fallback: "gearshape.fill"))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.primary.opacity(0.62))
                .frame(width: 28, height: 28)
                .accessibilityLabel("Open BatteryHub Settings")
        }
        .buttonStyle(UtilityIconButtonStyle())
        .help("Open BatteryHub Settings")
    }

    private var nativeHeaderSubtitle: String {
        if isRefreshing {
            return "Refreshing"
        }
        return latestUpdateText
    }

    @ViewBuilder
    private var nativeLowestBatteryPill: some View {
        if let lowest = overviewSummary.lowestPercent {
            Text("\(lowest)%")
                .font(DesignTokens.Typography.nativePopoverPill)
                .monospacedDigit()
                .foregroundStyle(lowest <= clampedLowBatteryThreshold ? DesignTokens.Palette.critical : DesignTokens.Palette.accent)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )
                .help("Lowest reported battery")
        }
    }

    private var nativeBluetoothStatusButton: some View {
        Button {
            BatteryHubSystemSettingsActions.openBluetoothSettings()
        } label: {
            Image(systemName: BatteryHubSymbols.bluetooth)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(bluetoothPowerColor)
                .frame(width: 30)
                .accessibilityLabel(bluetoothAccessibilityLabel)
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(bluetoothHelpText)
    }

    private var bluetoothPowerColor: Color {
        switch bluetoothPowerState {
        case .on: return DesignTokens.Palette.accent
        case .off, .unknown: return DesignTokens.Palette.secondaryText
        }
    }

    private var bluetoothAccessibilityLabel: String {
        switch bluetoothPowerState {
        case .on: return "Bluetooth is on. Open Bluetooth Settings."
        case .off: return "Bluetooth is off. Open Bluetooth Settings."
        case .unknown: return "Bluetooth status unavailable. Open Bluetooth Settings."
        }
    }

    private var bluetoothHelpText: String {
        switch bluetoothPowerState {
        case .on: return "Bluetooth is on"
        case .off: return "Bluetooth is off"
        case .unknown: return "Open Bluetooth Settings"
        }
    }

    private var nativePreviewNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: resolveSymbol("eye", fallback: "info.circle"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.warning)

            Text("Preview data")
                .font(DesignTokens.Typography.captionEmphasis)
                .foregroundStyle(DesignTokens.Palette.text)

            Text("Sample devices, not live Bluetooth.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nativeDeviceList: some View {
        ScrollView(showsIndicators: nativeItems.count > 8) {
            VStack(spacing: 8) {
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
            .padding(.vertical, 9)
        }
        .frame(maxHeight: contentMaxHeight)
    }

    private var nativeEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "battery.25")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("No reporting devices")
                        .font(DesignTokens.Typography.nativePopoverRowTitle)
                        .foregroundStyle(DesignTokens.Palette.text)
                    Text(isRefreshing ? "Scanning connected devices now." : "No connected devices are reporting battery levels.")
                        .font(DesignTokens.Typography.nativePopoverRowSubtitle)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
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

    private var overviewSummary: BatteryOverviewSummary {
        batteryOverviewSummary(for: sections, lowBatteryThreshold: clampedLowBatteryThreshold)
    }

    private var latestUpdateText: String {
        guard let latest = snapshots.map(\.snapshot.updatedAt).max() else { return "No devices" }
        let interval = abs(latest.timeIntervalSinceNow)
        if interval < 60 { return "Updated now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: latest, relativeTo: Date()))"
    }

    private var lowBatteryItemCount: Int {
        sections.reduce(0) { partial, section in
            partial + section.items.filter(isLowBatteryItem).count
        }
    }

    private var statusWindowWidth: CGFloat {
        StatusMenuSizing.width(for: configuration.style)
    }

    private var contentMaxHeight: CGFloat {
        StatusMenuSizing.contentMaxHeight(for: configuration.style)
    }

    private func isLowBatteryItem(_ item: DeviceListItem) -> Bool {
        switch item {
        case .device(let decorated):
            guard let percent = decorated.snapshot.percent else { return false }
            return percent <= clampedLowBatteryThreshold
                && decorated.snapshot.chargeState != .charging
                && decorated.snapshot.chargeState != .full
        case .airPods(_, _, let components):
            return components.contains { component in
                guard let percent = component.percent else { return false }
                return percent <= clampedLowBatteryThreshold
                    && component.chargeState != .charging
                    && component.chargeState != .full
            }
        }
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
    let style: StatusWindowStyle
    let showsAirPodsCard: Bool
    let showsMenuBarBattery: Bool
    let showsBatteryOverview: Bool
    var bluetoothPowerState: BluetoothPowerState = .on

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

                if style != .native && showsBatteryOverview {
                    previewOverview
                }

                if style != .native && showsAirPodsCard {
                    previewRow(
                        DashboardBatteryDevice(
                            id: "preview-airpods",
                            displayName: "AirPods Pro",
                            kind: .airPods,
                            percent: 61,
                            chargeState: .unplugged,
                            freshness: .fresh
                        )
                    )
                }

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
        switch style {
        case .native: return 2
        case .large: return 3
        case .compact: return 2
        }
    }

    private var previewMenuBarItem: some View {
        HStack(spacing: 5) {
            BatteryHubLogoMark(size: 14)

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
            BatteryHubLogoMark(size: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("Batteries")
                    .font(DesignTokens.Typography.nativePopoverRowTitle)
                    .foregroundStyle(DesignTokens.Palette.text)
                Text("Updated now")
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: resolveSymbol("gearshape", fallback: "gearshape.fill"))
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.primary.opacity(0.62))
                .frame(width: 20, height: 20)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.62))
                .frame(width: 20, height: 20)

            Text("18%")
                .font(DesignTokens.Typography.nativePopoverPill)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Palette.critical)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Capsule(style: .continuous).fill(DesignTokens.Palette.controlPill))

            Image(systemName: BatteryHubSymbols.bluetooth)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(previewBluetoothPowerColor)
                .frame(width: 24, height: 22)
                .background(Capsule(style: .continuous).fill(DesignTokens.Palette.controlPill))
        }
        .frame(height: 38)
    }

    private var previewBluetoothPowerColor: Color {
        switch bluetoothPowerState {
        case .on: return DesignTokens.Palette.accent
        case .off, .unknown: return DesignTokens.Palette.secondaryText
        }
    }

    private var previewOverview: some View {
        HStack(spacing: 6) {
            previewMetric("4", "Devices", color: DesignTokens.Palette.accent)
            previewMetric("1", "Low", color: DesignTokens.Palette.critical)
        }
    }

    private func previewMetric(_ value: String, _ title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(DesignTokens.Typography.nativePopoverPercent)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NativeMacStyle.rowCornerRadius, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
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
