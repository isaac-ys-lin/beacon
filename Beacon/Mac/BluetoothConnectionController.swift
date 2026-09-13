import Combine
import Foundation

/// A paired identity is independent of whether the device has ever supplied battery data.
struct PairedBluetoothDevice: Equatable, Identifiable, Sendable {
    let address: String
    let displayName: String
    let kind: DeviceKind
    let isConnected: Bool
    let requiresAudioConfirmation: Bool

    var id: String { "bluetooth-" + address.replacingOccurrences(of: ":", with: "-") }
}

enum BluetoothConnectionAction: String, Equatable, Sendable {
    case connect, disconnect
}

enum BluetoothConnectionPhase: String, Equatable, Sendable {
    case requesting, verifyingLink, verifyingAudio
    case connected, disconnected, failed, timedOut, audioUnverified, identityUnavailable, permissionDenied

    var isInProgress: Bool {
        [.requesting, .verifyingLink, .verifyingAudio].contains(self)
    }

    var isFailure: Bool { !isInProgress && self != .connected && self != .disconnected }

    var title: String {
        let key: String
        switch self {
        case .requesting: key = "Sending connection request"
        case .verifyingLink: key = "Checking Bluetooth connection"
        case .verifyingAudio: key = "Checking audio output"
        case .connected: key = "Connection confirmed"
        case .disconnected: key = "Disconnection confirmed"
        case .failed: key = "Connection change failed"
        case .timedOut: key = "Connection result not confirmed"
        case .audioUnverified: key = "Bluetooth connected; audio not confirmed"
        case .identityUnavailable: key = "Paired device identity unavailable"
        case .permissionDenied: key = "Bluetooth permission required"
        }
        return BeaconL10n.string(key)
    }
}

struct BluetoothConnectionOperation: Equatable, Identifiable, Sendable {
    let id: UUID
    let deviceID: String
    let address: String
    let displayName: String
    let action: BluetoothConnectionAction
    var kind: DeviceKind = .bluetoothPeripheral
    var phase: BluetoothConnectionPhase
    var detail: String
    var audioOutputUID: String?
}

struct BluetoothConnectionObservation: Equatable, Sendable {
    let isPaired: Bool
    let isConnected: Bool
    /// Non-nil only after an independent Core Audio default-output read matches the identity.
    var confirmedAudioOutputUID: String? = nil
    var failure: BluetoothConnectionPhase? = nil
    var errorCode: Int32? = nil
}

struct BluetoothCommandResult: Equatable, Sendable {
    var failure: BluetoothConnectionPhase? = nil
    var errorCode: Int32? = nil
}

/// A small injection seam for the existing app-process UI tests, not a hardware framework.
/// The native implementation starts an asynchronous Bluetooth request; no closure waits for
/// a connection on the UI thread. Only observe() can supply connection/output evidence.
@MainActor
struct BluetoothConnectionClient {
    var pairedDevices: () -> [PairedBluetoothDevice]
    var request: (String, BluetoothConnectionAction) -> BluetoothCommandResult
    var observe: (String) -> BluetoothConnectionObservation
    var selectAudioOutput: (String) -> Int32?
    var authorizationFailure: () -> BluetoothConnectionPhase? = { nil }

    static var disabled: Self {
        Self(pairedDevices: { [] }, request: { _, _ in .init(failure: .identityUnavailable) },
             observe: { _ in .init(isPaired: false, isConnected: false) }, selectAudioOutput: { _ in nil })
    }
}

@MainActor
final class BluetoothConnectionController: ObservableObject {
    @Published private(set) var authorizationFailure: BluetoothConnectionPhase?
    @Published private(set) var pairedDevices: [PairedBluetoothDevice] = []
    @Published private(set) var operations: [String: BluetoothConnectionOperation] = [:]
    private let client: BluetoothConnectionClient
    private let pollInterval: Duration
    private let maximumObservations: Int
    private var tasks: [String: Task<Void, Never>] = [:]

    init(client: BluetoothConnectionClient = .disabled, pollInterval: Duration = .milliseconds(250),
         maximumObservations: Int = 60) {
        self.client = client
        self.pollInterval = pollInterval
        self.maximumObservations = max(2, maximumObservations)
    }

    func refreshPairedDevices() {
        // Duplicate/invalid addresses are not selectable: guessing is worse than a clear failure.
        authorizationFailure = client.authorizationFailure()
        let devices = client.pairedDevices()
        let counts = Dictionary(grouping: devices, by: \.address)
        pairedDevices = devices.filter {
            counts[$0.address]?.count == 1
                && BluetoothDeviceControlSupport.normalizedAddress(from: $0.address) == $0.address
        }.sorted { $0.address < $1.address }
    }

