import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class BatteryHubStatusController: NSObject {
    private let model: BatteryHubModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenuPanelController = StatusMenuPanelController()
    private let settingsWindowController: BatteryHubSettingsWindowController
    private let hudController = BatteryHubHUDController()
    private let desktopWidgetController = BatteryHubDesktopWidgetController()
    private let shortcutController = BatteryHubShortcutController()
    private let bluetoothPowerStateObserver = BluetoothPowerStateObserver()
    private let menuLogger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "menu-bar")
    private let quickActionLogger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "quick-actions")
    private var storeObserver: AnyCancellable?
    private var refreshStateObserver: AnyCancellable?
    private var alertEventsObserver: AnyCancellable?
    private var notificationAuthorizationObserver: AnyCancellable?
    private var notificationDeliveryObserver: AnyCancellable?
    private var bluetoothPowerStateCancellable: AnyCancellable?
    private var preferencesObservers: [NSObjectProtocol] = []
    private var outsideClickMonitor: Any?

    init(model: BatteryHubModel) {
        self.model = model
        settingsWindowController = BatteryHubSettingsWindowController(model: model)
        super.init()

        updateStatusMenuContent()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.imageHugsTitle = true
            button.toolTip = "BatteryHub"
        }

        storeObserver = model.$store.sink { [weak self] _ in
            self?.updateStatusButton()
            self?.updateStatusMenuContent()
            self?.settingsWindowController.updateContent()
            self?.updateDesktopWidget()
        }
        refreshStateObserver = model.$isRefreshing.sink { [weak self] _ in
            self?.updateStatusButton()
            self?.updateStatusMenuContent()
            self?.settingsWindowController.updateContent()
        }
        notificationAuthorizationObserver = model.$notificationAuthorizationState.sink { [weak self] _ in
            self?.updateStatusMenuContent()
            self?.settingsWindowController.updateContent()
        }
        notificationDeliveryObserver = model.$latestNotificationDeliveryResult.sink { [weak self] _ in
            self?.settingsWindowController.updateContent()
        }
        alertEventsObserver = model.$latestAlertEvents
            .filter { !$0.isEmpty }
            .sink { [weak self] events in
                self?.hudController.show(event: events[0])
            }
        bluetoothPowerStateCancellable = bluetoothPowerStateObserver.$state
            .sink { [weak self] _ in
                self?.updateStatusMenuContent()
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
        BatteryHubIntentBridge.shared.register(
            handler: { [weak self] action in
                self?.performQuickAction(action)
            },
            snapshotProvider: { [weak model] in
                model?.store.decoratedSnapshots ?? []
            }
        )
        registerQuickActions()
        updateStatusButton()
        updateDesktopWidget()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if statusMenuPanelController.isShown {
            closeStatusMenu()
        } else {
            showStatusMenu(relativeTo: sender)
        }
    }

    private func updateStatusMenuContent(screen: NSScreen? = NSScreen.main) {
        let configuration = StatusWindowConfiguration.load()
        let nextSize = preferredPopoverContentSize(screen: screen, configuration: configuration)

        statusMenuPanelController.install(
            rootView: StatusMenuView(
                snapshots: model.store.decoratedSnapshots,
                isRefreshing: model.isRefreshing,
                isPreviewingData: model.isUsingPreviewData,
                configuration: configuration,
                bluetoothPowerState: bluetoothPowerStateObserver.state,
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
        configuration: StatusWindowConfiguration = .load()
    ) -> NSSize {
        let defaults = UserDefaults.standard
        let preferences = DeviceDisplayPreferences.load(from: defaults)
        let sections = statusMenuDeviceSections(
            model.store.decoratedSnapshots,
            preferences: preferences
        )
        let dashboardItemCount = sections.reduce(0) { partial, section in
            partial + section.items.count
        }
        let screenHeight = screen?.visibleFrame.height ?? 900
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: dashboardItemCount,
            showsOverview: configuration.showsBatteryOverview,
            visibleScreenHeight: screenHeight
        )
        return NSSize(width: size.width, height: size.height)
    }

    private func handlePreferencesChanged() {
        model.refreshNotificationAuthorizationStatus()
        updateStatusButton()
        updateStatusMenuContent()
        registerQuickActions()
        updateDesktopWidget()
    }

    private func updateDesktopWidget() {
        desktopWidgetController.update(
            snapshots: model.store.decoratedSnapshots,
            onOpenSettings: { [weak self] in
                self?.showSettingsWindow(initialPane: .dashboard)
            }
        )
    }

    private func registerQuickActions() {
        shortcutController.registerEnabledShortcuts { [weak self] action in
            Task { @MainActor in
                self?.performQuickAction(action)
            }
        }
    }

    private func performQuickAction(_ action: BatteryHubQuickAction) {
        quickActionLogger.info("Quick action performed action=\(action.rawValue, privacy: .public)")
        switch action {
        case .showDashboard:
            guard let button = statusItem.button else { return }
            if statusMenuPanelController.isShown {
                closeStatusMenu()
            } else {
                showStatusMenu(relativeTo: button)
            }
        case .refreshBatteries:
            Task { await model.refresh() }
        case .openSettings:
            showSettingsWindow()
        case .addDevice:
            closeStatusMenu()
            settingsWindowController.showWindow(
                initialPane: .devices,
                initiallyShowingAddDeviceGuide: true
            )
        case .openBluetoothSettings:
            BatteryHubSystemSettingsActions.openBluetoothSettings()
        case .connectNearbyDevice:
            performDeviceControlQuickAction(.connectNearby)
        case .disconnectLowestDevice:
            performDeviceControlQuickAction(.disconnectLowest)
        case .transferToMac:
            break
        }
    }

    private func performDeviceControlQuickAction(_ action: DeviceControlQuickAction) {
        guard let target = deviceControlTarget(
            for: action,
            snapshots: model.store.decoratedSnapshots,
            preferences: DeviceDisplayPreferences.load()
        ) else {
            return
        }

        switch target.action {
        case .connect:
            if BluetoothDeviceController.connect(deviceID: target.item.id) {
                Task { await model.refresh() }
            }
        case .disconnect:
            if BluetoothDeviceController.disconnect(deviceID: target.item.id) {
                Task { await model.refresh() }
            }
        default:
            return
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let configuration = StatusWindowConfiguration.load()
        let batteryText = configuration.showsMenuBarBattery
            ? MenuBarBatteryFormatter.menuBarText(for: model.store.decoratedSnapshots)
            : nil

        if let batteryText {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeft
            button.title = " \(batteryText)"
        } else {
            statusItem.length = BatteryHubMenuBarMetrics.imageOnlyLength
            button.imagePosition = .imageOnly
            button.title = ""
        }

        button.image = BatteryHubStatusIconImage.make()
        button.imageScaling = .scaleProportionallyUpOrDown
        if model.isRefreshing {
            button.toolTip = "BatteryHub · refreshing"
        } else {
            button.toolTip = batteryText.map { "BatteryHub · \($0)" } ?? "BatteryHub"
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
