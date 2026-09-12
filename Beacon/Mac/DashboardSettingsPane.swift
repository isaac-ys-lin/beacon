import SwiftUI

struct DashboardSettingsPane: View {
    let snapshots: [DecoratedBatterySnapshot]
    var isPreviewingData = false
    @Binding var showMenuBarBattery: Bool
    @Binding var showDesktopWidget: Bool
    @Binding var desktopWidgetStyleRawValue: String
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue

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
                    Toggle("Show lowest battery in menu bar", isOn: $showMenuBarBattery)
                } header: {
                    Text("Menu Bar Dashboard")
                } footer: {
                    Text("Choose the compact details shown when the menu bar icon opens the battery dashboard.")
                }

                Section {
                    Toggle("Show floating desktop widget", isOn: $showDesktopWidget)
                    Picker("Widget size", selection: $desktopWidgetStyleRawValue) {
                        ForEach(DesktopWidgetStyle.allCases) { style in
                            Image(systemName: style.symbolName)
                                .tag(style.rawValue)
                                .accessibilityLabel(style.accessibilityTitle)
                                .help(style.accessibilityTitle)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!showDesktopWidget)
                } header: {
                    Text("Desktop Widget")
                } footer: {
                    Text("A lightweight Batteries widget stays on screen while Beacon is running.")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sample Preview")
                        .font(DesignTokens.Typography.captionEmphasis)
                    Text("Sample devices illustrate the layout; they are not connected-device readings.")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    StatusWindowPreview(showsMenuBarBattery: showMenuBarBattery)
                        .frame(width: 292)
                    Divider()
                    HStack {
                        Text("Desktop Widget")
                            .font(DesignTokens.Typography.captionEmphasis)
                        Spacer()
                        Image(systemName: desktopWidgetStyle.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(DesignTokens.Palette.accent)
                            .accessibilityLabel(desktopWidgetStyle.accessibilityTitle)
                            .help(desktopWidgetStyle.accessibilityTitle)
                    }
                    Text(BeaconL10n.string(usesSamplePreview ? "Sample Preview" : "Latest Device Reports"))
                        .font(DesignTokens.Typography.captionEmphasis)
                        .accessibilityIdentifier("dashboard.preview.provenance")
                    Text(BeaconL10n.string(usesSamplePreview
                        ? "Sample devices illustrate the layout; they are not connected-device readings."
                        : "This preview uses the latest stored device reports, which may be out of date."))
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    BatteryDesktopWidgetView(
                        snapshots: desktopWidgetPreviewSnapshots,
                        style: desktopWidgetStyle,
                        onOpenSettings: {}
                    )
                    .scaleEffect(0.74, anchor: .topLeading)
                    .frame(
                        width: desktopWidgetStyle.width * 0.74,
                        height: desktopWidgetStyle.height * 0.74,
                        alignment: .topLeading
                    )
                    .opacity(showDesktopWidget ? 1 : 0.5)
                    .allowsHitTesting(false)
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

    private var desktopWidgetStyle: DesktopWidgetStyle {
        DesktopWidgetStyle(rawValue: desktopWidgetStyleRawValue) ?? .compact
    }

    private var desktopWidgetPreviewSnapshots: [DecoratedBatterySnapshot] {
        if !snapshots.isEmpty { return snapshots }
        let now = Date()
        return [
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-keyboard", displayName: "Magic Keyboard", kind: .keyboard,
                    percent: 82, chargeState: .unplugged, source: .coreBluetooth, updatedAt: now
                ), freshness: .fresh
            ),
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-mouse", displayName: "Magic Mouse", kind: .mouse,
                    percent: 24, chargeState: .unplugged, source: .coreBluetooth,
                    updatedAt: now.addingTimeInterval(-600)
                ), freshness: .stale
            ),
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-airpods", displayName: "AirPods Pro", kind: .airPods,
                    percent: 18, chargeState: .unplugged, source: .coreBluetooth, updatedAt: now
                ), freshness: .fresh
            ),
        ]
    }
}
