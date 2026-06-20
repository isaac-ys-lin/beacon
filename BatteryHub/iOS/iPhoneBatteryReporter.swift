import Foundation
import UIKit

public struct IPhoneBatteryPublishResult: Equatable, Sendable {
    public let snapshot: BatterySnapshot
    public let watchSnapshotCount: Int
    public let synchronizeAccepted: Bool
}

@MainActor
public final class iPhoneBatteryReporter {
    private let sync: CloudBatterySync

    public init(sync: CloudBatterySync = CloudBatterySync()) {
        self.sync = sync
    }

    @discardableResult
    public func publishCurrentBattery(
        now: Date = Date(),
        watchSnapshots: [BatterySnapshot] = []
    ) throws -> IPhoneBatteryPublishResult {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let percent = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : nil

        let snapshot = BatterySnapshot(
            deviceID: "iphone",
            displayName: UIDevice.current.name,
            kind: .iPhone,
            percent: percent,
            chargeState: Self.chargeState(from: UIDevice.current.batteryState),
            source: .iCloud,
            updatedAt: now
        )

        let synchronizeAccepted = try sync.publish([snapshot] + watchSnapshots, now: now)
        return IPhoneBatteryPublishResult(
            snapshot: snapshot,
            watchSnapshotCount: watchSnapshots.count,
            synchronizeAccepted: synchronizeAccepted
        )
    }

    private static func chargeState(from state: UIDevice.BatteryState) -> ChargeState {
        switch state {
        case .unknown: return .unknown
        case .unplugged: return .unplugged
        case .charging: return .charging
        case .full: return .full
        @unknown default: return .unknown
        }
    }
}
