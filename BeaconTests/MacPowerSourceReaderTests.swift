import IOKit.ps
import XCTest
@testable import Beacon

final class MacPowerSourceReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testInternalBatteryOnBatteryPowerIsUnplugged() {
        let snapshot = MacPowerSourceReader.snapshot(
            from: [[
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSCurrentCapacityKey: 57,
                kIOPSMaxCapacityKey: 100,
                kIOPSIsChargingKey: false,
                kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
            ]],
            macName: "Isaac's MacBook Air",
            now: now
        )

        XCTAssertEqual(snapshot?.deviceID, MacPowerSourceReader.deviceID)
        XCTAssertEqual(snapshot?.kind, .macBook)
        XCTAssertEqual(snapshot?.percent, 57)
        XCTAssertEqual(snapshot?.chargeState, .unplugged)
        XCTAssertEqual(snapshot?.source, .macPowerSource)
        XCTAssertEqual(snapshot?.displayName, "Isaac's MacBook Air")
    }

    func testChargingAndChargedStates() {
        let charging = MacPowerSourceReader.snapshot(from: [[
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ]], macName: "Mac", now: now)
        let charged = MacPowerSourceReader.snapshot(from: [[
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 100, kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: false, kIOPSIsChargedKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ]], macName: "Mac", now: now)
        // Optimised charging can hold at 80% on AC without charging.
        let held = MacPowerSourceReader.snapshot(from: [[
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: false, kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ]], macName: "Mac", now: now)

        XCTAssertEqual(charging?.chargeState, .charging)
        XCTAssertEqual(charged?.chargeState, .full)
        XCTAssertEqual(held?.chargeState, .unknown, "On AC but not charging is neither charging nor unplugged")
    }

    func testCapacityIsScaledWhenMaxIsNotHundred() {
        let snapshot = MacPowerSourceReader.snapshot(from: [[
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 2_500, kIOPSMaxCapacityKey: 5_000,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        ]], macName: "Mac", now: now)
        XCTAssertEqual(snapshot?.percent, 50)
    }

    func testDesktopMacWithoutInternalBatteryHasNoSnapshot() {
        XCTAssertNil(MacPowerSourceReader.snapshot(from: [], macName: "Mac mini", now: now))
        XCTAssertNil(MacPowerSourceReader.snapshot(from: [[
            kIOPSTypeKey: "UPS",
            kIOPSCurrentCapacityKey: 90, kIOPSMaxCapacityKey: 100,
        ]], macName: "Mac Studio", now: now))
    }

    func testMenuBarLowestIgnoresThisMac() {
        let mac = DecoratedBatterySnapshot(snapshot: BatterySnapshot(
            deviceID: MacPowerSourceReader.deviceID, displayName: "Mac", kind: .macBook,
            percent: 5, chargeState: .unplugged, source: .macPowerSource, updatedAt: Date()
        ), freshness: .fresh)
        let mouse = DecoratedBatterySnapshot(snapshot: BatterySnapshot(
            deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse,
            percent: 60, chargeState: .unknown, source: .ioRegistry, updatedAt: Date()
        ), freshness: .fresh)

        XCTAssertEqual(MenuBarBatteryFormatter.menuBarText(for: [mac, mouse]), "60%")
    }
}
