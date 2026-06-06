import SwiftUI

struct DeviceBatteryRow: View {
    let decorated: DecoratedBatterySnapshot

    var body: some View {
        let snapshot = decorated.snapshot

        HStack(spacing: 14) {
            Image(systemName: symbolName(for: snapshot.kind))
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 30, height: 30)
                .foregroundStyle(iconColor)

            Text(snapshot.displayName)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: DesignTokens.Spacing.md)

            HStack(spacing: 8) {
                Text(percentText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(percentColor)
                    .frame(minWidth: 34, alignment: .trailing)

                BatteryLevelPill(
                    percent: decorated.snapshot.percent ?? 0,
                    chargeState: decorated.snapshot.chargeState
                )
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .contentShape(Rectangle())
    }

    private var percentText: String {
        guard let percent = decorated.snapshot.percent else { return "" }
        return "\(percent)%"
    }

    private var statusText: String {
        if decorated.snapshot.percent == nil {
            return "No battery report"
        }
        if let percent = decorated.snapshot.percent, percent <= LowBatteryNotifier.threshold, decorated.snapshot.chargeState != .charging {
            return "Needs charging"
        }
        switch decorated.freshness {
        case .fresh: return decorated.snapshot.chargeState == .charging ? "Charging" : "Updated recently"
        case .stale: return "Last updated over 10 min ago"
        case .expired: return "Last updated over 30 min ago"
        }
    }

    private var iconColor: Color {
        if let percent = decorated.snapshot.percent, percent <= LowBatteryNotifier.threshold {
            return DesignTokens.Palette.critical
        }
        switch decorated.snapshot.chargeState {
        case .charging, .full: return DesignTokens.Palette.charging
        default: return DesignTokens.Palette.secondaryText
        }
    }

    private var percentColor: Color {
        guard let percent = decorated.snapshot.percent else { return DesignTokens.Palette.secondaryText }
        if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
        if decorated.freshness != .fresh { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.text
    }

    private func symbolName(for kind: DeviceKind) -> String {
        switch kind {
        case .macBook: return "desktopcomputer"
        case .iPhone: return "iphone"
        case .appleWatch: return "applewatch"
        case .airPods: return "airpodspro"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .bluetoothPeripheral: return "dot.radiowaves.left.and.right"
        }
    }
}

private struct BatteryLevelPill: View {
    let percent: Int
    let chargeState: ChargeState

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(borderColor, lineWidth: 1.6)
                    .frame(width: 34, height: 18)

                RoundedRectangle(cornerRadius: 3)
                    .fill(fillColor)
                    .frame(width: fillWidth, height: 12)
                    .padding(.leading, 4)

                if chargeState == .charging || chargeState == .full {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 18)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                }
            }

            Capsule()
                .fill(borderColor.opacity(0.72))
                .frame(width: 2.5, height: 7)
        }
        .accessibilityLabel("\(percent)%")
    }

    private var normalizedPercent: CGFloat {
        CGFloat(Swift.max(0, Swift.min(100, percent))) / 100
    }

    private var fillWidth: CGFloat {
        Swift.max(4, 26 * normalizedPercent)
    }

    private var fillColor: Color {
        if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
        if percent <= 45 { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.healthy
    }

    private var borderColor: Color {
        if chargeState == .charging || chargeState == .full {
            return DesignTokens.Palette.charging
        }
        return DesignTokens.Palette.secondaryText.opacity(0.55)
    }
}
