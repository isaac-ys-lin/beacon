import SwiftUI

struct BatteryHubSettingsView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let isRefreshing: Bool
    let isPreviewingData: Bool
    let onRefresh: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onOpenSoundSettings: () -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @AppStorage(LowBatteryNotifier.notificationsEnabledDefaultsKey) private var lowBatteryAlertsEnabled = true
    @AppStorage(LowBatteryNotifier.chargedNotificationsEnabledDefaultsKey) private var chargedBatteryAlertsEnabled = true
    @AppStorage(BatteryHUDPreferences.showActionHUDKey) private var showActionHUD = true
    @AppStorage(BatteryHUDPreferences.lowBatteryHUDEnabledKey) private var showLowBatteryHUD = true
    @AppStorage(BatteryHUDPreferences.chargedHUDEnabledKey) private var showChargedHUD = true
    @AppStorage(BatteryHUDPreferences.autoDismissEnabledKey) private var autoDismissActionHUD = true
    @AppStorage(BatteryHUDPreferences.dismissDelaySecondsKey) private var actionHUDDismissDelay = BatteryHUDPreferences.defaultDismissDelaySeconds
    @AppStorage(BatteryHUDPreferences.showDismissButtonKey) private var showActionHUDDismissButton = true
    @AppStorage(StatusWindowPreferences.styleKey) private var statusWindowStyleRawValue = StatusWindowStyle.native.rawValue
    @AppStorage(StatusWindowPreferences.showAirPodsCardKey) private var showAirPodsStatusCard = true
    @AppStorage(StatusWindowPreferences.showMenuBarBatteryKey) private var showMenuBarBattery = false
    @AppStorage(StatusWindowPreferences.showBatteryOverviewKey) private var showBatteryOverview = true
    @AppStorage(DesktopWidgetPreferences.showDesktopWidgetKey) private var showDesktopWidget = false
    @AppStorage(DesktopWidgetPreferences.widgetStyleKey) private var desktopWidgetStyleRawValue = DesktopWidgetStyle.compact.rawValue
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
        onRefresh: @escaping () -> Void,
        onOpenBluetoothSettings: @escaping () -> Void = {},
        onOpenSoundSettings: @escaping () -> Void = {},
        initialPane: SettingsPane = .devices,
        initialSelectedDeviceID: String? = nil,
        initiallyShowingAddDeviceGuide: Bool = false
    ) {
        self.snapshots = snapshots
        self.isRefreshing = isRefreshing
        self.isPreviewingData = isPreviewingData
        self.onRefresh = onRefresh
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
        self.onOpenSoundSettings = onOpenSoundSettings
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
        .onAppear {
            reconcileSelectedDeviceSelection()
        }
        .sheet(isPresented: $isShowingAddDeviceGuide) {
            AddDeviceGuideView(
                onOpenBluetoothSettings: onOpenBluetoothSettings,
                onDismiss: { isShowingAddDeviceGuide = false }
            )
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BatteryHub")
                .font(.system(size: 18, weight: .semibold))
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
                                .font(.system(size: 13, weight: .medium))
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
        }
        .padding(12)
        .frame(width: 190)
        .background(.regularMaterial)
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Text(selectedPane.title)
                .font(.system(size: 20, weight: .semibold))
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

            Group {
                if let selectedDevice {
                    alertDetail(for: selectedDevice)
                } else {
                    emptyAlertDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 22)
        }
    }

    private func deviceSelectionPane(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
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
                    .help(showUnavailableDevices ? "Hide disconnected and no-report devices" : "Show hidden devices")
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
        .padding(.top, 6)
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
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
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(deviceAlertSubtitle(for: row))
                    .font(.system(size: 11, weight: .medium))
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
            .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 94, alignment: .leading)

                Slider(value: deviceThresholdBinding(for: row.id), in: 5...50, step: 5)
                    .controlSize(.small)
                    .disabled(row.isHidden || !lowBatteryAlertsEnabled)

                Text("\(LowBatteryNotifier.threshold(forDeviceID: row.id))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
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
                Toggle("Notify when charged", isOn: deviceChargedAlertBinding(for: row.id))
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
            .font(.system(size: 12, weight: .medium))
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

                Spacer(minLength: 8)

                Text("\(clampedLowBatteryThreshold)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 40)

            HStack(spacing: 10) {
                Text("Default threshold")
                    .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 40, alignment: .leading)
        }
        .background(settingsCardBackground)
    }

    private var compactAlertPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyAlertDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No selectable devices")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Show hidden devices or connect a reporting device to edit per-device alerts.")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private var actionHUDTab: some View {
        HStack(alignment: .top, spacing: 18) {
            Form {
                Section {
                    Toggle("Show Action HUD", isOn: $showActionHUD)
                } header: {
                    Text("Action HUD")
                } footer: {
                    Text("Show polished in-app alerts for important battery events.")
                }

                Section {
                    ActionHUDEventToggle(
                        title: "Low battery",
                        subtitle: "Show when a device drops below its alert level.",
                        systemImage: "battery.25",
                        color: DesignTokens.Palette.critical,
                        isOn: $showLowBatteryHUD
                    )
                    .disabled(!showActionHUD)
                    .opacity(showActionHUD ? 1 : 0.45)

                    ActionHUDEventToggle(
                        title: "Finished charging",
                        subtitle: "Show when an opted-in device reaches full charge.",
                        systemImage: "battery.100",
                        color: DesignTokens.Palette.charging,
                        isOn: $showChargedHUD
                    )
                    .disabled(!showActionHUD)
                    .opacity(showActionHUD ? 1 : 0.45)
                } header: {
                    Text("Events")
                }

            }
            .formStyle(.grouped)
            .frame(minWidth: 350, maxWidth: 350, maxHeight: .infinity, alignment: .topLeading)

            actionHUDPreviewPanel
        }
        .frame(maxWidth: 650, maxHeight: .infinity, alignment: .top)
    }

    private var actionHUDPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Preview")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(autoDismissActionHUD ? "Dismisses after \(Int(clampedActionHUDDismissDelay)) seconds" : "Stays until dismissed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            VStack(spacing: 10) {
                BatteryActionHUDView(
                    event: BatteryAlertEvent(
                        kind: .lowBattery,
                        deviceID: "settings-watch",
                        displayName: "Apple Watch",
                        percent: clampedLowBatteryThreshold
                    ),
                    showsDismissButton: showActionHUDDismissButton
                )
                .scaleEffect(0.58)
                .frame(width: 302, height: 54)

                BatteryActionHUDView(
                    event: BatteryAlertEvent(
                        kind: .charged,
                        deviceID: "settings-iphone",
                        displayName: "iPhone",
                        percent: 100
                    ),
                    showsDismissButton: showActionHUDDismissButton
                )
                .scaleEffect(0.58)
                .frame(width: 302, height: 54)
            }
            .opacity(showActionHUD ? 1 : 0.45)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                hudStateRow("Low battery", isOn: showLowBatteryHUD)
                hudStateRow("Finished charging", isOn: showChargedHUD)
                hudStateRow("Manual close", isOn: showActionHUDDismissButton)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Behavior")
                    .font(.system(size: 13, weight: .semibold))

                Toggle("Auto-dismiss", isOn: $autoDismissActionHUD)
                    .disabled(!showActionHUD)

                HStack {
                    Slider(value: actionHUDDismissDelayBinding, in: 2...10, step: 1)
                        .disabled(!showActionHUD || !autoDismissActionHUD)
                    Text("\(Int(clampedActionHUDDismissDelay))s")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.accent)
                        .frame(width: 30, alignment: .trailing)
                }
                .opacity(autoDismissActionHUD ? 1 : 0.45)

                Toggle("Show dismiss button", isOn: $showActionHUDDismissButton)
                    .disabled(!showActionHUD)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(16)
        .frame(width: 330, alignment: .topLeading)
        .background(settingsCardBackground)
        .padding(.top, 18)
    }

    private var dashboardTab: some View {
        HStack(alignment: .top, spacing: 18) {
            Form {
                Section {
                    Picker("Dashboard size", selection: $statusWindowStyleRawValue) {
                        ForEach(StatusWindowStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show battery overview", isOn: $showBatteryOverview)
                        .disabled(statusWindowStyle == .native)
                    Toggle("Show AirPods status card", isOn: $showAirPodsStatusCard)
                        .disabled(statusWindowStyle != .large)
                    Toggle("Show lowest battery in menu bar", isOn: $showMenuBarBattery)
                } header: {
                    Text("Menu Bar Dashboard")
                } footer: {
                    Text("Native Compact uses a single system-style connected-device list. Large mode enables overview and AirPods detail cards.")
                }

                Section {
                    Toggle("Show floating desktop widget", isOn: $showDesktopWidget)

                    Picker("Widget size", selection: $desktopWidgetStyleRawValue) {
                        ForEach(DesktopWidgetStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!showDesktopWidget)
                } header: {
                    Text("Desktop Widget")
                } footer: {
                    Text("A lightweight Batteries widget stays on screen while BatteryHub is running.")
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)

                VStack(alignment: .leading, spacing: 14) {
                    StatusWindowPreview(
                        style: statusWindowStyle,
                        showsAirPodsCard: showAirPodsStatusCard && statusWindowStyle == .large,
                        showsMenuBarBattery: showMenuBarBattery,
                        showsBatteryOverview: showBatteryOverview
                    )
                    .frame(width: 292)

                    Divider()

                    HStack {
                        Text("Desktop Widget")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(desktopWidgetStyle.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.Palette.accent)
                    }

                    BatteryDesktopWidgetView(
                        snapshots: desktopWidgetPreviewSnapshots,
                        style: desktopWidgetStyle
                    )
                    .scaleEffect(0.74, anchor: .topLeading)
                    .frame(
                        width: desktopWidgetStyle.width * 0.74,
                        height: desktopWidgetStyle.height * 0.74,
                        alignment: .topLeading
                    )
                    .opacity(showDesktopWidget ? 1 : 0.5)
                }
                .padding(14)
                .frame(width: 322, alignment: .topLeading)
                .background(settingsCardBackground)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var quickActionsTab: some View {
        Form {
            Section {
                AutomationShortcutsBanner()

                ForEach(BatteryHubQuickAction.allCases) { action in
                    QuickActionSettingsRow(
                        action: action,
                        isEnabled: Binding(
                            get: { quickActionPreferences.isEnabled(action) },
                            set: { setQuickActionEnabled($0, for: action) }
                        )
                    )
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Enabled shortcuts are registered globally while BatteryHub is running. Supported actions also appear in macOS Shortcuts.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Core actions are available now: dashboard, refresh, settings, add device, Bluetooth pairing, connect nearby, and disconnect lowest.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.Palette.charging)
                    Label("Shortcuts can return battery summaries and trigger supported Bluetooth device controls.", systemImage: "list.bullet.rectangle")
                        .foregroundStyle(DesignTokens.Palette.charging)
                    Label("Cross-Mac transfer remains unavailable in this build.", systemImage: "minus.circle")
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
                .font(.system(size: 11, weight: .medium))
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
    }

    private func deviceDetail(for row: DeviceInspectorItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: deviceSymbolName(for: row.kind, displayName: row.displayName))
                    .font(.system(size: 34, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(detailIconColor(for: row))
                    .frame(width: 52, height: 52)
                    .overlay(alignment: .bottomTrailing) {
                        if let badge = detailIconBadge(for: row) {
                            Image(systemName: badge.symbolName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(badge.color)
                                .offset(x: 2, y: 1)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.displayName)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(detailSubtitle(for: row))
                        .font(.system(size: 12, weight: .medium))
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
                    isOn: Binding(
                        get: { LowBatteryNotifier.isChargedAlertEnabled(forDeviceID: row.id) },
                        set: { LowBatteryNotifier.setChargedAlertEnabled($0, forDeviceID: row.id) }
                    )
                )
                .disabled(row.isHidden || !chargedBatteryAlertsEnabled)
                .opacity(row.isHidden || !chargedBatteryAlertsEnabled ? 0.45 : 1)
            }
            .background(settingsCardBackground)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Low-battery threshold")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(LowBatteryNotifier.threshold(forDeviceID: row.id))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
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
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 13, weight: .semibold))
                            Text("Connect and disconnect use the paired Bluetooth address when macOS exposes one.")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.Palette.secondaryText)
                        }
                    }

                    HStack {
                        if BluetoothDeviceControlSupport.canConnect(row.item) {
                            Button {
                                _ = BluetoothDeviceController.connect(deviceID: row.id)
                                onRefresh()
                            } label: {
                                Label("Connect Device", systemImage: "dot.radiowaves.left.and.right")
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
                        .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Connected devices will appear here after the next refresh.")
                .font(.system(size: 12))
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.text)
                Text("Sample devices are shown for UI QA, not live Bluetooth.")
                    .font(.system(size: 10, weight: .medium))
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

    private var clampedActionHUDDismissDelay: Double {
        Swift.max(2, Swift.min(10, actionHUDDismissDelay))
    }

    private var actionHUDDismissDelayBinding: Binding<Double> {
        Binding(
            get: { clampedActionHUDDismissDelay },
            set: { actionHUDDismissDelay = $0.rounded() }
        )
    }

    private func deviceThresholdBinding(for deviceID: String) -> Binding<Double> {
        Binding(
            get: { Double(LowBatteryNotifier.threshold(forDeviceID: deviceID)) },
            set: { LowBatteryNotifier.setThreshold(Int($0.rounded()), forDeviceID: deviceID) }
        )
    }

    private func deviceChargedAlertBinding(for deviceID: String) -> Binding<Bool> {
        Binding(
            get: { LowBatteryNotifier.isChargedAlertEnabled(forDeviceID: deviceID) },
            set: { LowBatteryNotifier.setChargedAlertEnabled($0, forDeviceID: deviceID) }
        )
    }

    private var statusWindowStyle: StatusWindowStyle {
        StatusWindowStyle(rawValue: statusWindowStyleRawValue) ?? .native
    }

    private var desktopWidgetStyle: DesktopWidgetStyle {
        DesktopWidgetStyle(rawValue: desktopWidgetStyleRawValue) ?? .compact
    }

    private var desktopWidgetPreviewSnapshots: [DecoratedBatterySnapshot] {
        if !snapshots.isEmpty { return snapshots }
        let now = Date()
        return [
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-keyboard",
                    displayName: "Magic Keyboard",
                    kind: .keyboard,
                    percent: 82,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: now
                ),
                freshness: .fresh
            ),
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-mouse",
                    displayName: "Magic Mouse",
                    kind: .mouse,
                    percent: 24,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: now.addingTimeInterval(-600)
                ),
                freshness: .stale
            ),
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-watch",
                    displayName: "Apple Watch",
                    kind: .appleWatch,
                    percent: 18,
                    chargeState: .unplugged,
                    source: .watchConnectivity,
                    updatedAt: now
                ),
                freshness: .fresh
            ),
        ]
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

    private func setQuickActionEnabled(_ isEnabled: Bool, for action: BatteryHubQuickAction) {
        let nextPreferences = quickActionPreferences.setting(isEnabled, for: action)
        quickActionPreferences = nextPreferences
        nextPreferences.save()
    }

    private func reconcileSelectedDeviceSelection() {
        let rowIDs = Set(displayedDeviceRows.map(\.id))
        if let selectedDeviceID, rowIDs.contains(selectedDeviceID) {
            return
        }
        selectedDeviceID = displayedDeviceRows.first?.id
    }

    private func hudStateRow(_ title: String, isOn: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Spacer(minLength: 0)
        }
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

    private func deviceAlertSubtitle(for row: DeviceInspectorItem) -> String {
        if LowBatteryNotifier.hasCustomThreshold(forDeviceID: row.id) {
            return "Custom low-battery alert at \(LowBatteryNotifier.threshold(forDeviceID: row.id))%."
        }
        return "Using the global low-battery threshold."
    }

}

struct AddDeviceGuideView: View {
    let onOpenBluetoothSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add New Device")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Choose the kind of device you want BatteryHub to monitor.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            VStack(spacing: 8) {
                AddDeviceGuideRow(
                    title: "iPhone, iPad, or Apple Watch",
                    subtitle: "Companion apps sync battery reports automatically.",
                    systemImage: resolveSymbol("iphone.gen3", fallback: "iphone"),
                    actionTitle: "Automatic"
                )

                AddDeviceGuideRow(
                    title: "AirPods or Beats Device",
                    subtitle: "Pair in Bluetooth Settings, then refresh.",
                    systemImage: resolveSymbol("airpodspro", fallback: "headphones"),
                    actionTitle: "Bluetooth",
                    action: onOpenBluetoothSettings
                )

                AddDeviceGuideRow(
                    title: "Another Mac",
                    subtitle: "Cross-Mac transfer stays disabled.",
                    systemImage: resolveSymbol("macbook.and.iphone", fallback: "desktopcomputer"),
                    actionTitle: "Unavailable",
                    isEnabled: false
                )
            }

            HStack(spacing: 10) {
                Label("Devices appear automatically after BatteryHub receives a fresh battery report.", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
                .fill(DesignTokens.Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.8)
                )
        )
    }
}

