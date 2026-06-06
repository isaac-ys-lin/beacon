import Foundation
@preconcurrency import CoreBluetooth
import IOBluetooth
import IOKit
import os

public struct BluetoothDeviceScanner {
    private static let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "bluetooth")

    public init() {}

    @MainActor
    public func connectedCandidates() async -> [BluetoothBatteryCandidate] {
        let hid = readHIDBatteryCandidates()
        var candidates = hid
        let knownIDs = Set(candidates.map(\.deviceID))
        let classic = readConnectedIOBluetoothDevices().filter { !knownIDs.contains($0.deviceID) }
        candidates.append(contentsOf: classic)

        let profiler = await Self.readSystemProfilerBatteryCandidates()
        Self.logger.info("system_profiler returned \(profiler.count) battery candidates")
        for candidate in profiler {
            candidates.upsert(candidate)
        }

        if CBCentralManager.authorization == .allowedAlways {
            let ble = await BLEBatteryServiceReader().read(timeout: .seconds(2))
            Self.logger.info("BLE scan returned \(ble.count) battery candidates")
            for candidate in ble {
                candidates.upsert(candidate)
            }
        } else {
            Self.logger.info("BLE scan skipped because CoreBluetooth is not authorized")
        }
        return candidates
    }

    private func readConnectedIOBluetoothDevices() -> [BluetoothBatteryCandidate] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return devices.compactMap { device -> BluetoothBatteryCandidate? in
            guard device.isConnected() else { return nil }
            let name = device.nameOrAddress ?? "Bluetooth Device"
            let address = device.addressString ?? name
            return BluetoothBatteryCandidate(
                deviceID: address,
                displayName: name,
                transport: .classic,
                batteryPercent: nil
            )
        }
    }

    private func readHIDBatteryCandidates() -> [BluetoothBatteryCandidate] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [BluetoothBatteryCandidate] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            let name = property("Product", service: service) ?? property("ProductID", service: service) ?? "Bluetooth Device"
            let id = property("SerialNumber", service: service) ?? name
            let percent = intProperty("BatteryPercent", service: service)

            if percent != nil || name.localizedCaseInsensitiveContains("keyboard") {
                results.append(
                    BluetoothBatteryCandidate(
                        deviceID: id,
                        displayName: name,
                        transport: .hid,
                        batteryPercent: percent
                    )
                )
            }
        }
        return results
    }

    private static func readSystemProfilerBatteryCandidates() async -> [BluetoothBatteryCandidate] {
        await Task.detached(priority: .utility) {
            Self.systemProfilerBatteryCandidates()
        }.value
    }

    private static func systemProfilerBatteryCandidates() -> [BluetoothBatteryCandidate] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return parseSystemProfilerBluetoothData(data)
    }

    static func parseSystemProfilerBluetoothData(_ data: Data) -> [BluetoothBatteryCandidate] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else {
            return []
        }

        return sections.flatMap { section -> [BluetoothBatteryCandidate] in
            guard let connected = section["device_connected"] as? [[String: Any]] else {
                return []
            }

            return connected.flatMap { entry -> [BluetoothBatteryCandidate] in
                entry.compactMap { name, value in
                    guard
                        let device = value as? [String: Any],
                        let percent = batteryPercent(from: device)
                    else {
                        return nil
                    }

                    let address = stringValue(device["device_address"]) ?? name
                    let minorType = stringValue(device["device_minorType"]) ?? ""
                    let kindHint: DeviceKind? = minorType.localizedCaseInsensitiveContains("keyboard") ? .keyboard : nil

                    return BluetoothBatteryCandidate(
                        deviceID: address,
                        displayName: name,
                        transport: .systemProfiler,
                        batteryPercent: percent,
                        kindHint: kindHint
                    )
                }
            }
        }
    }

    private static func batteryPercent(from device: [String: Any]) -> Int? {
        let percents = device.compactMap { key, value -> Int? in
            guard key.hasPrefix("device_batteryLevel") else { return nil }
            return percentageValue(value)
        }
        return percents.min()
    }

    private static func percentageValue(_ value: Any) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }

        guard let string = stringValue(value) else {
            return nil
        }

        let digits = string.trimmingCharacters(in: CharacterSet(charactersIn: "%").union(.whitespacesAndNewlines))
        return Int(digits)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func property(_ key: String, service: io_object_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    private func intProperty(_ key: String, service: io_object_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }
}

private extension Array where Element == BluetoothBatteryCandidate {
    mutating func upsert(_ candidate: BluetoothBatteryCandidate) {
        if let index = firstIndex(where: { $0.deviceID == candidate.deviceID || $0.displayName.normalizedDeviceName == candidate.displayName.normalizedDeviceName }) {
            if candidate.batteryPercent != nil || self[index].batteryPercent == nil {
                self[index] = candidate
            }
        } else {
            append(candidate)
        }
    }
}

private extension String {
    var normalizedDeviceName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
private final class BLEBatteryServiceReader: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var continuation: CheckedContinuation<[BluetoothBatteryCandidate], Never>?
    private var candidates: [UUID: BluetoothBatteryCandidate] = [:]
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var timeoutTask: Task<Void, Never>?

    func read(timeout: Duration = .seconds(4)) async -> [BluetoothBatteryCandidate] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.central = CBCentralManager(delegate: self, queue: nil)
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish()
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            finish()
            return
        }

        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) {
            inspect(peripheral)
        }

        central.scanForPeripherals(
            withServices: [Self.batteryService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        inspect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripherals[peripheral.identifier] = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else {
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.batteryLevel,
              let value = characteristic.value?.first
        else {
            return
        }

        let name = peripheral.name ?? "Bluetooth Device"
        candidates[peripheral.identifier] = BluetoothBatteryCandidate(
            deviceID: peripheral.identifier.uuidString,
            displayName: name,
            transport: .ble,
            batteryPercent: Int(value)
        )
    }

    private func inspect(_ peripheral: CBPeripheral) {
        guard peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self

        if peripheral.state == .connected {
            peripheral.discoverServices([Self.batteryService])
        } else {
            central?.connect(peripheral)
        }
    }

    private func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil
        central?.stopScan()
        for peripheral in peripherals.values where peripheral.state == .connected {
            central?.cancelPeripheralConnection(peripheral)
        }
        let result = Array(candidates.values)
        continuation?.resume(returning: result)
        continuation = nil
        central = nil
    }
}
