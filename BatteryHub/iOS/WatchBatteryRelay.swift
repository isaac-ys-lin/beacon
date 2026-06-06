import Foundation
import WatchConnectivity

@MainActor
public final class WatchBatteryRelay: NSObject, @preconcurrency WCSessionDelegate {
    private let reporter: iPhoneBatteryReporter
    private var latestWatchSnapshots: [BatterySnapshot] = []

    public init(reporter: iPhoneBatteryReporter = iPhoneBatteryReporter()) {
        self.reporter = reporter
        super.init()
    }

    public func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard
            let data = userInfo["snapshot"] as? Data,
            let snapshot = try? JSONDecoder.batteryHub.decode(BatterySnapshot.self, from: data)
        else {
            return
        }
        let watchSnapshots = [snapshot]
        latestWatchSnapshots = watchSnapshots
        try? reporter.publishCurrentBattery(watchSnapshots: watchSnapshots)
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