private struct AddDeviceGuideRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String
    var isEnabled = true
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEnabled ? DesignTokens.Palette.text : DesignTokens.Palette.secondaryText)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Text(actionTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.tertiaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(DesignTokens.Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                            .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                    )
            )
            .opacity(isEnabled ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct SettingsPaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        if pane == .devices {
            BluetoothLogoMark(size: 20)
        } else {
            Image(systemName: pane.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case devices
    case alerts
    case actionHUD
    case quickActions
    case dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return "Devices"
        case .alerts: return "Alerts"
        case .actionHUD: return "Action HUD"
        case .quickActions: return "Quick Actions"
        case .dashboard: return "Dashboard"
        }
    }

    var systemImage: String {
        switch self {
        case .devices: return "dot.radiowaves.left.and.right"
        case .alerts: return "bell.badge"
        case .actionHUD: return "sparkles"
        case .quickActions: return "keyboard"
        case .dashboard: return resolveSymbol("macwindow", fallback: "rectangle")
        }
    }
}

private struct QuickActionSettingsRow: View {
    let action: BatteryHubQuickAction
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))

                    Text(shortcutText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospaced()
                        .foregroundStyle(action.isSupported ? DesignTokens.Palette.accent : DesignTokens.Palette.tertiaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DesignTokens.Palette.controlPill)
                        )

                    if action.isSupported {
                        Label("Shortcuts", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.Palette.charging)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DesignTokens.Palette.controlPill)
                            )
                    }
                }

                Text(action.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!action.isSupported)
        }
        .padding(.vertical, 4)
        .opacity(action.isSupported ? 1 : 0.48)
    }

    private var iconColor: Color {
        if !action.isSupported { return DesignTokens.Palette.secondaryText }
        return isEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText
    }

    private var shortcutText: String {
        action.shortcut?.displayText ?? "Unavailable"
    }
}

