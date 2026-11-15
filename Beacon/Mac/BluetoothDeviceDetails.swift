import Foundation

/// Static facts macOS reports for a paired Bluetooth device (System Information).
struct BluetoothDeviceDetails: Equatable, Sendable {
    let firmwareVersion: String?
    let vendorID: String?
    let productID: String?
}

/// Latest details keyed by lower-case colon address (`aa:bb:cc:dd:ee:ff`),
/// refreshed from the same `system_profiler` read that provides battery levels.
@MainActor
final class BluetoothDeviceDetailsStore: ObservableObject {
    static let shared = BluetoothDeviceDetailsStore()
    @Published private(set) var detailsByAddress: [String: BluetoothDeviceDetails] = [:]

    func replace(with details: [String: BluetoothDeviceDetails]) {
        guard !details.isEmpty, details != detailsByAddress else { return }
        detailsByAddress = details
    }

    func details(forDeviceID deviceID: String) -> BluetoothDeviceDetails? {
        BluetoothDeviceControlSupport.normalizedAddress(from: deviceID).flatMap { detailsByAddress[$0] }
    }

    nonisolated static func parse(systemProfilerJSON data: Data) -> [String: BluetoothDeviceDetails] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [:] }
        var result: [String: BluetoothDeviceDetails] = [:]
        for section in sections {
            let entries = ((section["device_connected"] as? [[String: Any]]) ?? [])
                + ((section["device_not_connected"] as? [[String: Any]]) ?? [])
            for entry in entries {
                for (_, value) in entry {
                    guard let device = value as? [String: Any],
                          let rawAddress = device["device_address"] as? String,
                          let address = BluetoothDeviceControlSupport.normalizedAddress(from: rawAddress)
                    else { continue }
                    let firmware = (device["device_firmwareVersion"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    result[address] = BluetoothDeviceDetails(
                        firmwareVersion: firmware?.isEmpty == false ? firmware : nil,
                        vendorID: device["device_vendorID"] as? String,
                        productID: device["device_productID"] as? String
                    )
                }
            }
        }
        return result
    }
}
