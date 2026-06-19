import AppKit
import SwiftUI

// MARK: - NSVisualEffectView wrapper (real vibrancy)

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

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

private struct StatusMenuPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.Palette.text)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? DesignTokens.Palette.hover : DesignTokens.Palette.controlPill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: DesignTokens.Motion.quick), value: configuration.isPressed)
    }
}

private struct StatusMenuPill: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: resolveSymbol(systemImage, fallback: "circle.fill"))
                .symbolRenderingMode(.hierarchical)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            Capsule(style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
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
}

enum StatusWindowPreferences {
    static let styleKey = "BatteryHub.statusWindowStyle"
    static let nativeDefaultMigrationKey = "BatteryHub.statusWindowStyle.nativeDefaultApplied"
    static let showAirPodsCardKey = "BatteryHub.showAirPodsStatusCard"
    static let showMenuBarBatteryKey = "BatteryHub.showMenuBarBattery"
    static let showBatteryOverviewKey = "BatteryHub.showBatteryOverview"

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
        if style == .native {
            let panelVerticalPadding: CGFloat = 24
            let headerHeight: CGFloat = 50
            let headerDividerHeight: CGFloat = 1
            let previewHeight: CGFloat = 0
            let rowHeight: CGFloat = 50
            let rowSeparatorHeight = CGFloat(max(0, dashboardItemCount - 1))
            let listVerticalPadding: CGFloat = dashboardItemCount == 0 ? 0 : 16
            let footerHeight: CGFloat = 85
            let emptyHeight: CGFloat = 82
            let contentHeight = dashboardItemCount == 0
                ? emptyHeight
                : listVerticalPadding + CGFloat(dashboardItemCount) * rowHeight + rowSeparatorHeight
            let desiredHeight = panelVerticalPadding
                + headerHeight
                + headerDividerHeight
                + previewHeight
                + contentHeight
                + footerHeight
            let minimumHeight: CGFloat = dashboardItemCount == 0 ? 260 : 248
            let screenCappedHeight = max(240, visibleScreenHeight - 46)
            return CGSize(width: width, height: min(max(desiredHeight, minimumHeight), screenCappedHeight))
        }

        let chromeHeight: CGFloat = 146
        let overviewHeight: CGFloat = showsOverview ? (style == .large ? 270 : 232) : 0
        let airPodsHeight: CGFloat = showsAirPodsCard ? 334 : 0
        let listHeight = listHeight(for: dashboardItemCount, style: style)
        let contentGaps = CGFloat([
            showsOverview,
            showsAirPodsCard,
            dashboardItemCount > 0
        ].filter { $0 }.count - 1).clamped(to: 0...3) * 14