private struct AutomationShortcutsBanner: View {
    private let actions = [
        ("Battery Summary", "list.bullet.rectangle"),
        ("Lowest Battery", "battery.25"),
        ("Low List", "exclamationmark.triangle"),
        ("Connect", "dot.radiowaves.left.and.right"),
        ("Disconnect", "bolt.horizontal.circle")
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: resolveSymbol("sparkles.rectangle.stack", fallback: "sparkles"))
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Palette.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text("Automation Shortcuts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.text)
                    Label("Actions", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(DesignTokens.Palette.charging)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DesignTokens.Palette.controlPill)
                        )
                }

                HStack(spacing: 6) {
                    ForEach(actions, id: \.0) { action in
                        Label(action.0, systemImage: action.1)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(DesignTokens.Palette.text.opacity(0.82))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.62))
                            )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct ActionHUDEventToggle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? color : DesignTokens.Palette.secondaryText)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

private struct AirPodsAudioControlsCard: View {
    let deviceID: String
    let onOpenSoundSettings: () -> Void
    let onOpenBluetoothSettings: () -> Void

    @State private var preferences: AirPodsAudioPreferences

    init(
        deviceID: String,
        onOpenSoundSettings: @escaping () -> Void,
        onOpenBluetoothSettings: @escaping () -> Void
    ) {
        self.deviceID = deviceID
        self.onOpenSoundSettings = onOpenSoundSettings
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
        _preferences = State(initialValue: AirPodsAudioPreferences.load(for: deviceID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Audio Controls", systemImage: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("AirPods")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule(style: .continuous).fill(DesignTokens.Palette.controlPill))
            }

            HStack(spacing: 8) {
                AudioPreferenceTile(
                    title: "Listening",
                    value: preferences.listeningMode.title,
                    systemImage: preferences.listeningMode.systemImage,
                    color: DesignTokens.Palette.accent
                )
                AudioPreferenceTile(
                    title: "Mic Input",
                    value: preferences.microphone.title,
                    systemImage: "mic",
                    color: DesignTokens.Palette.charging
                )
            }

            Picker("Listening Mode", selection: listeningModeBinding) {
                ForEach(AirPodsListeningModePreference.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Microphone", selection: microphoneBinding) {
                ForEach(AirPodsMicrophonePreference.allCases) { microphone in
                    Text(microphone.shortTitle).tag(microphone)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button {
                    onOpenSoundSettings()
                } label: {
                    Label("Sound Settings", systemImage: "speaker.wave.2")
                }

                Button {
                    onOpenBluetoothSettings()
                } label: {
                    Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                }

                Spacer()
            }
            .font(.system(size: 11, weight: .semibold))

            Text("BatteryHub keeps your preferred AirPods audio choices here; macOS applies the actual listening mode and mic switch from Sound Settings.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                )
        )
        .onChange(of: deviceID) { _, nextDeviceID in
            preferences = AirPodsAudioPreferences.load(for: nextDeviceID)
        }
    }

    private var listeningModeBinding: Binding<AirPodsListeningModePreference> {
        Binding(
            get: { preferences.listeningMode },
            set: { mode in
                preferences = preferences.settingListeningMode(mode)
                preferences.save(for: deviceID)
            }
        )
    }

    private var microphoneBinding: Binding<AirPodsMicrophonePreference> {
        Binding(
            get: { preferences.microphone },
            set: { microphone in
                preferences = preferences.settingMicrophone(microphone)
                preferences.save(for: deviceID)
            }
        )
    }
}

private struct AudioPreferenceTile: View {
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
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignTokens.Palette.card.opacity(0.72))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DesignTokens.Palette.card.opacity(0.72))
        )
    }
}

