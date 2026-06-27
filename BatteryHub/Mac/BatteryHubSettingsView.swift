import SwiftUI

enum NotificationPermissionActivationAction: Equatable {
    case none
    case requestAuthorization
    case openSystemSettings
}

enum NotificationPermissionRequestPolicy {
    static func activationAction(
        afterEnablingAlertPreference isEnabled: Bool,
        authorizationState: NotificationCenterAuthorizationState
    ) -> NotificationPermissionActivationAction {
        guard isEnabled else { return .none }

        switch authorizationState {
        case .unknown, .notDetermined:
            return .requestAuthorization
        case .denied:
            return .openSystemSettings
        case .authorized, .provisional:
            return .none
        }
    }

    static func shouldRequestAuthorization(
        afterEnablingAlertPreference isEnabled: Bool,
        authorizationState: NotificationCenterAuthorizationState
    ) -> Bool {
        activationAction(
            afterEnablingAlertPreference: isEnabled,
            authorizationState: authorizationState
        ) == .requestAuthorization
    }
}

struct BatteryHubSettingsView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let isRefreshing: Bool
    let isPreviewingData: Bool
    let notificationAuthorizationState: NotificationCenterAuthorizationState
    let onRefresh: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onOpenSoundSettings: () -> Void
    let onRefreshNotificationAuthorization: () -> Void
    let onRequestNotificationPermission: () -> Void
    let onOpenNotificationSettings: () -> Void
    let onQuit: () -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @AppStorage(LowBatteryNotifier.notificationsEnabledDefaultsKey) private var lowBatteryAlertsEnabled = true
    @AppStorage(LowBatteryNotifier.chargedNotificationsEnabledDefaultsKey) private var chargedBatteryAlertsEnabled = true
    @AppStorage(BatteryHUDPreferences.showActionHUDKey) private var showActionHUD = true
    @AppStorage(BatteryHUDPreferences.lowBatteryHUDEnabledKey) private var showLowBatteryHUD = true
    @AppStorage(BatteryHUDPreferences.chargedHUDEnabledKey) private var showChargedHUD = true
    @AppStorage(StatusWindowPreferences.showMenuBarBatteryKey) private var showMenuBarBattery = false
    @AppStorage(DesktopWidgetPreferences.showDesktopWidgetKey) private var showDesktopWidget = false
    @AppStorage(DesktopWidgetPreferences.widgetStyleKey) private var desktopWidgetStyleRawValue = DesktopWidgetStyle.compact.rawValue
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @AppStorage("BatteryHub.settings.showUnavailableDevices") private var showUnavailableDevices = true

    @State private var displayPreferences = DeviceDisplayPreferences.load()
    @State private var quickActionPreferences = BatteryHubQuickActionPreferences.load()
    @State private var selectedDeviceID: String?
    @State private var selectedPane: SettingsPane = .devices
    @State private var isShowingAddDeviceGuide = false

    init(
        snapshots: [DecoratedBatterySnapshot],
        isRefreshing: Bool = false,
        isPreviewingData: Bool = false,
        notificationAuthorizationState: NotificationCenterAuthorizationState = .unknown,
        onRefresh: @escaping () -> Void,
        onOpenBluetoothSettings: @escaping () -> Void = {},
        onOpenSoundSettings: @escaping () -> Void = {},
        onRefreshNotificationAuthorization: @escaping () -> Void = {},
        onRequestNotificationPermission: @escaping () -> Void = {},
        onOpenNotificationSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {},
        initialPane: SettingsPane = .devices,
        initialSelectedDeviceID: String? = nil,
        initiallyShowingAddDeviceGuide: Bool = false
    ) {
        self.snapshots = snapshots
        self.isRefreshing = isRefreshing
        self.isPreviewingData = isPreviewingData
        self.notificationAuthorizationState = notificationAuthorizationState
        self.onRefresh = onRefresh
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
        self.onOpenSoundSettings = onOpenSoundSettings
        self.onRefreshNotificationAuthorization = onRefreshNotificationAuthorization
        self.onRequestNotificationPermission = onRequestNotificationPermission
        self.onOpenNotificationSettings = onOpenNotificationSettings
        self.onQuit = onQuit
        _selectedPane = State(initialValue: initialPane)
        _selectedDeviceID = State(initialValue: initialSelectedDeviceID)
        _isShowingAddDeviceGuide = State(initialValue: initiallyShowingAddDeviceGuide)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            VStack(spacing: 0) {
                settingsHeader

                Divider()

                settingsDetail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 900, height: 620)
        .background(.regularMaterial)
        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
        .onAppear {
            reconcileSelectedDeviceSelection()
            onRefreshNotificationAuthorization()
        }
        .sheet(isPresented: $isShowingAddDeviceGuide) {
            AddDeviceGuideView(
                onOpenBluetoothSettings: onOpenBluetoothSettings,
                onDismiss: { isShowingAddDeviceGuide = false }
            )
        }
    }

    private var appearanceTheme: BatteryHubAppearanceTheme {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BatteryHub")
                .font(DesignTokens.Typography.sidebarTitle)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.top, 4)

            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        HStack(spacing: 9) {
                            SettingsPaneIcon(pane: pane)

                            Text(pane.title)
                                .font(selectedPane == pane ? DesignTokens.Typography.controlLabelEmphasis : DesignTokens.Typography.controlLabel)
                                .foregroundStyle(selectedPane == pane ? .primary : .secondary)

                            Spacer(minLength: 0)
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: NativeMacStyle.rowCornerRadius, style: .continuous)
                                    .fill(selectedPane == pane ? NativeMacStyle.rowSelection : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button(action: onQuit) {
                Label("Quit BatteryHub", systemImage: "power")
                    .font(DesignTokens.Typography.controlLabel)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            }
            .buttonStyle(.plain)
            .help("Quit BatteryHub")
        }
        .padding(12)
        .frame(width: 190)
        .background(.regularMaterial)
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Text(selectedPane.title)
                .font(DesignTokens.Typography.windowTitle)
                .lineLimit(1)

            Spacer()

            if selectedPane == .devices {
                Button {
                    isShowingAddDeviceGuide = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Device")
            }

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)
            .help(isRefreshing ? "Refreshing" : "Refresh")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            if isPreviewingData {
                previewDataBanner
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            Group {
                switch selectedPane {
                case .devices: devicesTab
                case .alerts: alertsTab
                case .actionHUD: actionHUDTab
                case .quickActions: quickActionsTab
                case .dashboard: dashboardTab
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var devicesTab: some View {
        HStack(spacing: 0) {
            deviceSelectionPane(title: "Devices", subtitle: devicesSubtitle)

            Divider()

            Group {
                if let selectedDevice {
                    ScrollView(showsIndicators: false) {
                        deviceDetail(for: selectedDevice)
                            .padding(1)
                    }
                } else {
                    emptyDeviceDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 22)
        }
    }

    private var alertsTab: some View {
        HStack(spacing: 0) {
            deviceSelectionPane(title: "Devices", subtitle: devicesSubtitle)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if let selectedDevice {
                        alertDetail(for: selectedDevice)
                    } else {
                        emptyAlertDetail
                    }
                }
                .padding(.top, 6)
                .padding(1)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 22)
        }
    }

    private func deviceSelectionPane(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Typography.sectionTitle)
                    Text(subtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer(minLength: 0)

                if hiddenDeviceCount > 0 {
                    Button {
                        showUnavailableDevices.toggle()
                        reconcileSelectedDeviceSelection()
                    } label: {
                        Label(
                            showUnavailableDevices ? "Hide Unavailable" : "Show Hidden",
                            systemImage: showUnavailableDevices ? "eye.slash" : "eye"
                        )
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .help(showUnavailableDevices ? "Hide disconnected devices" : "Show hidden devices")
                }
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(displayedDeviceRows) { row in
                        SettingsDeviceSidebarRow(
                            item: row,
                            isSelected: selectedDevice?.id == row.id,
                            symbolName: deviceSymbolName(for: row.kind, displayName: row.displayName),
                            iconColor: detailIconColor(for: row),
                            iconBadge: detailIconBadge(for: row),
                            alertSummary: alertSummary(for: row.item)
                        ) {
                            selectedDeviceID = row.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 260)
        .padding(.trailing, 18)
    }

    private func alertDetail(for row: DeviceInspectorItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            compactAlertHeader(for: row)
            compactDeviceAlertCard(for: row)
            compactGlobalAlertCard
            compactAlertPreviewCard
        }
        .frame(maxWidth: 560, alignment: .topLeading)
    }

    private func compactAlertHeader(for row: DeviceInspectorItem) -> some View {
        HStack(spacing: 12) {
            DeviceIconPlate(
                symbolName: deviceSymbolName(for: row.kind, displayName: row.displayName),
                color: detailIconColor(for: row),
                size: 34,
                badge: detailIconBadge(for: row)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(DesignTokens.Typography.rowTitleEmphasis)
                    .lineLimit(1)
                Text(deviceAlertSubtitle(for: row))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            compactAlertSummaryBadge(for: row)
        }
        .padding(.bottom, 2)
    }

    private func compactAlertSummaryBadge(for row: DeviceInspectorItem) -> some View {
        Text(row.isHidden ? "Hidden" : alertSummary(for: row.item))
            .font(DesignTokens.Typography.captionEmphasis)
            .monospacedDigit()
            .foregroundStyle(row.isHidden ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.accent)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule(style: .continuous).fill(DesignTokens.Palette.controlPill))
    }

    private func compactDeviceAlertCard(for row: DeviceInspectorItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            compactAlertTitleRow(
                title: "Selected Device",
                subtitle: row.isHidden ? "Hidden until it reconnects and reports battery." : "Overrides only this device.",
                systemImage: "bell.badge",
                color: row.isHidden ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.accent
            )
            .padding(.horizontal, 12)
            .frame(height: 44)

            Divider()
                .padding(.leading, 50)

            HStack(spacing: 10) {
                Text("Low threshold")
                    .font(DesignTokens.Typography.captionEmphasis)
                    .frame(width: 94, alignment: .leading)

                Slider(value: deviceThresholdBinding(for: row.id), in: 5...50, step: 5)
                    .controlSize(.small)
                    .disabled(row.isHidden || !lowBatteryAlertsEnabled)

                Text("\(LowBatteryNotifier.threshold(forDeviceID: row.id))%")
                    .font(DesignTokens.Typography.percentSmall)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .opacity(row.isHidden || !lowBatteryAlertsEnabled ? 0.5 : 1)

            Divider()
                .padding(.leading, 50)

            HStack(spacing: 12) {
                Toggle("Notify when charged", isOn: deviceChargedAlertBinding(for: row))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(row.isHidden || !chargedBatteryAlertsEnabled)

                Spacer(minLength: 8)

                Button("Use Global") {
                    LowBatteryNotifier.resetThreshold(forDeviceID: row.id)
                }
                .controlSize(.small)
                .disabled(row.isHidden || !LowBatteryNotifier.hasCustomThreshold(forDeviceID: row.id))
            }
            .font(DesignTokens.Typography.controlLabel)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .opacity(row.isHidden || !chargedBatteryAlertsEnabled ? 0.5 : 1)
        }
        .background(settingsCardBackground)
    }

    private var compactGlobalAlertCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactAlertTitleRow(
                title: "Global Defaults",
                subtitle: "Used when a device has no override.",
                systemImage: "slider.horizontal.3",
                color: DesignTokens.Palette.secondaryText
            )
            .padding(.horizontal, 12)
            .frame(height: 44)

            Divider()
                .padding(.leading, 50)

            HStack(spacing: 10) {
                Toggle("Low battery alerts", isOn: $lowBatteryAlertsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: lowBatteryAlertsEnabled) { _, isEnabled in
                        handleNotificationAlertPreferenceActivation(isEnabled)
                    }

                Spacer(minLength: 8)

                Text("\(clampedLowBatteryThreshold)%")
                    .font(DesignTokens.Typography.percentSmall)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 40, alignment: .trailing)
            }
            .font(DesignTokens.Typography.controlLabel)
            .padding(.horizontal, 12)
            .frame(height: 40)

            HStack(spacing: 10) {
                Text("Default threshold")
                    .font(DesignTokens.Typography.captionEmphasis)
                    .frame(width: 104, alignment: .leading)

                Slider(value: lowBatteryThresholdBinding, in: 5...50, step: 5)
                    .controlSize(.small)
                    .disabled(!lowBatteryAlertsEnabled)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .opacity(lowBatteryAlertsEnabled ? 1 : 0.5)

            Divider()
                .padding(.leading, 50)

            Toggle("Charged alerts", isOn: $chargedBatteryAlertsEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: chargedBatteryAlertsEnabled) { _, isEnabled in
                    handleNotificationAlertPreferenceActivation(isEnabled)
                }
                .font(DesignTokens.Typography.controlLabel)
                .padding(.horizontal, 12)
                .frame(height: 40, alignment: .leading)
        }
        .background(settingsCardBackground)
    }

    private var compactAlertPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(DesignTokens.Typography.captionEmphasis)
                .foregroundStyle(DesignTokens.Palette.secondaryText)

            HStack(spacing: 10) {
                SettingsAlertPreview(
                    title: "Low Battery",
                    subtitle: "At \(clampedLowBatteryThreshold)%",
                    systemImage: "battery.25",
                    color: DesignTokens.Palette.critical
                )
                SettingsAlertPreview(
                    title: "Fully Charged",
                    subtitle: "At 100%",
                    systemImage: "battery.100",
                    color: DesignTokens.Palette.charging
                )
            }
        }
        .padding(10)
        .background(settingsCardBackground)
    }

    private func compactAlertTitleRow(title: String, subtitle: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: resolveSymbol(systemImage, fallback: "bell"))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DesignTokens.Typography.captionEmphasis)
                Text(subtitle)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyAlertDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No selectable devices")
                .font(DesignTokens.Typography.sectionTitle)
            Text("Show hidden devices or connect a reporting device to edit per-device alerts.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private var actionHUDTab: some View {
        ActionHUDSettingsPane(
            showActionHUD: $showActionHUD,
            showLowBatteryHUD: $showLowBatteryHUD,
            showChargedHUD: $showChargedHUD,
            lowBatteryThreshold: clampedLowBatteryThreshold
        )
    }

    private var dashboardTab: some View {
        DashboardSettingsPane(
            snapshots: snapshots,
            showMenuBarBattery: $showMenuBarBattery,
            showDesktopWidget: $showDesktopWidget,
            desktopWidgetStyleRawValue: $desktopWidgetStyleRawValue
        )
    }

    private var quickActionsTab: some View {
        QuickActionsSettingsPane(preferences: $quickActionPreferences)
    }

    private func deviceDetail(for row: DeviceInspectorItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                DeviceIconPlate(
                    symbolName: deviceSymbolName(for: row.kind, displayName: row.displayName),
                    color: detailIconColor(for: row),
                    size: 36,
                    badge: detailIconBadge(for: row)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.displayName)
                        .font(DesignTokens.Typography.sectionTitle)
                        .lineLimit(1)
                    Text(detailSubtitle(for: row))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                SettingsDetailToggle(
                    title: "Keep visible",
                    subtitle: "Pinned devices stay at the top of the dashboard.",
                    systemImage: "pin.fill",
                    isOn: Binding(
                        get: { row.isPinned },
                        set: { setDisplayPreferences(displayPreferences.settingPinned($0, for: row.item)) }
                    )
                )
                .disabled(row.isHidden)
                .opacity(row.isHidden ? 0.45 : 1)

                Divider()
                    .padding(.leading, 50)

                SettingsDetailToggle(
                    title: "Notify when charged",
                    subtitle: "Best for devices that keep reporting while charging.",
                    systemImage: "battery.100",
                    isOn: deviceChargedAlertBinding(for: row)
                )
                .disabled(row.isHidden || !chargedBatteryAlertsEnabled)
                .opacity(row.isHidden || !chargedBatteryAlertsEnabled ? 0.45 : 1)
            }
            .background(settingsCardBackground)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Low-battery threshold")
                        .font(DesignTokens.Typography.captionEmphasis)
                    Spacer()
                    Text("\(LowBatteryNotifier.threshold(forDeviceID: row.id))%")
                        .font(DesignTokens.Typography.percentSmall)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.accent)
                }

                Slider(
                    value: Binding(
                        get: { Double(LowBatteryNotifier.threshold(forDeviceID: row.id)) },
                        set: { LowBatteryNotifier.setThreshold(Int($0.rounded()), forDeviceID: row.id) }
                    ),
                    in: 5...50,
                    step: 5
                )
                .disabled(row.isHidden || !lowBatteryAlertsEnabled)

                HStack {
                    Button("Use Global Default") {
                        LowBatteryNotifier.resetThreshold(forDeviceID: row.id)
                    }
                    .disabled(!LowBatteryNotifier.hasCustomThreshold(forDeviceID: row.id))

                    Spacer()

                    Text(alertSummary(for: row.item))
                        .font(DesignTokens.Typography.captionEmphasis)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
            }
            .padding(12)
            .background(settingsCardBackground)

            if row.kind == .airPods {
                AirPodsAudioControlsCard(
                    deviceID: row.id,
                    onOpenSoundSettings: onOpenSoundSettings,
                    onOpenBluetoothSettings: onOpenBluetoothSettings
                )
            }

            DeviceCurrentStatsCard(
                item: row.item,
                historySamples: BatteryHistoryStore.samples(for: row.id)
            )

            if BluetoothDeviceControlSupport.canConnect(row.item) || BluetoothDeviceControlSupport.canDisconnect(row.item) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        BluetoothLogoMark(size: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bluetooth Controls")
                                .font(DesignTokens.Typography.captionEmphasis)
                            Text("Connect and disconnect use the paired Bluetooth address when macOS exposes one.")
                                .font(DesignTokens.Typography.caption2)
                                .foregroundStyle(DesignTokens.Palette.secondaryText)
                        }
                    }

                    HStack {
                        if BluetoothDeviceControlSupport.canConnect(row.item) {
                            Button {
                                _ = BluetoothDeviceController.connect(deviceID: row.id)
                                onRefresh()
                            } label: {
                                Label("Connect Device", systemImage: BatteryHubSymbols.bluetooth)
                            }
                        }

                        if BluetoothDeviceControlSupport.canDisconnect(row.item) {
                            Button(role: .destructive) {
                                _ = BluetoothDeviceController.disconnect(deviceID: row.id)
                                onRefresh()
                            } label: {
                                Label("Disconnect Device", systemImage: "bolt.horizontal.circle")
                            }
                        }

                        Button {
                            onOpenBluetoothSettings()
                        } label: {
                            HStack(spacing: 6) {
                                BluetoothLogoMark(size: 16)
                                Text("Bluetooth Settings")
                            }
                        }

                        Spacer()
                    }
                }
                .padding(12)
                .background(settingsCardBackground)
            }

            HStack {
                if row.isUserHidden {
                    Button {
                        setDisplayPreferences(displayPreferences.restoring(row.item))
                    } label: {
                        Label("Restore Device", systemImage: "arrow.uturn.backward")
                    }
                } else if row.isUnavailable {
                    Label("Hidden until connected", systemImage: "eye.slash")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                } else {
                    Button(role: .destructive) {
                        setDisplayPreferences(displayPreferences.hiding(row.item))
                    } label: {
                        Label("Hide Device", systemImage: "eye.slash")
                    }
                }

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    private var emptyDeviceDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No devices")
                .font(DesignTokens.Typography.sectionTitle)
            Text("Connected devices will appear here after the next refresh.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
        }
        .padding(.top, 12)
    }

    private var deviceRows: [DeviceInspectorItem] {
        deviceInspectorItems(snapshots, preferences: displayPreferences)
    }

    private var displayedDeviceRows: [DeviceInspectorItem] {
        displayedDeviceInspectorItems(
            deviceRows,
            showHiddenUnavailable: showUnavailableDevices
        )
    }

    private var selectedDevice: DeviceInspectorItem? {
        if let selectedDeviceID,
           let row = displayedDeviceRows.first(where: { $0.id == selectedDeviceID }) {
            return row
        }
        return displayedDeviceRows.first
    }

    private var visibleDeviceCount: Int {
        deviceRows.filter { !$0.isHidden }.count
    }

    private var hiddenDeviceCount: Int {
        deviceRows.filter(\.isHidden).count
    }

    private var devicesSubtitle: String {
        if isRefreshing {
            return "Refreshing... · \(visibleDeviceCount) visible"
        }
        if !showUnavailableDevices, hiddenDeviceCount > 0 {
            return "\(visibleDeviceCount) visible · \(hiddenDeviceCount) hidden collapsed"
        }
        return "\(visibleDeviceCount) visible · \(hiddenDeviceCount) hidden"
    }

    private var previewDataBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: resolveSymbol("eye", fallback: "info.circle"))
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Palette.warning)

            VStack(alignment: .leading, spacing: 1) {
                Text("Preview data is active")
                    .font(DesignTokens.Typography.captionEmphasis)
                    .foregroundStyle(DesignTokens.Palette.text)
                Text("Sample devices are shown for UI QA, not live Bluetooth.")
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Palette.warning.opacity(0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignTokens.Palette.warning.opacity(0.22), lineWidth: 0.7)
                )
        )
    }

    private var clampedLowBatteryThreshold: Int {
        Swift.max(5, Swift.min(50, lowBatteryThreshold))
    }

    private var lowBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(clampedLowBatteryThreshold) },
            set: { lowBatteryThreshold = Int($0.rounded()) }
        )
    }

    private func deviceThresholdBinding(for deviceID: String) -> Binding<Double> {
        Binding(
            get: { Double(LowBatteryNotifier.threshold(forDeviceID: deviceID)) },
            set: { LowBatteryNotifier.setThreshold(Int($0.rounded()), forDeviceID: deviceID) }
        )
    }

    private func deviceChargedAlertBinding(for row: DeviceInspectorItem) -> Binding<Bool> {
        Binding(
            get: {
                LowBatteryNotifier.isChargedAlertEnabled(
                    forDeviceID: row.id,
                    displayName: row.displayName
                )
            },
            set: {
                LowBatteryNotifier.setChargedAlertEnabled(
                    $0,
                    forDeviceID: row.id,
                    displayName: row.displayName
                )
                handleNotificationAlertPreferenceActivation($0)
            }
        )
    }

    private func handleNotificationAlertPreferenceActivation(_ isEnabled: Bool) {
        switch NotificationPermissionRequestPolicy.activationAction(
            afterEnablingAlertPreference: isEnabled,
            authorizationState: notificationAuthorizationState
        ) {
        case .none:
            break
        case .requestAuthorization:
            onRequestNotificationPermission()
        case .openSystemSettings:
            onOpenNotificationSettings()
        }
    }

    @ViewBuilder
    private var settingsCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.regularMaterial)
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7))
        } else {
            shape
                .fill(.regularMaterial)
                .overlay(shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7))
        }
    }

    private func setDisplayPreferences(_ preferences: DeviceDisplayPreferences) {
        displayPreferences = preferences
        preferences.save()
    }

    private func reconcileSelectedDeviceSelection() {
        let rowIDs = Set(displayedDeviceRows.map(\.id))
        if let selectedDeviceID, rowIDs.contains(selectedDeviceID) {
            return
        }
        selectedDeviceID = displayedDeviceRows.first?.id
    }

    private func detailSubtitle(for row: DeviceInspectorItem) -> String {
        if row.item.connectionState == .disconnected { return "Paired, currently disconnected" }
        if !hasBatteryReport(row.item) { return "Connected, waiting for battery report" }
        if row.isHidden { return "Hidden from the menu bar dashboard" }
        if row.isPinned { return "Pinned to the top of the dashboard" }
        return "Visible in the menu bar dashboard"
    }

    private func detailIconBadge(for row: DeviceInspectorItem) -> DeviceIconBadge? {
        if row.item.connectionState == .disconnected { return .disconnected }
        if !hasBatteryReport(row.item) { return .stale }
        return nil
    }

    private func detailIconColor(for row: DeviceInspectorItem) -> Color {
        if row.item.connectionState == .disconnected { return DesignTokens.Palette.secondaryText }
        if !hasBatteryReport(row.item) { return DesignTokens.Palette.stale }
        if row.isHidden { return DesignTokens.Palette.secondaryText }
        if row.kind == .keyboard { return Color.primary.opacity(0.58) }
        return DesignTokens.Palette.accent
    }

    private func hasBatteryReport(_ item: DeviceListItem) -> Bool {
        switch item {
        case .device(let decorated):
            return decorated.snapshot.percent != nil
        case .airPods(_, _, let components):
            return components.contains { $0.percent != nil }
        }
    }

    private func alertSummary(for item: DeviceListItem) -> String {
        let hasCustomLow = LowBatteryNotifier.hasCustomThreshold(forDeviceID: item.id)
        let hasCharged = LowBatteryNotifier.isChargedAlertEnabled(
            forDeviceID: item.id,
            displayName: item.displayName
        )

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

    private func deviceAlertSubtitle(for row: DeviceInspectorItem) -> String {
        if LowBatteryNotifier.hasCustomThreshold(forDeviceID: row.id) {
            return "Custom low-battery alert at \(LowBatteryNotifier.threshold(forDeviceID: row.id))%."
        }
        return "Using the global low-battery threshold."
    }

}
