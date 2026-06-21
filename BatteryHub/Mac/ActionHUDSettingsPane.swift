import SwiftUI

struct ActionHUDSettingsPane: View {
    @Binding var showActionHUD: Bool
    @Binding var showLowBatteryHUD: Bool
    @Binding var showChargedHUD: Bool
    @Binding var autoDismissActionHUD: Bool
    @Binding var actionHUDDismissDelay: Double
    @Binding var showActionHUDDismissButton: Bool
    let lowBatteryThreshold: Int

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Form {
                Section {
                    Toggle("Show Action HUD", isOn: $showActionHUD)
                } header: {
                    Text("Action HUD")
                } footer: {
                    Text("Show polished in-app alerts for important battery events.")
                }

                Section {
                    ActionHUDEventToggle(
                        title: "Low battery",
                        subtitle: "Show when a device drops below its alert level.",
                        systemImage: "battery.25",
                        color: DesignTokens.Palette.critical,
                        isOn: $showLowBatteryHUD
                    )
                    .disabled(!showActionHUD)
                    .opacity(showActionHUD ? 1 : 0.45)

                    ActionHUDEventToggle(
                        title: "Finished charging",
                        subtitle: "Show when an opted-in device reaches full charge.",
                        systemImage: "battery.100",
                        color: DesignTokens.Palette.charging,
                        isOn: $showChargedHUD
                    )
                    .disabled(!showActionHUD)
                    .opacity(showActionHUD ? 1 : 0.45)
                } header: {
                    Text("Events")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 350, maxWidth: 350, maxHeight: .infinity, alignment: .topLeading)

            previewPanel
        }
        .frame(maxWidth: 650, maxHeight: .infinity, alignment: .top)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Preview")
                    .font(DesignTokens.Typography.sectionTitle)
                Text(autoDismissActionHUD ? "Dismisses after \(Int(clampedActionHUDDismissDelay)) seconds" : "Stays until dismissed")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            VStack(spacing: 10) {
                BatteryActionHUDView(
                    event: BatteryAlertEvent(
                        kind: .lowBattery,
                        deviceID: "settings-mouse",
                        displayName: "Magic Mouse",
                        percent: lowBatteryThreshold
                    ),
                    showsDismissButton: showActionHUDDismissButton
                )
                .scaleEffect(0.58)
                .frame(width: 302, height: 54)

                BatteryActionHUDView(
                    event: BatteryAlertEvent(
                        kind: .charged,
                        deviceID: "settings-keyboard",
                        displayName: "Magic Keyboard",
                        percent: 100
                    ),
                    showsDismissButton: showActionHUDDismissButton
                )
                .scaleEffect(0.58)
                .frame(width: 302, height: 54)
            }
            .opacity(showActionHUD ? 1 : 0.45)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                hudStateRow("Low battery", isOn: showLowBatteryHUD)
                hudStateRow("Finished charging", isOn: showChargedHUD)
                hudStateRow("Manual close", isOn: showActionHUDDismissButton)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Behavior")
                    .font(DesignTokens.Typography.captionEmphasis)

                Toggle("Auto-dismiss", isOn: $autoDismissActionHUD)
                    .disabled(!showActionHUD)

                HStack {
                    Slider(value: actionHUDDismissDelayBinding, in: 2...10, step: 1)
                        .disabled(!showActionHUD || !autoDismissActionHUD)
                    Text("\(Int(clampedActionHUDDismissDelay))s")
                        .font(DesignTokens.Typography.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.accent)
                        .frame(width: 30, alignment: .trailing)
                }
                .opacity(autoDismissActionHUD ? 1 : 0.45)

                Toggle("Show dismiss button", isOn: $showActionHUDDismissButton)
                    .disabled(!showActionHUD)
            }
            .font(DesignTokens.Typography.controlLabel)
        }
        .padding(16)
        .frame(width: 330, alignment: .topLeading)
        .background(settingsCardBackground)
        .padding(.top, 18)
    }

    private var clampedActionHUDDismissDelay: Double {
        Swift.max(2, Swift.min(10, actionHUDDismissDelay))
    }

    private var actionHUDDismissDelayBinding: Binding<Double> {
        Binding(
            get: { clampedActionHUDDismissDelay },
            set: { actionHUDDismissDelay = $0.rounded() }
        )
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

    @ViewBuilder
    private var settingsCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.regularMaterial)
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7))
        } else {
            shape
                .fill(.regularMaterial)
                .overlay(shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7))
        }
    }
}
