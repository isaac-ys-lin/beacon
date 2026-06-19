import SwiftUI

enum BatteryHUDPreferences {
    static let showActionHUDKey = "BatteryHub.showActionHUD"
    static let lowBatteryHUDEnabledKey = "BatteryHub.actionHUD.lowBatteryEnabled"
    static let chargedHUDEnabledKey = "BatteryHub.actionHUD.chargedEnabled"
    static let autoDismissEnabledKey = "BatteryHub.actionHUD.autoDismissEnabled"
    static let dismissDelaySecondsKey = "BatteryHub.actionHUD.dismissDelaySeconds"
    static let showDismissButtonKey = "BatteryHub.actionHUD.showDismissButton"

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
            return true
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
    let event: BatteryAlertEvent
    var showsDismissButton = BatteryHUDPreferences.showsDismissButton()
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 52, height: 52)

                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignTokens.Typography.rowTitleEmphasis)
                    .foregroundStyle(DesignTokens.Palette.text)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
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
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(DesignTokens.Palette.controlPill)
                        )
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 520, height: 92)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(DesignTokens.Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 14)
        )
    }

    private var title: String {
        switch event.kind {
        case .lowBattery:
            return "\(event.displayName) needs charging"
        case .charged:
            return "\(event.displayName) is charged"
        }
    }

    private var subtitle: String {
        switch event.kind {
        case .lowBattery:
            return "Battery below alert level."
        case .charged:
            return "Charged alert point reached."
        }
    }

    private var systemImage: String {
        switch event.kind {
        case .lowBattery:
            return resolveSymbol("battery.25", fallback: "battery.0")
        case .charged:
            return resolveSymbol("battery.100.bolt", fallback: "battery.100")
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .lowBattery:
            return DesignTokens.Palette.critical
        case .charged:
            return DesignTokens.Palette.charging
        }
    }

    private var iconBackground: Color {
        switch event.kind {
        case .lowBattery:
            return DesignTokens.Palette.critical.opacity(0.14)
        case .charged:
            return DesignTokens.Palette.charging.opacity(0.16)
        }
    }
}