        let desiredHeight = chromeHeight + overviewHeight + airPodsHeight + listHeight + contentGaps
        let minimumHeight: CGFloat
        if dashboardItemCount == 0 {
            minimumHeight = style == .large ? 330 : 300
        } else {
            minimumHeight = style == .large ? 640 : 560
        }
        let screenCappedHeight = max(280, visibleScreenHeight - 46)
        let height = min(max(desiredHeight, minimumHeight), screenCappedHeight)
        return CGSize(width: width, height: height)
    }

    private static func listHeight(for dashboardItemCount: Int, style: StatusWindowStyle) -> CGFloat {
        guard dashboardItemCount > 0 else { return 0 }
        let firstRowAllowance: CGFloat = style == .large ? 104 : 90
        let additionalRowHeight: CGFloat = style == .large ? 72 : 64
        return firstRowAllowance + CGFloat(max(0, dashboardItemCount - 1)) * additionalRowHeight
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct FeaturedAirPodsSummary {
    let name: String
    let id: String
    let components: [AirPodsComponent]

    var lowestPercent: Int? {
        let percents = components.compactMap(\.percent)
        guard !percents.isEmpty else { return nil }
        return percents.min()
    }

    var hasLowComponent: Bool {
        components.contains { ($0.percent ?? 100) <= LowBatteryNotifier.threshold }
    }

    var hasStaleComponent: Bool {
        components.contains { $0.freshness != .fresh }
    }

    var statusText: String {
        if hasLowComponent { return "Component low" }
        if hasStaleComponent { return "Component data stale" }
        return "Nearby battery status"
    }

    var statusColor: Color {
        if hasLowComponent { return DesignTokens.Palette.critical }
        if hasStaleComponent { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.secondaryText
    }
}

struct SelectedDeviceConfiguration: Equatable, Identifiable {
    let id: String
    let displayName: String
    let kind: DeviceKind
}

// MARK: - StatusMenuView

struct StatusMenuView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let isRefreshing: Bool
    let isPreviewingData: Bool
    let onRefresh: () -> Void
    let onOpenSettings: (SettingsPane, String?) -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @AppStorage(LowBatteryNotifier.notificationsEnabledDefaultsKey) private var lowBatteryAlertsEnabled = true
    @AppStorage(LowBatteryNotifier.chargedNotificationsEnabledDefaultsKey) private var chargedBatteryAlertsEnabled = true
    @AppStorage(StatusWindowPreferences.styleKey) private var statusWindowStyleRawValue = StatusWindowStyle.native.rawValue
    @AppStorage(StatusWindowPreferences.showAirPodsCardKey) private var showAirPodsStatusCard = true
    @AppStorage(StatusWindowPreferences.showMenuBarBatteryKey) private var showMenuBarBattery = false
    @AppStorage(StatusWindowPreferences.showBatteryOverviewKey) private var showBatteryOverview = true
    @State private var isShowingSettings = false
    @State private var displayPreferences = DeviceDisplayPreferences.load()
    @State private var selectedDeviceConfiguration: SelectedDeviceConfiguration?
    @State private var selectedDeviceAlertThreshold = Double(LowBatteryNotifier.defaultThreshold)
    @State private var selectedDeviceChargedAlertEnabled = false
    @State private var deviceControlMessage: String?

    init(
        snapshots: [DecoratedBatterySnapshot],
        isRefreshing: Bool = false,
        isPreviewingData: Bool = false,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping (SettingsPane, String?) -> Void = { _, _ in },
        initiallyShowingSettings: Bool = false,
        initialDisplayPreferences: DeviceDisplayPreferences = .load(),
        initialSelectedDeviceConfiguration: SelectedDeviceConfiguration? = nil
    ) {
        self.snapshots = snapshots
        self.isRefreshing = isRefreshing
        self.isPreviewingData = isPreviewingData
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        _isShowingSettings = State(initialValue: initiallyShowingSettings)
        _displayPreferences = State(initialValue: initialDisplayPreferences)
        _selectedDeviceConfiguration = State(initialValue: initialSelectedDeviceConfiguration)
        _selectedDeviceAlertThreshold = State(
            initialValue: Double(
                initialSelectedDeviceConfiguration.map {
                    LowBatteryNotifier.threshold(forDeviceID: $0.id)
                } ?? LowBatteryNotifier.defaultThreshold
            )
        )
        _selectedDeviceChargedAlertEnabled = State(
            initialValue: initialSelectedDeviceConfiguration.map {
                LowBatteryNotifier.isChargedAlertEnabled(forDeviceID: $0.id)
            } ?? false
        )
    }

    var body: some View {
        if statusWindowStyle == .native, !isShowingSettings {
            nativeBody
        } else {
            detailedBody
        }
    }

    private var detailedBody: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            header

            if let deviceControlMessage {
                StatusMenuPill(
                    text: deviceControlMessage,
                    systemImage: "bolt.horizontal.circle",
                    color: DesignTokens.Palette.secondaryText
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isPreviewingData {
                previewDataNotice
            }

            if isShowingSettings {
                ScrollView(showsIndicators: false) {
                    settingsPanel
                        .padding(.vertical, 1)
                }
                .frame(maxHeight: contentMaxHeight)
            } else if sections.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        if showBatteryOverview {
                            BatteryOverviewStrip(
                                summary: overviewSummary,
                                devices: overviewDevices,
                                lowBatteryThreshold: clampedLowBatteryThreshold
                            )
                        }

                        if showAirPodsStatusCard, statusWindowStyle == .large, let featuredAirPods {
                            AirPodsPlatterCard(summary: featuredAirPods)
                        }

                        ForEach(sections.indices, id: \.self) { index in
                            DeviceSectionCard(
                                section: sections[index],
                                preferences: displayPreferences,
                                onAction: handleDeviceContextAction
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: contentMaxHeight)
            }

            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: statusWindowWidth)
        .background {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.8)
                )
        }
    }

    private var nativeBody: some View {
        VStack(spacing: 0) {
            nativeHeader

            Divider()
                .overlay(NativeMacStyle.subtleStroke)
                .padding(.horizontal, 16)

            if isPreviewingData {
                nativePreviewNotice
            }

            if sections.isEmpty {
                nativeEmptyState
            } else {
                nativeDeviceList
            }

            nativeFooter
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: statusWindowWidth)
        .nativeSystemSurface(cornerRadius: NativeMacStyle.popoverCornerRadius)
    }

    private var nativeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            BluetoothLogoMark(size: 30)

            Text("Bluetooth")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.text)
                .lineLimit(1)

            Spacer()

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

            nativeBluetoothStatusButton
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var nativeBluetoothStatusButton: some View {
        Button {
            BatteryHubSystemSettingsActions.openBluetoothSettings()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: resolveSymbol("checkmark.circle.fill", fallback: "checkmark.circle"))
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text("On")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(DesignTokens.Palette.accent)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.Palette.controlPill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
                    )
            )
            .accessibilityLabel("Bluetooth is on. Open Bluetooth Settings.")
        }
        .buttonStyle(.plain)
        .help("Open Bluetooth Settings")
    }

    private var nativePreviewNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: resolveSymbol("eye", fallback: "info.circle"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.warning)

            Text("Preview data")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.text)

            Text("Sample devices, not live Bluetooth.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nativeDeviceList: some View {
        ScrollView(showsIndicators: nativeItems.count > 8) {
            VStack(spacing: 0) {
                ForEach(nativeItems.indices, id: \.self) { index in
                    let item = nativeItems[index]

                    NativeStatusRow(
                        item: item,
                        isPinned: displayPreferences.isPinned(item),
                        lowBatteryThreshold: clampedLowBatteryThreshold
                    )
                    .contextMenu {
                        deviceContextMenu(for: item, displayName: item.displayName)
                    }

                    if index < nativeItems.count - 1 {
                        Divider()
                            .overlay(NativeMacStyle.subtleStroke)
                            .padding(.leading, 58)
                            .padding(.trailing, 16)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: contentMaxHeight)
    }

    private var nativeEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BluetoothLogoMark(size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No reporting devices")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.text)
                    Text(isRefreshing ? "Scanning connected devices now." : "No connected devices are reporting battery levels.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nativeFooter: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(NativeMacStyle.subtleStroke)
                .padding(.horizontal, 16)

            NativeFooterButton(title: "BatteryHub Settings...", systemImage: "gearshape") {
                onOpenSettings(.devices, nil)
            }

            NativeFooterButton(title: "Bluetooth Settings...", systemImage: "dot.radiowaves.left.and.right", usesBluetoothLogo: true) {
                BatteryHubSystemSettingsActions.openBluetoothSettings()
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Computed sections

    private var sections: [DeviceSection] {
        dashboardDeviceSections(snapshots, preferences: displayPreferences)
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

    private var overviewDevices: [BatteryOverviewDevice] {
        batteryOverviewDevices(for: sections)
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

    private var staleItemCount: Int {
        sections.reduce(0) { partial, section in
            partial + section.items.filter(isStaleItem).count
        }
    }

    private var statusWindowStyle: StatusWindowStyle {
        StatusWindowStyle(rawValue: statusWindowStyleRawValue) ?? .native
    }

    private var statusWindowWidth: CGFloat {
        StatusMenuSizing.width(for: statusWindowStyle)
    }

    private var contentMaxHeight: CGFloat {
        StatusMenuSizing.contentMaxHeight(for: statusWindowStyle)
    }

    private var featuredAirPods: FeaturedAirPodsSummary? {
        for section in sections {
            for item in section.items {
                if case .airPods(let name, let id, let components) = item {
                    return FeaturedAirPodsSummary(name: name, id: id, components: components)
                }
            }
        }
        return nil
    }

    private var hiddenDeviceCount: Int {
        displayPreferences.hiddenDeviceIDs.count
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

    private func isStaleItem(_ item: DeviceListItem) -> Bool {
        switch item {
        case .device(let decorated):
            return decorated.freshness != .fresh
        case .airPods(_, _, let components):
            return components.contains { $0.freshness != .fresh }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Devices")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.accent)

                Text(headerStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .monospacedDigit()
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(UtilityIconButtonStyle())
                .disabled(isRefreshing)
                .help(isRefreshing ? "Refreshing" : "Refresh")

                Button {
                    if isShowingSettings {
                        withAnimation(.easeInOut(duration: DesignTokens.Motion.quick)) {
                            isShowingSettings = false
                        }
                    } else {
                        onOpenSettings(.devices, nil)
                    }
                } label: {
                    Image(systemName: isShowingSettings ? "xmark.circle" : "gearshape")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(UtilityIconButtonStyle())
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .help(isShowingSettings ? "Close Settings" : "Open Settings")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .padding(.bottom, 4)

            Text("No reporting devices")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(isRefreshing ? "Scanning connected, paired, and synced devices now." : "Currently no connected devices are reporting battery levels.")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    onOpenSettings(.devices, nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Button {
                    BatteryHubSystemSettingsActions.openBluetoothSettings()
                } label: {
                    Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            .buttonStyle(StatusMenuPillButtonStyle())
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private var previewDataNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: resolveSymbol("eye", fallback: "info.circle"))
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Palette.warning)

            Text("Preview data")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Palette.text)

            Text("Sample devices, not live Bluetooth.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DesignTokens.Palette.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(DesignTokens.Palette.warning.opacity(0.22), lineWidth: 0.7)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            StatusMenuPill(
                text: footerAlertText,
                systemImage: lowBatteryAlertsEnabled ? "bell.badge" : "bell.slash",
                color: lowBatteryItemCount > 0 ? DesignTokens.Palette.critical : DesignTokens.Palette.tertiaryText
            )

            Spacer()

            StatusMenuPill(
                text: staleItemCount > 0 ? "\(staleItemCount) stale" : "Best-effort sync",
                systemImage: staleItemCount > 0 ? "clock.badge.exclamationmark" : "checkmark.icloud",
                color: staleItemCount > 0 ? DesignTokens.Palette.stale : DesignTokens.Palette.tertiaryText
            )
        }
    }

    // MARK: - Settings panel

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if selectedDeviceConfiguration != nil {
                batteryAlertSettingsCard
                deviceControlsSettingsCard
                statusWindowSettingsCard
            } else {
                statusWindowSettingsCard
                batteryAlertSettingsCard
                deviceControlsSettingsCard
            }
        }
    }

    private var statusWindowSettingsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: resolveSymbol("macwindow", fallback: "rectangle"))
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Status Window")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.Palette.text)

                    Text("Choose how much detail opens from the menu bar.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
            }

            Picker("Window style", selection: $statusWindowStyleRawValue) {
                ForEach(StatusWindowStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $showAirPodsStatusCard) {
                Label {
                    Text("Show AirPods status card")
                        .font(.system(size: 12, weight: .medium))
                } icon: {
                    Image(systemName: resolveSymbol("airpodspro", fallback: "airpods"))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .toggleStyle(.switch)
            .disabled(statusWindowStyle != .large)
            .opacity(statusWindowStyle == .large ? 1 : 0.45)

            Toggle(isOn: $showMenuBarBattery) {
                Label {
                    Text("Show battery in menu bar")
                        .font(.system(size: 12, weight: .medium))
                } icon: {
                    Image(systemName: resolveSymbol("battery.100", fallback: "battery.25"))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $showBatteryOverview) {
                Label {
                    Text("Show battery overview")
                        .font(.system(size: 12, weight: .medium))
                } icon: {
                    Image(systemName: resolveSymbol("rectangle.and.hand.point.up.left", fallback: "rectangle"))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .toggleStyle(.switch)
            .disabled(statusWindowStyle == .native)
            .opacity(statusWindowStyle == .native ? 0.45 : 1)

            StatusWindowPreview(
                style: statusWindowStyle,
                showsAirPodsCard: showAirPodsStatusCard && statusWindowStyle == .large,
                showsMenuBarBattery: showMenuBarBattery,
                showsBatteryOverview: showBatteryOverview
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private var batteryAlertSettingsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: alertsAreEnabled ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(alertsAreEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Battery Alerts")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.Palette.text)

                    Text("Notify when devices are low or done charging.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                StatusMenuPill(
                    text: alertModeSummary,
                    systemImage: alertsAreEnabled ? "bell.badge" : "bell.slash",
                    color: alertsAreEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText
                )
            }

            lowBatteryAlertControls
            chargedBatteryAlertControls
            alertPreview

            if let selectedDeviceConfiguration {
                selectedDeviceAlertCard(for: selectedDeviceConfiguration)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private var lowBatteryAlertControls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Low battery")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Warn before a device becomes unavailable.")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                Toggle("", isOn: $lowBatteryAlertsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Text("Alert threshold")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(clampedLowBatteryThreshold)%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.accent)
                }

                Slider(value: thresholdSliderValue, in: 5...50, step: 5)
                    .disabled(!lowBatteryAlertsEnabled)
            }
            .opacity(lowBatteryAlertsEnabled ? 1 : 0.45)
        }
    }

    private var chargedBatteryAlertControls: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "battery.100")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(chargedBatteryAlertsEnabled ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Charged alerts")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Allow device-specific alerts when charging finishes.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $chargedBatteryAlertsEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(0.58))
        )
    }

    private var alertPreview: some View {
        VStack(spacing: 8) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "applewatch.side.right")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.Palette.critical)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Low battery preview")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Apple Watch reaches \(clampedLowBatteryThreshold)%")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                StatusMenuPill(
                    text: "\(clampedLowBatteryThreshold)%",
                    systemImage: "battery.25",
                    color: DesignTokens.Palette.critical
                )
            }

            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.Palette.charging)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Charged preview")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("iPhone finishes charging")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                StatusMenuPill(
                    text: "Full",
                    systemImage: "battery.100",
                    color: DesignTokens.Palette.charging
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
        .opacity(alertsAreEnabled ? 1 : 0.45)
    }

    private func selectedDeviceAlertCard(for selection: SelectedDeviceConfiguration) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                DeviceIconPlate(
                    symbolName: deviceSymbolName(for: selection.kind, displayName: selection.displayName),
                    color: DesignTokens.Palette.accent,
                    size: 32
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(deviceAlertSubtitle(for: selection.id))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Text("Device low-battery threshold")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(selectedDeviceAlertThreshold))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.accent)
                }

                Slider(
                    value: Binding(
                        get: { selectedDeviceAlertThreshold },
                        set: { newValue in
                            selectedDeviceAlertThreshold = newValue
                            LowBatteryNotifier.setThreshold(Int(newValue.rounded()), forDeviceID: selection.id)
                        }
                    ),
                    in: 5...50,
                    step: 5
                )
                .disabled(!lowBatteryAlertsEnabled)
            }
            .opacity(lowBatteryAlertsEnabled ? 1 : 0.45)

            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                Image(systemName: "battery.100")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selectedDeviceChargedAlertEnabled ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify when charged")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Best for devices that keep reporting while charging.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                Toggle("", isOn: selectedDeviceChargedAlertBinding(for: selection.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!chargedBatteryAlertsEnabled)
            }
            .opacity(chargedBatteryAlertsEnabled ? 1 : 0.45)

            HStack {
                Button("Use Global Default") {
                    LowBatteryNotifier.resetThreshold(forDeviceID: selection.id)
                    selectedDeviceAlertThreshold = Double(clampedLowBatteryThreshold)
                }
                .font(.system(size: 11, weight: .semibold))
                .disabled(!LowBatteryNotifier.hasCustomThreshold(forDeviceID: selection.id))

                Spacer()

                StatusMenuPill(
                    text: selectedDeviceChargedAlertEnabled ? "Low + Full" : "\(Int(selectedDeviceAlertThreshold))%",
                    systemImage: selectedDeviceChargedAlertEnabled ? "bell.badge" : "battery.25",
                    color: selectedDeviceChargedAlertEnabled ? DesignTokens.Palette.charging : DesignTokens.Palette.critical
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(0.82))
        )
    }

    private func selectedDeviceChargedAlertBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedDeviceChargedAlertEnabled },
            set: { newValue in
                selectedDeviceChargedAlertEnabled = newValue
                LowBatteryNotifier.setChargedAlertEnabled(newValue, forDeviceID: id)
            }
        )
    }

    private var deviceControlsSettingsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: "pin")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Device Controls")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.Palette.text)

                    Text("Pinned devices stay at the top. Removed devices stay hidden until restored.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                DeviceControlMetric(
                    title: "Pinned",
                    value: "\(displayPreferences.pinnedDeviceIDs.count)",
                    systemImage: "pin.fill",
                    color: displayPreferences.pinnedDeviceIDs.isEmpty ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.accent
                )

                DeviceControlMetric(
                    title: "Hidden",
                    value: "\(hiddenDeviceCount)",
                    systemImage: "eye.slash",
                    color: hiddenDeviceCount == 0 ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.stale
                )
            }

            deviceInspectorList

            if hiddenDeviceCount > 0 {
                Button {
                    setDisplayPreferences(displayPreferences.restoringAllHidden())
                } label: {
                    Label("Restore Hidden Devices", systemImage: "arrow.uturn.backward")
                }
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private var deviceInspectorList: some View {
        VStack(spacing: 8) {
            ForEach(deviceInspectorRows) { inspectorItem in
                DeviceInspectorRow(
                    inspectorItem: inspectorItem,
                    symbolName: deviceSymbolName(for: inspectorItem.kind, displayName: inspectorItem.displayName),
                    alertSummary: alertSummary(for: inspectorItem.item),
                    onSelectAlerts: {
                        selectDeviceConfiguration(for: inspectorItem.item)
                    },
                    onTogglePin: {
                        setDisplayPreferences(displayPreferences.settingPinned(!inspectorItem.isPinned, for: inspectorItem.item))
                    },
                    onHide: {
                        setDisplayPreferences(displayPreferences.hiding(inspectorItem.item))
                    },
                    onRestore: {
                        setDisplayPreferences(displayPreferences.restoring(inspectorItem.item))
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    private var clampedLowBatteryThreshold: Int {
        Swift.max(5, Swift.min(50, lowBatteryThreshold))
    }

    private var alertsAreEnabled: Bool {
        lowBatteryAlertsEnabled || chargedBatteryAlertsEnabled
    }

    private var alertModeSummary: String {
        switch (lowBatteryAlertsEnabled, chargedBatteryAlertsEnabled) {
        case (true, true):
            return "Low + Full"
        case (true, false):
            return "Low"
        case (false, true):
            return "Full"
        case (false, false):
            return "Off"
        }
    }

    private var thresholdSliderValue: Binding<Double> {
        Binding(
            get: { Double(clampedLowBatteryThreshold) },
            set: { lowBatteryThreshold = Int($0.rounded()) }
        )
    }

    private var deviceInspectorRows: [DeviceInspectorItem] {
        deviceInspectorItems(snapshots, preferences: displayPreferences)
    }

    private var footerAlertText: String {
        if isRefreshing { return "Refreshing" }
        if !alertsAreEnabled { return "Alerts off" }
        if lowBatteryItemCount > 0 { return "\(lowBatteryItemCount) low" }
        if !lowBatteryAlertsEnabled && chargedBatteryAlertsEnabled { return "Full alerts on" }
        return "Alerts below \(clampedLowBatteryThreshold)%"
    }

    private var headerStatusText: String {
        let deviceText = "\(visibleItemCount) \(visibleItemCount == 1 ? "device" : "devices")"
        if isRefreshing {
            return "Refreshing... · \(deviceText)"
        }
        return "\(latestUpdateText) · \(deviceText)"
    }

    private var cardBackground: some ShapeStyle {
        DesignTokens.Palette.card
            .shadow(.inner(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1))
    }

    private func handleDeviceContextAction(_ action: DeviceContextMenuAction, item: DeviceListItem) {
        switch action {
        case .batteryAlerts:
            selectDeviceConfiguration(for: item)
            onOpenSettings(.alerts, item.id)
        case .audioControls:
            selectDeviceConfiguration(for: item)
            onOpenSettings(.devices, item.id)
        case .options:
            selectDeviceConfiguration(for: item)
            onOpenSettings(.devices, item.id)
        case .refresh:
            onRefresh()
        case .connect:
            let didConnect = BluetoothDeviceController.connect(deviceID: item.id)
            deviceControlMessage = didConnect
                ? "Connect requested for \(item.displayName)"
                : "Connect unavailable for \(item.displayName)"
            onRefresh()
        case .pin, .unpin:
            setDisplayPreferences(displayPreferences.togglingPin(for: item))
        case .remove:
            setDisplayPreferences(displayPreferences.hiding(item))
        case .disconnect:
            let didDisconnect = BluetoothDeviceController.disconnect(deviceID: item.id)
            deviceControlMessage = didDisconnect
                ? "Disconnect requested for \(item.displayName)"
                : "Disconnect unavailable for \(item.displayName)"
            onRefresh()
        }
    }

    private func selectDeviceConfiguration(for item: DeviceListItem) {
        selectedDeviceConfiguration = SelectedDeviceConfiguration(
            id: item.id,
            displayName: item.displayName,
            kind: item.kind
        )
        selectedDeviceAlertThreshold = Double(LowBatteryNotifier.threshold(forDeviceID: item.id))
        selectedDeviceChargedAlertEnabled = LowBatteryNotifier.isChargedAlertEnabled(forDeviceID: item.id)
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
                Label(action.title(for: displayName), systemImage: resolveSymbol(action.systemImage, fallback: "circle"))
            }
            .disabled(!action.isEnabled(for: item))
        }
    }

    private func deviceAlertSubtitle(for id: String) -> String {
        if LowBatteryNotifier.hasCustomThreshold(forDeviceID: id) {
            return "Custom alert overrides the global threshold."
        }
        return "Using global alert threshold."
    }

    private func alertSummary(for item: DeviceListItem) -> String {
        let hasCustomLow = LowBatteryNotifier.hasCustomThreshold(forDeviceID: item.id)
        let hasCharged = LowBatteryNotifier.isChargedAlertEnabled(forDeviceID: item.id)

        switch (hasCustomLow, hasCharged) {
        case (true, true):
            return "\(LowBatteryNotifier.threshold(forDeviceID: item.id))% + Full"
        case (true, false):
            return "\(LowBatteryNotifier.threshold(forDeviceID: item.id))%"
        case (false, true):
            return "Global + Full"
        case (false, false):
            return "Global"
        }
    }

}

// MARK: - Settings preview

struct StatusWindowPreview: View {
    let style: StatusWindowStyle
    let showsAirPodsCard: Bool
    let showsMenuBarBattery: Bool
    let showsBatteryOverview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Spacer()
                Text(style.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.accent)
            }

            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Palette.accent)
                if showsMenuBarBattery {
                    Text("42%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.text)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.Palette.controlPill)
            )

            VStack(spacing: 5) {
                if style != .native && showsBatteryOverview {
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(index == 0 ? DesignTokens.Palette.healthy.opacity(0.74) : DesignTokens.Palette.secondaryText.opacity(0.24))
                                .frame(height: 18)
                        }
                    }
                }

                if style != .native && showsAirPodsCard {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DesignTokens.Palette.accent.opacity(0.20))
                        .overlay(
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(DesignTokens.Palette.accent.opacity(0.58))
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Capsule()
                                        .fill(DesignTokens.Palette.text.opacity(0.48))
                                        .frame(width: 86, height: 5)
                                    Capsule()
                                        .fill(DesignTokens.Palette.secondaryText.opacity(0.38))
                                        .frame(width: 58, height: 4)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                        )
                        .frame(height: 42)
                }

                ForEach(0..<rowCount, id: \.self) { index in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(DesignTokens.Palette.secondaryText.opacity(0.30))
                            .frame(width: 18, height: 18)

                        Capsule()
                            .fill(DesignTokens.Palette.text.opacity(0.42))
                            .frame(width: index == 1 ? 112 : 88, height: 5)

                        Spacer()

                        Capsule()
                            .fill(DesignTokens.Palette.healthy.opacity(0.74))
                            .frame(width: 28, height: 8)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )
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
}