private struct DeviceCurrentStatsCard: View {
    let item: DeviceListItem
    let historySamples: [BatteryHistorySample]

    private var historySummary: BatteryHistorySummary? {
        BatteryHistoryStore.summary(for: historySamples)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Current Stats", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(connectionText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(connectionColor)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule(style: .continuous).fill(DesignTokens.Palette.controlPill))
            }

            VStack(spacing: 0) {
                SettingsInfoRow(
                    title: "Battery",
                    value: batteryText,
                    systemImage: batteryIcon,
                    color: batteryColor
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Report",
                    value: reportText,
                    systemImage: reportIcon,
                    color: reportColor
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Connection",
                    value: connectionText,
                    systemImage: connectionIcon,
                    color: connectionColor
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Source",
                    value: sourceText,
                    systemImage: "antenna.radiowaves.left.and.right",
                    color: DesignTokens.Palette.accent
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Updated",
                    value: updatedText,
                    systemImage: "clock",
                    color: updatedColor
                )
            }
            .background(settingsGroupBackground)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Battery Trend")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                    Spacer()
                    Text(trendText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(trendColor)
                }

                BatteryHistorySparkline(samples: historySummary?.samples ?? [])
                    .frame(height: 34)

                Text(rangeText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .lineLimit(1)
            }
            .padding(12)
            .background(settingsGroupBackground)
        }
    }

    private var settingsGroupBackground: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
            )
    }

    private var batteryText: String {
        switch item {
        case .device(let decorated):
            return decorated.snapshot.percent.map { "\($0)%" } ?? "No report"
        case .airPods(_, _, let components):
            let percents = components.compactMap(\.percent)
            guard let lowest = percents.min() else { return "No report" }
            return "\(lowest)% low"
        }
    }

    private var batteryIcon: String {
        switch item {
        case .device(let decorated):
            if decorated.snapshot.chargeState == .charging { return "battery.100.bolt" }
            return "battery.100"
        case .airPods:
            return "battery.100"
        }
    }

    private var batteryColor: Color {
        switch item {
        case .device(let decorated):
            guard let percent = decorated.snapshot.percent else { return DesignTokens.Palette.secondaryText }
            if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
            if decorated.snapshot.chargeState == .charging || decorated.snapshot.chargeState == .full {
                return DesignTokens.Palette.charging
            }
            return DesignTokens.Palette.accent
        case .airPods(_, _, let components):
            let percents = components.compactMap(\.percent)
            if let lowest = percents.min(), lowest <= LowBatteryNotifier.threshold {
                return DesignTokens.Palette.critical
            }
            if components.contains(where: { $0.chargeState == .charging || $0.chargeState == .full }) {
                return DesignTokens.Palette.charging
            }
            return DesignTokens.Palette.accent
        }
    }

    private var sourceText: String {
        switch item {
        case .device(let decorated):
            return sourceLabel(for: decorated.snapshot.source)
        case .airPods:
            return "Bluetooth"
        }
    }

    private var reportText: String {
        switch item {
        case .device(let decorated):
            guard decorated.snapshot.percent != nil else { return "No report" }
            switch decorated.freshness {
            case .fresh: return "Reporting"
            case .stale: return "Stale"
            case .expired: return "Expired"
            }
        case .airPods(_, _, let components):
            guard components.contains(where: { $0.percent != nil }) else { return "No report" }
            if components.contains(where: { $0.freshness == .expired }) { return "Expired" }
            if components.contains(where: { $0.freshness == .stale }) { return "Stale" }
            return "Reporting"
        }
    }

    private var reportIcon: String {
        switch reportText {
        case "Reporting": return "checkmark.circle.fill"
        case "No report": return "minus.circle"
        case "Stale", "Expired": return "clock.badge.exclamationmark"
        default: return "clock"
        }
    }

    private var reportColor: Color {
        switch reportText {
        case "Reporting": return DesignTokens.Palette.charging
        case "Stale", "Expired": return DesignTokens.Palette.stale
        default: return DesignTokens.Palette.secondaryText
        }
    }

    private var connectionText: String {
        item.connectionState == .disconnected ? "Disconnected" : "Connected"
    }

    private var connectionColor: Color {
        item.connectionState == .disconnected ? DesignTokens.Palette.stale : DesignTokens.Palette.charging
    }

    private var connectionIcon: String {
        item.connectionState == .disconnected ? "xmark.circle" : "link.circle.fill"
    }

    private var updatedText: String {
        switch item {
        case .device(let decorated):
            let interval = abs(decorated.snapshot.updatedAt.timeIntervalSinceNow)
            if interval < 60 { return "Now" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: decorated.snapshot.updatedAt, relativeTo: Date())
        case .airPods:
            return "Grouped"
        }
    }

    private var updatedColor: Color {
        switch item {
        case .device(let decorated):
            return decorated.freshness == .fresh ? DesignTokens.Palette.accent : DesignTokens.Palette.stale
        case .airPods(_, _, let components):
            return components.contains { $0.freshness != .fresh } ? DesignTokens.Palette.stale : DesignTokens.Palette.accent
        }
    }

    private var trendText: String {
        guard let historySummary else { return "Collecting" }
        return historySummary.trendDescription
    }

    private var trendColor: Color {
        guard let historySummary else { return DesignTokens.Palette.secondaryText }
        if historySummary.delta > 0 { return DesignTokens.Palette.charging }
        if historySummary.delta < 0 { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.secondaryText
    }

    private var rangeText: String {
        guard let historySummary else {
            return "BatteryHub will build a trend as reports arrive."
        }
        return "Range \(historySummary.minimumPercent)% - \(historySummary.maximumPercent)% across \(historySummary.samples.count) reports."
    }

    private func sourceLabel(for source: BatterySource) -> String {
        switch source {
        case .macPowerSource: return "Local Mac"
        case .iCloud: return "iCloud"
        case .watchConnectivity: return "Watch"
        case .ioRegistry: return "IORegistry"
        case .coreBluetooth, .ioBluetooth: return "Bluetooth"
        case .systemProfiler: return "System"
        case .bluetoothUnsupported: return "Bluetooth"
        }
    }
}

