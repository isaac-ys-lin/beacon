import Foundation
import IOKit.ps

public struct MacPowerSourceReader {
    public init() {}

    public func read(now: Date = Date()) -> [BatterySnapshot] {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return []
        }

        return sources.compactMap { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                return nil
            }
            return Self.snapshot(from: description, now: now)
        }
    }

    static func snapshot(from description: [String: Any], now: Date) -> BatterySnapshot? {
        guard
            let current = description[kIOPSCurrentCapacityKey as String] as? Int,
            let max = description[kIOPSMaxCapacityKey as String] as? Int,
            max > 0
        else {
            return nil
        }

        let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) == true
        let percent = Swift.max(0, Swift.min(100, Int((Double(current) / Double(max) * 100).rounded())))

        return BatterySnapshot(
            deviceID: "macbook",
            displayName: "MacBook",
            kind: .macBook,
            percent: percent,
            chargeState: isCharging ? .charging : .unplugged,
            source: .macPowerSource,
            updatedAt: now
        )
    }
}
