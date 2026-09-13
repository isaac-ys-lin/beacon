import SwiftUI

struct ConnectionActionHUDView: View {
    let operation: BluetoothConnectionOperation
    let showsDismissButton: Bool
    let onDismiss: () -> Void
    let onReview: () -> Void
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            if operation.phase.isInProgress {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(operation.phase.title)
            } else {
                Image(systemName: operation.phase.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(operation.phase.isFailure ? theme.statusLow : theme.statusOK)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(operation.displayName).font(.headline).lineLimit(1)
                    .accessibilityIdentifier("hud.connection.device")
                Text(operation.phase.title).font(.callout).lineLimit(2)
                    .accessibilityIdentifier("hud.connection.state")
                Text(operation.address).font(.caption2).monospaced().foregroundStyle(theme.textMuted)
                    .accessibilityLabel(BeaconL10n.format("Device identity: %@", operation.address))
                if !operation.phase.isInProgress {
                    Button("Review Result", action: onReview)
                        .accessibilityIdentifier("hud.connection.review")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsDismissButton {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                    .accessibilityIdentifier("hud.dismiss")
                    .help("Dismiss")
            }
        }
        .padding(18)
        .frame(width: 520, height: 150)
        .background(RoundedRectangle(cornerRadius: BatteryActionHUDView.cornerRadius)
            .fill(theme.panel.opacity(0.96))
            .overlay(RoundedRectangle(cornerRadius: BatteryActionHUDView.cornerRadius)
                .stroke(theme.hairlineDefault, lineWidth: 0.8)))
        .foregroundStyle(theme.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud.connection")
        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
    }

    private var appearanceTheme: BeaconAppearanceTheme {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
    }
    private var theme: BeaconThemePalette { appearanceTheme.palette(resolvedSystemScheme: colorScheme) }
}
