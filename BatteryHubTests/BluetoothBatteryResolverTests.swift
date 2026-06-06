import XCTest
@testable import BatteryHub

final class BluetoothBatteryResolverTests: XCTestCase {
    func testIORegistryBatteryPercentCreatesKeyboardSnapshot() {
        let device = BluetoothBatteryCandidate(
            deviceID: "apple-keyboard",
            displayName: "Magic Keyboard",
            transport: .hid,
            batteryPercent: 64
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.displayName, "Magic Keyboard")
        XCTAssertEqual(snapshot.kind, .keyboard)
        XCTAssertEqual(snapshot.percent, 64)
        XCTAssertEqual(snapshot.source, .ioRegistry)
    }

    func testDeviceWithoutBatteryIsVisibleAsUnsupported() {
        let device = BluetoothBatteryCandidate(
            deviceID: "speaker",
            displayName: "Kitchen Speaker",
            transport: .unknown,
            batteryPercent: nil
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.percent, nil)
        XCTAssertEqual(snapshot.source, .bluetoothUnsupported)
    }

    func testSystemProfilerParserKeepsOnlyConnectedBatteryDevices() throws {
        let json = """
        {
          "SPBluetoothDataType" : [
            {
              "device_connected" : [
                {
                  "Keychron K3 Max" : {
                    "device_address" : "D1:B3:88:E2:67:CB",
                    "device_batteryLevelMain" : "100%",
                    "device_minorType" : "Keyboard"
                  }
                },
                {
                  "Kitchen" : {
                    "device_address" : "40:ED:CF:4E:B5:6A"
                  }
                }
              ],
              "device_not_connected" : [
                {
                  "Yi Sung’s AirPods Pro" : {
                    "device_address" : "7C:F3:4D:74:56:78",
                    "device_batteryLevelLeft" : "100%",
                    "device_batteryLevelRight" : "92%"
                  }
                }
              ]
            }
          ]
        }
        """

        let candidates = BluetoothDeviceScanner.parseSystemProfilerBluetoothData(Data(json.utf8))

        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.displayName, "Keychron K3 Max")
        XCTAssertEqual(candidate.batteryPercent, 100)

        let snapshot = BluetoothBatteryResolver.snapshot(
            from: candidate,
            now: Date(timeIntervalSince1970: 50)
        )
        XCTAssertEqual(snapshot.kind, .keyboard)
        XCTAssertEqual(snapshot.source, .systemProfiler)
    }
}
