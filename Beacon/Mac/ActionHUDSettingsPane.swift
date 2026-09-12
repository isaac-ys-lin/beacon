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
        HStack(alignment: .top, spacing: 18) {
            Form {
                Section {
                    Toggle("Show Action HUD", isOn: $showActionHUD)
                } footer: {
                    Text("Show polished in-app alerts for important battery events.")
                }

                Section {
                    eventToggle(
                        title: "Low battery",
                        subtitle: "Show when a device drops below its alert level.",
                        isOn: $showLowBatteryHUD,
                        identifier: "hud.settings.low-battery"
                    )
                    eventToggle(
                        title: "Finished charging",
                        subtitle: "Show when an opted-in device reaches full charge.",
                        isOn: $showChargedHUD,
                        identifier: "hud.settings.charged"
                    )
                } header: {
                    Text("Events")
                }

                Section {
                    Toggle("Dismiss automatically", isOn: $autoDismissEnabled)
                        .disabled(!showActionHUD || !showDismissButton)
                        .help(BeaconL10n.string(
                            showDismissButton
                                ? "Keep the HUD visible until dismissed."
                                : "Enable the dismiss button before turning off automatic dismissal."
                        ))
                        .accessibilityIdentifier("hud.settings.auto-dismiss")

                    HStack(spacing: 10) {
                        Text("Dismiss after")
                        Slider(value: dismissDelayBinding, in: 2...10, step: 1)
                            .accessibilityLabel("Dismiss after")
                            .accessibilityValue(Text(BeaconL10n.format("%@ sec", String(Int(clampedDismissDelay)))))
                        Text(BeaconL10n.format("%@ sec", String(Int(clampedDismissDelay))))
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                    .disabled(!showActionHUD || !autoDismissEnabled)
                    .opacity(showActionHUD && autoDismissEnabled ? 1 : 0.45)
                    .accessibilityIdentifier("hud.settings.dismiss-delay")

                    Toggle("Show dismiss button", isOn: $showDismissButton)
                        .disabled(!showActionHUD || !autoDismissEnabled)
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
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ScrollView { previewPanel }.frame(width: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if !autoDismissEnabled && !showDismissButton {
                autoDismissEnabled = true
            }
        }
    }

    private func eventToggle(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isOn: Binding<Bool>,
        identifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DesignTokens.Typography.captionEmphasis)
                Text(subtitle)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
        .accessibilityIdentifier(identifier)
        .disabled(!showActionHUD)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview").font(DesignTokens.Typography.sectionTitle)
            VStack(spacing: 10) {
                BatteryActionHUDView(
                    event: BatteryAlertEvent(
                        kind: .lowBattery, deviceID: "settings-mouse",
                        displayName: "Magic Mouse", percent: lowBatteryThreshold
                    ),
                    showsDismissButton: showDismissButton
                )
                .scaleEffect(0.58)
                .frame(width: 248, height: 54)
                BatteryActionHUDView(
                    event: BatteryAlertEvent(
                        kind: .charged, deviceID: "settings-keyboard",
                        displayName: "Magic Keyboard", percent: 100
                    ),
                    showsDismissButton: showDismissButton
                )
                .scaleEffect(0.58)
                .frame(width: 248, height: 54)
            }
            .opacity(showActionHUD ? 1 : 0.45)
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                hudStateRow(BeaconL10n.string("Low battery"), isOn: showLowBatteryHUD)
                hudStateRow(BeaconL10n.string("Finished charging"), isOn: showChargedHUD)
                hudStateRow(
                    BeaconL10n.format("Auto dismiss (%d sec)", Int(clampedDismissDelay)),
                    isOn: autoDismissEnabled
                )
                hudStateRow(BeaconL10n.string("Dismiss button"), isOn: showDismissButton)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .beaconSettingsCardSurface()
        .padding(.top, 18)
    }

    private func hudStateRow(_ title: String, isOn: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Spacer(minLength: 0)
        }
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
