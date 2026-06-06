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
final class BatteryHubStatusController: NSObject, NSPopoverDelegate {
    private let model: BatteryHubModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var storeObserver: AnyCancellable?
    private var outsideClickMonitor: Any?

    init(model: BatteryHubModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 378, height: 260)
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
        }
        updateStatusButton()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updatePopoverContent()
            let anchor = NSRect(
                x: sender.bounds.midX - 1,
                y: sender.bounds.minY,
                width: 2,
                height: sender.bounds.height
            )
            popover.show(relativeTo: anchor, of: sender, preferredEdge: .minY)
            startOutsideClickMonitor()
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
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
        button.title = ""
        button.image = BluetoothStatusIconImage.make()
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

private enum BluetoothStatusIconImage {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let path = NSBezierPath()
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let midX = rect.midX - 0.1
            let top = rect.maxY - 1.45
            let bottom = rect.minY + 1.45
            let upper = rect.midY + 3.45
            let lower = rect.midY - 3.45
            let right = rect.maxX - 2.65
            let left = rect.minX + 3.75

            path.move(to: NSPoint(x: midX, y: top))
            path.line(to: NSPoint(x: right, y: upper))
            path.line(to: NSPoint(x: midX, y: rect.midY))
            path.line(to: NSPoint(x: right, y: lower))
            path.line(to: NSPoint(x: midX, y: bottom))
            path.line(to: NSPoint(x: midX, y: top))
            path.move(to: NSPoint(x: left, y: upper))
            path.line(to: NSPoint(x: midX, y: rect.midY))
            path.line(to: NSPoint(x: left, y: lower))

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "BatteryHub"
        return image
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
