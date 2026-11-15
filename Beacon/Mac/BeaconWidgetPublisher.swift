import Foundation
import WidgetKit

/// Shares the dashboard's battery list with the WidgetKit extension.
enum BeaconWidgetPublisher {
    static func payload(from items: [DeviceListItem], now: Date = Date()) -> BeaconWidgetPayload {
        let devices = items.compactMap { item -> BeaconWidgetDevice? in
            switch item {
            case .device(let decorated):
                guard isDashboardVisibleItem(item), let percent = decorated.snapshot.percent else { return nil }
                return BeaconWidgetDevice(
                    id: item.id,
                    name: item.displayName,
                    kind: widgetKind(for: item.kind),
                    percent: percent,
                    isCharging: decorated.snapshot.chargeState == .charging
                )
            case .airPods(_, _, let components):
                let active = activeAirPodsComponents(components).filter { $0.connectionState == .connected }
                // Earbuds first: the case level is not what the listener runs out of.
                let buds = active.filter { $0.slot != .case }.compactMap(\.percent)
                guard let percent = buds.min() ?? active.compactMap(\.percent).min() else { return nil }
                return BeaconWidgetDevice(
                    id: item.id,
                    name: item.displayName,
                    kind: .headphones,
                    percent: percent,
                    isCharging: active.contains { $0.slot != .case && $0.chargeState == .charging }
                )
            }
        }
        return BeaconWidgetPayload(devices: devices, updatedAt: now)
    }

    static func publish(_ items: [DeviceListItem]) {
        if BeaconWidgetStore.save(payload(from: items)) {
            WidgetCenter.shared.reloadTimelines(ofKind: BeaconWidgetStore.widgetKind)
        }
    }

    private static func widgetKind(for kind: DeviceKind) -> BeaconWidgetDevice.Kind {
        switch kind {
        case .macBook: return .mac
        case .iPhone: return .iPhone
        case .appleWatch: return .watch
        case .airPods: return .headphones
        case .keyboard: return .keyboard
        case .mouse: return .mouse
        case .trackpad: return .trackpad
        case .bluetoothPeripheral: return .other
        }
    }
}
