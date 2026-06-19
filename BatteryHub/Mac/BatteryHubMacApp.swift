import AppKit
import Combine
import SwiftUI
import os

@main
final class BatteryHubMacApp: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) private static var retainedDelegate: BatteryHubMacApp?

    private var model: BatteryHubModel?
    private var statusController: BatteryHubStatusController?

    static func main() {
        let app = NSApplication.shared
        let delegate = BatteryHubMacApp()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.run()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusWindowPreferences.applyNativeDefaultIfNeeded()
        LowBatteryNotifier.requestAuthorization()

        let model = BatteryHubModel()
        self.model = model
        statusController = BatteryHubStatusController(model: model)
        model.start()
    }
}

@MainActor
final class BatteryHubStatusController: NSObject, NSPopoverDelegate {
    private let model: BatteryHubModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let popoverContentCoordinator = StatusPopoverContentCoordinator()
    private let settingsWindowController: BatteryHubSettingsWindowController
    private let hudController = BatteryHubHUDController()
    private let desktopWidgetController = BatteryHubDesktopWidgetController()
    private let shortcutController = BatteryHubShortcutController()
    private var storeObserver: AnyCancellable?
    private var refreshStateObserver: AnyCancellable?
    private var alertEventsObserver: AnyCancellable?
    private var preferencesObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?

