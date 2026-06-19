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
        XCTAssertEqual(decoded.snapshots[0].connectionState, .connected)
        XCTAssertEqual(decoded.publishedAt, Date(timeIntervalSince1970: 456))
    }

    func testEnvelopeDecodesSnapshotsWithoutConnectionState() throws {
        let json = """
        {
          "publishedAt" : "1970-01-01T00:07:36Z",
          "schemaVersion" : 1,
          "snapshots" : [
            {
              "chargeState" : "charging",
              "deviceID" : "iphone",
              "displayName" : "Isaac's iPhone",
              "kind" : "iPhone",
              "percent" : 75,
              "source" : "iCloud",
              "updatedAt" : "1970-01-01T00:02:03Z"
            }
          ]
        }
        """

        let decoded = try JSONDecoder.batteryHub.decode(SyncEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.snapshots[0].connectionState, .connected)
        XCTAssertEqual(decoded.snapshots[0].percent, 75)
    }
}