// MARK: - Native status rows

private struct NativeStatusRow: View {
    let item: DeviceListItem
    let isPinned: Bool
    let lowBatteryThreshold: Int
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            NativeDeviceGlyph(
                symbolName: deviceSymbolName(for: item.kind, displayName: item.displayName)
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignTokens.Palette.accent)
                    }
                }

                if let statusText {
                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let percent {
                HStack(spacing: 5) {
                    Text("\(percent)%")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .monospacedDigit()
                        .lineLimit(1)

                    NativeBatteryIndicator(percent: percent, chargeState: chargeState, color: statusColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: NativeMacStyle.rowCornerRadius, style: .continuous)
                .fill(isHovered ? NativeMacStyle.rowSelection : Color.clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var percent: Int? {
        switch item {
        case .device(let decorated):
            return decorated.snapshot.percent
        case .airPods(_, _, let components):
            return components.compactMap(\.percent).min()
        }
    }

    private var chargeState: ChargeState {
        switch item {
        case .device(let decorated):
            return decorated.snapshot.chargeState
        case .airPods(_, _, let components):
            if components.contains(where: { $0.chargeState == .charging }) { return .charging }
            if !components.isEmpty,
               components.allSatisfy({ $0.chargeState == .full || $0.percent == 100 }) {
                return .full
            }
            return .unplugged
        }
    }

    private var hasStaleSignal: Bool {
        switch item {
        case .device(let decorated):
            return decorated.freshness != .fresh
        case .airPods(_, _, let components):
            return components.contains { $0.freshness != .fresh }
        }
    }

    private var isLow: Bool {
        guard let percent else { return false }
        return percent <= lowBatteryThreshold && chargeState != .charging && chargeState != .full
    }

    private var statusText: String? {
        if chargeState == .charging { return "Charging" }
        if chargeState == .full { return "Full" }
        if isLow { return "Low battery" }
        if hasStaleSignal { return "Last report may be stale" }
        return nil
    }

    private var statusColor: Color {
        if isLow { return DesignTokens.Palette.critical }
        if chargeState == .charging || chargeState == .full { return DesignTokens.Palette.charging }
        if hasStaleSignal { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.text
    }
}

private struct NativeDeviceGlyph: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 20, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.primary.opacity(0.58))
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}

private struct NativeBatteryIndicator: View {
    let percent: Int
    let chargeState: ChargeState
    let color: Color

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 18, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color.opacity(0.86))
            .frame(width: 28, alignment: .trailing)
            .accessibilityLabel("\(percent)%")
    }

    private var symbolName: String {
        if chargeState == .charging {
            return resolveSymbol("battery.100percent.bolt", fallback: "battery.100.bolt")
        }
        if percent >= 88 {
            return resolveSymbol("battery.100percent", fallback: "battery.100")
        }
        if percent >= 63 {
            return resolveSymbol("battery.75percent", fallback: "battery.75")
        }
        if percent >= 38 {
            return resolveSymbol("battery.50percent", fallback: "battery.50")
        }
        if percent >= 13 {
            return resolveSymbol("battery.25percent", fallback: "battery.25")
        }
        return resolveSymbol("battery.0percent", fallback: "battery.0")
    }
}

