import XCTest
@testable import BatteryHub

final class CloudBatterySyncTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let envelope = SyncEnvelope(
            schemaVersion: 1,
            snapshots: [
                BatterySnapshot(
                    deviceID: "iphone",
                    displayName: "Isaac's iPhone",
                    kind: .iPhone,
                    percent: 75,
                    chargeState: .charging,
                    source: .iCloud,
                    updatedAt: Date(timeIntervalSince1970: 123)
                )
            ],
            publishedAt: Date(timeIntervalSince1970: 456)
        )

        let data = try JSONEncoder.batteryHub.encode(envelope)
        let decoded = try JSONDecoder.batteryHub.decode(SyncEnvelope.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.snapshots[0].percent, 75)
        XCTAssertEqual(decoded.publishedAt, Date(timeIntervalSince1970: 456))
    }
}
