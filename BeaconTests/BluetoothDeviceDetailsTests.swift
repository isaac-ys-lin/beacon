import XCTest
@testable import Beacon

@MainActor
final class BluetoothDeviceDetailsTests: XCTestCase {
    func testParsesFirmwareForConnectedAndPairedDevices() throws {
        let json = """
        {"SPBluetoothDataType":[{
          "device_connected":[{"Keychron K3 Max":{"device_address":"F4:EE:25:01:02:03","device_firmwareVersion":"0.2.1","device_productID":"0x0A30","device_vendorID":"0x3434"}}],
          "device_not_connected":[{"AirPods":{"device_address":"AC:90:85:AA:BB:CC","device_firmwareVersion":"9B47"}},
                                  {"No Address":{"device_firmwareVersion":"1.0"}}]
        }]}
        """
        let details = BluetoothDeviceDetailsStore.parse(systemProfilerJSON: Data(json.utf8))

        XCTAssertEqual(details["f4:ee:25:01:02:03"]?.firmwareVersion, "0.2.1")
        XCTAssertEqual(details["f4:ee:25:01:02:03"]?.productID, "0x0A30")
        XCTAssertEqual(details["ac:90:85:aa:bb:cc"]?.firmwareVersion, "9B47")
        XCTAssertEqual(details.count, 2)
    }

    func testLooksUpByBeaconDeviceIDIncludingAirPodsComponents() {
        let store = BluetoothDeviceDetailsStore()
        store.replace(with: ["ac:90:85:aa:bb:cc": BluetoothDeviceDetails(firmwareVersion: "9B47", vendorID: nil, productID: nil)])

        XCTAssertEqual(store.details(forDeviceID: "bluetooth-AC:90:85:AA:BB:CC")?.firmwareVersion, "9B47")
        XCTAssertNil(store.details(forDeviceID: "trusted-iphone-0000"))
    }
}
