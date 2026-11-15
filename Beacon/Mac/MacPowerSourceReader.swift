import Foundation
import IOKit.ps

/// Reads this Mac's internal battery through the public IOPowerSources API.
/// Desktop Macs have no internal battery and produce no snapshot.
enum MacPowerSourceReader {
    static let deviceID = "this-mac"
    static let showsThisMacDefaultsKey = "Beacon.dashboard.showsThisMac"

    static func readSnapshot(now: Date = Date()) -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let descriptions = list.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return snapshot(from: descriptions, macName: Host.current().localizedName ?? "This Mac", now: now)
    }

    static func snapshot(from descriptions: [[String: Any]], macName: String, now: Date) -> BatterySnapshot? {
        guard let battery = descriptions.first(where: {
            ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        }),
            let current = battery[kIOPSCurrentCapacityKey] as? Int,
            let maximum = battery[kIOPSMaxCapacityKey] as? Int,
            maximum > 0
        else { return nil }

        let percent = Swift.max(0, Swift.min(100, Int((Double(current) / Double(maximum) * 100).rounded())))
        let onAC = (battery[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let isCharging = battery[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = battery[kIOPSIsChargedKey] as? Bool ?? false
        let chargeState: ChargeState = if isCharging {
            .charging
        } else if isCharged {
            .full
        } else if onAC {
            .unknown
        } else {
            .unplugged
        }

        return BatterySnapshot(
            deviceID: deviceID,
            displayName: macName,
            kind: .macBook,
            percent: percent,
            chargeState: chargeState,
            connectionState: .connected,
            source: .macPowerSource,
            provider: .macPowerSource,
            readStatus: .reported,
            identityStrength: .strong,
            updatedAt: now
        )
    }
}
