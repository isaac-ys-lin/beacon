import Foundation
@preconcurrency import CoreBluetooth
import IOBluetooth
import IOKit
import os

public struct BluetoothDeviceScanner {
    private static let logger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "bluetooth")
    private static let systemProfilerTimeout: TimeInterval = 5
    private static let bleBatteryScanTimeout: Duration = .seconds(6)

    public init() {}

    public func connectedCandidates() async -> [BluetoothBatteryCandidate] {
        await connectedCandidateReport().candidates
    }

    public func connectedCandidateReport(now: Date = Date()) async -> BluetoothCandidateScanReport {
        async let localRead = Self.readLocalBatteryCandidates()
        async let profilerRead = Self.readSystemProfilerBatteryCandidates()
        async let bleRead = Self.readBLEBatteryCandidates(now: now)
        async let usbRead = IPhoneUSBBatteryProvider.readCandidate(now: now)

        let (local, profiler, ble, usb) = await (localRead, profilerRead, bleRead, usbRead)

        var candidates = local
        var attempts: [BatteryProviderAttempt] = [
            BatteryProviderAttempt(
                provider: .ioRegistry,
                status: Self.status(for: local),
                candidateCount: local.count,
                message: "IORegistry returned \(local.count) Bluetooth battery candidates",
                attemptedAt: now
            )
        ]

        Self.logger.info("system_profiler returned \(profiler.count) battery candidates")
        attempts.append(
            BatteryProviderAttempt(
                provider: .systemProfiler,
                status: Self.status(for: profiler),
                candidateCount: profiler.count,
                message: "system_profiler returned \(profiler.count) battery candidates",
                attemptedAt: Date()
            )
        )
        for candidate in profiler {
            candidates.upsert(candidate)
        }

        Self.logger.info("Known BLE scan returned \(ble.candidates.count) battery candidates")
        attempts.append(ble.attempt)
        for candidate in ble.candidates {
            candidates.upsert(candidate)
        }

        Self.logger.info("USB iPhone read returned \(usb.attempt.candidateCount) battery candidates")
        attempts.append(usb.attempt)
        if let candidate = usb.candidate {
            candidates.upsert(candidate)
        }

        let collapsed = Self.collapsingDuplicateIPhones(candidates)
        return BluetoothCandidateScanReport(candidates: collapsed, attempts: attempts)
    }

    private struct BLEBatteryProviderResult: Sendable {
        let candidates: [BluetoothBatteryCandidate]
        let attempt: BatteryProviderAttempt
    }

    /// The same iPhone can surface through multiple providers (USB `ideviceinfo`,
    /// BLE, system_profiler) under different display names — iOS `DeviceName`
    /// ("Yi's iPhone") vs the Bluetooth name ("YisiPhone") — which `upsert`'s
    /// name-based dedup cannot collapse. Fold all iPhone candidates into one,
    /// preferring the battery-bearing (USB) reading.
    static func collapsingDuplicateIPhones(
        _ candidates: [BluetoothBatteryCandidate]
    ) -> [BluetoothBatteryCandidate] {
        let iPhones = candidates.filter(Self.isIPhoneCandidate)
        guard iPhones.count > 1 else { return candidates }

        let preferred = iPhones.first { $0.batteryPercent != nil && $0.connectionState == .connected }
            ?? iPhones.first { $0.batteryPercent != nil }
            ?? iPhones.first { $0.connectionState == .connected }
            ?? iPhones[0]

        var result: [BluetoothBatteryCandidate] = []
        var insertedIPhone = false
        for candidate in candidates {
            if Self.isIPhoneCandidate(candidate) {
                if !insertedIPhone {
                    result.append(preferred)
                    insertedIPhone = true
                }
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    private static func isIPhoneCandidate(_ candidate: BluetoothBatteryCandidate) -> Bool {
        if let hint = candidate.kindHint { return hint == .iPhone }
        let name = candidate.displayName.lowercased()
        return name.contains("iphone") || name.contains("ios")
    }

    private static func status(for candidates: [BluetoothBatteryCandidate]) -> BatteryReadStatus {
        candidates.contains { $0.batteryPercent != nil } ? .reported : .noReport
    }

    private static func readLocalBatteryCandidates() async -> [BluetoothBatteryCandidate] {
        await Task.detached(priority: .utility) {
            let scanner = BluetoothDeviceScanner()
            var candidates = scanner.readAppleDeviceManagementBatteryCandidates()
            for candidate in scanner.readHIDBatteryCandidates() {
                candidates.upsert(candidate)
            }
            return candidates
        }.value
    }

    private func readAppleDeviceManagementBatteryCandidates() -> [BluetoothBatteryCandidate] {
        let classNames = [
            "AppleDeviceManagementHIDEventService",
            "AppleUserHIDEventService",
            "IOHIDEventService"
        ]

        var results: [BluetoothBatteryCandidate] = []
        var seenIDs = Set<String>()

        for className in classNames {
            var iterator: io_iterator_t = 0
            let matching = IOServiceMatching(className)
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            while true {
                let service = IOIteratorNext(iterator)
                if service == 0 { break }
                defer { IOObjectRelease(service) }

                let properties = Self.appleDeviceManagementProperties(from: service)
                guard let candidate = Self.appleDeviceManagementCandidate(from: properties),
                      !seenIDs.contains(candidate.deviceID)
                else {
                    continue
                }
                seenIDs.insert(candidate.deviceID)
                results.append(candidate)
            }
        }

        return results
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
            let id = property("PhysicalDeviceUniqueID", service: service)
                ?? property("DeviceAddress", service: service)
                ?? property("SerialNumber", service: service)
                ?? name
            let percent = intProperty("BatteryPercent", service: service)
            let transport = property("Transport", service: service) ?? ""
            let usagePage = intProperty("PrimaryUsagePage", service: service)
            let usage = intProperty("PrimaryUsage", service: service)
            let kindHint = Self.hidKindHint(
                name: name,
                transport: transport,
                primaryUsagePage: usagePage,
                primaryUsage: usage
            )

            if Self.shouldIncludeHIDCandidate(
                batteryPercent: percent,
                transport: transport,
                kindHint: kindHint
            ) {
                results.append(
                    BluetoothBatteryCandidate(
                        deviceID: id,
                        displayName: name,
                        transport: .hid,
                        batteryPercent: percent,
                        kindHint: kindHint
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

    @MainActor
    private static func readBLEBatteryCandidates(now: Date) async -> BLEBatteryProviderResult {
        switch CBCentralManager.authorization {
        case .allowedAlways, .notDetermined:
            let candidates = await BLEBatteryServiceReader().read(timeout: bleBatteryScanTimeout)
            return BLEBatteryProviderResult(
                candidates: candidates,
                attempt: BatteryProviderAttempt(
                    provider: .coreBluetoothBatteryService,
                    status: Self.status(for: candidates),
                    candidateCount: candidates.count,
                    message: "Known BLE scan returned \(candidates.count) battery candidates",
                    attemptedAt: Date()
                )
            )
        case .denied, .restricted:
            let message = "Known BLE scan skipped because CoreBluetooth authorization is \(String(describing: CBCentralManager.authorization))"
            Self.logger.info("\(message, privacy: .public)")
            return BLEBatteryProviderResult(
                candidates: [],
                attempt: BatteryProviderAttempt(
                    provider: .coreBluetoothBatteryService,
                    status: .unauthorized,
                    candidateCount: 0,
                    message: message,
                    attemptedAt: now
                )
            )
        @unknown default:
            let message = "Known BLE scan skipped because CoreBluetooth authorization is unknown"
            Self.logger.info("\(message, privacy: .public)")
            return BLEBatteryProviderResult(
                candidates: [],
                attempt: BatteryProviderAttempt(
                    provider: .coreBluetoothBatteryService,
                    status: .unavailable,
                    candidateCount: 0,
                    message: message,
                    attemptedAt: now
                )
            )
        }
    }

    private static func systemProfilerBatteryCandidates() -> [BluetoothBatteryCandidate] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let timeoutWorkItem = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
        }

        do {
            try process.run()
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + systemProfilerTimeout,
                execute: timeoutWorkItem
            )
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeoutWorkItem.cancel()
            guard process.terminationStatus == 0 else { return [] }
            return parseSystemProfilerBluetoothData(data)
        } catch {
            timeoutWorkItem.cancel()
            return []
        }
    }

    static func parseSystemProfilerBluetoothData(_ data: Data) -> [BluetoothBatteryCandidate] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else {
            return []
        }

        return sections.flatMap { section -> [BluetoothBatteryCandidate] in
            let connectedEntries = (section["device_connected"] as? [[String: Any]]) ?? []
            let disconnectedEntries = (section["device_not_connected"] as? [[String: Any]]) ?? []

            let fromConnected = connectedEntries.flatMap { entry -> [BluetoothBatteryCandidate] in
                entry.flatMap { name, value -> [BluetoothBatteryCandidate] in
                    guard let device = value as? [String: Any] else { return [] }
                    return candidates(fromSystemProfilerDeviceNamed: name, device: device, connectionState: .connected)
                }
            }
            let fromDisconnected = disconnectedEntries.flatMap { entry -> [BluetoothBatteryCandidate] in
                entry.flatMap { name, value -> [BluetoothBatteryCandidate] in
                    guard let device = value as? [String: Any] else { return [] }
                    return candidates(fromSystemProfilerDeviceNamed: name, device: device, connectionState: .disconnected)
                }
            }
            return fromConnected + fromDisconnected
        }
    }

    private static func candidates(fromSystemProfilerDeviceNamed name: String, device: [String: Any], connectionState: ConnectionState = .connected) -> [BluetoothBatteryCandidate] {
        let address = stringValue(device["device_address"]) ?? name
        let minorType = stringValue(device["device_minorType"]) ?? ""
        let kindHint = kindHint(name: name, minorType: minorType)
        let levels = batteryLevels(from: device)
        guard !levels.isEmpty else { return [] }

        if isAirPods(name: name, minorType: minorType), levels.count > 1 {
            return levels.map { level in
                let component = level.component ?? "Battery"
                return BluetoothBatteryCandidate(
                    deviceID: "\(address)-\(component.lowercased())",
                    displayName: "\(name) \(component)",
                    transport: .systemProfiler,
                    batteryPercent: level.percent,
                    kindHint: .airPods,
                    connectionState: connectionState
                )
            }
        }

        guard let percent = batteryPercent(from: device) else {
            return []
        }

        return [
            BluetoothBatteryCandidate(
                deviceID: address,
                displayName: name,
                transport: .systemProfiler,
                batteryPercent: percent,
                kindHint: kindHint,
                connectionState: connectionState
            )
        ]
    }

    private static func batteryLevels(from device: [String: Any]) -> [(component: String?, percent: Int)] {
        device.compactMap { key, value -> (component: String?, percent: Int, order: Int, key: String)? in
            guard key.hasPrefix("device_batteryLevel"),
                  let percent = percentageValue(value)
            else {
                return nil
            }

            let component = batteryComponent(from: key)
            return (component, percent, batteryComponentSortOrder(component), key)
        }
        .sorted { left, right in
            if left.order != right.order {
                return left.order < right.order
            }
            return left.key.localizedStandardCompare(right.key) == .orderedAscending
        }
        .map { (component: $0.component, percent: $0.percent) }
    }

    private static func batteryComponent(from key: String) -> String? {
        let prefix = "device_batteryLevel"
        guard key.count > prefix.count else { return nil }
        return String(key.dropFirst(prefix.count))
    }

    private static func batteryComponentSortOrder(_ component: String?) -> Int {
        switch component?.lowercased() {
        case "case": return 0
        case "left": return 1
        case "right": return 2
        case nil, "main": return 3
        default: return 4
        }
    }

    private static func kindHint(name: String, minorType: String) -> DeviceKind? {
        let text = "\(name) \(minorType)".lowercased()
        if text.contains("airpods") || text.contains("air pods") { return .airPods }
        if text.contains("keyboard") { return .keyboard }
        if text.contains("mouse") { return .mouse }
        if text.contains("trackpad") { return .trackpad }
        return nil
    }

    static func hidKindHint(
        name: String,
        transport: String,
        primaryUsagePage: Int?,
        primaryUsage: Int?
    ) -> DeviceKind? {
        if let nameHint = kindHint(name: name, minorType: "") {
            return nameHint
        }

        guard transport.localizedCaseInsensitiveContains("bluetooth"),
              primaryUsagePage == 1,
              let primaryUsage
        else {
            return nil
        }

        switch primaryUsage {
        case 2:
            return .mouse
        case 5:
            return .trackpad
        case 6:
            return .keyboard
        default:
            return nil
        }
    }

    static func shouldIncludeHIDCandidate(
        batteryPercent: Int?,
        transport: String,
        kindHint: DeviceKind?
    ) -> Bool {
        if batteryPercent != nil {
            return true
        }

        return transport.localizedCaseInsensitiveContains("bluetooth")
            && (kindHint == .keyboard || kindHint == .mouse || kindHint == .trackpad)
    }

    static func appleDeviceManagementCandidate(from properties: [String: Any]) -> BluetoothBatteryCandidate? {
        let name = stringValue(properties["Product"])
            ?? stringValue(properties["ProductName"])
            ?? stringValue(properties["DeviceName"])
            ?? "Bluetooth Device"
        let transport = stringValue(properties["Transport"]) ?? ""
        let isBuiltIn = boolValue(properties["Built-In"]) ?? boolValue(properties["BuiltIn"]) ?? false
        let percent = batteryPercent(fromAppleDeviceProperties: properties)
        let primaryUsagePage = intValue(properties["PrimaryUsagePage"])
        let primaryUsage = intValue(properties["PrimaryUsage"])
        let kindHint = hidKindHint(
            name: name,
            transport: transport,
            primaryUsagePage: primaryUsagePage,
            primaryUsage: primaryUsage
        ) ?? kindHint(name: name, minorType: "")

        guard shouldIncludeAppleDeviceManagementCandidate(
            batteryPercent: percent,
            transport: transport,
            isBuiltIn: isBuiltIn,
            kindHint: kindHint
        ) else {
            return nil
        }

        let id = stringValue(properties["DeviceAddress"])
            ?? stringValue(properties["BluetoothDeviceAddress"])
            ?? stringValue(properties["SerialNumber"])
            ?? stringValue(properties["HIDDeviceID"])
            ?? stringValue(properties["LocationID"])
            ?? name

        return BluetoothBatteryCandidate(
            deviceID: id,
            displayName: name,
            transport: .hid,
            batteryPercent: percent,
            kindHint: kindHint,
            connectionState: .connected
        )
    }

    static func shouldIncludeAppleDeviceManagementCandidate(
        batteryPercent: Int?,
        transport: String,
        isBuiltIn: Bool,
        kindHint: DeviceKind?
    ) -> Bool {
        if batteryPercent != nil {
            return !isBuiltIn
        }

        return !isBuiltIn
            && transport.localizedCaseInsensitiveContains("bluetooth")
            && (kindHint == .keyboard || kindHint == .mouse || kindHint == .trackpad)
    }

    static func mergedCandidate(
        existing: BluetoothBatteryCandidate,
        with candidate: BluetoothBatteryCandidate
    ) -> BluetoothBatteryCandidate {
        let displayName = candidate.displayName.isGenericBluetoothDisplayName
            ? existing.displayName
            : candidate.displayName

        return BluetoothBatteryCandidate(
            deviceID: candidate.deviceID,
            displayName: displayName,
            transport: candidate.transport,
            batteryPercent: candidate.batteryPercent,
            kindHint: candidate.kindHint ?? existing.kindHint,
            connectionState: candidate.connectionState,
            chargeState: candidate.chargeState
        )
    }

    private static func isAirPods(name: String, minorType: String) -> Bool {
        kindHint(name: name, minorType: minorType) == .airPods
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

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        if let string = stringValue(value) { return Int(string) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = stringValue(value) {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func batteryPercent(fromAppleDeviceProperties properties: [String: Any]) -> Int? {
        if let percent = batteryPercent(fromTrustedBatteryDictionary: properties) {
            return percent
        }

        // IORegistry entries include large descriptor arrays where fields named like
        // BatteryLevel can mean HID usage metadata instead of current charge.
        // Only recurse into known state containers, not arbitrary descriptor arrays.
        for key in ["HIDEventServiceProperties", "DeviceManagement", "PowerSource", "Battery"] {
            guard let nestedValue = properties[key],
                  let percent = batteryPercent(fromTrustedBatteryContainer: nestedValue) else {
                continue
            }
            return percent
        }

        return nil
    }

    private static func batteryPercent(fromTrustedBatteryContainer value: Any) -> Int? {
        if let dictionary = value as? [String: Any] {
            if let percent = batteryPercent(fromTrustedBatteryDictionary: dictionary) {
                return percent
            }

            for nestedValue in dictionary.values {
                if let percent = batteryPercent(fromTrustedBatteryContainer: nestedValue) {
                    return percent
                }
            }
            return nil
        }

        return nil
    }

    private static func batteryPercent(fromTrustedBatteryDictionary dictionary: [String: Any]) -> Int? {
        for key in trustedBatteryPercentKeys {
            guard let value = dictionary[key] else { continue }
            if let percent = percentageValue(value) {
                return percent
            }
        }
        return nil
    }

    private static let trustedBatteryPercentKeys: [String] = [
        "BatteryPercent",
        "BatteryPercentage",
        "BatteryLevel",
        "Battery Level",
        "DeviceBatteryPercent",
        "DeviceBatteryPercentage",
        "DeviceBatteryLevel",
        "CurrentBatteryPercent",
        "CurrentBatteryLevel"
    ]

    private static func appleDeviceManagementProperties(from service: io_object_t) -> [String: Any] {
        var rawProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &rawProperties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
              let properties = rawProperties?.takeRetainedValue() as? [String: Any]
        else {
            return [:]
        }
        return properties
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

enum BluetoothDeviceController {
    @discardableResult
    static func connect(deviceID: String) -> Bool {
        guard let address = BluetoothDeviceControlSupport.normalizedAddress(from: deviceID),
              let device = IOBluetoothDevice(addressString: address)
        else {
            return false
        }

        if device.isConnected() {
            return true
        }

        return device.openConnection() == kIOReturnSuccess
    }

    @discardableResult
    static func disconnect(deviceID: String) -> Bool {
        guard let address = BluetoothDeviceControlSupport.normalizedAddress(from: deviceID),
              let device = IOBluetoothDevice(addressString: address)
        else {
            return false
        }

        if !device.isConnected() {
            return true
        }

        return device.closeConnection() == kIOReturnSuccess
    }
}

private extension Array where Element == BluetoothBatteryCandidate {
    mutating func upsert(_ candidate: BluetoothBatteryCandidate) {
        if let index = firstIndex(where: { $0.deviceID == candidate.deviceID || $0.displayName.normalizedDeviceName == candidate.displayName.normalizedDeviceName }) {
            let existing = self[index]
            let resolved = BluetoothDeviceScanner.mergedCandidate(existing: existing, with: candidate)
            if candidate.batteryPercent != nil || self[index].batteryPercent == nil {
                self[index] = resolved
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

    var isGenericBluetoothDisplayName: Bool {
        let normalized = normalizedDeviceName
        return normalized.isEmpty
            || normalized == "bluetooth device"
            || normalized == "unknown"
            || normalized == "unknown device"
    }
}

enum BLEBatteryReadStateAction: Equatable {
    case wait
    case scanKnownPeripherals
    case finish
}

enum BLEBatteryReadStatePolicy {
    static func action(for state: CBManagerState) -> BLEBatteryReadStateAction {
        switch state {
        case .poweredOn:
            return .scanKnownPeripherals
        case .unknown, .resetting:
            return .wait
        case .unsupported, .unauthorized, .poweredOff:
            return .finish
        @unknown default:
            return .finish
        }
    }
}

enum BLEBatteryDiscoveryWindow {
    static let emptyPeripheralTimeout: Duration = .milliseconds(1500)

    static func timeout(
        configured: Duration,
        inspectedKnownPeripheral: Bool
    ) -> Duration {
        guard !inspectedKnownPeripheral else { return configured }
        return configured < emptyPeripheralTimeout ? configured : emptyPeripheralTimeout
    }
}

@MainActor
private final class BLEBatteryServiceReader: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let hidService = CBUUID(string: "1812")

    private var central: CBCentralManager?
    private var continuation: CheckedContinuation<[BluetoothBatteryCandidate], Never>?
    private var candidates: [UUID: BluetoothBatteryCandidate] = [:]
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectionAttemptIDs = Set<UUID>()
    private var timeoutTask: Task<Void, Never>?
    private var discoveryWindowTask: Task<Void, Never>?
    private var configuredTimeout: Duration = .seconds(4)
    /// Peripherals whose battery read is still in flight. Once the initially
    /// connected set has all resolved we can finish without waiting out the
    /// full timeout window — the common case where nothing needs the full scan.
    private var pendingResolutionIDs = Set<UUID>()
    private var inspectedAnyPeripheral = false
    private var didStartInitialInspection = false

    func read(timeout: Duration = .seconds(4)) async -> [BluetoothBatteryCandidate] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.configuredTimeout = timeout
            self.central = CBCentralManager(delegate: self, queue: nil)
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish()
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch BLEBatteryReadStatePolicy.action(for: central.state) {
        case .wait:
            return
        case .finish:
            finish()
            return
        case .scanKnownPeripherals:
            break
        }

        let batteryPeripherals = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let hidPeripherals = central.retrieveConnectedPeripherals(withServices: [Self.hidService])
        let hasKnownPeripheral = !batteryPeripherals.isEmpty || !hidPeripherals.isEmpty

        for peripheral in batteryPeripherals {
            inspect(peripheral)
        }
        for peripheral in hidPeripherals {
            inspect(peripheral)
        }

        central.scanForPeripherals(
            withServices: [Self.batteryService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        didStartInitialInspection = true
        scheduleDiscoveryWindowFinishIfNeeded(inspectedKnownPeripheral: hasKnownPeripheral)
        checkEarlyFinish()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        inspect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripherals[peripheral.identifier] = nil
        connectionAttemptIDs.remove(peripheral.identifier)
        resolve(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectionAttemptIDs.contains(peripheral.identifier) {
            peripherals[peripheral.identifier] = nil
            connectionAttemptIDs.remove(peripheral.identifier)
        }
        resolve(peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            resolve(peripheral.identifier)
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else {
            resolve(peripheral.identifier)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.batteryLevel, let value = characteristic.value?.first else {
            resolve(peripheral.identifier)
            return
        }
        let name = peripheral.name ?? "Bluetooth Device"
        candidates[peripheral.identifier] = BluetoothBatteryCandidate(
            deviceID: peripheral.identifier.uuidString,
            displayName: name,
            transport: .ble,
            batteryPercent: Int(value)
        )
        resolve(peripheral.identifier)
    }

    private func inspect(_ peripheral: CBPeripheral) {
        guard peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        inspectedAnyPeripheral = true
        pendingResolutionIDs.insert(peripheral.identifier)
        if peripheral.state == .connected {
            peripheral.discoverServices([Self.batteryService])
        } else {
            connectionAttemptIDs.insert(peripheral.identifier)
            central?.connect(peripheral)
        }
    }

    /// Marks a peripheral as done (battery read, or terminal failure) and
    /// finishes the scan early once every inspected peripheral has resolved.
    private func resolve(_ identifier: UUID) {
        pendingResolutionIDs.remove(identifier)
        checkEarlyFinish()
    }

    private func checkEarlyFinish() {
        guard didStartInitialInspection,
              inspectedAnyPeripheral,
              pendingResolutionIDs.isEmpty
        else { return }
        finish()
    }

    private func scheduleDiscoveryWindowFinishIfNeeded(inspectedKnownPeripheral: Bool) {
        let timeout = BLEBatteryDiscoveryWindow.timeout(
            configured: configuredTimeout,
            inspectedKnownPeripheral: inspectedKnownPeripheral
        )
        guard timeout != configuredTimeout else { return }
        discoveryWindowTask?.cancel()
        discoveryWindowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            self?.finish()
        }
    }

    private func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil
        discoveryWindowTask?.cancel()
        discoveryWindowTask = nil
        if central?.state == .poweredOn {
            central?.stopScan()
            for peripheral in peripherals.values where connectionAttemptIDs.contains(peripheral.identifier) {
                central?.cancelPeripheralConnection(peripheral)
            }
        }
        let result = Array(candidates.values)
        continuation?.resume(returning: result)
        continuation = nil
        connectionAttemptIDs.removeAll()
        central = nil
    }
}
