import SwiftUI

struct ActionHUDSettingsPane: View {
    @Binding var showActionHUD: Bool
    @Binding var showLowBatteryHUD: Bool
    @Binding var showChargedHUD: Bool
    @Binding var autoDismissEnabled: Bool
    @Binding var dismissDelaySeconds: Double
    @Binding var showDismissButton: Bool
    let lowBatteryThreshold: Int

    var body: some View {
        Form {
            Section {
                preview
                Toggle("Show Action HUD", isOn: $showActionHUD)
                    .accessibilityLabel(Text("Show Action HUD"))
            } footer: {
                Text("Show device connection progress, results, and battery alerts.")
            }

            Section {
                Toggle("Low battery", isOn: $showLowBatteryHUD)
                    .accessibilityLabel(Text("Low battery"))
                    .accessibilityIdentifier("hud.settings.low-battery")
                Toggle("Finished charging", isOn: $showChargedHUD)
                    .accessibilityLabel(Text("Finished charging"))
                    .accessibilityIdentifier("hud.settings.charged")
            } header: {
                Text("Events")
            }
            .disabled(!showActionHUD)

            Section {
                Toggle("Dismiss automatically", isOn: $autoDismissEnabled)
                    .accessibilityLabel(Text("Dismiss automatically"))
                    .disabled(!showDismissButton)
                    .help(BeaconL10n.string(
                        showDismissButton
                            ? "Keep the HUD visible until dismissed."
                            : "Enable the dismiss button before turning off automatic dismissal."
                    ))
                    .accessibilityIdentifier("hud.settings.auto-dismiss")

                LabeledContent("Dismiss after") {
                    HStack(spacing: 10) {
                        Slider(value: dismissDelayBinding, in: 2...10, step: 1)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            .accessibilityLabel("Dismiss after")
                            .accessibilityValue(Text(BeaconL10n.format("%@ sec", String(Int(clampedDismissDelay)))))
                        Text(BeaconL10n.format("%@ sec", String(Int(clampedDismissDelay))))
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                }
                .disabled(!autoDismissEnabled)
                .accessibilityIdentifier("hud.settings.dismiss-delay")

                Toggle("Show dismiss button", isOn: $showDismissButton)
                    .accessibilityLabel(Text("Show dismiss button"))
                    .disabled(!autoDismissEnabled)
                    .help(BeaconL10n.string(
                        autoDismissEnabled
                            ? "Show a close button on the HUD."
                            : "Automatic dismissal must stay on if the dismiss button is hidden."
                    ))
                    .accessibilityIdentifier("hud.settings.dismiss-button")
            } header: {
                Text("Behavior")
            } footer: {
                Text("The HUD always keeps at least one way to close it.")
            }
            .disabled(!showActionHUD)
        }
        .formStyle(.grouped)
        .onAppear {
            if !autoDismissEnabled && !showDismissButton {
                autoDismissEnabled = true
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 4) {
            BatteryActionHUDView(
                event: BatteryAlertEvent(
                    kind: .lowBattery, deviceID: "settings-mouse",
                    displayName: "Magic Mouse", percent: lowBatteryThreshold
                ),
                showsDismissButton: showDismissButton
            )
            .fixedSize()
            .scaleEffect(0.6)
            .frame(height: 50)
            BatteryActionHUDView(
                event: BatteryAlertEvent(
                    kind: .charged, deviceID: "settings-keyboard",
                    displayName: "Magic Keyboard", percent: 100
                ),
                showsDismissButton: showDismissButton
            )
            .fixedSize()
            .scaleEffect(0.6)
            .frame(height: 50)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .opacity(showActionHUD ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(BeaconL10n.string("Action HUD preview")))
        .accessibilityAddTraits(.isImage)
    }

    private var clampedDismissDelay: Double {
        Swift.max(2, Swift.min(10, dismissDelaySeconds))
    }

    private var dismissDelayBinding: Binding<Double> {
        Binding(
            get: { clampedDismissDelay },
            set: { dismissDelaySeconds = Swift.max(2, Swift.min(10, $0)) }
        )
    }
}
