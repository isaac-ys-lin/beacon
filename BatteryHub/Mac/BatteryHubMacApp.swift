import AppKit
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
        UNUserNotificationCenter.current().delegate = self

        let model = BatteryHubModel()
        self.model = model
        statusController = BatteryHubStatusController(model: model)
        model.refreshNotificationAuthorizationStatus()
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

    static func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
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

enum BatteryHubStatusIconImage {
    static func make() -> NSImage {
        let image = NSImage(named: BatteryHubSymbols.statusGlyphAsset)
            ?? NSImage(systemSymbolName: BatteryHubSymbols.app, accessibilityDescription: "BatteryHub")
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
    @Published private(set) var notificationAuthorizationState: NotificationCenterAuthorizationState = .unknown
    @Published private(set) var latestNotificationDeliveryResult: NotificationCenterDeliveryResult?

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
        BatteryHistoryStore.record(nextStore.snapshots)
        store = nextStore
        logger.info("Visible external snapshots: \(nextStore.externalBatterySnapshots.count)")
        latestAlertEvents = LowBatteryNotifier.notifyIfNeeded(
            for: nextStore.externalBatterySnapshots,
            deliveryHandler: { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.setLatestNotificationDeliveryResult(result)
                    self?.refreshNotificationAuthorizationStatus()
                }
            }
        )
    }

    func refreshNotificationAuthorizationStatus() {
        Task { [weak self] in
            let state = await LowBatteryNotifier.currentAuthorizationState()
            await MainActor.run {
                self?.setNotificationAuthorizationState(state)
            }
        }
    }

    func requestNotificationAuthorization() {
        setNotificationAuthorizationState(.unknown)
        LowBatteryNotifier.requestAuthorization { [weak self] state, result in
            Task { @MainActor [weak self] in
                self?.setNotificationAuthorizationState(state)
                if let result {
                    self?.setLatestNotificationDeliveryResult(result)
                }
            }
        }
    }

    func sendTestNotification() {
        LowBatteryNotifier.sendTestNotification { [weak self] result in
            Task { @MainActor [weak self] in
                self?.setLatestNotificationDeliveryResult(result)
                self?.refreshNotificationAuthorizationStatus()
            }
        }
    }

    private func setNotificationAuthorizationState(_ state: NotificationCenterAuthorizationState) {
        guard notificationAuthorizationState != state else { return }
        notificationAuthorizationState = state
    }

    private func setLatestNotificationDeliveryResult(_ result: NotificationCenterDeliveryResult?) {
        guard latestNotificationDeliveryResult != result else { return }
        latestNotificationDeliveryResult = result
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
