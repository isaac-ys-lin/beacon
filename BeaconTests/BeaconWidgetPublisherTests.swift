import XCTest
@testable import Beacon

final class BeaconWidgetPublisherTests: XCTestCase {
    func testPayloadUsesVisibleReportedDevicesAndLowestEarbud() {
        let now = Date()
        let keyboard = DecoratedBatterySnapshot(snapshot: BatterySnapshot(
            deviceID: "bluetooth-aa:bb:cc:dd:ee:01", displayName: "Magic Keyboard", kind: .keyboard,
            percent: 64, chargeState: .charging, source: .ioRegistry, updatedAt: now
        ), freshness: .fresh)
        let unreported = DecoratedBatterySnapshot(snapshot: BatterySnapshot(
            deviceID: "bluetooth-aa:bb:cc:dd:ee:02", displayName: "Keychron", kind: .keyboard,
            percent: nil, chargeState: .unknown, source: .bluetoothUnsupported, updatedAt: now
        ), freshness: .fresh)
        let airPods = DeviceListItem.airPods(name: "AirPods Pro", id: "airpods", components: [
            AirPodsComponent(slot: .left, percent: 80, chargeState: .unplugged, freshness: .fresh, connectionState: .connected, updatedAt: now),
            AirPodsComponent(slot: .right, percent: 72, chargeState: .unplugged, freshness: .fresh, connectionState: .connected, updatedAt: now),
            AirPodsComponent(slot: .case, percent: 30, chargeState: .unplugged, freshness: .fresh, connectionState: .connected, updatedAt: now),
        ])

        let payload = BeaconWidgetPublisher.payload(
            from: [.device(keyboard), .device(unreported), airPods], now: now
        )

        XCTAssertEqual(payload.devices.map(\.name), ["Magic Keyboard", "AirPods Pro"])
        XCTAssertEqual(payload.devices.first?.isCharging, true)
        XCTAssertEqual(payload.devices.last?.percent, 72)
        XCTAssertEqual(payload.devices.last?.kind, .headphones)
    }
}
