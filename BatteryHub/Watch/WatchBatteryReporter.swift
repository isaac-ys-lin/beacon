import Foundation
import WatchConnectivity
import WatchKit

public final class WatchBatteryReporter: NSObject, WCSessionDelegate {
    public override init() {
        super.init()
    }

    public func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func sendCurrentBattery(now: Date = Date()) {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let rawLevel = WKInterfaceDevice.current().batteryLevel
        let percent = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : nil

        let snapshot = BatterySnapshot(
            deviceID: "apple-watch",
            displayName: WKInterfaceDevice.current().name,
            kind: .appleWatch,
            percent: percent,
            chargeState: chargeState(from: WKInterfaceDevice.current().batteryState),
            source: .watchConnectivity,
            updatedAt: now
        )

        guard let data = try? JSONEncoder.batteryHub.encode(snapshot) else {
            return
        }
        WCSession.default.transferUserInfo(["snapshot": data])
    }

    private func chargeState(from state: WKInterfaceDeviceBatteryState) -> ChargeState {
        switch state {
        case .unknown: return .unknown
        case .unplugged: return .unplugged
        case .charging: return .charging
        case .full: return .full
        @unknown default: return .unknown
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
}