    func device(for deviceID: String) -> PairedBluetoothDevice? {
        guard let address = BluetoothDeviceControlSupport.normalizedAddress(from: deviceID) else { return nil }
        return pairedDevices.first { $0.address == address }
    }

    func operation(for deviceID: String) -> BluetoothConnectionOperation? {
        guard let address = BluetoothDeviceControlSupport.normalizedAddress(from: deviceID) else { return nil }
        return operations[address]
    }

    /// true means accepted by this coordinator, never "connected". The published operation
    /// remains in progress until independent observations confirm the requested result.
    @discardableResult
    func perform(_ action: BluetoothConnectionAction, deviceID: String, displayName: String,
                 verifyOnly: Bool = false) -> Bool {
        guard let address = BluetoothDeviceControlSupport.normalizedAddress(from: deviceID) else { return false }
        guard operations[address]?.phase.isInProgress != true else { return false }
        refreshPairedDevices()
        let token = UUID()
        let target = device(for: deviceID)
        operations[address] = BluetoothConnectionOperation(id: token, deviceID: deviceID, address: address,
            displayName: target?.displayName ?? displayName, action: action,
            kind: target?.kind ?? .bluetoothPeripheral,
            phase: .requesting, detail: BeaconL10n.string("A request is not a confirmed result."))
        if let failure = authorizationFailure {
            finish(address: address, token: token, phase: failure,
                   detail: BeaconL10n.string("Allow Beacon in Bluetooth Privacy Settings, then check again."))
            return false
        }
        guard let target else {
            finish(address: address, token: token, phase: .identityUnavailable,
                   detail: BeaconL10n.string("Pair the exact device in Bluetooth Settings, then check again. Beacon will not choose a same-named device."))
            return false
        }
        tasks[address] = Task { [weak self] in
            guard let self else { return }
            if !verifyOnly {
                let request = client.request(address, action)
                if let failure = request.failure {
                    finish(address: address, token: token, phase: failure,
                           detail: commandFailureDetail(request.errorCode))
                    refreshPairedDevices()
                    return
                }
            }
            update(address: address, token: token, phase: .verifyingLink,
                   detail: BeaconL10n.string("Waiting for macOS to confirm the actual device state."))
            var linkWasEstablished = false
            var consecutiveConfirmations = 0
            var lastObservation: BluetoothConnectionObservation?
            var requestedAudio = false
            var audioRequestError: Int32?
            for _ in 0..<maximumObservations {
                guard !Task.isCancelled, operations[address]?.id == token else { return }
                let observation = client.observe(address)
                lastObservation = observation
                if let failure = observation.failure {
                    finish(address: address, token: token, phase: failure,
                           detail: commandFailureDetail(observation.errorCode))
                    refreshPairedDevices()
                    return
                }
                guard observation.isPaired else {
                    finish(address: address, token: token, phase: .identityUnavailable,
                           detail: BeaconL10n.string("The paired identity disappeared while checking. No other device was selected."))
                    refreshPairedDevices()
                    return
                }
                let linkMatches = action == .connect ? observation.isConnected : !observation.isConnected
                let outputMatches = action == .disconnect || !target.requiresAudioConfirmation
                    || observation.confirmedAudioOutputUID != nil
                if linkMatches && outputMatches {
                    consecutiveConfirmations += 1
                    if consecutiveConfirmations >= 2 {
                        let detail = action == .disconnect
                            ? BeaconL10n.string("macOS reports that this Bluetooth link is disconnected.")
                            : BeaconL10n.string(target.requiresAudioConfirmation
                                ? "Bluetooth and the default audio output were independently confirmed."
                                : "macOS reports that this Bluetooth link is connected.")
                        finish(address: address, token: token, phase: action == .connect ? .connected : .disconnected,
                               detail: detail, audioOutputUID: observation.confirmedAudioOutputUID)
                        refreshPairedDevices()
                        return
                    }
                } else {
                    consecutiveConfirmations = 0
                    if action == .connect, linkWasEstablished, !observation.isConnected {
                        finish(address: address, token: token, phase: .failed,
                               detail: BeaconL10n.string("The connection dropped before confirmation. Keep the device nearby and retry."))
                        refreshPairedDevices()
                        return
                    }
                    if action == .connect, observation.isConnected, target.requiresAudioConfirmation {
                        update(address: address, token: token, phase: .verifyingAudio,
                               detail: BeaconL10n.string("Bluetooth is connected. Audio output still needs independent confirmation."))
                        if !requestedAudio && !verifyOnly {
                            // nil means no uniquely mapped output exists yet; try again on the next poll.
                            if let code = client.selectAudioOutput(address) {
                                requestedAudio = true
                                audioRequestError = code == 0 ? nil : code
                            }
                        }
                    }
                }
                linkWasEstablished = linkWasEstablished || observation.isConnected
                do { try await Task.sleep(for: pollInterval) } catch { return }
            }
            let audioOnly = action == .connect && lastObservation?.isConnected == true && target.requiresAudioConfirmation
            let detail = audioOnly
                ? BeaconL10n.string("Open Sound Settings, select the intended output, then Check Result. An unmapped audio identity is not treated as success.")
                : BeaconL10n.string("macOS did not confirm the requested state before the deadline. Check the device and retry; the system request may still complete later.")
            finish(address: address, token: token, phase: audioOnly ? .audioUnverified : .timedOut,
                   detail: detail + (audioRequestError.map { " (\($0))" } ?? ""))
            refreshPairedDevices()
        }
        return true
    }