private struct BatteryHistorySparkline: View {
    let samples: [BatteryHistorySample]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.Palette.card.opacity(0.58))

                if samples.count >= 2 {
                    sparkPath(in: proxy.size)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Palette.accent,
                                    trendColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                        )
                        .padding(7)
                } else {
                    HStack(spacing: 5) {
                        ForEach(0..<8, id: \.self) { _ in
                            Capsule(style: .continuous)
                                .fill(DesignTokens.Palette.separator.opacity(0.55))
                                .frame(width: 16, height: 4)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private var sortedSamples: [BatteryHistorySample] {
        samples.sorted { $0.recordedAt < $1.recordedAt }
    }

    private var trendColor: Color {
        guard let first = sortedSamples.first, let last = sortedSamples.last else {
            return DesignTokens.Palette.secondaryText
        }
        if last.percent > first.percent { return DesignTokens.Palette.charging }
        if last.percent < first.percent { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.accent
    }

    private func sparkPath(in size: CGSize) -> Path {
        let points = sortedSamples
        guard points.count >= 2 else { return Path() }
        let width = max(size.width - 14, 1)
        let height = max(size.height - 14, 1)
        let minPercent = Double(points.map(\.percent).min() ?? 0)
        let maxPercent = Double(points.map(\.percent).max() ?? 100)
        let denominator = max(maxPercent - minPercent, 1)

        var path = Path()
        for (index, sample) in points.enumerated() {
            let x = CGFloat(index) / CGFloat(points.count - 1) * width
            let normalized = (Double(sample.percent) - minPercent) / denominator
            let y = height - CGFloat(normalized) * height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: resolveSymbol(systemImage, fallback: "circle"))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.text)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
    }
}

private struct SettingsDeviceSidebarRow: View {
    let item: DeviceInspectorItem
    let isSelected: Bool
    let symbolName: String
    let iconColor: Color
    let iconBadge: DeviceIconBadge?
    let alertSummary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)
                    .overlay(alignment: .bottomTrailing) {
                        if let iconBadge {
                            Image(systemName: iconBadge.symbolName)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(iconBadge.color)
                                .offset(x: 5, y: 4)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.isHidden ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.text)
                        .lineLimit(1)
                    Text(rowSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: NativeMacStyle.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? NativeMacStyle.rowSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var rowSubtitle: String {
        if item.isUserHidden { return "Hidden · \(alertSummary)" }
        if item.isUnavailable { return "Hidden until connected · \(alertSummary)" }
        if item.isPinned { return "Pinned · \(alertSummary)" }
        return "Visible · \(alertSummary)"
    }
}

private struct SettingsDetailToggle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
    }
}

private struct SettingsAlertPreview: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(0.62))
        )
    }
}
