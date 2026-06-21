import SwiftUI

struct QuickActionsSettingsPane: View {
    @Binding var preferences: BatteryHubQuickActionPreferences

    var body: some View {
        Form {
            Section {
                AutomationShortcutsBanner()

                ForEach(BatteryHubQuickAction.allCases) { action in
                    QuickActionSettingsRow(
                        action: action,
                        isEnabled: Binding(
                            get: { preferences.isEnabled(action) },
                            set: { setQuickActionEnabled($0, for: action) }
                        )
                    )
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Enabled shortcuts are registered globally while BatteryHub is running. Supported actions also appear in macOS Shortcuts.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Core actions are available now: dashboard, refresh, settings, add device, Bluetooth pairing, connect nearby, and disconnect lowest.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.Palette.charging)
                    Label("Shortcuts can return battery summaries and trigger supported Bluetooth device controls.", systemImage: "list.bullet.rectangle")
                        .foregroundStyle(DesignTokens.Palette.charging)
                    Label("Cross-Mac transfer remains unavailable in this build.", systemImage: "minus.circle")
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
                .font(DesignTokens.Typography.caption)
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
    }

    private func setQuickActionEnabled(_ isEnabled: Bool, for action: BatteryHubQuickAction) {
        let nextPreferences = preferences.setting(isEnabled, for: action)
        preferences = nextPreferences
        nextPreferences.save()
    }
}
