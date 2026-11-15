import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    let versionInfo: BeaconVersionInfo
    let onPreferencesReset: () -> Void

    @StateObject private var launchAtLoginModel: LaunchAtLoginSettingsModel
    @State private var isShowingClearHistoryConfirmation = false
    @State private var isShowingResetConfirmation = false
    @State private var operationMessage: String?
    @State private var operationIsError = false

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
        Form {
            launchAtLoginSection
            historySection
            resetSection
            aboutSection
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear all battery history?",
            isPresented: $isShowingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Battery History", role: .destructive) {
                operationIsError = false
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
                operationIsError = false
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginModel.refresh(clearError: false)
        }
    }

    private var launchAtLoginSection: some View {
        Section {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLoginModel.isRequested },
                    set: { launchAtLoginModel.setEnabled($0) }
                )
            )
            .accessibilityLabel("Launch Beacon at login")
            .accessibilityIdentifier("general.launch-at-login.toggle")

            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(launchAtLoginStatusColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(launchAtLoginModel.title)
                        .accessibilityIdentifier("general.launch-at-login.status")
                }
            }

            HStack(spacing: 8) {
                Button("Open Login Items Settings") {
                    BeaconGeneralSystemActions.openLoginItemsSettings()
                }
                .accessibilityIdentifier("general.launch-at-login.settings")
                Spacer(minLength: 0)
                Button {
                    launchAtLoginModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh")
                .accessibilityIdentifier("general.launch-at-login.refresh")
            }

            if let errorMessage = launchAtLoginModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Palette.critical)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("general.launch-at-login.error")
            }
        } footer: {
            Text(launchAtLoginModel.subtitle)
        }
    }

    private var historySection: some View {
        Section {
            LabeledContent("Battery History") {
                Text("\(BatteryHistoryStore.sampleCount()) samples")
            }
            HStack(spacing: 8) {
                Button("Export History…") {
                    exportHistory()
                }
                .accessibilityIdentifier("general.history.export")

                Button("Clear History…", role: .destructive) {
                    isShowingClearHistoryConfirmation = true
                }
                .accessibilityIdentifier("general.history.clear")
            }
            .disabled(BatteryHistoryStore.sampleCount() == 0)

            if let operationMessage {
                Label(operationMessage, systemImage: operationIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(operationIsError ? DesignTokens.Palette.critical : DesignTokens.Palette.charging)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("general.operation-result")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Beacon stores up to seven days of battery samples locally on this Mac.")
        }
    }

    private var resetSection: some View {
        Section {
            LabeledContent("Reset App Preferences") {
                Button("Reset…", role: .destructive) {
                    isShowingResetConfirmation = true
                }
                .accessibilityIdentifier("general.preferences.reset")
            }
        } footer: {
            Text("Keeps battery history and Launch at Login unchanged.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "\(versionInfo.version) (\(versionInfo.build))")
            Link(destination: BeaconGeneralSystemActions.releasesURL) {
                Text("Direct Download")
            }
            .accessibilityIdentifier("general.releases")
            Link(destination: BeaconGeneralSystemActions.supportURL) {
                Text("Report")
            }
            .accessibilityIdentifier("general.support")
            Link(destination: BeaconGeneralSystemActions.localDataURL) {
                Text("Data and Preferences")
            }
            .accessibilityIdentifier("general.local-data")
        } header: {
            Text("About")
        } footer: {
            Text("Distributed outside the Mac App Store. Beacon never downloads updates in the background, and battery reports stay on this Mac.")
        }
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
                operationIsError = false
                operationMessage = BeaconL10n.string("Battery history exported.")
            }
        } catch {
            operationIsError = true
            operationMessage = BeaconL10n.format("Export failed: %@", error.localizedDescription)
        }
    }
}