private struct NativeFooterButton: View {
    let title: String
    let systemImage: String
    var usesBluetoothLogo = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if usesBluetoothLogo {
                    BluetoothLogoMark(size: 22)
                        .frame(width: 22)
                } else {
                    Image(systemName: resolveSymbol(systemImage, fallback: "circle"))
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .frame(width: 20)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.text)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: NativeMacStyle.rowCornerRadius, style: .continuous)
                    .fill(isHovered ? NativeMacStyle.rowSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Battery overview

private struct BatteryOverviewStrip: View {
    let summary: BatteryOverviewSummary
    let devices: [BatteryOverviewDevice]
    let lowBatteryThreshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery Overview")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.Palette.text)

                    Text("\(summary.reportedItemCount) reporting · alert below \(lowBatteryThreshold)%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .monospacedDigit()
                }

                Spacer()

                BatteryOverviewMetric(
                    title: "Low",
                    value: "\(summary.lowBatteryItemCount)",
                    systemImage: "bell.badge",
                    color: summary.lowBatteryItemCount > 0 ? DesignTokens.Palette.critical : DesignTokens.Palette.secondaryText
                )
                .frame(width: 70)
            }

            if !devices.isEmpty {
                HStack(spacing: 10) {
                    ForEach(devices) { device in
                        BatteryOverviewRing(
                            device: device,
                            lowBatteryThreshold: lowBatteryThreshold
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                BatteryOverviewMetric(
                    title: "Lowest",
                    value: lowestValue,
                    systemImage: "battery.25",
                    color: lowestColor
                )

                BatteryOverviewMetric(
                    title: "Charging",
                    value: "\(summary.chargingItemCount)",
                    systemImage: "bolt.fill",
                    color: summary.chargingItemCount > 0 ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText
                )

                BatteryOverviewMetric(
                    title: "Stale",
                    value: "\(summary.staleItemCount)",
                    systemImage: "clock.badge.exclamationmark",
                    color: summary.staleItemCount > 0 ? DesignTokens.Palette.stale : DesignTokens.Palette.secondaryText
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
        )
    }

    private var lowestValue: String {
        summary.lowestPercent.map { "\($0)%" } ?? "—"
    }

    private var lowestColor: Color {
        guard let percent = summary.lowestPercent else { return DesignTokens.Palette.secondaryText }
        if percent <= lowBatteryThreshold { return DesignTokens.Palette.critical }
        if percent <= 45 { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.healthy
    }
}

private struct BatteryOverviewRing: View {
    let device: BatteryOverviewDevice
    let lowBatteryThreshold: Int

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(DesignTokens.Palette.secondaryText.opacity(0.18), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: CGFloat(Swift.max(2, Swift.min(100, device.percent))) / 100)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.30), radius: 4)

                Image(systemName: symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
            }
            .frame(width: 54, height: 54)
            .overlay(alignment: .topTrailing) {
                if device.chargeState == .charging || device.chargeState == .full {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(DesignTokens.Palette.charging))
                        .offset(x: 2, y: -2)
                }
            }

            Text("\(device.percent)%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ringColor)

            Text(shortName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
        .accessibilityLabel("\(device.displayName), \(device.percent)%")
    }

    private var ringColor: Color {
        if device.percent <= lowBatteryThreshold { return DesignTokens.Palette.critical }
        if device.freshness != .fresh { return DesignTokens.Palette.stale }
        if device.percent <= 45 { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.healthy
    }

    private var iconColor: Color {
        if device.freshness != .fresh { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.secondaryText
    }

    private var shortName: String {
        let name = device.displayName
        let replacements = ["Magic ", "Isaac's ", "BatteryHub ", "Apple "]
        return replacements.reduce(name) { partial, token in
            partial.replacingOccurrences(of: token, with: "")
        }
    }

    private var symbolName: String {
        deviceSymbolName(for: device.kind, displayName: device.displayName)
    }
}

private struct BatteryOverviewMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: resolveSymbol(systemImage, fallback: "circle.fill"))
                    .font(.system(size: 10, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
    }
}

private struct DeviceControlMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: resolveSymbol(systemImage, fallback: "circle.fill"))
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
    }
}

