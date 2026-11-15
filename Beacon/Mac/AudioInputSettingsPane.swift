import SwiftUI

struct AudioInputSettingsPane: View {
    @ObservedObject private var controller = AudioInputController.shared
    @State private var preferences = AudioInputController.shared.preferences

    var body: some View {
        Form {
            Section {
                Toggle("Lock audio input", isOn: binding(\.isEnabled))
                    .accessibilityIdentifier("audio.lock")
                Picker("Preferred input", selection: binding(\.preferredUID)) {
                    Text("Choose…").tag(String?.none)
                    deviceOptions(including: preferences.preferredUID)
                }
                .disabled(!preferences.isEnabled)
                Picker("Fallback input", selection: binding(\.fallbackUID)) {
                    Text("None").tag(String?.none)
                    deviceOptions(including: preferences.fallbackUID)
                }
                .disabled(!preferences.isEnabled)
                Toggle("Show a HUD when Beacon restores the input", isOn: binding(\.notifiesOnRestore))
                    .disabled(!preferences.isEnabled)
            } header: {
                Text("Audio Input Lock")
            } footer: {
                Text("Keeps your Mac on the preferred microphone. When an app, Control Center or a newly connected headset switches the input, Beacon switches it back. The fallback is used while the preferred microphone is disconnected.")
            }

            Section {
                LabeledContent("Current input") {
                    Text(currentName)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("audio.current")
            } footer: {
                Text("Turn a headset microphone off with the Toggle Headset Microphone shortcut in Quick Actions. Using the built-in microphone lets AirPods and other headsets keep their high-quality playback.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            controller.start()
            preferences = controller.preferences
        }
    }

    private var currentName: String {
        controller.devices.first { $0.uid == controller.currentUID }?.name ?? BeaconL10n.string("None")
    }

    @ViewBuilder
    private func deviceOptions(including selectedUID: String?) -> some View {
        ForEach(controller.devices) { device in
            Text(device.name).tag(Optional(device.uid))
        }
        // Keep a remembered but disconnected device selectable, as System Settings does.
        if let selectedUID, !controller.devices.contains(where: { $0.uid == selectedUID }) {
            Text(BeaconL10n.string("Disconnected device")).tag(Optional(selectedUID))
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AudioInputLockPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { newValue in
                preferences[keyPath: keyPath] = newValue
                if keyPath == \AudioInputLockPreferences.isEnabled, preferences.isEnabled, preferences.preferredUID == nil {
                    preferences.preferredUID = controller.currentUID
                }
                controller.update(preferences)
            }
        )
    }
}
