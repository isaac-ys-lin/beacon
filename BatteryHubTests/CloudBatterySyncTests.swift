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

    func testCompanionSyncDiagnosticsReportsLatestIPhoneAndWatchSnapshots() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let snapshots = [
            BatterySnapshot(
                deviceID: "iphone-old",
                displayName: "Yi Sung iPhone",
                kind: .iPhone,
                percent: 40,
                chargeState: .unplugged,
                source: .iCloud,
                updatedAt: older
            ),
            BatterySnapshot(
                deviceID: "watch",
                displayName: "Yi Sung Apple Watch",
                kind: .appleWatch,
                percent: 82,
                chargeState: .charging,
                source: .watchConnectivity,
                updatedAt: older
            ),
            BatterySnapshot(
                deviceID: "iphone-new",
                displayName: "Yi Sung iPhone",
                kind: .iPhone,
                percent: 73,
                chargeState: .unplugged,
                source: .iCloud,
                updatedAt: newer
            )
        ]
        let envelope = SyncEnvelope(snapshots: snapshots, publishedAt: newer)

        let diagnostics = CompanionSyncDiagnostics(
            snapshots: snapshots,
            envelope: envelope
        )

        XCTAssertEqual(diagnostics.envelopePublishedAt, newer)
        XCTAssertTrue(diagnostics.iPhone.hasReport)
        XCTAssertEqual(diagnostics.iPhone.percent, 73)
        XCTAssertEqual(diagnostics.iPhone.updatedAt, newer)
        XCTAssertTrue(diagnostics.appleWatch.hasReport)
        XCTAssertEqual(diagnostics.appleWatch.percent, 82)
        XCTAssertEqual(diagnostics.appleWatch.source, .watchConnectivity)
    }

    func testCompanionSyncDiagnosticsKeepsLoadErrorWhenNoReportsArrive() {
        let diagnostics = CompanionSyncDiagnostics(
            snapshots: [],
            loadErrorDescription: "Missing entitlement"
        )

        XCTAssertEqual(diagnostics.loadErrorDescription, "Missing entitlement")
        XCTAssertFalse(diagnostics.iPhone.hasReport)
        XCTAssertFalse(diagnostics.appleWatch.hasReport)
        XCTAssertNil(diagnostics.envelopePublishedAt)
    }
}
