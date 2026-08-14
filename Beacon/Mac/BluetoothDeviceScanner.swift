import Foundation
@preconcurrency import CoreBluetooth
import IOBluetooth
import IOKit
import os

public struct BluetoothDeviceScanner {
    private static let logger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "bluetooth")
    private static let signposter = OSSignposter(logger: logger)
    private static let refreshTimeout: Duration = .seconds(8)
    private static let systemProfilerTimeout: Duration = .seconds(5)
    private static let bleBatteryScanTimeout: Duration = .seconds(6)

    public init() {}

    public func connectedCandidates() async -> [BluetoothBatteryCandidate] {
        await connectedCandidateReport().candidates
    }

    public func connectedCandidateReport(now: Date = Date()) async -> BluetoothCandidateScanReport {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.refreshTimeout)
        let expectedProviders: Set<BatteryProvider> = [
            .ioRegistry,
            .systemProfiler,
            .coreBluetoothBatteryService,
            .ideviceInfo,
        ]
        var outcomes: [BatteryProvider: BluetoothProviderOutcome] = [:]

        await withTaskGroup(of: BluetoothProviderCollectionEvent.self) { group in
            group.addTask {
                .outcome(await Self.instrumented(provider: .ioRegistry) {
                    let candidates = await Self.readLocalBatteryCandidates()
                    return Self.outcome(
                        provider: .ioRegistry,
                        candidates: candidates,
                        now: now,
                        message: "IORegistry returned \(candidates.count) Bluetooth battery candidates"
                    )
                })
            }
            group.addTask {
                .outcome(await Self.instrumented(provider: .systemProfiler) {
                    await Self.readSystemProfilerBatteryCandidates(now: now, deadline: deadline)
                })
            }
            group.addTask {
                .outcome(await Self.instrumented(provider: .coreBluetoothBatteryService) {
                    let result = await Self.readBLEBatteryCandidates(now: now)
                    return BluetoothProviderOutcome(candidates: result.candidates, attempt: result.attempt)
                })
            }
            group.addTask {
                .outcome(await Self.instrumented(provider: .ideviceInfo) {
                    let result = await IPhoneUSBBatteryProvider.readCandidate(now: now, deadline: deadline)
                    return BluetoothProviderOutcome(
                        candidates: result.candidate.map { [$0] } ?? [],
                        attempt: result.attempt
                    )
                })
            }
            group.addTask {
                do {
                    try await Task.sleep(for: Self.refreshTimeout)
                } catch {
                    return .deadline
                }
                return .deadline
            }

            while let event = await group.next() {
                switch event {
                case .outcome(let outcome):
                    outcomes[outcome.attempt.provider] = outcome
                    if outcomes.keys.count == expectedProviders.count {
                        group.cancelAll()
                        return
                    }
                case .deadline:
                    group.cancelAll()
                    return
                }
            }
        }

        for provider in expectedProviders where outcomes[provider] == nil {
            outcomes[provider] = BluetoothProviderOutcome(
                candidates: [],
                attempt: BatteryProviderAttempt(
                    provider: provider,
                    status: .timedOut,
                    candidateCount: 0,
                    message: "Provider did not finish before the refresh deadline",
                    attemptedAt: now
                )
            )
        }

        let orderedOutcomes = outcomes.values.sorted {
            Self.providerRank($0.attempt.provider) > Self.providerRank($1.attempt.provider)
        }
        let merged = Self.mergingCandidates(orderedOutcomes.flatMap(\.candidates))
        let collapsed = Self.collapsingDuplicateIPhones(merged)
        let attempts = orderedOutcomes.map(\.attempt)
        let authoritativeProviders = Set(
            attempts.filter { $0.status == .reported || $0.status == .noReport }.map(\.provider)
        )
        Self.logger.info("Battery provider refresh completed outcomes=\(attempts.count) candidates=\(collapsed.count)")
        return BluetoothCandidateScanReport(
            candidates: collapsed,
            attempts: attempts,
            authoritativeProviders: authoritativeProviders
        )
    }

    private struct BluetoothProviderOutcome: Sendable {
        let candidates: [BluetoothBatteryCandidate]
        let attempt: BatteryProviderAttempt
    }

    private enum BluetoothProviderCollectionEvent: Sendable {
        case outcome(BluetoothProviderOutcome)
        case deadline
    }

    private struct BLEBatteryProviderResult: Sendable {
        let candidates: [BluetoothBatteryCandidate]
        let attempt: BatteryProviderAttempt
    }

    static func bleReadStatus(
        completion: BLEBatteryReadCompletion,
        candidates: [BluetoothBatteryCandidate]
    ) -> BatteryReadStatus {
        switch completion {
        case .completed:
            return status(for: candidates)
        case .timedOut, .cancelled:
            return .timedOut
        case .unauthorized:
            return .unauthorized
        case .unavailable:
            return .unavailable
        }
    }

    private static func outcome(
        provider: BatteryProvider,
        candidates: [BluetoothBatteryCandidate],
        now: Date,
        message: String
    ) -> BluetoothProviderOutcome {
        BluetoothProviderOutcome(
            candidates: candidates,
            attempt: BatteryProviderAttempt(
                provider: provider,
                status: status(for: candidates),
                candidateCount: candidates.count,
                message: message,
                attemptedAt: now
            )
        )
    }

    private static func instrumented(
        provider: BatteryProvider,
        operation: () async -> BluetoothProviderOutcome
    ) async -> BluetoothProviderOutcome {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            "BatteryProvider",
            id: id,
            "provider=\(provider.rawValue, privacy: .public)"
        )
        let outcome = await operation()
        signposter.endInterval(
            "BatteryProvider",
            state,
            "status=\(outcome.attempt.status.rawValue, privacy: .public) count=\(outcome.candidates.count)"
        )
        return outcome
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

        let preferred = iPhones.max { left, right in
            candidatePreference(left) < candidatePreference(right)
        } ?? iPhones[0]

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

    private static func candidatePreference(_ candidate: BluetoothBatteryCandidate) -> (Int, Int, Int, String) {
        (
            candidate.connectionState == .connected ? 1 : 0,
            candidate.batteryPercent == nil ? 0 : 1,
            transportRank(candidate.transport),
            candidate.deviceID
        )
    }

    private static func status(for candidates: [BluetoothBatteryCandidate]) -> BatteryReadStatus {
        candidates.contains { $0.batteryPercent != nil } ? .reported : .noReport
    }

    private static func readLocalBatteryCandidates() async -> [BluetoothBatteryCandidate] {
        guard !Task.isCancelled else { return [] }
        let scanner = BluetoothDeviceScanner()
        let candidates = scanner.readAppleDeviceManagementBatteryCandidates()
            + scanner.readHIDBatteryCandidates()
        return mergingCandidates(candidates)
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
            guard !Task.isCancelled else { break }
            var iterator: io_iterator_t = 0
            let matching = IOServiceMatching(className)
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            while true {
                guard !Task.isCancelled else { break }
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
            guard !Task.isCancelled else { break }
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            let name = property("Product", service: service) ?? property("ProductID", service: service) ?? "Bluetooth Device"
            let physicalID = property("PhysicalDeviceUniqueID", service: service)
            let address = property("DeviceAddress", service: service)
            let serial = property("SerialNumber", service: service)
            let id = physicalID ?? address ?? serial ?? name
            let identityEvidence: BluetoothIdentityEvidence = if physicalID != nil {
                .physicalDeviceUniqueID
            } else if address != nil {
                .deviceAddress
            } else if serial != nil {
                .serialNumber
            } else {
                .normalizedName
            }
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
                        kindHint: kindHint,
                        identityEvidence: identityEvidence
                    )
                )
            }
        }
        return results
    }

    private static func readSystemProfilerBatteryCandidates(
        now: Date,
        deadline: ContinuousClock.Instant,
        runner: BatteryProviderRunner = BatteryProviderRunner()
    ) async -> BluetoothProviderOutcome {
        let remaining = ContinuousClock().now.duration(to: deadline)
        guard remaining > .zero else {
            return BluetoothProviderOutcome(
                candidates: [],
                attempt: BatteryProviderAttempt(
                    provider: .systemProfiler,
                    status: .timedOut,
                    candidateCount: 0,
                    message: "system_profiler did not start before the refresh deadline",
                    attemptedAt: now
                )
            )
        }

        do {
            let result = try await runner.run(
                executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
                arguments: ["SPBluetoothDataType", "-json"],
                timeout: min(systemProfilerTimeout, remaining)
            )
            let candidates = result.succeeded ? parseSystemProfilerBluetoothData(result.output) : []
            let status: BatteryReadStatus
            if result.timedOut || result.wasCancelled {
                status = .timedOut
            } else if result.terminationStatus != 0 {
                status = .unavailable
            } else {
                status = Self.status(for: candidates)
            }
            return BluetoothProviderOutcome(
                candidates: candidates,
                attempt: BatteryProviderAttempt(
                    provider: .systemProfiler,
                    status: status,
                    candidateCount: candidates.count,
                    message: status == .timedOut
                        ? "system_profiler timed out"
                        : "system_profiler returned \(candidates.count) battery candidates",
                    attemptedAt: now
                )
            )
        } catch {
            return BluetoothProviderOutcome(
                candidates: [],
                attempt: BatteryProviderAttempt(
                    provider: .systemProfiler,
                    status: .unavailable,
                    candidateCount: 0,
                    message: "system_profiler could not be launched",
                    attemptedAt: now
                )
            )
        }
    }

    @MainActor
    private static func readBLEBatteryCandidates(now: Date) async -> BLEBatteryProviderResult {
        switch CBCentralManager.authorization {
        case .allowedAlways, .notDetermined:
            let readResult = await BLEBatteryServiceReader().read(timeout: bleBatteryScanTimeout)
            let status = bleReadStatus(
                completion: readResult.completion,
                candidates: readResult.candidates
            )
            return BLEBatteryProviderResult(
                candidates: readResult.candidates,
                attempt: BatteryProviderAttempt(
                    provider: .coreBluetoothBatteryService,
                    status: status,
                    candidateCount: readResult.candidates.count,
                    message: "Known BLE scan finished with \(status.rawValue) and \(readResult.candidates.count) battery candidates",
                    attemptedAt: now
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
        let reportedAddress = stringValue(device["device_address"])
        let address = reportedAddress ?? name
        let identityEvidence: BluetoothIdentityEvidence = reportedAddress == nil ? .normalizedName : .deviceAddress
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
                    connectionState: connectionState,
                    identityEvidence: identityEvidence
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
                connectionState: connectionState,
                identityEvidence: identityEvidence
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

        let address = stringValue(properties["DeviceAddress"])
            ?? stringValue(properties["BluetoothDeviceAddress"])
        let serial = stringValue(properties["SerialNumber"])
        let fallbackID = stringValue(properties["HIDDeviceID"])
            ?? stringValue(properties["LocationID"])
        let id = address ?? serial ?? fallbackID ?? name
        let identityEvidence: BluetoothIdentityEvidence = if address != nil {
            .deviceAddress
        } else if serial != nil {
            .serialNumber
        } else {
            .normalizedName
        }

        return BluetoothBatteryCandidate(
            deviceID: id,
            displayName: name,
            transport: .hid,
            batteryPercent: percent,
            kindHint: kindHint,
            connectionState: .connected,
            identityEvidence: identityEvidence
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
        let values = [existing, candidate]
        let connected = values.filter { $0.connectionState == .connected }
        let eligible = connected.isEmpty ? values : connected
        let identityWinner = values.max { left, right in
            if left.identityEvidence.strength != right.identityEvidence.strength {
                return left.identityEvidence.strength < right.identityEvidence.strength
            }
            return transportRank(left.transport) < transportRank(right.transport)
        } ?? candidate
        let displayWinner = eligible
            .filter { !$0.displayName.isGenericBluetoothDisplayName }
            .max { transportRank($0.transport) < transportRank($1.transport) }
            ?? identityWinner
        let percentWinner = eligible
            .filter { $0.batteryPercent != nil }
            .max { transportRank($0.transport) < transportRank($1.transport) }
        let connectionWinner = values.max {
            connectionRank($0.connectionState) < connectionRank($1.connectionState)
        } ?? candidate
        let provenanceWinner = percentWinner ?? connectionWinner
        let chargeState = eligible
            .filter { $0.chargeState != .unknown }
            .max { transportRank($0.transport) < transportRank($1.transport) }?
            .chargeState ?? .unknown
        return BluetoothBatteryCandidate(
            deviceID: identityWinner.deviceID,
            displayName: displayWinner.displayName,
            transport: provenanceWinner.transport,
            batteryPercent: percentWinner?.batteryPercent,
            kindHint: displayWinner.kindHint ?? identityWinner.kindHint ?? provenanceWinner.kindHint,
            connectionState: connectionWinner.connectionState,
            chargeState: chargeState,
            identityEvidence: identityWinner.identityEvidence
        )
    }

    static func mergingCandidates(_ candidates: [BluetoothBatteryCandidate]) -> [BluetoothBatteryCandidate] {
        let ambiguousStrongClusters = Set(
            Dictionary(grouping: candidates.filter { $0.identityEvidence.strength == 2 }) {
                candidateClusterKey($0)
            }
            .compactMap { key, values in
                Set(values.map(\.deviceID)).count > 1 ? key : nil
            }
        )
        var merged: [BluetoothBatteryCandidate] = []
        for candidate in candidates {
            let clusterIsAmbiguous = ambiguousStrongClusters.contains(candidateClusterKey(candidate))
            let matchingIndex = merged.firstIndex { existing in
                if clusterIsAmbiguous, existing.deviceID != candidate.deviceID {
                    return false
                }
                return canMerge(existing, candidate)
            }
            if let index = matchingIndex {
                merged[index] = mergedCandidate(existing: merged[index], with: candidate)
            } else {
                merged.append(candidate)
            }
        }
        return merged
    }

    private static func canMerge(
        _ left: BluetoothBatteryCandidate,
        _ right: BluetoothBatteryCandidate
    ) -> Bool {
        if left.deviceID == right.deviceID { return true }
        guard candidateKind(left) == candidateKind(right),
              left.displayName.normalizedDeviceName == right.displayName.normalizedDeviceName
        else {
            return false
        }
        let hasConflictingStrongIDs = left.identityEvidence.strength == 2
            && right.identityEvidence.strength == 2
            && left.deviceID != right.deviceID
        return !hasConflictingStrongIDs
    }

    private static func candidateClusterKey(_ candidate: BluetoothBatteryCandidate) -> String {
        "\(candidateKind(candidate))|\(candidate.displayName.normalizedDeviceName)"
    }

    private static func candidateKind(_ candidate: BluetoothBatteryCandidate) -> DeviceKind {
        if let kindHint = candidate.kindHint { return kindHint }
        let name = candidate.displayName.lowercased()
        if name.contains("iphone") || name.contains("ios") { return .iPhone }
        if name.contains("airpods") || name.contains("air pods") { return .airPods }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse") { return .mouse }
        if name.contains("trackpad") { return .trackpad }
        return .bluetoothPeripheral
    }

    private static func connectionRank(_ state: ConnectionState) -> Int {
        switch state {
        case .connected: return 2
        case .disconnected: return 1
        case .unknown: return 0
        }
    }

    private static func transportRank(_ transport: BluetoothTransport) -> Int {
        switch transport {
        case .usb: return 6
        case .hid: return 5
        case .systemProfiler: return 4
        case .classic: return 3
        case .ble: return 2
        case .unknown: return 1
        }
    }

    private static func providerRank(_ provider: BatteryProvider) -> Int {
        switch provider {
        case .ideviceInfo: return 6
        case .ioRegistry: return 5
        case .systemProfiler: return 4
        case .ioBluetooth: return 3
        case .coreBluetoothBatteryService: return 2
        case .bluetoothUnsupported: return 1
        case .macPowerSource: return 0
        }
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

enum BLEBatteryReadCompletion: Equatable, Sendable {
    case completed
    case timedOut
    case cancelled
    case unauthorized
    case unavailable
}

private struct BLEBatteryServiceReadResult: Sendable {
    let candidates: [BluetoothBatteryCandidate]
    let completion: BLEBatteryReadCompletion
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
    private var continuation: CheckedContinuation<BLEBatteryServiceReadResult, Never>?
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

    func read(timeout: Duration = .seconds(4)) async -> BLEBatteryServiceReadResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.configuredTimeout = timeout
                self.central = CBCentralManager(delegate: self, queue: nil)
                self.timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        self?.finish(completion: .timedOut)
                    } catch {
                        // Another terminal reason completed the read.
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(completion: .cancelled)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch BLEBatteryReadStatePolicy.action(for: central.state) {
        case .wait:
            return
        case .finish:
            switch central.state {
            case .unauthorized:
                finish(completion: .unauthorized)
            case .unsupported, .poweredOff:
                finish(completion: .unavailable)
            default:
                finish(completion: .unavailable)
            }
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
            batteryPercent: Int(value),
            identityEvidence: .coreBluetoothUUID
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
        finish(completion: .completed)
    }

    private func scheduleDiscoveryWindowFinishIfNeeded(inspectedKnownPeripheral: Bool) {
        let timeout = BLEBatteryDiscoveryWindow.timeout(
            configured: configuredTimeout,
            inspectedKnownPeripheral: inspectedKnownPeripheral
        )
        guard timeout != configuredTimeout else { return }
        discoveryWindowTask?.cancel()
        discoveryWindowTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
                self?.finish(completion: .completed)
            } catch {
                // Another terminal reason completed the read.
            }
        }
    }

    private func finish(completion: BLEBatteryReadCompletion) {
        guard let continuation else { return }
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
        let result = BLEBatteryServiceReadResult(
            candidates: Array(candidates.values),
            completion: completion
        )
        self.continuation = nil
        continuation.resume(returning: result)
        connectionAttemptIDs.removeAll()
        central = nil
    }
}
