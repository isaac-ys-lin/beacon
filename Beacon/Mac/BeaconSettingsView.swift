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

struct BeaconSettingsView: View {
    @ObservedObject var connections: BluetoothConnectionController
    let snapshots: [DecoratedBatterySnapshot]
    let isRefreshing: Bool
    let isPreviewingData: Bool
    let refreshDiagnostics: BatteryRefreshDiagnostics
    let trustedIPhones: [TrustedIPhone]
    let trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport?
    let notificationAuthorizationState: NotificationCenterAuthorizationState
    let latestNotificationDeliveryResult: NotificationCenterDeliveryResult?
    let onRefresh: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onOpenSoundSettings: () -> Void
    let onRefreshNotificationAuthorization: () -> Void
    let onRequestNotificationPermission: () -> Void
    let onOpenNotificationSettings: () -> Void
    let onSendTestNotification: () -> Void
    let onTrustConnectedIPhone: () async -> Void
    let iPhonePreviewTools: IPhoneToolAvailability?
    let onForgetTrustedIPhone: (String) -> Void
    let onQuit: () -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @AppStorage(LowBatteryNotifier.notificationsEnabledDefaultsKey) private var lowBatteryAlertsEnabled = true
    @AppStorage(LowBatteryNotifier.chargedNotificationsEnabledDefaultsKey) private var chargedBatteryAlertsEnabled = true
    @AppStorage(BatteryHUDPreferences.showActionHUDKey) private var showActionHUD = true
    @AppStorage(BatteryHUDPreferences.lowBatteryHUDEnabledKey) private var showLowBatteryHUD = true
    @AppStorage(BatteryHUDPreferences.chargedHUDEnabledKey) private var showChargedHUD = true
    @AppStorage(BatteryHUDPreferences.autoDismissEnabledKey) private var autoDismissHUD = true
    @AppStorage(BatteryHUDPreferences.dismissDelaySecondsKey) private var hudDismissDelaySeconds = BatteryHUDPreferences.defaultDismissDelaySeconds
    @AppStorage(BatteryHUDPreferences.showDismissButtonKey) private var showHUDDismissButton = false
    @AppStorage(StatusWindowPreferences.showMenuBarBatteryKey) private var showMenuBarBattery = false
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @AppStorage("Beacon.settings.showUnavailableDevices") private var showUnavailableDevices = true

    @State private var displayPreferences = DeviceDisplayPreferences.load()
    @State private var quickActionPreferences = BeaconQuickActionPreferences.load()
    @State private var inspectedDeviceID: String?
    @State private var selectedPane: SettingsPane = .devices
    @State private var isShowingAddDeviceGuide = false
    @State private var isShowingIPhoneSetup = false
    @State private var alertPreferencesRevision = 0