    init(model: BatteryHubModel) {
        self.model = model
        settingsWindowController = BatteryHubSettingsWindowController(model: model)
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = preferredPopoverContentSize()
        popover.delegate = self
        updatePopoverContent()

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
            self?.updatePopoverContent()
            self?.settingsWindowController.updateContent()
            self?.updateDesktopWidget()
        }
        refreshStateObserver = model.$isRefreshing.sink { [weak self] _ in
            self?.updateStatusButton()
            self?.updatePopoverContent()
            self?.settingsWindowController.updateContent()
        }
        alertEventsObserver = model.$latestAlertEvents
            .filter { !$0.isEmpty }
            .sink { [weak self] events in
                self?.hudController.show(event: events[0])
            }
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusButton()
                self?.updatePopoverContent()
                self?.registerQuickActions()
                self?.updateDesktopWidget()
            }
        }
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
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(relativeTo: sender)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
    }

    private func updatePopoverContent(screen: NSScreen? = NSScreen.main) {
        let nextSize = preferredPopoverContentSize(screen: screen)
        if !popover.contentSize.isApproximatelyEqual(to: nextSize) {
            popover.contentSize = nextSize
        }

        popoverContentCoordinator.install(
            rootView: StatusMenuView(
                snapshots: model.store.decoratedSnapshots,
                isRefreshing: model.isRefreshing,
                isPreviewingData: model.isUsingPreviewData,
                onRefresh: { [weak model] in
                    Task { await model?.refresh() }
                },
                onOpenSettings: { [weak self] pane, selectedDeviceID in
                    self?.showSettingsWindow(initialPane: pane, selectedDeviceID: selectedDeviceID)
                }
            ),
            in: popover
        )
    }

    private func showSettingsWindow(
        initialPane: SettingsPane = .devices,
        selectedDeviceID: String? = nil
    ) {
        popover.performClose(nil)
        settingsWindowController.showWindow(
            initialPane: initialPane,
            initialSelectedDeviceID: selectedDeviceID
        )
    }

    private func showPopover(relativeTo sender: NSStatusBarButton) {
        updatePopoverContent(screen: sender.window?.screen)
        let anchor = NSRect(
            x: sender.bounds.midX - 1,
            y: sender.bounds.minY,
            width: 2,
            height: sender.bounds.height
        )
        popover.show(relativeTo: anchor, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func preferredPopoverContentSize(screen: NSScreen? = NSScreen.main) -> NSSize {
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: StatusWindowPreferences.styleKey)
            .flatMap(StatusWindowStyle.init(rawValue:)) ?? .native
        let preferences = DeviceDisplayPreferences.load(from: defaults)
        let sections = dashboardDeviceSections(
            model.store.decoratedSnapshots,
            preferences: preferences
        )
        let dashboardItemCount = sections.reduce(0) { partial, section in
            partial + section.items.count
        }
        let showsOverview = boolPreference(
            StatusWindowPreferences.showBatteryOverviewKey,
            defaultValue: true,
            defaults: defaults
        )
        let showsAirPodsCard = style == .large
            && boolPreference(
                StatusWindowPreferences.showAirPodsCardKey,
                defaultValue: true,
                defaults: defaults
            )
            && sections.contains { section in
                section.items.contains { item in
                    if case .airPods = item { return true }
                    return false
                }
            }
        let screenHeight = screen?.visibleFrame.height ?? 900
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: dashboardItemCount,
            showsOverview: showsOverview,
            showsAirPodsCard: showsAirPodsCard,
            style: style,
            visibleScreenHeight: screenHeight
        )
        return NSSize(width: size.width, height: size.height)
    }

    private func boolPreference(
        _ key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
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
        switch action {
        case .showDashboard:
            guard let button = statusItem.button else { return }
            if popover.isShown {
                popover.performClose(nil)
            } else {
                showPopover(relativeTo: button)
            }
        case .refreshBatteries:
            Task { await model.refresh() }
        case .openSettings:
            showSettingsWindow()
        case .addDevice:
            popover.performClose(nil)
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
        let batteryText = UserDefaults.standard.bool(forKey: StatusWindowPreferences.showMenuBarBatteryKey)
            ? MenuBarBatteryFormatter.menuBarText(for: model.store.decoratedSnapshots)
            : nil

        if let batteryText {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeft
            button.title = " \(batteryText)"
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            button.title = ""
        }

        button.image = BluetoothStatusIconImage.make()
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
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}

@MainActor
final class StatusPopoverContentCoordinator {
    private(set) var hostingController: NSHostingController<StatusMenuView>?

    func install(rootView: StatusMenuView, in popover: NSPopover) {
        if let hostingController {
            hostingController.rootView = rootView
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        popover.contentViewController = hostingController
    }
}

private extension NSSize {
    func isApproximatelyEqual(to other: NSSize) -> Bool {
        abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}

@MainActor
final class BatteryHubSettingsWindowController {
    private let model: BatteryHubModel
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
    }

    func updateContent() {
        guard let window else { return }
        let rootView = BatteryHubSettingsView(
            snapshots: model.store.decoratedSnapshots,
            isRefreshing: model.isRefreshing,
            isPreviewingData: model.isUsingPreviewData,
            onRefresh: { [weak model] in
                Task { await model?.refresh() }
            },
            onOpenBluetoothSettings: {
                BatteryHubSystemSettingsActions.openBluetoothSettings()
            },
            onOpenSoundSettings: {
                BatteryHubSystemSettingsActions.openSoundSettings()
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

@MainActor
final class BatteryHubHUDController {
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func show(event: BatteryAlertEvent) {
        guard BatteryHUDPreferences.isEnabled(for: event.kind) else { return }

        let window = existingOrNewWindow()
        window.contentViewController = NSHostingController(
            rootView: BatteryActionHUDView(
                event: event,
                showsDismissButton: BatteryHUDPreferences.showsDismissButton(),
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
        position(window)

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }

        scheduleAutoDismiss(for: window)
    }

    private func scheduleAutoDismiss(for window: NSWindow) {
        dismissTask?.cancel()
        guard BatteryHUDPreferences.isAutoDismissEnabled() else {
            dismissTask = nil
            return
        }

        let delay = BatteryHUDPreferences.dismissDelaySeconds()
        dismissTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .seconds(delay))
            await MainActor.run {
                guard let self, let window, window == self.window else { return }
                self.dismiss()
            }
        }
    }

    private func dismiss() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
            }
        }
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 92),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.window = window
        return window
    }

    private func position(_ window: NSWindow) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 520, height: 92)
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 42
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

enum BatteryHubSystemSettingsActions {
    static func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum MenuBarBatteryFormatter {
    static func menuBarText(for snapshots: [DecoratedBatterySnapshot]) -> String? {
        let percents = snapshots.compactMap { decorated -> Int? in
            guard decorated.freshness != .expired else { return nil }
            return decorated.snapshot.percent
        }

        guard let lowestPercent = percents.min() else { return nil }
        return "\(lowestPercent)%"
    }
}

private enum BluetoothStatusIconImage {
    static func make() -> NSImage {
        let symbolName = BatteryHubSymbols.bluetooth
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BatteryHub")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(size: NSSize(width: 18, height: 18))

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "BatteryHub"
        return image
    }
}

@MainActor
final class BatteryHubModel: ObservableObject {
    @Published private(set) var store = BatterySnapshotStore()
    @Published private(set) var isRefreshing = false
    @Published private(set) var latestAlertEvents: [BatteryAlertEvent] = []

    private let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "refresh")
    private var refreshLoop: Task<Void, Never>?
    private let usesPreviewData: Bool

    var isUsingPreviewData: Bool {
        usesPreviewData
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        usesPreviewData = environment["BATTERYHUB_PREVIEW_DATA"] == "1"
        #else
        usesPreviewData = false
        #endif
    }

    func start() {
        guard refreshLoop == nil else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        if usesPreviewData {
            seedPreviewData()
            return
        }

        refreshLoop = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                await self?.refresh()
            }
        }
    }

    deinit {
        refreshLoop?.cancel()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if usesPreviewData {
            seedPreviewData()
            return
        }

        var nextStore = store
        let bluetoothSnapshots = await BluetoothBatteryResolver().read()
        logger.info("Bluetooth refresh returned \(bluetoothSnapshots.count) snapshots")
        nextStore.merge(bluetoothSnapshots)
        if let envelope = try? CloudBatterySync().load() {
            nextStore.merge(envelope.snapshots)
        }
        BatteryHistoryStore.record(nextStore.snapshots)
        store = nextStore
        logger.info("Visible external snapshots: \(nextStore.externalBatterySnapshots.count)")
        latestAlertEvents = LowBatteryNotifier.notifyIfNeeded(for: nextStore.externalBatterySnapshots)
    }

    private func seedPreviewData() {
        var nextStore = BatterySnapshotStore(now: Date.init)
        let now = Date()
        let previewSnapshots = Self.previewSnapshots(now: now)
        nextStore.merge(previewSnapshots)
        seedPreviewHistory(now: now)
        store = nextStore
        logger.info("Preview battery data loaded for UI QA")
    }

    private func seedPreviewHistory(now: Date) {
        let samples = [
            BatterySnapshot(
                deviceID: "preview-keyboard",
                displayName: "Magic Keyboard",
                kind: .keyboard,
                percent: 87,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now.addingTimeInterval(-10_800)
            ),
            BatterySnapshot(
                deviceID: "preview-keyboard",
                displayName: "Magic Keyboard",
                kind: .keyboard,
                percent: 84,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now.addingTimeInterval(-5_400)
            ),
            BatterySnapshot(
                deviceID: "preview-keyboard",
                displayName: "Magic Keyboard",
                kind: .keyboard,
                percent: 82,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now
            ),
            BatterySnapshot(
                deviceID: "preview-mouse",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: 42,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now.addingTimeInterval(-10_800)
            ),
            BatterySnapshot(
                deviceID: "preview-mouse",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: 35,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now.addingTimeInterval(-5_400)
            ),
            BatterySnapshot(
                deviceID: "preview-mouse",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: 31,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now
            ),
        ]
        BatteryHistoryStore.record(samples, now: now)
    }

    private static func previewSnapshots(now: Date) -> [BatterySnapshot] {
        [
            BatterySnapshot(
                deviceID: "preview-mac",
                displayName: "MacBook Pro",
                kind: .macBook,
                percent: nil,
                chargeState: .unknown,
                source: .macPowerSource,
                updatedAt: now
            ),
            BatterySnapshot(
                deviceID: "preview-keyboard",
                displayName: "Magic Keyboard",
                kind: .keyboard,
                percent: 82,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now
            ),
            BatterySnapshot(
                deviceID: "preview-mouse",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: 31,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now.addingTimeInterval(-720)
            ),
            BatterySnapshot(
                deviceID: "preview-iphone",
                displayName: "Isaac's iPhone",
                kind: .iPhone,
                percent: 64,
                chargeState: .charging,
                source: .iCloud,
                updatedAt: now
            ),
            BatterySnapshot(
                deviceID: "preview-watch",
                displayName: "Apple Watch",
                kind: .appleWatch,
                percent: 18,
                chargeState: .unplugged,
                source: .watchConnectivity,
                updatedAt: now
            ),
            BatterySnapshot(
                deviceID: "preview-airpods-case",
                displayName: "Isaac's AirPods Pro Case",
                kind: .airPods,
                percent: 90,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now
            ),
            BatterySnapshot(
                deviceID: "preview-airpods-left",
                displayName: "Isaac's AirPods Pro Left",
                kind: .airPods,
                percent: 72,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now
            ),
            BatterySnapshot(
                deviceID: "preview-airpods-right",
                displayName: "Isaac's AirPods Pro Right",
                kind: .airPods,
                percent: 68,
                chargeState: .unplugged,
                source: .coreBluetooth,
                updatedAt: now
            ),
        ]
    }
}
