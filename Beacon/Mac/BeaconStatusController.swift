import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class BeaconStatusController: NSObject {
    private let model: BeaconModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenuPanelController = StatusMenuPanelController()
    private let settingsWindowController: BeaconSettingsWindowController
    private let hudController = BeaconHUDController()
    private let desktopWidgetController = BeaconDesktopWidgetController()
    private let shortcutController = BeaconShortcutController()
    private let bluetoothPowerStateObserver: BluetoothPowerStateObserver?
    private let menuLogger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "menu-bar")
    private let quickActionLogger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "quick-actions")
    private var operationObserver: AnyCancellable?
    private var lastHUDOperations: [String: BluetoothConnectionOperation] = [:]
    private var connectionObserver: AnyCancellable?
    private var storeObserver: AnyCancellable?
    private var refreshStateObserver: AnyCancellable?
    private var refreshDiagnosticsObserver: AnyCancellable?
    private var alertEventsObserver: AnyCancellable?
    private var notificationAuthorizationObserver: AnyCancellable?
    private var notificationDeliveryObserver: AnyCancellable?
    private var trustedIPhoneRegistryObserver: AnyCancellable?
    private var trustedIPhoneEnrollmentObserver: AnyCancellable?
    private var bluetoothPowerStateCancellable: AnyCancellable?
    private var preferencesObservers: [NSObjectProtocol] = []
    private var outsideClickMonitor: Any?

    init(model: BeaconModel) {
        // Preview fixtures must not create a real Bluetooth manager or prompt for hardware access.
        self.model = model
        let isHostedUnitTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        bluetoothPowerStateObserver = model.isUsingPreviewData || isHostedUnitTest ? nil : BluetoothPowerStateObserver()
        settingsWindowController = BeaconSettingsWindowController(model: model)
        super.init()

        statusMenuPanelController.onRequestClose = { [weak self] in
            self?.closeStatusMenu()
        }

        updateStatusMenuContent()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.imageHugsTitle = true
            button.toolTip = "Beacon"
        }

        hudController.onReviewOperation = { [weak self] deviceID in
            self?.showSettingsWindow(initialPane: .devices, selectedDeviceID: deviceID)
        }
        operationObserver = model.connections.$operations.sink { [weak self] operations in
            guard let self else { return }
            for operation in operations.values.sorted(by: { $0.address < $1.address }) {
                guard self.lastHUDOperations[operation.address] != operation else { continue }
                self.lastHUDOperations[operation.address] = operation
                self.hudController.show(operation: operation)
            }
        }
        connectionObserver = model.connections.objectWillChange.sink { [weak self] in
            // @Published sends before storing its new value. Read after that emission completes.
            Task { @MainActor in self?.updateStatusMenuContent() }
        }
        storeObserver = model.$store.sink { [weak self] store in
            self?.updateStatusButton(store: store)
            self?.updateStatusMenuContent(store: store)
            self?.settingsWindowController.updateContent(store: store)
            self?.updateDesktopWidget(store: store)
        }
        refreshStateObserver = model.$isRefreshing.sink { [weak self] isRefreshing in
            self?.updateStatusButton(isRefreshing: isRefreshing)
            self?.updateStatusMenuContent(isRefreshing: isRefreshing)
            self?.settingsWindowController.updateContent(isRefreshing: isRefreshing)
            self?.updateDesktopWidget()
        }
        refreshDiagnosticsObserver = model.$latestRefreshDiagnostics.sink { [weak self] diagnostics in
            self?.updateStatusButton(refreshDiagnostics: diagnostics)
            self?.updateDesktopWidget(refreshDiagnostics: diagnostics)
            self?.settingsWindowController.updateContent(refreshDiagnostics: diagnostics)
            self?.updateStatusMenuContent(refreshDiagnostics: diagnostics)
        }
        notificationAuthorizationObserver = model.$notificationAuthorizationState.sink { [weak self] authorizationState in
            self?.updateStatusMenuContent()
            self?.settingsWindowController.updateContent(notificationAuthorizationState: authorizationState)
        }
        notificationDeliveryObserver = model.$latestNotificationDeliveryResult.sink { [weak self] _ in
            self?.settingsWindowController.updateContent()
        }
        trustedIPhoneRegistryObserver = model.$trustedIPhoneRegistry.sink { [weak self] registry in
            self?.updateStatusMenuContent()
            self?.settingsWindowController.updateContent(trustedIPhones: registry.devices)
            self?.updateDesktopWidget()
        }
        trustedIPhoneEnrollmentObserver = model.$trustedIPhoneEnrollmentResult.sink { [weak self] report in
            self?.updateStatusMenuContent()
            self?.settingsWindowController.updateContent(enrollmentResult: report)
            self?.updateDesktopWidget()
        }
        alertEventsObserver = model.$latestAlertEvents
            .filter { !$0.isEmpty }
            .sink { [weak self] events in
                for event in events { self?.hudController.show(event: event) }
            }
        bluetoothPowerStateCancellable = bluetoothPowerStateObserver?.$state
            .sink { [weak self] _ in
                self?.updateStatusMenuContent()
                self?.updateDesktopWidget()
            }
        preferencesObservers = [
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePreferencesChanged()
                }
            },
            NotificationCenter.default.addObserver(
                forName: StatusWindowPreferences.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePreferencesChanged()
                }
            }
        ]
        BeaconIntentBridge.shared.register(
            handler: { [weak self] action in
                self?.performQuickAction(action) ?? false
            },
            snapshotProvider: { [weak model] in
                guard let model else { return [] }
                return batterySnapshotsWithKnownFailures(model.store.decoratedSnapshots, diagnostics: model.latestRefreshDiagnostics)
            }
        )
        registerQuickActions()
        updateStatusButton()
        updateDesktopWidget()
    }

    func showDeviceSetup() {
        closeStatusMenu()
        settingsWindowController.showWindow(initialPane: .devices, initiallyShowingAddDeviceGuide: true)
    }

    #if DEBUG
    func showSettingsForUITesting() {
        showSettingsWindow(initialPane: .devices)
        if ProcessInfo.processInfo.environment["BEACON_SETTINGS_MINIMUM_SIZE"] == "1" {
            settingsWindowController.debugWindow?.setContentSize(NSSize(width: 900, height: 620))
        }
    }

    func showDesktopWidgetForUITesting() {
        // Use the same presentation and routing as the user's actual desktop panel.
        // The test sets visibility/style through the argument domain, not saved preferences.
        updateDesktopWidget()
        desktopWidgetController.exposeWindowToAccessibilityForUITesting()
    }

    func showHUDForUITesting() {
        if ProcessInfo.processInfo.environment["BEACON_HUD_SCENARIO"] == "connection-events" {
            hudController.prepareOperationUITesting()
            model.connections.perform(.connect, deviceID: "bluetooth-aa-bb-cc-dd-ee-02", displayName: "Test Headphones")
            hudController.exposeWindowToAccessibilityForUITesting()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.hudController.showForUITesting(event: BatteryAlertEvent(kind: .lowBattery,
                    deviceID: "ui-test-device", displayName: "Queued Keyboard", percent: 12))
            }
            return
        }
        hudController.showForUITesting(
            event: BatteryAlertEvent(
                kind: .lowBattery,
                deviceID: "ui-test-device",
                displayName: "UI Test Keyboard",
                percent: 12
            )
        )
        hudController.exposeWindowToAccessibilityForUITesting()
    }

    func showStatusMenuForUITesting() {
        guard let button = statusItem.button else { return }
        showStatusMenu(relativeTo: button)
        statusMenuPanelController.exposePanelToAccessibilityForUITesting()
    }
    #endif

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        // Don't overlap the popover with an open Settings window — surface the
        // window instead.
        if settingsWindowController.isWindowOpen {
            settingsWindowController.bringToFront()
            return
        }
        if statusMenuPanelController.isShown {
            closeStatusMenu()
        } else {
            showStatusMenu(relativeTo: sender)
        }
    }

    private func updateStatusMenuContent(
        screen: NSScreen? = NSScreen.main,
        store: BatterySnapshotStore? = nil,
        isRefreshing: Bool? = nil,
        refreshDiagnostics: BatteryRefreshDiagnostics? = nil
    ) {
        let configuration = StatusWindowConfiguration.load()
        let renderedStore = store ?? model.store
        let nextSize = preferredPopoverContentSize(
            screen: screen,
            configuration: configuration,
            store: renderedStore,
            isRefreshing: isRefreshing ?? model.isRefreshing,
            refreshDiagnostics: refreshDiagnostics ?? model.latestRefreshDiagnostics
        )

        statusMenuPanelController.install(
            rootView: StatusMenuView(
                snapshots: batterySnapshotsWithKnownFailures(renderedStore.decoratedSnapshots,
                    diagnostics: refreshDiagnostics ?? model.latestRefreshDiagnostics),
                connections: model.connections,
                isRefreshing: isRefreshing ?? model.isRefreshing,
                isPreviewingData: model.isUsingPreviewData,
                configuration: configuration,
                refreshDiagnostics: refreshDiagnostics ?? model.latestRefreshDiagnostics,
                onSetUpDevice: { [weak self] in self?.showDeviceSetup() },
                onRefresh: { [weak model] in
                    Task { await model?.refresh() }
                },
                onOpenSettings: { [weak self] pane, selectedDeviceID in
                    self?.showSettingsWindow(initialPane: pane, selectedDeviceID: selectedDeviceID)
                }
            ),
            contentSize: nextSize
        )
    }

    private func showSettingsWindow(
        initialPane: SettingsPane = .devices,
        selectedDeviceID: String? = nil
    ) {
        closeStatusMenu()
        settingsWindowController.showWindow(
            initialPane: initialPane,
            initialSelectedDeviceID: selectedDeviceID
        )
    }

    private func showStatusMenu(relativeTo sender: NSStatusBarButton) {
        updateStatusMenuContent(screen: sender.window?.screen)
        statusMenuPanelController.show(relativeTo: sender)
        menuLogger.info("Status menu opened")
        startOutsideClickMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeStatusMenu() {
        let wasShown = statusMenuPanelController.isShown
        statusMenuPanelController.close()
        stopOutsideClickMonitor()
        if wasShown {
            menuLogger.info("Status menu closed")
        }
    }

    private func preferredPopoverContentSize(
        screen: NSScreen? = NSScreen.main,
        configuration: StatusWindowConfiguration = .load(),
        store: BatterySnapshotStore? = nil,
        isRefreshing: Bool = false,
        refreshDiagnostics: BatteryRefreshDiagnostics = BatteryRefreshDiagnostics()
    ) -> NSSize {
        let defaults = UserDefaults.standard
        let preferences = DeviceDisplayPreferences.load(from: defaults)
        let renderedStore = store ?? model.store
        let presented = model.connections.snapshots(including: renderedStore.decoratedSnapshots)
        let sections = statusMenuDeviceSections(
            presented, preferences: preferences,
            pairedDeviceIDs: model.connections.pairedPresentationIDs(in: presented)
        )
        let dashboardItemCount = sections.reduce(0) { partial, section in
            partial + section.items.count
        }
        let screenHeight = screen?.visibleFrame.height ?? 900
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: dashboardItemCount,
            visibleScreenHeight: screenHeight,
            supplementalHeight: (DeviceSetupRecoveryState.resolve(
                visibleCount: dashboardItemCount, isRefreshing: isRefreshing, diagnostics: refreshDiagnostics
            ) == .ready ? 0 : 230) + (model.isUsingPreviewData ? 34 : 0)
                + (refreshDiagnostics.attempts.contains { $0.status != .reported && $0.status != .noReport } ? 38 : 0)
                + CGFloat(model.connections.pairedDevices.count) * 48
                + CGFloat(model.connections.operations.count) * 92
        )
        return NSSize(width: size.width, height: size.height)
    }

    private func handlePreferencesChanged() {
        hudController.refreshPreferences()
        model.refreshNotificationAuthorizationStatus()
        updateStatusButton()
        updateStatusMenuContent()
        registerQuickActions()
        updateDesktopWidget()
    }

    private func updateDesktopWidget(store: BatterySnapshotStore? = nil, refreshDiagnostics: BatteryRefreshDiagnostics? = nil) {
        let renderedStore = store ?? model.store
        desktopWidgetController.update(
            snapshots: batterySnapshotsWithKnownFailures(renderedStore.decoratedSnapshots, diagnostics: refreshDiagnostics ?? model.latestRefreshDiagnostics),
            onOpenSettings: { [weak self] in
                self?.showSettingsWindow(initialPane: .dashboard)
            }
        )
    }

    private func registerQuickActions() {
        shortcutController.registerEnabledShortcuts { [weak self] action in
            Task { @MainActor in
                _ = self?.performQuickAction(action)
            }
        }
    }

    @discardableResult
    private func performQuickAction(_ action: BeaconQuickAction) -> Bool {
        quickActionLogger.info("Quick action performed action=\(action.rawValue, privacy: .public)")
        switch action {
        case .showDashboard:
            guard let button = statusItem.button else { return false }
            if statusMenuPanelController.isShown {
                closeStatusMenu()
            } else {
                showStatusMenu(relativeTo: button)
            }
            return true
        case .refreshBatteries:
            Task { await model.refresh() }
            return true
        case .openSettings:
            showSettingsWindow()
            return true
        case .addDevice:
            closeStatusMenu()
            settingsWindowController.showWindow(
                initialPane: .devices,
                initiallyShowingAddDeviceGuide: true
            )
            return true
        case .openBluetoothSettings:
            BeaconSystemSettingsActions.openBluetoothSettings()
            return true
        case .connectNearbyDevice:
            return performDeviceControlQuickAction(.connectNearby)
        case .disconnectLowestDevice:
            return performDeviceControlQuickAction(.disconnectLowest)
        case .transferToMac:
            return false
        }
    }

    private func performDeviceControlQuickAction(_ action: DeviceControlQuickAction) -> Bool {
        model.connections.refreshPairedDevices()
        guard let target = deviceControlTarget(
            for: action,
            snapshots: model.connections.snapshots(including: model.store.decoratedSnapshots).filter {
                model.connections.device(for: $0.id) != nil
            },
            preferences: DeviceDisplayPreferences.load()
        ) else {
            return false
        }

        guard target.action == .connect || target.action == .disconnect else { return false }
        let accepted = model.connections.perform(target.action == .connect ? .connect : .disconnect,
            deviceID: target.item.id, displayName: target.item.displayName)
        // The existing shortcut contract says "requested", not "connected". Keep the result
        // discoverable in the same overview until the operation HUD is wired separately.
        if let button = statusItem.button { showStatusMenu(relativeTo: button) }
        return accepted
    }

    private func updateStatusButton(
        store: BatterySnapshotStore? = nil,
        isRefreshing: Bool? = nil,
        refreshDiagnostics: BatteryRefreshDiagnostics? = nil
    ) {
        guard let button = statusItem.button else { return }
        let configuration = StatusWindowConfiguration.load()
        let renderedStore = store ?? model.store
        let renderedIsRefreshing = isRefreshing ?? model.isRefreshing
        let batteryText = configuration.showsMenuBarBattery
            ? MenuBarBatteryFormatter.menuBarText(for: batterySnapshotsWithKnownFailures(
                renderedStore.decoratedSnapshots, diagnostics: refreshDiagnostics ?? model.latestRefreshDiagnostics))
            : nil

        if let batteryText {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeft
            button.title = " \(batteryText)"
        } else {
            statusItem.length = BeaconMenuBarMetrics.imageOnlyLength
            button.imagePosition = .imageOnly
            button.title = ""
        }

        button.image = BeaconStatusIconImage.make()
        button.imageScaling = .scaleProportionallyUpOrDown
        if renderedIsRefreshing {
            button.toolTip = "Beacon · refreshing"
        } else {
            button.toolTip = batteryText.map { "Beacon · \($0)" } ?? "Beacon"
        }
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor in
                self?.closeStatusMenu()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}
