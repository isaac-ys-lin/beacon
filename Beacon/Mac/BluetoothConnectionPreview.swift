#if DEBUG
import Foundation

/// The app's existing DEBUG process fixture seam. No Bluetooth/Core Audio calls, preference
/// writes, or history writes occur here. UI tests always display the preview-data banner.
@MainActor
private final class BluetoothConnectionPreview {
    let scenario: String
    var requested: [String: BluetoothConnectionAction] = [:]
    var requestedAt: [String: Date] = [:]
    var connected = Set<String>()
    let addresses = ["aa:bb:cc:dd:ee:01", "aa:bb:cc:dd:ee:02"]

    init(scenario: String) { self.scenario = scenario }

    var client: BluetoothConnectionClient {
        BluetoothConnectionClient(pairedDevices: { [self] in
            addresses.map { PairedBluetoothDevice(address: $0, displayName: "Test Headphones",
                kind: .bluetoothPeripheral, isConnected: connected.contains($0), requiresAudioConfirmation: true) }
        }, request: { [self] address, action in
            requested[address] = action
            requestedAt[address] = Date()
            return scenario == "denied" ? .init(failure: .permissionDenied, errorCode: -1) : .init()
        }, observe: { [self] address in
            guard let action = requested[address], let started = requestedAt[address] else {
                return .init(isPaired: true, isConnected: connected.contains(address))
            }
            let elapsed = Date().timeIntervalSince(started)
            guard elapsed >= 1.5, scenario != "timeout" else {
                return .init(isPaired: true, isConnected: connected.contains(address))
            }
            if action == .disconnect {
                connected.remove(address)
                return .init(isPaired: true, isConnected: false)
            }
            if scenario == "dropped", elapsed > 1.8 {
                connected.remove(address)
                return .init(isPaired: true, isConnected: false)
            }
            connected.insert(address)
            let confirmed = scenario != "audio-unverified" && scenario != "dropped" && elapsed >= 2.0
            return .init(isPaired: true, isConnected: true,
                confirmedAudioOutputUID: confirmed ? "fixture-output-\(address)" : nil)
        }, selectAudioOutput: { _ in 0 })
    }
}

@MainActor
extension BluetoothConnectionController {
    static func preview(scenario: String) -> BluetoothConnectionController {
        BluetoothConnectionController(client: BluetoothConnectionPreview(scenario: scenario).client,
            pollInterval: .milliseconds(150), maximumObservations: 24)
    }
}
#endif
