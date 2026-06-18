import AppKit
import SwiftUI

// MARK: - SF Symbol runtime resolution

/// Resolves `symbol` at runtime; if NSImage returns nil (symbol unavailable on this OS),
/// returns `fallback` instead. This self-corrects on older macOS where some symbols don't exist.
func resolveSymbol(_ symbol: String, fallback: String) -> String {
    guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
        return fallback
    }
    return symbol
}

// MARK: - Shared row chrome

private struct DeviceIconTile: View {
    let symbolName: String
    let color: Color
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)

            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)

            if isActive {
                Circle()
                    .fill(DesignTokens.Palette.charging)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 0.7))
                    .offset(x: 13, y: -13)
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct StatusCapsule: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.Palette.controlPill)
            )
    }
}

// MARK: - DeviceBatteryRow

struct DeviceBatteryRow: View {
    let decorated: DecoratedBatterySnapshot
    @State private var isHovered = false

    var body: some View {
        let snapshot = decorated.snapshot

        HStack(spacing: 14) {
            DeviceIconTile(
                symbolName: symbolName(for: snapshot),
                color: iconColor,
                isActive: snapshot.chargeState == .charging || snapshot.chargeState == .full
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(statusLineColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            if let percent = snapshot.percent {
                HStack(spacing: 8) {
                    Text("\(percent)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(percentColor)
                        .frame(minWidth: 34, alignment: .trailing)

                    BatteryLevelPill(
                        percent: percent,
                        chargeState: snapshot.chargeState
                    )
                }
            } else {
                StatusCapsule(text: "No report", color: DesignTokens.Palette.tertiaryText)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
        .background(
            isHovered
                ? RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                    .fill(DesignTokens.Palette.hover)
                : nil
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: DesignTokens.Motion.quick)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Colors

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

    private var statusLine: String {
        let snapshot = decorated.snapshot
        if snapshot.percent == nil {
            return "\(sourceLabel) · no battery report"
        }
        if let percent = snapshot.percent,
           percent <= LowBatteryNotifier.threshold,
           snapshot.chargeState != .charging,
           snapshot.chargeState != .full {
            return "\(sourceLabel) · needs charging"
        }
        switch decorated.freshness {
        case .fresh:
            switch snapshot.chargeState {
            case .charging: return "\(sourceLabel) · charging"
            case .full: return "\(sourceLabel) · fully charged"
            case .unknown: return "\(sourceLabel) · updated recently"
            case .unplugged: return "\(sourceLabel) · fresh"
            }
        case .stale:
            return "\(sourceLabel) · stale"
        case .expired:
            return "\(sourceLabel) · expired"
        }
    }

    private var statusLineColor: Color {
        if let percent = decorated.snapshot.percent, percent <= LowBatteryNotifier.threshold {
            return DesignTokens.Palette.critical
        }
        if decorated.freshness != .fresh {
            return DesignTokens.Palette.stale
        }
        return DesignTokens.Palette.secondaryText
    }

    private var sourceLabel: String {
        switch decorated.snapshot.source {
        case .macPowerSource: return "Local Mac"
        case .iCloud: return "iCloud"
        case .watchConnectivity: return "Watch relay"
        case .ioRegistry: return "IORegistry"
        case .coreBluetooth, .ioBluetooth: return "Bluetooth"
        case .systemProfiler: return "System"
        case .bluetoothUnsupported: return "Bluetooth"
        }
    }

    // MARK: - Symbol resolution

    /// Returns a precise SF Symbol name based on both kind and displayName.
    /// Uses runtime resolution so symbols unavailable on older macOS automatically
    /// fall back to a safe symbol.
    private func symbolName(for snapshot: BatterySnapshot) -> String {
        switch snapshot.kind {
        case .macBook:
            return macSymbol(for: snapshot.displayName)
        case .iPhone:
            return resolveSymbol("iphone.gen3", fallback: "iphone")
        case .appleWatch:
            return resolveSymbol("applewatch.side.right", fallback: "applewatch")
        case .airPods:
            return airPodsSymbol(for: snapshot.displayName)
        case .keyboard:
            return "keyboard"
        case .mouse:
            return resolveSymbol("magicmouse", fallback: "computermouse")
        case .trackpad:
            return resolveSymbol("rectangle.and.hand.point.up.left.fill", fallback: "rectangle.and.hand.point.up.left")
        case .bluetoothPeripheral:
            return "dot.radiowaves.left.and.right"
        }
    }

    private func macSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("mac mini") || lower.contains("macmini") {
            return resolveSymbol("macmini", fallback: "desktopcomputer")
        }
        if lower.contains("macbook") {
            return resolveSymbol("macbook", fallback: "desktopcomputer")
        }
        if lower.contains("imac") {
            return "desktopcomputer"
        }
        if lower.contains("mac studio") {
            return resolveSymbol("macstudio", fallback: "desktopcomputer")
        }
        if lower.contains("mac pro") {
            return resolveSymbol("macpro.gen3", fallback: "desktopcomputer")
        }
        return "desktopcomputer"
    }

    private func airPodsSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("max") {
            return resolveSymbol("airpodsmax", fallback: "headphones")
        }
        if lower.contains("pro") {
            return resolveSymbol("airpodspro", fallback: "airpods")
        }
        // Third-generation: "airpods (3rd generation)" or similar
        if lower.contains("3rd") || lower.contains("gen 3") || lower.contains("generation 3") {
            return resolveSymbol("airpods.gen3", fallback: "airpods")
        }
        return "airpods"
    }
}

// MARK: - AirPodsBatteryRow

struct AirPodsBatteryRow: View {
    let name: String
    let id: String
    let components: [AirPodsComponent]
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                DeviceIconTile(
                    symbolName: airPodsHeaderSymbol,
                    color: airPodsStatusColor,
                    isActive: componentSummaryPercent.map { $0 > LowBatteryNotifier.threshold } ?? false
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(airPodsStatusLine)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(airPodsStatusColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: DesignTokens.Spacing.md)

                if let summary = componentSummaryPercent {
                    HStack(spacing: 8) {
                        Text("\(summary)%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(summary <= LowBatteryNotifier.threshold ? DesignTokens.Palette.critical : DesignTokens.Palette.text)
                            .frame(minWidth: 34, alignment: .trailing)

                        BatteryLevelPill(percent: summary, chargeState: .unplugged)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer().frame(width: 44) // align under the text
                ForEach(components, id: \.slot.rawValue) { component in
                    AirPodsComponentChip(component: component)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            isHovered
                ? RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                    .fill(DesignTokens.Palette.hover)
                : nil
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: DesignTokens.Motion.quick)) {
                isHovered = hovering
            }
        }
    }

    private var airPodsHeaderSymbol: String {
        let lower = name.lowercased()
        if lower.contains("max") { return resolveSymbol("airpodsmax", fallback: "headphones") }
        if lower.contains("pro") { return resolveSymbol("airpodspro", fallback: "airpods") }
        if lower.contains("3rd") || lower.contains("gen 3") {
            return resolveSymbol("airpods.gen3", fallback: "airpods")
        }
        return "airpods"
    }

    private var componentSummaryPercent: Int? {
        let percents = components.compactMap(\.percent)
        guard !percents.isEmpty else { return nil }
        return percents.min()
    }

    private var airPodsStatusLine: String {
        if components.contains(where: { ($0.percent ?? 100) <= LowBatteryNotifier.threshold }) {
            return "Nearby · component needs charging"
        }
        if components.contains(where: { $0.freshness != .fresh }) {
            return "Nearby · component data stale"
        }
        return "Nearby · component batteries"
    }

    private var airPodsStatusColor: Color {
        if components.contains(where: { ($0.percent ?? 100) <= LowBatteryNotifier.threshold }) {
            return DesignTokens.Palette.critical
        }
        if components.contains(where: { $0.freshness != .fresh }) {
            return DesignTokens.Palette.stale
        }
        return DesignTokens.Palette.secondaryText
    }
}

// MARK: - AirPodsComponentChip

private struct AirPodsComponentChip: View {
    let component: AirPodsComponent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: slotSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.secondaryText)

            if let percent = component.percent {
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(chipTextColor(percent: percent))

                MiniPill(percent: percent, chargeState: component.chargeState)
            } else {
                Text("–")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                .fill(DesignTokens.Palette.card)
        )
    }

    private var slotSymbol: String {
        switch component.slot {
        case .case:
            return resolveSymbol("airpods.chargingcase", fallback: "battery.100")
        case .left:
            return resolveSymbol("airpod.left", fallback: "l.circle")
        case .right:
            return resolveSymbol("airpod.right", fallback: "r.circle")
        }
    }

    private func chipTextColor(percent: Int) -> Color {
        if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
        if component.freshness != .fresh { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.text
    }
}

// MARK: - MiniPill

private struct MiniPill: View {
    let percent: Int
    let chargeState: ChargeState

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(borderColor, lineWidth: 1.2)
                    .frame(width: 22, height: 11)

                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(width: fillWidth, height: 7)
                    .padding(.leading, 2.5)

                if chargeState == .charging || chargeState == .full {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 11)
                }
            }

            Capsule()
                .fill(borderColor.opacity(0.72))
                .frame(width: 1.5, height: 4.5)
        }
        .accessibilityLabel("\(percent)%")
    }