    func pairedPresentationIDs(in snapshots: [DecoratedBatterySnapshot]) -> Set<String> {
        // Aggregated AirPods use the group ID, not an individual left/right/case ID.
        Set(groupedDeviceItems(snapshots).flatMap(\.items).filter { device(for: $0.id) != nil || operation(for: $0.id) != nil }.map(\.id))
    }

    func snapshots(including snapshots: [DecoratedBatterySnapshot]) -> [DecoratedBatterySnapshot] {
        var represented = Set<String>()
        var result = snapshots.map { decorated in
            let s = decorated.snapshot
            guard let paired = device(for: s.id) else { return decorated }
            represented.insert(paired.address)
            // A reconnection does not refresh the battery report or its timestamp.
            let freshness: Freshness = paired.isConnected && s.connectionState != .connected
                && decorated.freshness == .fresh ? .stale : decorated.freshness
            return DecoratedBatterySnapshot(snapshot: BatterySnapshot(deviceID: s.id, displayName: s.displayName,
                kind: s.kind, percent: s.percent, chargeState: s.chargeState,
                connectionState: paired.isConnected ? .connected : .disconnected, source: s.source,
                provider: s.provider, readStatus: s.readStatus, confidence: s.confidence,
                identityStrength: s.identityStrength, updatedAt: s.updatedAt), freshness: freshness)
        }
        for paired in pairedDevices where !represented.contains(paired.address) {
            represented.insert(paired.address)
            result.append(DecoratedBatterySnapshot(snapshot: BatterySnapshot(deviceID: paired.id,
                displayName: paired.displayName, kind: paired.kind, percent: nil, chargeState: .unknown,
                connectionState: paired.isConnected ? .connected : .disconnected, source: .ioBluetooth,
                readStatus: .noReport, identityStrength: .strong, updatedAt: .distantPast), freshness: .expired))
        }
        // A vanished paired identity must not also remove its failure/recovery entry.
        let snapshotAddresses = Set(snapshots.compactMap {
            BluetoothDeviceControlSupport.normalizedAddress(from: $0.id)
        })
        for operation in operations.values.sorted(by: { $0.address < $1.address })
            where !represented.contains(operation.address) && !snapshotAddresses.contains(operation.address) {
            result.append(DecoratedBatterySnapshot(snapshot: BatterySnapshot(deviceID: operation.deviceID,
                displayName: operation.displayName, kind: operation.kind, percent: nil, chargeState: .unknown,
                connectionState: .unknown, source: .ioBluetooth, readStatus: .noReport,
                identityStrength: .strong, updatedAt: .distantPast), freshness: .expired))
        }
        // Presentation only: never persist these entries as battery history.
        return result
    }

    private func commandFailureDetail(_ code: Int32?) -> String {
        BeaconL10n.string("macOS rejected the request. Check Bluetooth permission, pairing and device availability, then retry.")
            + (code.map { " (\($0))" } ?? "")
    }

    private func update(address: String, token: UUID, phase: BluetoothConnectionPhase, detail: String) {
        guard var operation = operations[address], operation.id == token else { return }
        operation.phase = phase
        operation.detail = detail
        operations[address] = operation
    }

    private func finish(address: String, token: UUID, phase: BluetoothConnectionPhase, detail: String,
                        audioOutputUID: String? = nil) {
        guard var operation = operations[address], operation.id == token else { return }
        operation.phase = phase
        operation.detail = detail
        operation.audioOutputUID = audioOutputUID
        operations[address] = operation
        tasks[address] = nil
    }
}
