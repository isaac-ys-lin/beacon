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
        LowBatteryNotifier.requestAuthorization()

        let model = BatteryHubModel()
        self.model = model
        statusController = BatteryHubStatusController(model: model)
        model.start()
    }
}

@MainActor
final class BatteryHubStatusController: NSObject {
    private let model: BatteryHubModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var storeObserver: AnyCancellable?

    init(model: BatteryHubModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 378, height: 260)
        updatePopoverContent()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
        }

        storeObserver = model.$store.sink { [weak self] _ in
            self?.updateStatusButton()
            self?.updatePopoverContent()
        }
        updateStatusButton()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updatePopoverContent()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    private func updatePopoverContent() {
        popover.contentViewController = NSHostingController(
            rootView: StatusMenuView(
                snapshots: model.store.decoratedExternalBatterySnapshots,
                onRefresh: { [weak model] in
                    Task { await model?.refresh() }
                }
            )
        )
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = " \(summaryText)"
        button.image = NSImage(systemSymbolName: summarySymbol, accessibilityDescription: "BatteryHub")
    }

    private var summaryText: String {
        let percents = model.store.externalBatterySnapshots.compactMap(\.percent)
        guard let lowest = percents.min() else { return "Hub" }
        return "Hub \(lowest)%"
    }

    private var summarySymbol: String {
        let lowest = model.store.externalBatterySnapshots.compactMap(\.percent).min() ?? 100
        switch lowest {
        case 0...20: return "battery.25percent"
        case 21...60: return "battery.50percent"
        case 61...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

@MainActor
final class BatteryHubModel: ObservableObject {
    @Published private(set) var store = BatterySnapshotStore()

    private let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "refresh")
    private var refreshLoop: Task<Void, Never>?

    func start() {
        guard refreshLoop == nil else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
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
        var nextStore = store
        let bluetoothSnapshots = await BluetoothBatteryResolver().read()
        logger.info("Bluetooth refresh returned \(bluetoothSnapshots.count) snapshots")
        nextStore.merge(bluetoothSnapshots)
        if let envelope = try? CloudBatterySync().load() {
            nextStore.merge(envelope.snapshots)
        }
        store = nextStore
        logger.info("Visible external snapshots: \(nextStore.externalBatterySnapshots.count)")
        LowBatteryNotifier.notifyIfNeeded(for: nextStore.externalBatterySnapshots)
    }
}
