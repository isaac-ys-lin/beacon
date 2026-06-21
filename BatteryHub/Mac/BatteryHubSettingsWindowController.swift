import AppKit
import SwiftUI
import os

@MainActor
final class BatteryHubSettingsWindowController {
    private let model: BatteryHubModel
    private let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "settings")
    private var window: NSWindow?
    private var hostingController: NSHostingController<BatteryHubSettingsView>?
    private var initialPane: SettingsPane = .devices
    private var initialSelectedDeviceID: String?
    private var initiallyShowingAddDeviceGuide = false

    init(model: BatteryHubModel) {
        self.model = model
    }

    func showWindow(
        initialPane: SettingsPane = .devices,
        initialSelectedDeviceID: String? = nil,
        initiallyShowingAddDeviceGuide: Bool = false
    ) {
        self.initialPane = initialPane
        self.initialSelectedDeviceID = initialSelectedDeviceID
        self.initiallyShowingAddDeviceGuide = initiallyShowingAddDeviceGuide
        let window = existingOrNewWindow()
        updateContent()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let hasSelectedDevice = initialSelectedDeviceID == nil ? "false" : "true"
        let showsAddDeviceGuide = initiallyShowingAddDeviceGuide ? "true" : "false"
        logger.info("Settings window opened pane=\(initialPane.rawValue, privacy: .public) hasSelectedDevice=\(hasSelectedDevice, privacy: .public) addDeviceGuide=\(showsAddDeviceGuide, privacy: .public)")
    }

    func updateContent() {
        guard let window else { return }
        let rootView = BatteryHubSettingsView(
            snapshots: model.store.decoratedSnapshots,
            isRefreshing: model.isRefreshing,
            isPreviewingData: model.isUsingPreviewData,
            notificationAuthorizationState: model.notificationAuthorizationState,
            latestNotificationDeliveryResult: model.latestNotificationDeliveryResult,
            onRefresh: { [weak model] in
                Task { await model?.refresh() }
            },
            onOpenBluetoothSettings: {
                BatteryHubSystemSettingsActions.openBluetoothSettings()
            },
            onOpenSoundSettings: {
                BatteryHubSystemSettingsActions.openSoundSettings()
            },
            onRefreshNotificationAuthorization: { [weak model] in
                model?.refreshNotificationAuthorizationStatus()
            },
            onRequestNotificationPermission: { [weak model] in
                model?.requestNotificationAuthorization()
            },
            onOpenNotificationSettings: {
                BatteryHubSystemSettingsActions.openNotificationSettings()
            },
            onSendTestNotification: { [weak model] in
                model?.sendTestNotification()
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            initialPane: initialPane,
            initialSelectedDeviceID: initialSelectedDeviceID,
            initiallyShowingAddDeviceGuide: initiallyShowingAddDeviceGuide
        )
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            self.hostingController = hostingController
            window.contentViewController = hostingController
        }
        initiallyShowingAddDeviceGuide = false
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BatteryHub Settings"
        window.minSize = NSSize(width: 820, height: 560)
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .controlBackgroundColor
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        return window
    }
}
