import AppKit
import Combine
import CoreBluetooth
import SwiftUI
import UserNotifications
import os

@main
final class BatteryHubMacApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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
        UNUserNotificationCenter.current().delegate = self
        LowBatteryNotifier.requestAuthorization()

        let model = BatteryHubModel()
        self.model = model
        statusController = BatteryHubStatusController(model: model)
        model.start()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

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
    private var storeObserver: AnyCancellable?
    private var refreshStateObserver: AnyCancellable?
    private var alertEventsObserver: AnyCancellable?
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
        startOutsideClickMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeStatusMenu() {
        statusMenuPanelController.close()
        stopOutsideClickMonitor()
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
            showsOverview: configuration.showsOverviewInDashboard,
            showsAirPodsCard: configuration.showsAirPodsCard(in: sections),
            style: configuration.style,
            visibleScreenHeight: screenHeight
        )
        return NSSize(width: size.width, height: size.height)
    }

    private func handlePreferencesChanged() {
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
            statusItem.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            button.title = ""
        }

        button.image = BatteryHubStatusIconImage.make()
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

@MainActor
final class StatusMenuPanelController {
    private(set) var hostingController: NSHostingController<StatusMenuView>?
    private(set) var panel: BatteryHubStatusPanel?
    private var contentSize: NSSize = StatusMenuSizing.preferredContentSize(
        dashboardItemCount: 0,
        showsOverview: false,
        showsAirPodsCard: false,
        style: .native,
        visibleScreenHeight: 900
    )

    var isShown: Bool {
        panel?.isVisible == true
    }

    func install(rootView: StatusMenuView, contentSize: NSSize) {
        self.contentSize = contentSize
        if let hostingController {
            hostingController.rootView = rootView
            hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
            applyRoundedMask(to: hostingController.view)
            applyRoundedMask(to: panel?.contentView)
            panel?.setContentSize(contentSize)
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
        applyRoundedMask(to: hostingController.view)

        let panel = BatteryHubStatusPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        applyRoundedMask(to: panel.contentView)
        self.panel = panel
    }

    func show(relativeTo sender: NSStatusBarButton) {
        guard let panel else { return }
        guard let window = sender.window else {
            panel.center()
            panel.orderFrontRegardless()
            return
        }

        let buttonFrame = window.convertToScreen(sender.convert(sender.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = StatusMenuPanelPositioning.frame(
            contentSize: contentSize,
            buttonFrame: buttonFrame,
            visibleFrame: visibleFrame
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func applyRoundedMask(to view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = NativeMacStyle.popoverCornerRadius
        if #available(macOS 10.15, *) {
            view.layer?.cornerCurve = .continuous
        }
        view.layer?.masksToBounds = true
    }
}

final class BatteryHubStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum StatusMenuPanelPositioning {
    static let margin: CGFloat = 8
    static let verticalGap: CGFloat = 6

    static func frame(
        contentSize: NSSize,
        buttonFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return NSRect(
                x: buttonFrame.midX - contentSize.width / 2,
                y: buttonFrame.minY - contentSize.height - verticalGap,
                width: contentSize.width,
                height: contentSize.height
            )
        }

        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - contentSize.width - margin
        let proposedX = buttonFrame.midX - contentSize.width / 2
        let x = min(max(proposedX, minX), max(minX, maxX))

        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - contentSize.height - margin
        let proposedY = buttonFrame.minY - contentSize.height - verticalGap
        let y = min(max(proposedY, minY), max(minY, maxY))

        return NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height)
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
            syncDiagnostics: model.companionSyncDiagnostics,
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
            onClearCompanionSync: { [weak model] in
                model?.clearCompanionSync()
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

@MainActor
final class BatteryHubHUDController {
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func show(event: BatteryAlertEvent) {
        guard BatteryHUDPreferences.isEnabled(for: event.kind) else { return }

        let window = existingOrNewWindow()
        let hostingController = NSHostingController(
            rootView: BatteryActionHUDView(
                event: event,
                showsDismissButton: BatteryHUDPreferences.showsDismissButton(),
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
        hostingController.view.frame = NSRect(origin: .zero, size: Self.hudSize)
        window.contentViewController = hostingController
        applyRoundedTransparentMask(to: hostingController.view)
        applyRoundedTransparentMask(to: window.contentView)
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

    private static let hudSize = NSSize(width: 520, height: 92)

    private func applyRoundedTransparentMask(to view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = BatteryActionHUDView.cornerRadius
        if #available(macOS 10.15, *) {
            view.layer?.cornerCurve = .continuous
        }
        view.layer?.masksToBounds = true
    }

    private func position(_ window: NSWindow) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.hudSize
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 42
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

enum BluetoothPowerState: Equatable {
    case on
    case off
    case unknown
}

@MainActor
final class BluetoothPowerStateObserver: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    @Published private(set) var state: BluetoothPowerState = .unknown

    private var central: CBCentralManager?

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .on
        case .poweredOff:
            state = .off
        default:
            state = .unknown
        }
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

private enum BatteryHubStatusIconImage {
    static func make() -> NSImage {
        let symbolName = BatteryHubSymbols.app
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
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
    @Published private(set) var companionSyncDiagnostics = CompanionSyncDiagnostics.empty

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
            logger.info("Battery refresh loop skipped under XCTest")
            return
        }
        if usesPreviewData {
            logger.info("Battery refresh loop using preview data")
            seedPreviewData()
            return
        }

        logger.info("Battery refresh loop started")
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
        logger.info("Battery refresh started")
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
        let cloudSync = CloudBatterySync()
        let envelope: SyncEnvelope?
        let syncLoadErrorDescription: String?
        do {
            envelope = try cloudSync.load()
            syncLoadErrorDescription = nil
        } catch {
            envelope = nil
            syncLoadErrorDescription = error.localizedDescription
            logger.error("iCloud battery sync load failed: \(error.localizedDescription)")
        }
        if let envelope {
            nextStore.merge(envelope.snapshots)
        } else if syncLoadErrorDescription == nil {
            nextStore.removeCompanionSyncSnapshots()
        }
        BatteryHistoryStore.record(nextStore.snapshots)
        store = nextStore
        companionSyncDiagnostics = CompanionSyncDiagnostics(
            snapshots: nextStore.snapshots,
            envelope: envelope,
            loadErrorDescription: syncLoadErrorDescription
        )
        logger.info("Visible external snapshots: \(nextStore.externalBatterySnapshots.count)")
        latestAlertEvents = LowBatteryNotifier.notifyIfNeeded(for: nextStore.externalBatterySnapshots)
    }

    func clearCompanionSync() {
        let syncAccepted = CloudBatterySync().clear()
        var nextStore = store
        nextStore.removeCompanionSyncSnapshots()
        store = nextStore
        companionSyncDiagnostics = CompanionSyncDiagnostics(snapshots: nextStore.snapshots)
        logger.info("Cleared companion sync snapshots syncAccepted=\(syncAccepted)")
    }

    private func seedPreviewData() {
        var nextStore = BatterySnapshotStore(now: Date.init)
        let now = Date()
        let previewSnapshots = Self.previewSnapshots(now: now)
        nextStore.merge(previewSnapshots)
        seedPreviewHistory(now: now)
        store = nextStore
        companionSyncDiagnostics = CompanionSyncDiagnostics(
            snapshots: nextStore.snapshots,
            envelope: SyncEnvelope(snapshots: previewSnapshots, publishedAt: now)
        )
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
