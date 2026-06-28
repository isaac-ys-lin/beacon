import CoreBluetooth
import XCTest
@testable import Beacon

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

    func testDisconnectedPairedDeviceKeepsConnectionState() {
        let device = BluetoothBatteryCandidate(
            deviceID: "20-C1-9B-AA-BB-CC",
            displayName: "Magic Mouse",
            transport: .classic,
            batteryPercent: nil,
            kindHint: .mouse,
            connectionState: .disconnected
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.deviceID, "bluetooth-20-C1-9B-AA-BB-CC")
        XCTAssertEqual(snapshot.kind, .mouse)
        XCTAssertNil(snapshot.percent)
        XCTAssertEqual(snapshot.connectionState, .disconnected)
        XCTAssertEqual(snapshot.source, .bluetoothUnsupported)
    }

    func testBLEBatteryServiceClassifiesIPhoneWithProviderMetadata() {
        let device = BluetoothBatteryCandidate(
            deviceID: "16AE09F1-3309-CF7D-793F-80F1EE3B4933",
            displayName: "YiSungiPhone",
            transport: .ble,
            batteryPercent: 80
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.deviceID, "bluetooth-iphone-yisungiphone")
        XCTAssertEqual(snapshot.displayName, "YiSungiPhone")
        XCTAssertEqual(snapshot.kind, .iPhone)
        XCTAssertEqual(snapshot.percent, 80)
        XCTAssertEqual(snapshot.source, .coreBluetooth)
        XCTAssertEqual(snapshot.provider, .coreBluetoothBatteryService)
        XCTAssertEqual(snapshot.readStatus, .reported)
        XCTAssertEqual(snapshot.confidence, .medium)
    }

    func testBLEIPhoneUUIDChurnKeepsStableSnapshotIdentity() {
        let first = BluetoothBatteryResolver.snapshot(
            from: BluetoothBatteryCandidate(
                deviceID: "16AE09F1-3309-CF7D-793F-80F1EE3B4933",
                displayName: "YiSungiPhone",
                transport: .ble,
                batteryPercent: 80
            ),
            now: Date(timeIntervalSince1970: 50)
        )
        let second = BluetoothBatteryResolver.snapshot(
            from: BluetoothBatteryCandidate(
                deviceID: "E845C788-1D87-AE9D-C050-44E65C6807E1",
                displayName: "YiSungiPhone",
                transport: .ble,
                batteryPercent: 79
            ),
            now: Date(timeIntervalSince1970: 70)
        )

        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertEqual(second.deviceID, "bluetooth-iphone-yisungiphone")
    }

    func testResolverReportCarriesProviderDiagnostics() {
        let scanReport = BluetoothCandidateScanReport(
            candidates: [
                BluetoothBatteryCandidate(
                    deviceID: "16AE09F1-3309-CF7D-793F-80F1EE3B4933",
                    displayName: "YiSungiPhone",
                    transport: .ble,
                    batteryPercent: 80
                )
            ],
            attempts: [
                BatteryProviderAttempt(
                    provider: .coreBluetoothBatteryService,
                    status: .reported,
                    candidateCount: 1,
                    message: "Known BLE scan returned 1 battery candidate",
                    attemptedAt: Date(timeIntervalSince1970: 40)
                )
            ]
        )

        let report = BluetoothBatteryResolver.report(from: scanReport, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(report.snapshots.map(\.deviceID), ["bluetooth-iphone-yisungiphone"])
        XCTAssertEqual(report.diagnostics.snapshotCount, 1)
        XCTAssertEqual(report.diagnostics.attempts.count, 1)
        XCTAssertEqual(report.diagnostics.attempts[0].provider, .coreBluetoothBatteryService)
        XCTAssertEqual(report.diagnostics.attempts[0].status, .reported)
        XCTAssertEqual(report.diagnostics.attempts[0].candidateCount, 1)
    }

    func testIPhoneUSBBatteryParserReadsCapacityAndDeviceName() {
        let output = """
        BatteryCurrentCapacity: 77
        BatteryIsCharging: false
        DeviceName: YiSungiPhone
        """

        let reading = IPhoneUSBBatteryProvider.parse(output)

        XCTAssertEqual(reading?.percent, 77)
        XCTAssertEqual(reading?.displayName, "YiSungiPhone")
    }

    func testIPhoneUSBBatteryCandidateCreatesUSBProviderSnapshot() throws {
        let candidate = try XCTUnwrap(
            IPhoneUSBBatteryProvider.candidate(
                from: IPhoneUSBBatteryReading(percent: 77, displayName: "YiSungiPhone")
            )
        )

        let snapshot = BluetoothBatteryResolver.snapshot(
            from: candidate,
            now: Date(timeIntervalSince1970: 70)
        )

        XCTAssertEqual(snapshot.deviceID, "usb-iphone-yisungiphone")
        XCTAssertEqual(snapshot.kind, .iPhone)
        XCTAssertEqual(snapshot.percent, 77)
        XCTAssertEqual(snapshot.source, .ideviceInfo)
        XCTAssertEqual(snapshot.provider, .ideviceInfo)
        XCTAssertEqual(snapshot.confidence, .high)
    }

    func testIPhoneUSBParserSurfacesChargingState() {
        let charging = """
        BatteryCurrentCapacity: 64
        BatteryIsCharging: true
        ExternalConnected: true
        FullyCharged: false
        DeviceName: YiSungiPhone
        """
        XCTAssertEqual(IPhoneUSBBatteryProvider.parse(charging)?.chargeState, .charging)

        let full = """
        BatteryCurrentCapacity: 100
        BatteryIsCharging: false
        ExternalConnected: true
        FullyCharged: true
        DeviceName: YiSungiPhone
        """
        XCTAssertEqual(IPhoneUSBBatteryProvider.parse(full)?.chargeState, .full)

        let unplugged = """
        BatteryCurrentCapacity: 55
        BatteryIsCharging: false
        ExternalConnected: false
        FullyCharged: false
        DeviceName: YiSungiPhone
        """
        XCTAssertEqual(IPhoneUSBBatteryProvider.parse(unplugged)?.chargeState, .unplugged)
    }

    func testChargingCandidateProducesChargingSnapshotForPulse() throws {
        let candidate = try XCTUnwrap(
            IPhoneUSBBatteryProvider.candidate(
                from: IPhoneUSBBatteryReading(percent: 50, displayName: "YiSungiPhone", chargeState: .charging)
            )
        )
        let snapshot = BluetoothBatteryResolver.snapshot(from: candidate, now: Date(timeIntervalSince1970: 70))
        XCTAssertEqual(snapshot.chargeState, .charging)
    }

    func testCollapsingDuplicateIPhonesKeepsBatteryBearingAcrossDifferentNames() {
        let bleIPhone = BluetoothBatteryCandidate(
            deviceID: "ble-uuid",
            displayName: "YiSungiPhone",
            transport: .ble,
            batteryPercent: nil,
            kindHint: .iPhone
        )
        let keyboard = BluetoothBatteryCandidate(
            deviceID: "kbd",
            displayName: "Magic Keyboard",
            transport: .hid,
            batteryPercent: 80,
            kindHint: .keyboard
        )
        let usbIPhone = BluetoothBatteryCandidate(
            deviceID: "usb-iphone-yisung-s-iphone",
            displayName: "YiSung's iPhone",
            transport: .usb,
            batteryPercent: 62,
            kindHint: .iPhone
        )

        let collapsed = BluetoothDeviceScanner.collapsingDuplicateIPhones([bleIPhone, keyboard, usbIPhone])

        let iPhones = collapsed.filter { $0.kindHint == .iPhone }
        XCTAssertEqual(iPhones.count, 1)
        XCTAssertEqual(iPhones.first?.batteryPercent, 62)
        XCTAssertEqual(iPhones.first?.displayName, "YiSung's iPhone")
        XCTAssertEqual(collapsed.contains { $0.kindHint == .keyboard }, true)
    }

    func testBluetoothHIDUsageClassifiesKeychronAsKeyboard() {
        let hint = BluetoothDeviceScanner.hidKindHint(
            name: "Keychron K3 Max",
            transport: "Bluetooth Low Energy",
            primaryUsagePage: 1,
            primaryUsage: 6
        )

        XCTAssertEqual(hint, .keyboard)
    }

    func testUSBKeyboardBacklightDoesNotBecomeBeaconCandidate() {
        let hint = BluetoothDeviceScanner.hidKindHint(
            name: "Keyboard Backlight",
            transport: "USB",
            primaryUsagePage: 65280,
            primaryUsage: 15
        )

        XCTAssertEqual(hint, .keyboard)
        XCTAssertFalse(
            BluetoothDeviceScanner.shouldIncludeHIDCandidate(
                batteryPercent: nil,
                transport: "USB",
                kindHint: hint
            )
        )
    }

    func testAppleDeviceManagementBatteryPercentCreatesMagicKeyboardCandidate() throws {
        let candidate = try XCTUnwrap(
            BluetoothDeviceScanner.appleDeviceManagementCandidate(
                from: [
                    "Product": "吳郁庭 Fendy 的 Magic Keyboard",
                    "Transport": "Bluetooth Low Energy",
                    "DeviceAddress": "AA:BB:CC:DD:EE:FF",
                    "BatteryPercent": 89,
                    "PrimaryUsagePage": 1,
                    "PrimaryUsage": 6
                ]
            )
        )

        XCTAssertEqual(candidate.deviceID, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(candidate.displayName, "吳郁庭 Fendy 的 Magic Keyboard")
        XCTAssertEqual(candidate.batteryPercent, 89)
        XCTAssertEqual(candidate.kindHint, .keyboard)

        let snapshot = BluetoothBatteryResolver.snapshot(
            from: candidate,
            now: Date(timeIntervalSince1970: 50)
        )
        XCTAssertEqual(snapshot.percent, 89)
        XCTAssertEqual(snapshot.kind, .keyboard)
        XCTAssertEqual(snapshot.source, .ioRegistry)
    }

    func testAppleDeviceManagementFindsNestedBatteryPercent() throws {
        let candidate = try XCTUnwrap(
            BluetoothDeviceScanner.appleDeviceManagementCandidate(
                from: [
                    "Product": "吳郁庭 Fendy 的 Magic Trackpad",
                    "Transport": "Bluetooth",
                    "SerialNumber": "trackpad-serial",
                    "PrimaryUsagePage": 1,
                    "PrimaryUsage": 5,
                    "HIDEventServiceProperties": [
                        "DeviceManagement": [
                            "BatteryLevel": "88%"
                        ]
                    ]
                ]
            )
        )

        XCTAssertEqual(candidate.displayName, "吳郁庭 Fendy 的 Magic Trackpad")
        XCTAssertEqual(candidate.batteryPercent, 88)
        XCTAssertEqual(candidate.kindHint, .trackpad)
    }

    func testAppleDeviceManagementIgnoresDescriptorBatteryLevelMetadata() throws {
        let candidate = try XCTUnwrap(
            BluetoothDeviceScanner.appleDeviceManagementCandidate(
                from: [
                    "Product": "吳郁庭 Fendy 的 Magic Keyboard",
                    "Transport": "Bluetooth Low Energy",
                    "DeviceAddress": "AA:BB:CC:DD:EE:FF",
                    "PrimaryUsagePage": 1,
                    "PrimaryUsage": 6,
                    "Elements": [
                        [
                            "Name": "Battery Strength",
                            "BatteryLevel": 6
                        ]
                    ]
                ]
            )
        )

        XCTAssertNil(candidate.batteryPercent)
        XCTAssertEqual(candidate.kindHint, .keyboard)
    }

    func testAppleDeviceManagementSkipsBuiltInKeyboardTrackpad() {
        let candidate = BluetoothDeviceScanner.appleDeviceManagementCandidate(
            from: [
                "Product": "Apple Internal Keyboard / Trackpad",
                "Transport": "FIFO",
                "Built-In": true,
                "BatteryPercent": 100,
                "PrimaryUsagePage": 65280,
                "PrimaryUsage": 11
            ]
        )

        XCTAssertNil(candidate)
    }

    func testBLEBatteryReadPolicyScansKnownPeripheralsWhenPoweredOn() {
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .unknown), .wait)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .resetting), .wait)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .poweredOn), .scanKnownPeripherals)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .poweredOff), .finish)
        XCTAssertEqual(BLEBatteryReadStatePolicy.action(for: .unauthorized), .finish)
    }

    func testBLEBatteryMergePreservesHIDDisplayNameForGenericPeripheralName() {
        let hidCandidate = BluetoothBatteryCandidate(
            deviceID: "9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
            displayName: "Keychron K3 Max",
            transport: .hid,
            batteryPercent: nil,
            kindHint: .keyboard
        )
        let bleCandidate = BluetoothBatteryCandidate(
            deviceID: "9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
            displayName: "Bluetooth Device",
            transport: .ble,
            batteryPercent: 95
        )

        let merged = BluetoothDeviceScanner.mergedCandidate(existing: hidCandidate, with: bleCandidate)

        XCTAssertEqual(merged.displayName, "Keychron K3 Max")
        XCTAssertEqual(merged.kindHint, .keyboard)
        XCTAssertEqual(merged.batteryPercent, 95)
        XCTAssertEqual(merged.transport, .ble)
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