private struct DeviceInspectorRow: View {
    let inspectorItem: DeviceInspectorItem
    let symbolName: String
    let alertSummary: String
    let onSelectAlerts: () -> Void
    let onTogglePin: () -> Void
    let onHide: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            DeviceIconPlate(
                symbolName: symbolName,
                color: inspectorItem.isHidden ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.accent,
                size: 30,
                badge: inspectorItem.isHidden ? .disconnected : nil
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(inspectorItem.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(inspectorItem.isHidden ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.text)
                        .lineLimit(1)

                    if inspectorItem.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Palette.accent)
                    }
                }

                HStack(spacing: 6) {
                    DeviceInspectorChip(
                        text: inspectorItem.isHidden ? "Hidden" : "Visible",
                        systemImage: inspectorItem.isHidden ? "eye.slash" : "eye",
                        color: inspectorItem.isHidden ? DesignTokens.Palette.stale : DesignTokens.Palette.secondaryText
                    )

                    DeviceInspectorChip(
                        text: alertSummary,
                        systemImage: "bell.badge",
                        color: DesignTokens.Palette.secondaryText
                    )
                }
            }

            Spacer(minLength: 0)

            if inspectorItem.isHidden {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .help("Restore Device")
            } else {
                Button(action: onTogglePin) {
                    Image(systemName: inspectorItem.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .help(inspectorItem.isPinned ? "Unpin Device" : "Pin Device")

                Button(action: onSelectAlerts) {
                    Image(systemName: "bell.badge")
                }
                .buttonStyle(.plain)
                .help("Battery Alerts")

                Button(action: onHide) {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.plain)
                .help("Hide Device")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(inspectorItem.isHidden ? 0.42 : 0.78))
        )
    }
}

