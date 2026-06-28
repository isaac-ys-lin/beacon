import SwiftUI

enum BatteryHUDPreferences {
    static let showActionHUDKey = "Beacon.showActionHUD"
    static let lowBatteryHUDEnabledKey = "Beacon.actionHUD.lowBatteryEnabled"
    static let chargedHUDEnabledKey = "Beacon.actionHUD.chargedEnabled"
    static let autoDismissEnabledKey = "Beacon.actionHUD.autoDismissEnabled"
    static let dismissDelaySecondsKey = "Beacon.actionHUD.dismissDelaySeconds"
    static let showDismissButtonKey = "Beacon.actionHUD.showDismissButton"

    static let defaultDismissDelaySeconds = 4.0

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: showActionHUDKey) != nil else {
            return true
        }
        return defaults.bool(forKey: showActionHUDKey)
    }

    static func isEnabled(for kind: BatteryAlertKind, defaults: UserDefaults = .standard) -> Bool {
        guard isEnabled(defaults: defaults) else { return false }
        let key = eventKey(for: kind)
        guard defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
    }

    static func eventKey(for kind: BatteryAlertKind) -> String {
        switch kind {
        case .lowBattery:
            return lowBatteryHUDEnabledKey
        case .charged:
            return chargedHUDEnabledKey
        }
    }

    static func isAutoDismissEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: autoDismissEnabledKey) != nil else {
            return true
        }
        return defaults.bool(forKey: autoDismissEnabledKey)
    }

    static func showsDismissButton(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: showDismissButtonKey) != nil else {
            return false
        }
        return defaults.bool(forKey: showDismissButtonKey)
    }

    static func dismissDelaySeconds(defaults: UserDefaults = .standard) -> Double {
        let rawValue: Double
        if defaults.object(forKey: dismissDelaySecondsKey) == nil {
            rawValue = defaultDismissDelaySeconds
        } else {
            rawValue = defaults.double(forKey: dismissDelaySecondsKey)
        }
        return Swift.max(2, Swift.min(10, rawValue))
    }
}

struct BatteryActionHUDView: View {
    static let cornerRadius: CGFloat = 24

    let event: BatteryAlertEvent
    var showsDismissButton = BatteryHUDPreferences.showsDismissButton()
    var onDismiss: (() -> Void)?
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 52, height: 52)

                BeaconLogoMark(size: 30)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignTokens.Typography.rowTitleEmphasis)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let percent = event.percent {
                Text("\(percent)%")
                    .font(DesignTokens.Typography.percentLarge)
                    .monospacedDigit()
                    .foregroundStyle(iconColor)
                    .frame(minWidth: 58, alignment: .trailing)
            }

            if showsDismissButton {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(theme.hover.opacity(0.70))
                        )
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 520, height: 92)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(theme.panel.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .stroke(theme.hairlineDefault, lineWidth: 0.8)
                )
                .shadow(color: theme.shadow, radius: 32, x: 0, y: 16)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
    }

    private var title: String {
        switch event.kind {
        case .lowBattery:
            return "\(event.displayName) is running low"
        case .charged:
            return "\(event.displayName) is charged"
        }
    }

    private var subtitle: String {
        switch event.kind {
        case .lowBattery:
            if let percent = event.percent {
                return "Down to \(percent)%. Charge it soon."
            }
            return "Battery below alert level."
        case .charged:
            return "Charged alert point reached."
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .lowBattery:
            guard let percent = event.percent else { return theme.statusLow }
            return percent <= 10 ? theme.statusCritical : theme.statusLow
        case .charged:
            return theme.statusOK
        }
    }

    private var iconBackground: Color {
        switch event.kind {
        case .lowBattery:
            return iconColor.opacity(0.16)
        case .charged:
            return theme.accentSoft
        }
    }

    private var appearanceTheme: BeaconAppearanceTheme {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
    }

    private var theme: BeaconThemePalette {
        appearanceTheme.palette(resolvedSystemScheme: colorScheme)
    }
}
