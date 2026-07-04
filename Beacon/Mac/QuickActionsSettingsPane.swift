import SwiftUI

struct QuickActionsSettingsPane: View {
    @Binding var preferences: BeaconQuickActionPreferences

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            shortcutsForm
            statusPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shortcutsForm: some View {
        Form {
            Section {
                AutomationShortcutsBanner()

                ForEach(BeaconQuickAction.allCases) { action in
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
                Text("Enabled shortcuts are registered globally while Beacon is running. Supported actions also appear in macOS Shortcuts.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 372, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusPanel: some View {
        let summary = quickActionSettingsSummary(for: preferences)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: resolveSymbol("sparkles.rectangle.stack", fallback: "sparkles"))
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Automation")
                        .font(DesignTokens.Typography.sectionTitle)
                    Text("Global shortcuts and Shortcuts actions.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
            }

            VStack(spacing: 8) {
                summaryMetricRow(
                    "Enabled",
                    value: "\(summary.enabledSupportedActions.count) of \(summary.supportedActionCount)",
                    systemImage: "checkmark.circle.fill",
                    color: DesignTokens.Palette.charging
                )
                summaryMetricRow(
                    "Default On",
                    value: "\(summary.defaultEnabledActionCount)",
                    systemImage: "bolt.circle.fill",
                    color: DesignTokens.Palette.accent
                )
                summaryMetricRow(
                    "Excluded",
                    value: "\(summary.unsupportedActions.count)",
                    systemImage: "minus.circle.fill",
                    color: DesignTokens.Palette.secondaryText
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Enabled Shortcuts")
                    .font(DesignTokens.Typography.captionEmphasis)

                if summary.enabledSupportedActions.isEmpty {
                    Text("No shortcuts enabled")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                } else {
                    ForEach(Array(summary.enabledSupportedActions.prefix(4)), id: \.id) { action in
                        actionChip(for: action)
                    }

                    if summary.enabledSupportedActions.count > 4 {
                        Text("+\(summary.enabledSupportedActions.count - 4) more")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Palette.secondaryText)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                statusRow("Core actions available", isActive: true)
                statusRow("macOS Shortcuts supported", isActive: true)
                statusRow("Cross-Mac transfer excluded", isActive: false)
            }
        }
        .padding(16)
        .frame(width: 278, alignment: .topLeading)
        .beaconSettingsCardSurface()
        .padding(.top, 18)
    }

    private func setQuickActionEnabled(_ isEnabled: Bool, for action: BeaconQuickAction) {
        let nextPreferences = preferences.setting(isEnabled, for: action)
        preferences = nextPreferences
        nextPreferences.save()
    }

    private func summaryMetricRow(
        _ title: String,
        value: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Spacer(minLength: 0)
            Text(value)
                .font(DesignTokens.Typography.captionEmphasis)
                .foregroundStyle(DesignTokens.Palette.text)
        }
    }

    private func actionChip(for action: BeaconQuickAction) -> some View {
        HStack(spacing: 7) {
            Image(systemName: action.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Palette.accent)
            Text(action.title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(0.92))
        )
    }

    private func statusRow(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Spacer(minLength: 0)
        }
    }
}

struct QuickActionSettingsSummary: Equatable {
    let supportedActions: [BeaconQuickAction]
    let enabledSupportedActions: [BeaconQuickAction]
    let disabledSupportedActions: [BeaconQuickAction]
    let unsupportedActions: [BeaconQuickAction]
    let defaultEnabledActionCount: Int

    var supportedActionCount: Int { supportedActions.count }
}

func quickActionSettingsSummary(
    for preferences: BeaconQuickActionPreferences
) -> QuickActionSettingsSummary {
    let supportedActions = BeaconQuickAction.allCases.filter(\.isSupported)
    let enabledSupportedActions = supportedActions.filter { preferences.isEnabled($0) }
    let disabledSupportedActions = supportedActions.filter { !preferences.isEnabled($0) }
    let unsupportedActions = BeaconQuickAction.allCases.filter { !$0.isSupported }
    let defaultEnabledActionCount = supportedActions.filter(\.isEnabledByDefault).count

    return QuickActionSettingsSummary(
        supportedActions: supportedActions,
        enabledSupportedActions: enabledSupportedActions,
        disabledSupportedActions: disabledSupportedActions,
        unsupportedActions: unsupportedActions,
        defaultEnabledActionCount: defaultEnabledActionCount
    )
}