    private var normalizedPercent: CGFloat {
        CGFloat(Swift.max(0, Swift.min(100, percent))) / 100
    }

    private var fillWidth: CGFloat {
        Swift.max(2.5, 17 * normalizedPercent)
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

// MARK: - BatteryLevelPill (main row, kept from original)

struct BatteryLevelPill: View {
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

// MARK: - Previews

#if DEBUG
private func mockDecorated(
    id: String = UUID().uuidString,
    name: String,
    kind: DeviceKind,
    percent: Int?,
    chargeState: ChargeState = .unplugged,
    freshness: Freshness = .fresh
) -> DecoratedBatterySnapshot {
    DecoratedBatterySnapshot(
        snapshot: BatterySnapshot(
            deviceID: id,
            displayName: name,
            kind: kind,
            percent: percent,
            chargeState: chargeState,
            source: .coreBluetooth,
            updatedAt: Date()
        ),
        freshness: freshness
    )
}

#Preview("DeviceBatteryRow — various states", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        DeviceBatteryRow(decorated: mockDecorated(name: "MacBook Pro",    kind: .macBook,   percent: 87))
        Divider().padding(.leading, 58)
        DeviceBatteryRow(decorated: mockDecorated(name: "Mac mini",       kind: .macBook,   percent: nil))
        Divider().padding(.leading, 58)
        DeviceBatteryRow(decorated: mockDecorated(name: "Isaac's iPhone", kind: .iPhone,    percent: 42, chargeState: .charging))
        Divider().padding(.leading, 58)
        DeviceBatteryRow(decorated: mockDecorated(name: "Apple Watch",    kind: .appleWatch, percent: 18))
        Divider().padding(.leading, 58)
        DeviceBatteryRow(decorated: mockDecorated(name: "Magic Keyboard", kind: .keyboard,   percent: 95))
        Divider().padding(.leading, 58)
        DeviceBatteryRow(decorated: mockDecorated(name: "BT Speaker",     kind: .bluetoothPeripheral, percent: 30, freshness: .stale))
    }
    .frame(width: 378)
}

#Preview("DeviceBatteryRow — dark", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        DeviceBatteryRow(decorated: mockDecorated(name: "MacBook Pro",    kind: .macBook,   percent: 87))
        Divider().padding(.leading, 58)
        DeviceBatteryRow(decorated: mockDecorated(name: "Mac mini",       kind: .macBook,   percent: nil))
        Divider().padding(.leading, 58)
        DeviceBatteryRow(decorated: mockDecorated(name: "Isaac's iPhone", kind: .iPhone,    percent: 8, chargeState: .unplugged))
    }
    .frame(width: 378)
    .preferredColorScheme(.dark)
}

#Preview("AirPodsBatteryRow — 3-component", traits: .sizeThatFitsLayout) {
    AirPodsBatteryRow(
        name: "John's AirPods Pro",
        id: "AA-BB-CC-DD-EE-FF",
        components: [
            AirPodsComponent(slot: .case,  percent: 90, chargeState: .unplugged, freshness: .fresh),
            AirPodsComponent(slot: .left,  percent: 75, chargeState: .unplugged, freshness: .fresh),
            AirPodsComponent(slot: .right, percent: 80, chargeState: .unplugged, freshness: .fresh),
        ]
    )
    .frame(width: 378)
}

#Preview("AirPodsBatteryRow — low + nil case", traits: .sizeThatFitsLayout) {
    AirPodsBatteryRow(
        name: "AirPods (3rd generation)",
        id: "11-22-33-44-55-66",
        components: [
            AirPodsComponent(slot: .case,  percent: nil, chargeState: .unknown,  freshness: .fresh),
            AirPodsComponent(slot: .left,  percent: 12,  chargeState: .unplugged, freshness: .fresh),
            AirPodsComponent(slot: .right, percent: 15,  chargeState: .unplugged, freshness: .stale),
        ]
    )
    .frame(width: 378)
}
#endif
