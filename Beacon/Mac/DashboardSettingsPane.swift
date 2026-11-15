import SwiftUI

struct DashboardSettingsPane: View {
    let snapshots: [DecoratedBatterySnapshot]
    var isPreviewingData = false
    @Binding var showMenuBarBattery: Bool
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @AppStorage(MacPowerSourceReader.showsThisMacDefaultsKey) private var showsThisMac = true

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Form {
                Section {
                    Picker("Theme", selection: $appearanceThemeRawValue) {
                        ForEach(BeaconAppearanceTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your current macOS appearance. Dark and Light keep Beacon fixed.")
                }

                Section {
                    Toggle("Show this Mac's battery", isOn: $showsThisMac)
                    Toggle("Show lowest battery in menu bar", isOn: $showMenuBarBattery)
                } header: {
                    Text("Menu Bar Dashboard")
                } footer: {
                    Text("The dashboard can include this Mac's built-in battery. The menu bar percentage shows the lowest accessory, since macOS already shows the Mac's own battery.")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(BeaconL10n.string(usesSamplePreview ? "Sample Preview" : "Latest Device Reports"))
                        .font(DesignTokens.Typography.captionEmphasis)
                        .accessibilityIdentifier("dashboard.preview.provenance")
                    Text(BeaconL10n.string(usesSamplePreview
                        ? "Sample devices illustrate the layout; they are not connected-device readings."
                        : "This preview uses the latest stored device reports, which may be out of date."))
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    StatusWindowPreview(showsMenuBarBattery: showMenuBarBattery)
                        .frame(width: 292)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(BeaconL10n.string("Battery dashboard preview")))
                        .accessibilityAddTraits(.isImage)
                }
            }
            .padding(14)
            .frame(width: 322, alignment: .topLeading)
            .beaconSettingsCardSurface()
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: showMenuBarBattery) { _, _ in
            StatusWindowPreferences.notifyChanged()
        }
    }

    private var usesSamplePreview: Bool { isPreviewingData || snapshots.isEmpty }
}
