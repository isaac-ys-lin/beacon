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
        updateContent()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let hasSelectedDevice = initialSelectedDeviceID == nil ? "false" : "true"
        let showsAddDeviceGuide = initiallyShowingAddDeviceGuide ? "true" : "false"
        logger.info("Settings window opened pane=\(initialPane.rawValue, privacy: .public) hasSelectedDevice=\(hasSelectedDevice, privacy: .public) addDeviceGuide=\(showsAddDeviceGuide, privacy: .public)")
    }

    func updateContent() {
        guard let window else { return }
        let rootView = BeaconSettingsView(
            snapshots: model.store.decoratedSnapshots,
            isRefreshing: model.isRefreshing,
            isPreviewingData: model.isUsingPreviewData,
            notificationAuthorizationState: model.notificationAuthorizationState,
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
        window.title = "Beacon Settings"
        window.minSize = NSSize(width: 820, height: 560)
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .controlBackgroundColor
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        installCloseShortcutMonitorIfNeeded()
        return window
    }

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
