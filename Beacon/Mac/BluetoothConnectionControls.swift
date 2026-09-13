import SwiftUI

struct BluetoothConnectionControls: View {
    let item: DeviceListItem
    @ObservedObject var controller: BluetoothConnectionController
    var compact = false

    var body: some View {
        if let address = BluetoothDeviceControlSupport.normalizedAddress(from: item.id) {
            let paired = controller.device(for: item.id)
            let operation = controller.operation(for: item.id)
            let busy = operation?.phase.isInProgress == true
            VStack(alignment: .leading, spacing: 7) {
                if let operation {
                    HStack(alignment: .top, spacing: 7) {
                        if busy { ProgressView().controlSize(.small) }
                        else {
                            Image(systemName: operation.phase.isFailure ? "exclamationmark.triangle" : "checkmark.circle")
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if !busy { Text("Last operation result").font(.caption2).foregroundStyle(.secondary) }
                            Text(operation.phase.title).font(.caption.bold())
                                .accessibilityIdentifier("connection.state.\(address)")
                            if !compact || operation.phase.isFailure {
                                Text(operation.detail).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else if !compact {
                    Text(BeaconL10n.string(controller.authorizationFailure != nil
                        ? "Allow Beacon in Bluetooth Privacy Settings, then check again."
                        : paired == nil ? "This device is not in the current paired-device list."
                        : "Connection control does not require a battery report."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if compact && controller.pairedDevices.filter({ $0.displayName == item.displayName }).count > 1 {
                    Text(address).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        .accessibilityLabel(Text(BeaconL10n.format("Device identity: %@", address)))
                }
                HStack(spacing: 8) {
                    Button(BeaconL10n.string(paired?.isConnected == true && paired?.requiresAudioConfirmation == true
                        ? "Use for Audio" : "Connect")) { run(.connect) }
                        .disabled(busy || paired == nil || (paired?.isConnected == true && paired?.requiresAudioConfirmation != true))
                        .accessibilityIdentifier("connection.connect.\(address)")
                    Button("Disconnect") { run(.disconnect) }
                        .disabled(busy || paired?.isConnected != true)
                        .accessibilityIdentifier("connection.disconnect.\(address)")
                    if let operation, operation.phase.isFailure {
                        Button("Check Result") {
                            controller.perform(operation.action, deviceID: item.id,
                                displayName: item.displayName, verifyOnly: true)
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("connection.check.\(address)")
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
                if let operation, operation.phase.isFailure {
                    HStack(spacing: 8) {
                        Button("Try Again") { run(operation.action) }
                            .accessibilityIdentifier("connection.retry.\(address)")
                        Button(BeaconL10n.string(operation.phase == .audioUnverified ? "Sound Settings"
                            : operation.phase == .permissionDenied ? "Privacy & Security" : "Bluetooth Settings")) {
                            if operation.phase == .audioUnverified { BeaconSystemSettingsActions.openSoundSettings() }
                            else if operation.phase == .permissionDenied { DeviceSetupSystemActions.openPrivacySettings() }
                            else { BeaconSystemSettingsActions.openBluetoothSettings() }
                        }
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                }
                if controller.authorizationFailure != nil && operation == nil {
                    Button("Privacy & Security", action: DeviceSetupSystemActions.openPrivacySettings)
                }
                if !compact {
                    DisclosureGroup("Connection Details") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(address).textSelection(.enabled)
                            if let uid = operation?.audioOutputUID { Text(uid).textSelection(.enabled) }
                            Text("Device names are not used to match Bluetooth identities or audio outputs.")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(compact ? 0 : 12)
        }
    }

    private func run(_ action: BluetoothConnectionAction) {
        controller.perform(action, deviceID: item.id, displayName: item.displayName)
    }
}
