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

    func testSystemProfilerParserSplitsConnectedAirPodsBatteryComponents() {
        let json = """
        {
          "SPBluetoothDataType" : [
            {
              "device_connected" : [
                {
                  "Yi Sung’s AirPods Pro" : {
                    "device_address" : "7C:F3:4D:74:56:78",
                    "device_batteryLevelCase" : "70%",
                    "device_batteryLevelLeft" : "100%",
                    "device_batteryLevelRight" : "92%",
                    "device_minorType" : "Headphones"
                  }
                }
              ],
              "device_not_connected" : [
                {
                  "Old AirPods" : {
                    "device_address" : "AA:BB:CC:DD:EE:FF",
                    "device_batteryLevelCase" : "10%",
                    "device_batteryLevelLeft" : "11%",
                    "device_batteryLevelRight" : "12%",
                    "device_minorType" : "Headphones"
                  }
                }
              ]
            }
          ]
        }
        """

        let candidates = BluetoothDeviceScanner.parseSystemProfilerBluetoothData(Data(json.utf8))

        XCTAssertEqual(candidates.map(\.displayName), [
            "Yi Sung’s AirPods Pro Case",
            "Yi Sung’s AirPods Pro Left",
            "Yi Sung’s AirPods Pro Right"
        ])
        XCTAssertEqual(candidates.map(\.batteryPercent), [70, 100, 92])
        XCTAssertEqual(
            candidates.map { String(describing: BluetoothBatteryResolver.snapshot(from: $0, now: Date(timeIntervalSince1970: 50)).kind) },
            ["airPods", "airPods", "airPods"]
        )
    }

    func testSystemProfilerParserClassifiesMagicMouseTrackpadAndKeyboard() {
        let json = """
        {
          "SPBluetoothDataType" : [
            {
              "device_connected" : [
                {
                  "Magic Mouse" : {
                    "device_address" : "11:22:33:44:55:66",
                    "device_batteryLevelMain" : "50%",
                    "device_minorType" : "Mouse"
                  }
                },
                {
                  "Magic Trackpad" : {
                    "device_address" : "22:33:44:55:66:77",
                    "device_batteryLevelMain" : "90%",
                    "device_minorType" : "Trackpad"
                  }
                },
                {
                  "Magic Keyboard" : {
                    "device_address" : "33:44:55:66:77:88",
                    "device_batteryLevelMain" : "42%",
                    "device_minorType" : "Keyboard"
                  }
                }
              ]
            }
          ]
        }
        """

        let candidates = BluetoothDeviceScanner.parseSystemProfilerBluetoothData(Data(json.utf8))
        let kinds = candidates.map {
            String(describing: BluetoothBatteryResolver.snapshot(from: $0, now: Date(timeIntervalSince1970: 50)).kind)
        }

        XCTAssertEqual(candidates.map(\.displayName), ["Magic Mouse", "Magic Trackpad", "Magic Keyboard"])
        XCTAssertEqual(kinds, ["mouse", "trackpad", "keyboard"])
    }
}
