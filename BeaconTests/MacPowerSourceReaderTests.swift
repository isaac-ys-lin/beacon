import XCTest
@testable import Beacon

final class MacPowerSourceReaderTests: XCTestCase {
    func testSnapshotFromPowerSourceDictionary() {
        let dictionary: [String: Any] = [
            "Name": "InternalBattery-0",
            "Current Capacity": 81,
            "Max Capacity": 100,
            "Is Charging": true
        ]

        let snapshot = MacPowerSourceReader.snapshot(from: dictionary, now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(snapshot?.kind, .macBook)
        XCTAssertEqual(snapshot?.percent, 81)
        XCTAssertEqual(snapshot?.chargeState, .charging)
        XCTAssertEqual(snapshot?.source, .macPowerSource)
    }
}
