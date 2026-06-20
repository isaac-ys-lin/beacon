import Foundation
import os
import WatchConnectivity

@MainActor
public final class WatchBatteryRelay: NSObject, WCSessionDelegate {
    private let reporter: iPhoneBatteryReporter
    private let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.ios", category: "watch-relay")

    public init(reporter: iPhoneBatteryReporter) {
        self.reporter = reporter
        super.init()
    }

    public func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard
            let data = userInfo["snapshot"] as? Data,
            let snapshot = try? JSONDecoder.batteryHub.decode(BatterySnapshot.self, from: data)
        else {
            return
        }
        Task { @MainActor in
            self.relayWatchSnapshot(snapshot)
        }
    }

    private func relayWatchSnapshot(_ snapshot: BatterySnapshot) {
        let watchSnapshots = [snapshot]
        do {
            let result = try reporter.publishCurrentBattery(watchSnapshots: watchSnapshots)
            logger.info(
                "Relayed watch battery snapshot percent=\(snapshot.percent ?? -1) iPhonePercent=\(result.snapshot.percent ?? -1) syncAccepted=\(result.synchronizeAccepted)"
            )
        } catch {
            logger.error("Failed to relay watch battery snapshot: \(error.localizedDescription)")
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
