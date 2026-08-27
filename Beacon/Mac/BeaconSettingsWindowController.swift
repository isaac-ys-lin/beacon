import AppKit
import SwiftUI
import os

@MainActor
final class BeaconSettingsWindowController {
    private let model: BeaconModel
    private let logger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "settings")
    private var window: NSWindow?
    private var hostingController: NSHostingController<BeaconSettingsView>?
    private var initialPane: SettingsPane = .devices
    private var initialSelectedDeviceID: String?
    private var initiallyShowingAddDeviceGuide = false
    private var closeShortcutMonitor: Any?

    /// True while the Settings window is on screen (or only miniaturized).
    /// Used by the status controller to avoid overlapping it with the popover.
    var isWindowOpen: Bool {
        (window?.isVisible ?? false) || (window?.isMiniaturized ?? false)
    }

    init(model: BeaconModel) {
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
        // A route request is different from a model refresh. SwiftUI preserves
        // @State when only the rootView value changes, so rebuild the host here
        // to guarantee the requested pane, device, and Add Device sheet win.
        updateContent(rebuildHostingController: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let hasSelectedDevice = initialSelectedDeviceID == nil ? "false" : "true"
        let showsAddDeviceGuide = initiallyShowingAddDeviceGuide ? "true" : "false"
        logger.info("Settings window opened pane=\(initialPane.rawValue, privacy: .public) hasSelectedDevice=\(hasSelectedDevice, privacy: .public) addDeviceGuide=\(showsAddDeviceGuide, privacy: .public)")
    }

    func updateContent(
        store: BatterySnapshotStore? = nil,
        isRefreshing: Bool? = nil,
        refreshDiagnostics: BatteryRefreshDiagnostics? = nil,
        notificationAuthorizationState: NotificationCenterAuthorizationState? = nil,
        rebuildHostingController: Bool = false
    ) {
        guard let window else { return }
        let renderedStore = store ?? model.store
        let rootView = BeaconSettingsView(
            snapshots: renderedStore.decoratedSnapshots,
            isRefreshing: isRefreshing ?? model.isRefreshing,
            isPreviewingData: model.isUsingPreviewData,
            refreshDiagnostics: refreshDiagnostics ?? model.latestRefreshDiagnostics,
            trustedIPhones: model.trustedIPhoneRegistry.devices,
            trustedIPhoneEnrollmentResult: model.trustedIPhoneEnrollmentResult,
            notificationAuthorizationState: notificationAuthorizationState ?? model.notificationAuthorizationState,
            latestNotificationDeliveryResult: model.latestNotificationDeliveryResult,
            onRefresh: { [weak model] in
                Task { await model?.refresh() }
            },
            onOpenBluetoothSettings: {
                BeaconSystemSettingsActions.openBluetoothSettings()
            },
            onOpenSoundSettings: {
                BeaconSystemSettingsActions.openSoundSettings()
            },
            onRefreshNotificationAuthorization: { [weak model] in
                model?.refreshNotificationAuthorizationStatus()
            },
            onRequestNotificationPermission: { [weak model] in
                model?.requestNotificationAuthorization()
            },
            onOpenNotificationSettings: {
                BeaconSystemSettingsActions.openNotificationSettings()
            },
            onSendTestNotification: { [weak model] in
                model?.sendTestNotification()
            },
            onTrustConnectedIPhone: { [weak model] in
                Task { await model?.trustConnectedIPhones() }
            },
            onForgetTrustedIPhone: { [weak model] udid in
                model?.forgetTrustedIPhone(udid: udid)
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            initialPane: initialPane,
            initialSelectedDeviceID: initialSelectedDeviceID,
            initiallyShowingAddDeviceGuide: initiallyShowingAddDeviceGuide
        )
        if let hostingController, !rebuildHostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            self.hostingController = hostingController
            window.contentViewController = hostingController
        }
        // Assigning a content view controller can reset AppKit's content size
        // constraints, so re-apply the contract after every host update.
        window.contentMinSize = Self.minimumContentSize
        initiallyShowingAddDeviceGuide = false
    }

    /// Brings an already-open Settings window to the front without resetting the
    /// selected pane/device (unlike `showWindow`).
    func bringToFront() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        window.title = BeaconL10n.string("Beacon Settings")
        // This requirement is expressed in SwiftUI content coordinates. Using
        // `minSize` would include the title bar and leave only 588pt of content.
        window.contentMinSize = Self.minimumContentSize
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .controlBackgroundColor
        window.isReleasedWhenClosed = false
        let autosaveName = "Beacon.SettingsWindow"
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(autosaveName)
        self.window = window
        installCloseShortcutMonitorIfNeeded()
        return window
    }

    private static let minimumContentSize = NSSize(width: 900, height: 620)

    #if DEBUG
    var debugWindow: NSWindow? { window }
    var debugHostingControllerIdentifier: ObjectIdentifier? {
        hostingController.map(ObjectIdentifier.init)
    }
    #endif

    /// Wires ⌘W to close the Settings window. The app is a menu-bar accessory
    /// with no main menu, so the standard Close key equivalent has nothing to
    /// handle it; a local key monitor fills that gap and consumes the event to
    /// avoid the system beep.
    private func installCloseShortcutMonitorIfNeeded() {
        guard closeShortcutMonitor == nil else { return }
        closeShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
                window.performClose(nil)
                return nil
            }
            return event
        }
    }
}