    init(
        snapshots: [DecoratedBatterySnapshot],
        connections: BluetoothConnectionController = BluetoothConnectionController(),
        isRefreshing: Bool = false,
        isPreviewingData: Bool = false,
        refreshDiagnostics: BatteryRefreshDiagnostics = BatteryRefreshDiagnostics(),
        trustedIPhones: [TrustedIPhone] = [],
        trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport? = nil,
        notificationAuthorizationState: NotificationCenterAuthorizationState = .unknown,
        latestNotificationDeliveryResult: NotificationCenterDeliveryResult? = nil,
        onRefresh: @escaping () -> Void,
        onOpenBluetoothSettings: @escaping () -> Void = {},
        onOpenSoundSettings: @escaping () -> Void = {},
        onRefreshNotificationAuthorization: @escaping () -> Void = {},
        onRequestNotificationPermission: @escaping () -> Void = {},
        onOpenNotificationSettings: @escaping () -> Void = {},
        onSendTestNotification: @escaping () -> Void = {},
        onTrustConnectedIPhone: @escaping () async -> Void = {},
        iPhonePreviewTools: IPhoneToolAvailability? = nil,
        onForgetTrustedIPhone: @escaping (String) -> Void = { _ in },
        onQuit: @escaping () -> Void = {},
        initialPane: SettingsPane = .devices,
        initialSelectedDeviceID: String? = nil,
        initiallyShowingAddDeviceGuide: Bool = false
    ) {
        self.snapshots = snapshots
        self.connections = connections
        self.isRefreshing = isRefreshing
        self.isPreviewingData = isPreviewingData
        self.refreshDiagnostics = refreshDiagnostics
        self.trustedIPhones = trustedIPhones
        self.trustedIPhoneEnrollmentResult = trustedIPhoneEnrollmentResult
        self.notificationAuthorizationState = notificationAuthorizationState
        self.latestNotificationDeliveryResult = latestNotificationDeliveryResult
        self.onRefresh = onRefresh
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
        self.onOpenSoundSettings = onOpenSoundSettings
        self.onRefreshNotificationAuthorization = onRefreshNotificationAuthorization
        self.onRequestNotificationPermission = onRequestNotificationPermission
        self.onOpenNotificationSettings = onOpenNotificationSettings
        self.onSendTestNotification = onSendTestNotification
        self.onTrustConnectedIPhone = onTrustConnectedIPhone
        self.iPhonePreviewTools = iPhonePreviewTools
        self.onForgetTrustedIPhone = onForgetTrustedIPhone
        self.onQuit = onQuit
        // Per-device alert settings now live in the device's detail sheet.
        let routesToDevice = initialSelectedDeviceID != nil && initialPane == .alerts
        _selectedPane = State(initialValue: routesToDevice ? .devices : initialPane)
        _inspectedDeviceID = State(initialValue: initialSelectedDeviceID)
        _isShowingAddDeviceGuide = State(initialValue: initiallyShowingAddDeviceGuide)
    }

