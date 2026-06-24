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
    static let designReferenceAssetName = BatteryHubSymbols.headerLogoAsset

    static func make(size: NSSize = NSSize(
        width: BatteryHubMenuBarMetrics.iconSide,
        height: BatteryHubMenuBarMetrics.iconSide
    )) -> NSImage {
        let statusIconSize = NSSize(
            width: size.width,
            height: size.height
        )
        let image = beaconTemplateImage(size: statusIconSize)
            ?? NSImage(named: designReferenceAssetName)
            ?? NSImage(systemSymbolName: BatteryHubSymbols.app, accessibilityDescription: "BatteryHub")
            ?? NSImage(size: statusIconSize)

        image.size = statusIconSize
        image.isTemplate = true
        image.accessibilityDescription = "BatteryHub"
        return image
    }

    private static func beaconTemplateImage(size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let image = NSImage(size: size, flipped: true) { _ in
            let scale = min(size.width, size.height)
                / BatteryHubStatusIconDrawingMetrics.canvasSide
                * BatteryHubStatusIconDrawingMetrics.artworkScale
            let origin = NSPoint(
                x: (size.width - BatteryHubStatusIconDrawingMetrics.canvasSide * scale) / 2,
                y: (size.height - BatteryHubStatusIconDrawingMetrics.canvasSide * scale) / 2
            )
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let stem = NSBezierPath()
            stem.lineCapStyle = .round
            stem.lineJoinStyle = .round
            stem.lineWidth = BatteryHubStatusIconDrawingMetrics.stemLineWidth * scale
            stem.move(to: scaledPoint(x: 14, y: 17, scale: scale, origin: origin))
            stem.line(to: scaledPoint(x: 14, y: 28, scale: scale, origin: origin))
            stem.stroke()

            drawArc(
                radius: 6,
                startDegrees: -16,
                endDegrees: -74,
                lineWidth: BatteryHubStatusIconDrawingMetrics.innerArcLineWidth * scale,
                scale: scale,
                origin: origin
            )
            drawArc(
                radius: 10.5,
                startDegrees: -12,
                endDegrees: -78,
                lineWidth: BatteryHubStatusIconDrawingMetrics.outerArcLineWidth * scale,
                scale: scale,
                origin: origin
            )

            let dotRadius = BatteryHubStatusIconDrawingMetrics.dotDiameter / 2
            let dotRect = NSRect(
                x: origin.x + (14 - dotRadius) * scale,
                y: origin.y + (15 - dotRadius) * scale,
                width: BatteryHubStatusIconDrawingMetrics.dotDiameter * scale,
                height: BatteryHubStatusIconDrawingMetrics.dotDiameter * scale
            )
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawArc(
        radius: CGFloat,
        startDegrees: CGFloat,
        endDegrees: CGFloat,
        lineWidth: CGFloat,
        scale: CGFloat,
        origin: NSPoint
    ) {
        let points = cubicArcPoints(
            center: NSPoint(x: 14, y: 15),
            radius: radius,
            startRadians: startDegrees * .pi / 180,
            endRadians: endDegrees * .pi / 180
        )
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth
        path.move(to: scaledPoint(points.start, scale: scale, origin: origin))
        path.curve(
            to: scaledPoint(points.end, scale: scale, origin: origin),
            controlPoint1: scaledPoint(points.control1, scale: scale, origin: origin),
            controlPoint2: scaledPoint(points.control2, scale: scale, origin: origin)
        )
        path.stroke()
    }

    private static func cubicArcPoints(
        center: NSPoint,
        radius: CGFloat,
        startRadians: CGFloat,
        endRadians: CGFloat
    ) -> (start: NSPoint, control1: NSPoint, control2: NSPoint, end: NSPoint) {
        let delta = endRadians - startRadians
        let kappa = 4 / 3 * tan(delta / 4)
        let start = point(center: center, radius: radius, radians: startRadians)
        let end = point(center: center, radius: radius, radians: endRadians)
        let startDerivative = NSPoint(x: -radius * sin(startRadians), y: radius * cos(startRadians))
        let endDerivative = NSPoint(x: -radius * sin(endRadians), y: radius * cos(endRadians))
        let control1 = NSPoint(x: start.x + kappa * startDerivative.x, y: start.y + kappa * startDerivative.y)
        let control2 = NSPoint(x: end.x - kappa * endDerivative.x, y: end.y - kappa * endDerivative.y)
        return (start, control1, control2, end)
    }

    private static func point(center: NSPoint, radius: CGFloat, radians: CGFloat) -> NSPoint {
        NSPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private static func scaledPoint(x: CGFloat, y: CGFloat, scale: CGFloat, origin: NSPoint) -> NSPoint {
        NSPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    private static func scaledPoint(_ point: NSPoint, scale: CGFloat, origin: NSPoint) -> NSPoint {
        scaledPoint(x: point.x, y: point.y, scale: scale, origin: origin)
    }
}

private enum BatteryHubStatusIconDrawingMetrics {
    static let canvasSide: CGFloat = 36
    static let artworkScale: CGFloat = 1.04
    static let stemLineWidth: CGFloat = 3.25
    static let innerArcLineWidth: CGFloat = 2.75
    static let outerArcLineWidth: CGFloat = 2.65
    static let dotDiameter: CGFloat = 6.2
}

enum BatteryHubMenuBarMetrics {
    static let iconSide: CGFloat = 24
    static let imageOnlyLength: CGFloat = 32
}

private enum BatteryRefreshLimits {
    static let timeout: Duration = .seconds(8)
}

private actor RefreshRaceGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

@MainActor
final class BatteryHubModel: ObservableObject {
    @Published private(set) var store = BatterySnapshotStore()
    @Published private(set) var isRefreshing = false
    @Published private(set) var latestAlertEvents: [BatteryAlertEvent] = []
    @Published private(set) var notificationAuthorizationState: NotificationCenterAuthorizationState = .unknown
    @Published private(set) var latestNotificationDeliveryResult: NotificationCenterDeliveryResult?
    @Published private(set) var latestRefreshDiagnostics = BatteryRefreshDiagnostics()

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
        guard let readReport = await readBluetoothSnapshotsWithTimeout() else {
            logger.error("Bluetooth refresh timed out after 8 seconds")
            latestRefreshDiagnostics = BatteryRefreshDiagnostics(
                attempts: [
                    BatteryProviderAttempt(
                        provider: .coreBluetoothBatteryService,
                        status: .timedOut,
                        candidateCount: 0,
                        message: "Battery refresh timed out after 8 seconds",
                        attemptedAt: Date()
                    )
                ],
                refreshedAt: Date(),
                snapshotCount: 0
            )
            return
        }
        let bluetoothSnapshots = readReport.snapshots
        latestRefreshDiagnostics = readReport.diagnostics
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

    private func readBluetoothSnapshotsWithTimeout() async -> BluetoothBatteryReadReport? {
        let resolverTask = Task.detached(priority: .utility) {
            await BluetoothBatteryResolver().readReport()
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = RefreshRaceGate<BluetoothBatteryReadReport?>(continuation)

                Task {
                    let snapshots = await resolverTask.value
                    await gate.resume(returning: snapshots)
                }

                Task {
                    try? await Task.sleep(for: BatteryRefreshLimits.timeout)
                    resolverTask.cancel()
                    await gate.resume(returning: nil)
                }
            }
        } onCancel: {
            resolverTask.cancel()
        }
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