private struct DeviceInspectorChip: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: resolveSymbol(systemImage, fallback: "circle.fill"))
                .symbolRenderingMode(.hierarchical)
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(
            Capsule(style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
    }
}

// MARK: - DeviceSectionCard

private struct DeviceSectionCard: View {
    let section: DeviceSection
    let preferences: DeviceDisplayPreferences
    let onAction: (DeviceContextMenuAction, DeviceListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(section.items.indices, id: \.self) { index in
                itemView(for: section.items[index])

                if index < section.items.count - 1 {
                    Divider()
                        .overlay(DesignTokens.Palette.separator)
                        .padding(.leading, 66)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Palette.card)
                .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 5)
                .shadow(color: .white.opacity(0.42), radius: 0.5, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    @ViewBuilder
    private func itemView(for item: DeviceListItem) -> some View {
        switch item {
        case .device(let decorated):
            DeviceBatteryRow(decorated: decorated, isPinned: preferences.isPinned(item))
                .contextMenu {
                    deviceContextMenu(for: item, displayName: decorated.snapshot.displayName)
                }
        case .airPods(let name, let id, let components):
            AirPodsBatteryRow(
                name: name,
                id: id,
                components: components,
                isPinned: preferences.isPinned(item)
            )
                .contextMenu {
                    deviceContextMenu(for: item, displayName: name)
                }
        }
    }

    @ViewBuilder
    private func deviceContextMenu(for item: DeviceListItem, displayName: String) -> some View {
        ForEach(deviceContextMenuActions(for: item, preferences: preferences)) { action in
            if action == .pin || action == .unpin || action == .remove {
                Divider()
            }

            Button {
                onAction(action, item)
            } label: {
                Label(action.title(for: displayName), systemImage: resolveSymbol(action.systemImage, fallback: "circle"))
            }
            .disabled(!action.isEnabled(for: item))
        }
    }
}

// MARK: - AirPods platter

private struct AirPodsPlatterCard: View {
    let summary: FeaturedAirPodsSummary
    @State private var preferences: AirPodsAudioPreferences

    init(summary: FeaturedAirPodsSummary) {
        self.summary = summary
        _preferences = State(initialValue: AirPodsAudioPreferences.load(for: summary.id))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            VStack(spacing: 3) {
                Text(summary.name)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(summary.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(summary.statusColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Label("\(preferences.listeningMode.shortTitle) · Mic \(preferences.microphone.shortTitle)", systemImage: "waveform")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)

                Spacer()

                Button {
                    BatteryHubSystemSettingsActions.openSoundSettings()
                } label: {
                    Image(systemName: resolveSymbol("speaker.wave.2", fallback: "gearshape"))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Open Sound Settings")
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.Palette.controlPill.opacity(0.82))
            )

            AirPodsProductStage(name: summary.name, color: summary.statusColor)

            HStack(spacing: 10) {
                ForEach(summary.components, id: \.slot.rawValue) { component in
                    AirPodsComponentReadout(component: component)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignTokens.Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
                .shadow(color: .white.opacity(0.32), radius: 0.5, x: 0, y: 1)
        )
        .onChange(of: summary.id) { _, nextID in
            preferences = AirPodsAudioPreferences.load(for: nextID)
        }
    }

}

private struct AirPodsProductStage: View {
    let name: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.8)
                )

            if isOverEar {
                Image(systemName: resolveSymbol("airpodsmax", fallback: "headphones"))
                    .font(.system(size: 58, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
                    .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 5)
            } else {
                HStack(spacing: 34) {
                    Image(systemName: earbudSymbolName)
                        .font(.system(size: 58, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(color)
                        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 5)

                    Image(systemName: resolveSymbol("airpods.chargingcase", fallback: "battery.100"))
                        .font(.system(size: 64, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 5)
                }
            }
        }
        .frame(height: 110)
    }

    private var lowerName: String {
        name.lowercased()
    }

    private var isOverEar: Bool {
        lowerName.contains("max")
    }

    private var earbudSymbolName: String {
        let lower = lowerName
        if lower.contains("pro") { return resolveSymbol("airpodspro", fallback: "airpods") }
        if lower.contains("3rd") || lower.contains("gen 3") {
            return resolveSymbol("airpods.gen3", fallback: "airpods")
        }
        return "airpods"
    }
}

private struct AirPodsComponentReadout: View {
    let component: AirPodsComponent

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: slotSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(labelColor)

                Text(slotLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            if let percent = component.percent {
                VStack(spacing: 4) {
                    BatteryLevelPill(percent: percent, chargeState: component.chargeState)

                    Text("\(percent)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(labelColor)
                }
            } else {
                Text("No report")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .frame(height: 34)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
        )
    }

    private var slotLabel: String {
        switch component.slot {
        case .case: return "Case"
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    private var slotSymbol: String {
        switch component.slot {
        case .case:
            return resolveSymbol("airpods.chargingcase", fallback: "battery.100")
        case .left:
            return resolveSymbol("airpod.left", fallback: "l.circle")
        case .right:
            return resolveSymbol("airpod.right", fallback: "r.circle")
        }
    }

    private var labelColor: Color {
        guard let percent = component.percent else { return DesignTokens.Palette.tertiaryText }
        if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
        if component.freshness != .fresh { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.text
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
    // Mobile + audio section
    mockDecorated(id: "iph1", name: "Isaac's iPhone",   kind: .iPhone,    percent: 42, chargeState: .charging),
    mockDecorated(id: "wtc1", name: "Apple Watch",      kind: .appleWatch, percent: 18),
    // AirPods 3-component
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-case",  name: "John's AirPods Pro Case",  kind: .airPods, percent: 90),
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-left",  name: "John's AirPods Pro Left",  kind: .airPods, percent: 75),
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-right", name: "John's AirPods Pro Right", kind: .airPods, percent: 80),
]

private let previewSnapshotsEdge: [DecoratedBatterySnapshot] = [
    // Critical battery
    mockDecorated(id: "iph2", name: "Low iPhone",       kind: .iPhone,    percent: 8),
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