    var body: some View {
        let _ = alertPreferencesRevision
        let _ = isShowingIPhoneSetup
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                settingsSidebar

                Divider()

                VStack(spacing: 0) {
                    settingsHeader

                    Divider()

                    settingsDetail
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .frame(
            minWidth: 900,
            idealWidth: 900,
            minHeight: 620,
            idealHeight: 620,
            alignment: .topLeading
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
        .onAppear {
            onRefreshNotificationAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            alertPreferencesRevision &+= 1
        }
        .sheet(isPresented: $isShowingAddDeviceGuide) {
            if isShowingIPhoneSetup {
                IPhoneSetupView(
                    snapshots: snapshots, trustedIPhones: trustedIPhones,
                    enrollmentResult: trustedIPhoneEnrollmentResult, diagnostics: refreshDiagnostics,
                    previewTools: iPhonePreviewTools, isPreviewingData: isPreviewingData,
                    onCheck: onTrustConnectedIPhone, onForget: onForgetTrustedIPhone,
                    onBack: { isShowingIPhoneSetup = false },
                    onDismiss: { isShowingAddDeviceGuide = false }
                )
            } else {
                DeviceSetupGuide(
                    enrollmentResult: nil,
                    onOpenBluetoothSettings: onOpenBluetoothSettings,
                    onTrustConnectedIPhone: { isShowingIPhoneSetup = true },
                    onRefresh: onRefresh,
                    onDismiss: { isShowingAddDeviceGuide = false }
                )
            }
        }
    }

    private var appearanceTheme: BeaconAppearanceTheme {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding<SettingsPane?>(
                get: { selectedPane },
                set: { if let pane = $0 { selectedPane = pane } }
            )) {
                Section {
                    ForEach(SettingsPane.allCases) { pane in
                        Label {
                            Text(pane.title)
                        } icon: {
                            SettingsPaneIcon(pane: pane)
                        }
                        .tag(pane)
                        .accessibilityIdentifier("settings.pane.\(pane.id)")
                    }
                } header: {
                    Text("Beacon")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            Button(action: onQuit) {
                Label("Quit Beacon", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .help("Quit Beacon")
        }
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Text(selectedPane.title)
                .font(DesignTokens.Typography.windowTitle)
                .lineLimit(1)

            if isPreviewingData {
                Text("Preview Data")
                    .font(DesignTokens.Typography.caption2Emphasis)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(.quaternary))
                    .help("Sample devices are shown for UI QA, not live Bluetooth.")
                    .accessibilityIdentifier("settings.preview-badge")
            }

            Spacer()

            if selectedPane == .devices {
                Button {
                    isShowingIPhoneSetup = false
                    isShowingAddDeviceGuide = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Set Up Device")
                .accessibilityLabel("Set Up Device")
                .accessibilityIdentifier("settings.add-device")
            }

            if selectedPane == .devices || selectedPane == .dashboard {
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
                .accessibilityIdentifier("settings.refresh")
                .accessibilityLabel(isRefreshing ? "Refreshing" : "Refresh")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var settingsDetail: some View {
        Group {
            switch selectedPane {
            case .general: generalTab
            case .devices: devicesTab
            case .alerts: alertsTab
            case .actionHUD: actionHUDTab
            case .quickActions: quickActionsTab.padding(18)
            case .audio: AudioInputSettingsPane().padding(18)
            case .dashboard: dashboardTab.padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Devices

    private var devicesTab: some View {
        Form {
            let recovery = DeviceSetupRecoveryState.resolve(
                visibleCount: displayedDeviceRows.count, isRefreshing: isRefreshing, diagnostics: refreshDiagnostics
            )
            if recovery != .ready {
                Section {
                    DeviceSetupRecoveryCard(
                        state: recovery,
                        isRefreshing: isRefreshing,
                        onSetUp: { isShowingIPhoneSetup = false; isShowingAddDeviceGuide = true },
                        onRefresh: onRefresh,
                        surfaced: false
                    )
                }
            }
            if hasRefreshProblems {
                Section {
                    RefreshRecoveryView(diagnostics: refreshDiagnostics, snapshots: snapshots,
                        isRefreshing: isRefreshing,
                        onInspect: { showUnavailableDevices = true; inspectedDeviceID = $0 }, onRefresh: onRefresh)
                }
            }

            if !shownDeviceRows.isEmpty {
                Section {
                    ForEach(shownDeviceRows) { row in
                        deviceListRow(row)
                    }
                } header: {
                    Text("My Devices")
                }
            }

            if hiddenDeviceCount > 0 {
                Section {
                    if showUnavailableDevices {
                        ForEach(hiddenDeviceRows) { row in
                            deviceListRow(row)
                        }
                    }
                } header: {
                    HStack {
                        Text("Hidden Devices")
                        Spacer()
                        Button(showUnavailableDevices ? BeaconL10n.string("Hide") : BeaconL10n.format("Show %d", hiddenDeviceCount)) {
                            showUnavailableDevices.toggle()
                        }
                        .buttonStyle(.link)
                        .font(DesignTokens.Typography.caption)
                        .accessibilityIdentifier("settings.hidden-devices.toggle")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if deviceRows.isEmpty && recoveryIsEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "battery.0",
                    description: Text("Connected devices will appear here after the next refresh.")
                )
            }
        }
        .sheet(isPresented: isInspectingDevice) {
            if let row = inspectedDevice {
                DeviceDetailSheet(
                    connections: connections,
                    row: row,
                    refreshDiagnostics: refreshDiagnostics,
                    defaultThreshold: clampedLowBatteryThreshold,
                    lowBatteryAlertsEnabled: lowBatteryAlertsEnabled,
                    chargedBatteryAlertsEnabled: chargedBatteryAlertsEnabled,
                    onSetPinned: { setDisplayPreferences(displayPreferences.settingPinned($0, for: row.item)) },
                    onHide: { setDisplayPreferences(displayPreferences.hiding(row.item)) },
                    onRestore: { setDisplayPreferences(displayPreferences.restoring(row.item)) },
                    onAlertPreferenceEnabled: handleNotificationAlertPreferenceActivation,
                    onOpenSoundSettings: onOpenSoundSettings,
                    onOpenBluetoothSettings: onOpenBluetoothSettings,
                    onDone: { inspectedDeviceID = nil }
                )
            }
        }
    }

    private func deviceListRow(_ row: DeviceInspectorItem) -> some View {
        let presentation = DeviceBatteryPresentation(item: row.item)
        let subtitle = deviceRowSubtitle(row, presentation: presentation)
        return Button {
            inspectedDeviceID = row.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: deviceSymbolName(for: row.kind, displayName: row.displayName))
                    .font(.system(size: 15))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.displayName)
                        .foregroundStyle(row.isHidden ? .secondary : .primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if row.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(presentation.valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.displayName)
        .accessibilityValue([presentation.valueText, subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Shows device details")
        .accessibilityIdentifier("settings.device.\(row.id)")
    }

    private func deviceRowSubtitle(_ row: DeviceInspectorItem, presentation: DeviceBatteryPresentation) -> String? {
        if row.isUserHidden { return BeaconL10n.string("Hidden") }
        if row.isUnavailable { return BeaconL10n.string("Hidden until connected") }
        return presentation.state == .current ? nil : presentation.state.title
    }

    private var isInspectingDevice: Binding<Bool> {
        Binding(
            get: { inspectedDevice != nil },
            set: { if !$0 { inspectedDeviceID = nil } }
        )
    }

    private var inspectedDevice: DeviceInspectorItem? {
        guard let inspectedDeviceID else { return nil }
        return deviceRows.first { $0.id == inspectedDeviceID }
    }

    private var shownDeviceRows: [DeviceInspectorItem] {
        deviceRows.filter { !$0.isHidden }
    }

    private var hiddenDeviceRows: [DeviceInspectorItem] {
        deviceRows.filter(\.isHidden)
    }

    private var hasRefreshProblems: Bool {
        refreshDiagnostics.attempts.contains {
            $0.status != .reported && ($0.status != .noReport || $0.affectedDeviceIDs != nil)
        }
    }

    private var recoveryIsEmpty: Bool {
        DeviceSetupRecoveryState.resolve(
            visibleCount: 0, isRefreshing: isRefreshing, diagnostics: refreshDiagnostics
        ) == .empty
    }

    private var generalTab: some View {
        GeneralSettingsPane(onPreferencesReset: applyResetPreferenceState)
    }

    // MARK: - Alerts

    private var alertsTab: some View {
        Form {
            Section {
                LabeledContent("Notifications") {
                    HStack(spacing: 6) {
                        // Status color rides on a dot; the words stay at full text contrast.
                        Circle()
                            .fill(notificationAuthorizationColor)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(notificationAuthorizationState.title)
                        if notificationAuthorizationState == .unknown {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .accessibilityIdentifier("alerts.notification-center")

                HStack(spacing: 8) {
                    if notificationAuthorizationState.canRequestPermission {
                        Button("Allow Notifications", action: onRequestNotificationPermission)
                            .accessibilityIdentifier("alerts.notification.allow")
                    }
                    if notificationAuthorizationState.canOpenSystemSettings {
                        Button("Open Settings", action: onOpenNotificationSettings)
                            .accessibilityIdentifier("alerts.notification.settings")
                    }
                    if notificationAuthorizationState.canSendTestNotification {
                        Button("Send Test", action: onSendTestNotification)
                            .accessibilityIdentifier("alerts.notification.test")
                    }
                    Spacer(minLength: 0)
                    Button(action: onRefreshNotificationAuthorization) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh notification status")
                    .accessibilityLabel("Refresh notification status")
                    .accessibilityIdentifier("alerts.notification.refresh")
                }

                if let latestNotificationDeliveryResult {
                    Label {
                        Text(latestNotificationDeliveryResult.title + " · " + latestNotificationDeliveryResult.subtitle)
                    } icon: {
                        Image(systemName: latestNotificationDeliveryResult.state == .queued ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(latestNotificationDeliveryResult.state == .queued ? DesignTokens.Palette.charging : DesignTokens.Palette.critical)
                    }
                    .accessibilityIdentifier("alerts.notification.result")
                }
            } footer: {
                Text(notificationAuthorizationState.subtitle)
            }

            Section {
                Toggle("Low battery alerts", isOn: $lowBatteryAlertsEnabled)
                    .accessibilityLabel(Text("Low battery alerts"))
                    .accessibilityIdentifier("alerts.global.low")
                    .onChange(of: lowBatteryAlertsEnabled) { _, isEnabled in
                        handleNotificationAlertPreferenceActivation(isEnabled)
                    }
                LabeledContent("Default threshold") {
                    HStack(spacing: 10) {
                        Slider(value: lowBatteryThresholdBinding, in: 5...50, step: 5)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            .accessibilityLabel("Default threshold")
                            .accessibilityValue("\(clampedLowBatteryThreshold)%")
                            .accessibilityIdentifier("alerts.global.threshold")
                        Text("\(clampedLowBatteryThreshold)%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!lowBatteryAlertsEnabled)
            } header: {
                Text("Low Battery")
            } footer: {
                Text("Devices without their own threshold use this value. Set a device's threshold in Devices.")
            }

            Section {
                Toggle("Charged alerts", isOn: $chargedBatteryAlertsEnabled)
                    .accessibilityLabel(Text("Charged alerts"))
                    .accessibilityIdentifier("alerts.global.charged")
                    .onChange(of: chargedBatteryAlertsEnabled) { _, isEnabled in
                        handleNotificationAlertPreferenceActivation(isEnabled)
                    }
            } header: {
                Text("Full Charge")
            } footer: {
                Text("Also turn on Notify when charged for each device in Devices.")
            }
        }
        .formStyle(.grouped)
    }

    private var notificationAuthorizationColor: Color {
        switch notificationAuthorizationState {
        case .authorized:
            return DesignTokens.Palette.charging
        case .provisional, .notDetermined, .unknown:
            return DesignTokens.Palette.warning
        case .denied:
            return DesignTokens.Palette.critical
        }
    }

    private var actionHUDTab: some View {
        ActionHUDSettingsPane(
            showActionHUD: $showActionHUD,
            showLowBatteryHUD: $showLowBatteryHUD,
            showChargedHUD: $showChargedHUD,
            autoDismissEnabled: $autoDismissHUD,
            dismissDelaySeconds: $hudDismissDelaySeconds,
            showDismissButton: $showHUDDismissButton,
            lowBatteryThreshold: clampedLowBatteryThreshold
        )
    }

    private var dashboardTab: some View {
        DashboardSettingsPane(
            snapshots: snapshots,
            isPreviewingData: isPreviewingData,
            showMenuBarBattery: $showMenuBarBattery
        )
    }

    private var quickActionsTab: some View {
        QuickActionsSettingsPane(preferences: $quickActionPreferences)
    }

    private func applyResetPreferenceState() {
        lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
        lowBatteryAlertsEnabled = true
        chargedBatteryAlertsEnabled = true
        showActionHUD = true
        showLowBatteryHUD = true
        showChargedHUD = true
        autoDismissHUD = true
        hudDismissDelaySeconds = BatteryHUDPreferences.defaultDismissDelaySeconds
        showHUDDismissButton = false
        showMenuBarBattery = false
        appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
        showUnavailableDevices = true
        displayPreferences = DeviceDisplayPreferences()
        quickActionPreferences = BeaconQuickActionPreferences()
        StatusWindowPreferences.notifyChanged()
    }

    private var deviceRows: [DeviceInspectorItem] {
        let presented = connections.snapshots(including: snapshots)
        return deviceInspectorItems(presented, preferences: displayPreferences,
            pairedDeviceIDs: connections.pairedPresentationIDs(in: presented))
    }

    private var displayedDeviceRows: [DeviceInspectorItem] {
        displayedDeviceInspectorItems(
            deviceRows,
            showHiddenUnavailable: showUnavailableDevices
        )
    }

    private var hiddenDeviceCount: Int {
        deviceRows.filter(\.isHidden).count
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

    private func setDisplayPreferences(_ preferences: DeviceDisplayPreferences) {
        displayPreferences = preferences
        preferences.save()
    }
}

/// A device's details and its own alert overrides, presented like the ⓘ sheet
/// in System Settings > Bluetooth.
struct DeviceDetailSheet: View {
    @ObservedObject var connections: BluetoothConnectionController
    let row: DeviceInspectorItem
    let refreshDiagnostics: BatteryRefreshDiagnostics
    let defaultThreshold: Int
    let lowBatteryAlertsEnabled: Bool
    let chargedBatteryAlertsEnabled: Bool
    let onSetPinned: (Bool) -> Void
    let onHide: () -> Void
    let onRestore: () -> Void
    let onAlertPreferenceEnabled: (Bool) -> Void
    let onOpenSoundSettings: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onDone: () -> Void

    @State private var preferencesRevision = 0

    var body: some View {
        let _ = preferencesRevision
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: deviceSymbolName(for: row.kind, displayName: row.displayName))
                            .font(.system(size: 26))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(DeviceBatteryPresentation(item: row.item).valueText)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if BluetoothDeviceControlSupport.normalizedAddress(from: row.id) != nil {
                        BluetoothConnectionControls(item: row.item, controller: connections)
                    }
                }

                DeviceStatsSections(
                    item: row.item,
                    historySamples: BatteryHistoryStore.samples(for: row.id)
                )

                Section {
                    LabeledContent("Low-battery alert") {
                        HStack(spacing: 10) {
                            Slider(value: thresholdBinding, in: 5...50, step: 5)
                                .labelsHidden()
                                .frame(maxWidth: 180)
                                .accessibilityLabel("Low-battery threshold")
                                .accessibilityValue("\(threshold)%")
                                .accessibilityIdentifier("settings.device.threshold")
                            Text("\(threshold)%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .disabled(!lowBatteryAlertsEnabled)
                    Toggle("Notify when charged", isOn: chargedBinding)
                        .accessibilityLabel(Text("Notify when charged"))
                        .disabled(!chargedBatteryAlertsEnabled)
                        .accessibilityIdentifier("settings.device.charged")
                    if hasCustomThreshold {
                        Button("Use Default Threshold") {
                            LowBatteryNotifier.resetThreshold(forDeviceID: row.id)
                        }
                        .accessibilityIdentifier("settings.device.use-default")
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text(alertFooter)
                }
                .disabled(row.isHidden)

                Section {
                    Toggle("Pin to Top", isOn: Binding(get: { row.isPinned }, set: onSetPinned))
                        .accessibilityLabel(Text("Pin to Top"))
                        .accessibilityIdentifier("settings.device.pin")
                } footer: {
                    Text("Pinned devices appear first in the menu bar while connected.")
                }
                .disabled(row.isHidden)

                if row.kind == .airPods {
                    AirPodsAudioControlsSection(
                        onOpenSoundSettings: onOpenSoundSettings,
                        onOpenBluetoothSettings: onOpenBluetoothSettings
                    )
                }

                Section {
                    DisclosureGroup("Refresh Diagnostics") {
                        RefreshHealthDisclosureView(diagnostics: refreshDiagnostics)
                    }
                    if row.isUserHidden {
                        Button("Restore Device", action: onRestore)
                    } else if row.isUnavailable {
                        LabeledContent("Visibility", value: BeaconL10n.string("Hidden until connected"))
                    } else {
                        Button("Hide Device", role: .destructive, action: onHide)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("settings.device.done")
            }
            .padding(12)
        }
        .frame(width: 480, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            preferencesRevision &+= 1
        }
    }

    private var threshold: Int {
        LowBatteryNotifier.threshold(forDeviceID: row.id)
    }

    private var hasCustomThreshold: Bool {
        LowBatteryNotifier.hasCustomThreshold(forDeviceID: row.id)
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(threshold) },
            set: { LowBatteryNotifier.setThreshold(Int($0.rounded()), forDeviceID: row.id) }
        )
    }

    private var chargedBinding: Binding<Bool> {
        Binding(
            get: { LowBatteryNotifier.isChargedAlertEnabled(forDeviceID: row.id, displayName: row.displayName) },
            set: {
                LowBatteryNotifier.setChargedAlertEnabled($0, forDeviceID: row.id, displayName: row.displayName)
                onAlertPreferenceEnabled($0)
            }
        )
    }

    private var alertFooter: String {
        if row.isHidden {
            return BeaconL10n.string("Hidden until it reconnects and reports battery.")
        }
        if !lowBatteryAlertsEnabled {
            return BeaconL10n.string("Low-battery alerts are off for all devices.")
        }
        if hasCustomThreshold {
            return BeaconL10n.format("Custom low-battery alert at %d%%.", threshold)
        }
        return BeaconL10n.format("Using the default low-battery threshold of %d%%.", defaultThreshold)
    }
}

func batteryAlertSummary(threshold: Int, lowEnabled: Bool, chargedEnabled: Bool) -> String {
    switch (lowEnabled, chargedEnabled) {
    case (true, true): return BeaconL10n.format("Low at %d%% · Full charge", threshold)
    case (true, false): return BeaconL10n.format("Low at %d%%", threshold)
    case (false, true): return BeaconL10n.string("Full charge")
    case (false, false): return BeaconL10n.string("Alerts off")
    }
}
