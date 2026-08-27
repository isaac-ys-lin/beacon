import SwiftUI

struct GeneralSettingsPane: View {
    let versionInfo: BeaconVersionInfo
    let onPreferencesReset: () -> Void

    @StateObject private var launchAtLoginModel: LaunchAtLoginSettingsModel
    @State private var isShowingClearHistoryConfirmation = false
    @State private var isShowingResetConfirmation = false
    @State private var operationMessage: String?

    init(
        versionInfo: BeaconVersionInfo = .current(),
        launchAtLoginModel: LaunchAtLoginSettingsModel? = nil,
        onPreferencesReset: @escaping () -> Void = {}
    ) {
        self.versionInfo = versionInfo
        self.onPreferencesReset = onPreferencesReset
        _launchAtLoginModel = StateObject(
            wrappedValue: launchAtLoginModel ?? LaunchAtLoginSettingsModel()
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    launchAtLoginCard
                    dataCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                aboutCard
                    .frame(width: 278, alignment: .topLeading)
            }
            .padding(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Clear all battery history?",
            isPresented: $isShowingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Battery History", role: .destructive) {
                BatteryHistoryStore.clear()
                operationMessage = BeaconL10n.string("Battery history cleared. New samples will appear after future refreshes.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved trend sample. Export a CSV first if you want a copy.")
        }
        .confirmationDialog(
            "Reset Beacon preferences?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Preferences", role: .destructive) {
                _ = BeaconPreferencesResetter.resetAppPreferences()
                onPreferencesReset()
                operationMessage = BeaconL10n.string("Preferences reset. Battery history and Launch at Login were kept.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores display, alert, HUD, device, and shortcut preferences. Battery history and Launch at Login are not changed.")
        }
        .onAppear {
            launchAtLoginModel.refresh()
        }
    }

    private var launchAtLoginCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "power.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(DesignTokens.Typography.sectionTitle)
                    Text("Uses the macOS login item service.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { launchAtLoginModel.isRequested },
                        set: { launchAtLoginModel.setEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Launch Beacon at login")
                .accessibilityIdentifier("general.launch-at-login.toggle")
            }

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(launchAtLoginModel.title)
                    .font(DesignTokens.Typography.captionEmphasis)
                    .foregroundStyle(launchAtLoginStatusColor)
                Text(launchAtLoginModel.subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if launchAtLoginModel.status == .requiresApproval {
                Button("Open Login Items Settings") {
                    BeaconGeneralSystemActions.openLoginItemsSettings()
                }
                .controlSize(.small)
            }

            if let errorMessage = launchAtLoginModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.critical)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("general.launch-at-login.error")
            }
        }
        .padding(14)
        .beaconSettingsCardSurface()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data and Preferences", systemImage: "externaldrive.fill")
                .font(DesignTokens.Typography.sectionTitle)

            Text("Beacon stores up to seven days of battery samples locally on this Mac.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)

            HStack(spacing: 8) {
                Button("Export History…") {
                    exportHistory()
                }
                .disabled(BatteryHistoryStore.sampleCount() == 0)
                .accessibilityIdentifier("general.history.export")

                Button("Clear History…", role: .destructive) {
                    isShowingClearHistoryConfirmation = true
                }
                .disabled(BatteryHistoryStore.sampleCount() == 0)
                .accessibilityIdentifier("general.history.clear")

                Spacer(minLength: 0)

                Text("\(BatteryHistoryStore.sampleCount()) samples")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            Divider()

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset App Preferences")
                        .font(DesignTokens.Typography.captionEmphasis)
                    Text("Keeps battery history and Launch at Login unchanged.")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
                Spacer()
                Button("Reset…", role: .destructive) {
                    isShowingResetConfirmation = true
                }
                .accessibilityIdentifier("general.preferences.reset")
            }

            if let operationMessage {
                Label(operationMessage, systemImage: "checkmark.circle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.charging)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("general.operation-result")
            }
        }
        .padding(14)
        .beaconSettingsCardSurface()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image("BeaconAppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Beacon")
                        .font(DesignTokens.Typography.windowTitle)
                    Text(versionInfo.displayText)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
            }

            Divider()

            Label("Direct Download", systemImage: "shippingbox.fill")
                .font(DesignTokens.Typography.captionEmphasis)

            Text("This build is distributed outside the Mac App Store.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)

            Text("Beacon does not contact an update service or download updates in the background. Install a newer signed build manually when one is provided.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Label("Local by Design", systemImage: "lock.shield.fill")
                .font(DesignTokens.Typography.captionEmphasis)

            Text("Battery reports and history stay on this Mac. Beacon has no account or cloud sync in this build.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .beaconSettingsCardSurface()
        .accessibilityIdentifier("general.about")
    }

    private var launchAtLoginStatusColor: Color {
        switch launchAtLoginModel.status {
        case .enabled:
            return DesignTokens.Palette.charging
        case .requiresApproval:
            return DesignTokens.Palette.warning
        case .notRegistered:
            return DesignTokens.Palette.secondaryText
        case .notFound:
            return DesignTokens.Palette.critical
        }
    }

    private func exportHistory() {
        do {
            let exported = try BatteryHistoryExportPanel.present(
                csvData: BatteryHistoryStore.csvData()
            )
            if exported {
                operationMessage = BeaconL10n.string("Battery history exported.")
            }
        } catch {
            operationMessage = BeaconL10n.format("Export failed: %@", error.localizedDescription)
        }
    }
}
