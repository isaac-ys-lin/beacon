import SwiftUI

struct DashboardSettingsPane: View {
    let snapshots: [DecoratedBatterySnapshot]
    @Binding var showMenuBarBattery: Bool
    @Binding var showDesktopWidget: Bool
    @Binding var desktopWidgetStyleRawValue: String
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Form {
                Section {
                    Picker("Theme", selection: $appearanceThemeRawValue) {
                        ForEach(BatteryHubAppearanceTheme.allCases) { theme in
                            Text(theme.title)
                                .tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your current macOS appearance. Dark and Light keep BatteryHub fixed.")
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
                    Text("A lightweight Batteries widget stays on screen while BatteryHub is running.")
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                StatusWindowPreview(
                    showsMenuBarBattery: showMenuBarBattery
                )
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
            }
            .padding(14)
            .frame(width: 322, alignment: .topLeading)
            .background(settingsCardBackground)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: showMenuBarBattery) { _, _ in
            StatusWindowPreferences.notifyChanged()
        }
    }

    private var desktopWidgetStyle: DesktopWidgetStyle {
        DesktopWidgetStyle(rawValue: desktopWidgetStyleRawValue) ?? .compact
    }

    private var desktopWidgetPreviewSnapshots: [DecoratedBatterySnapshot] {
        if !snapshots.isEmpty { return snapshots }
        let now = Date()
        return [
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-keyboard",
                    displayName: "Magic Keyboard",
                    kind: .keyboard,
                    percent: 82,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: now
                ),
                freshness: .fresh
            ),
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-mouse",
                    displayName: "Magic Mouse",
                    kind: .mouse,
                    percent: 24,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: now.addingTimeInterval(-600)
                ),
                freshness: .stale
            ),
            DecoratedBatterySnapshot(
                snapshot: BatterySnapshot(
                    deviceID: "preview-airpods",
                    displayName: "AirPods Pro",
                    kind: .airPods,
                    percent: 18,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: now
                ),
                freshness: .fresh
            ),
        ]
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
