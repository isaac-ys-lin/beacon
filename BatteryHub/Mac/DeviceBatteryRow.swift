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

struct BluetoothLogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)

        ZStack {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
                }

            BluetoothGlyphShape()
                .stroke(
                    Color.primary.opacity(0.62),
                    style: StrokeStyle(
                        lineWidth: max(1.1, size * 0.068),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .padding(size * 0.25)
        }
        .frame(width: size, height: size)
        .ifAvailableGlass(shape: shape)
        .accessibilityLabel("Bluetooth")
    }
}

struct SettingsLogoMark: View {
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)

        ZStack {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
                }

            Image(systemName: resolveSymbol("gearshape.2.fill", fallback: "gearshape.fill"))
                .font(.system(size: max(12, size * 0.52), weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.primary.opacity(0.62))
        }
        .frame(width: size, height: size)
        .ifAvailableGlass(shape: shape)
        .accessibilityLabel("Settings")
    }
}

private extension View {
    @ViewBuilder
    func ifAvailableGlass<S: Shape>(shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
        }
    }
}

private struct BluetoothGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let midX = rect.midX
        let midY = rect.midY
        let topY = rect.minY + rect.height * 0.03
        let bottomY = rect.maxY - rect.height * 0.03
        let leftX = rect.minX + rect.width * 0.06
        let rightX = rect.maxX - rect.width * 0.08
        let upperY = rect.minY + rect.height * 0.30
        let lowerY = rect.maxY - rect.height * 0.30

        var path = Path()
        path.move(to: CGPoint(x: midX, y: topY))
        path.addLine(to: CGPoint(x: midX, y: bottomY))

        path.move(to: CGPoint(x: midX, y: topY))
        path.addLine(to: CGPoint(x: rightX, y: upperY))
        path.addLine(to: CGPoint(x: midX, y: midY))
        path.addLine(to: CGPoint(x: leftX, y: upperY))

        path.move(to: CGPoint(x: midX, y: bottomY))
        path.addLine(to: CGPoint(x: rightX, y: lowerY))
        path.addLine(to: CGPoint(x: midX, y: midY))
        path.addLine(to: CGPoint(x: leftX, y: lowerY))

        return path
    }
}

// MARK: - Shared device iconography

func deviceSymbolName(for kind: DeviceKind, displayName: String = "") -> String {
    switch kind {
    case .macBook:
        return macDeviceSymbolName(for: displayName)
    case .iPhone:
        return resolveSymbol("iphone.gen3", fallback: "iphone")
    case .appleWatch:
        return resolveSymbol("applewatch", fallback: "watch.analog")
    case .airPods:
        return airPodsDeviceSymbolName(for: displayName)
    case .keyboard:
        return keyboardDeviceSymbolName()
    case .mouse:
        return resolveSymbol("magicmouse", fallback: "cursorarrow")
    case .trackpad:
        return resolveSymbol("rectangle.and.hand.point.up.left", fallback: "rectangle")
    case .bluetoothPeripheral:
        return resolveSymbol("antenna.radiowaves.left.and.right", fallback: "dot.radiowaves.left.and.right")
    }
}

private func macDeviceSymbolName(for name: String) -> String {
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
    return resolveSymbol("macbook", fallback: "desktopcomputer")
}

private func keyboardDeviceSymbolName() -> String {
    return resolveSymbol("keyboard", fallback: "rectangle.grid.3x2")
}

private func airPodsDeviceSymbolName(for name: String) -> String {
    let lower = name.lowercased()
    if lower.contains("max") {
        return resolveSymbol("airpodsmax", fallback: "headphones")
    }
    if lower.contains("pro") {
        return resolveSymbol("airpodspro", fallback: "airpods")
    }
    if lower.contains("3rd") || lower.contains("gen 3") || lower.contains("generation 3") {
        return resolveSymbol("airpods.gen3", fallback: "airpods")
    }
    return "airpods"
}

enum DeviceIconBadge: Equatable {
    case connected
    case charging
    case low
    case stale
    case disconnected

    var symbolName: String {
        switch self {
        case .connected: return "checkmark"
        case .charging: return "bolt.fill"
        case .low: return "exclamationmark"
        case .stale: return "clock"
        case .disconnected: return "xmark"
        }
    }

    var color: Color {
        switch self {
        case .connected: return DesignTokens.Palette.charging
        case .charging: return DesignTokens.Palette.charging
        case .low: return DesignTokens.Palette.critical
        case .stale: return DesignTokens.Palette.stale
        case .disconnected: return DesignTokens.Palette.secondaryText
        }
    }
}

struct DeviceIconPlate: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 34
    var badge: DeviceIconBadge?

    init(
        symbolName: String,
        color: Color,
        size: CGFloat = 34,
        badge: DeviceIconBadge? = nil
    ) {
        self.symbolName = symbolName
        self.color = color
        self.size = size
        self.badge = badge
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

        ZStack {
            shape
                .fill(.regularMaterial)
                .overlay(
                    shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
                )

            Image(systemName: symbolName)
                .font(.system(size: max(12, size * 0.54), weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: size * 0.72, height: size * 0.72)
                .accessibilityHidden(true)

            if let badge {
                ZStack {
                    Circle()
                        .fill(badge.color)
                    Image(systemName: badge.symbolName)
                        .font(.system(size: max(6, size * 0.18), weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: max(12, size * 0.36), height: max(12, size * 0.36))
                .overlay(Circle().stroke(.white.opacity(0.78), lineWidth: 0.8))
                .shadow(color: badge.color.opacity(0.25), radius: 3, x: 0, y: 1)
                .offset(x: size * 0.34, y: -size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .ifAvailableGlass(shape: shape)
    }
}

private struct StatusCapsule: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.captionEmphasis)
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

private struct BatteryReadout: View {
    let percent: Int
    let chargeState: ChargeState
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("\(percent)%")
                .font(DesignTokens.Typography.percentSmall)
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(minWidth: 34, alignment: .trailing)

            BatteryLevelPill(
                percent: percent,
                chargeState: chargeState
            )
        }
        .frame(width: 82, alignment: .trailing)
    }
}

// MARK: - DeviceBatteryRow

struct DeviceBatteryRow: View {
    let decorated: DecoratedBatterySnapshot
    var isPinned = false
    @State private var isHovered = false

    var body: some View {
        let snapshot = decorated.snapshot

        HStack(spacing: 14) {
            DeviceIconPlate(
                symbolName: deviceSymbolName(for: snapshot.kind, displayName: snapshot.displayName),
                color: iconColor,
                badge: iconBadge
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(snapshot.displayName)
                        .font(DesignTokens.Typography.rowTitleEmphasis)
                        .foregroundStyle(DesignTokens.Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isPinned {
                        Image(systemName: resolveSymbol("pin.fill", fallback: "pin"))
                            .font(.system(size: 9, weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(DesignTokens.Palette.accent)
                    }
                }

                Text(statusLine)
                    .font(DesignTokens.Typography.rowSubtitle)
                    .foregroundStyle(statusLineColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            if snapshot.connectionState == .disconnected {
                StatusCapsule(text: "Disconnected", color: DesignTokens.Palette.stale)
            } else if let percent = snapshot.percent {
                BatteryReadout(
                    percent: percent,
                    chargeState: snapshot.chargeState,
                    color: percentColor
                )
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
        if decorated.snapshot.connectionState == .disconnected {
            return DesignTokens.Palette.stale
        }
        if let percent = decorated.snapshot.percent, percent <= LowBatteryNotifier.threshold {
            return DesignTokens.Palette.critical
        }
        switch decorated.snapshot.chargeState {
        case .charging, .full: return DesignTokens.Palette.charging
        default: return DesignTokens.Palette.secondaryText
        }
    }

    private var iconBadge: DeviceIconBadge? {
        let snapshot = decorated.snapshot
        if snapshot.connectionState == .disconnected {
            return .disconnected
        }
        if let percent = snapshot.percent,
           percent <= LowBatteryNotifier.threshold,
           snapshot.chargeState != .charging,
           snapshot.chargeState != .full {
            return .low
        }
        if snapshot.chargeState == .charging || snapshot.chargeState == .full {
            return .charging
        }
        if decorated.freshness != .fresh {
            return .stale
        }
        return nil
    }

    private var percentColor: Color {
        guard let percent = decorated.snapshot.percent else { return DesignTokens.Palette.secondaryText }
        if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
        if decorated.freshness != .fresh { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.text
    }

    private var statusLine: String {
        let snapshot = decorated.snapshot
        if snapshot.connectionState == .disconnected {
            return "\(sourceLabel) · disconnected"
        }
        if snapshot.percent == nil {
            return "\(sourceLabel) · no report"
        }
        if let percent = snapshot.percent,
           percent <= LowBatteryNotifier.threshold,
           snapshot.chargeState != .charging,
           snapshot.chargeState != .full {
            return "\(sourceLabel) · low"
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
        if decorated.snapshot.connectionState == .disconnected {
            return DesignTokens.Palette.stale
        }
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

}

// MARK: - AirPodsBatteryRow

struct AirPodsBatteryRow: View {
    let name: String
    let id: String
    let components: [AirPodsComponent]
    var isPinned = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                DeviceIconPlate(
                    symbolName: airPodsHeaderSymbol,
                    color: airPodsStatusColor,
                    badge: airPodsIconBadge
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(name)
                            .font(DesignTokens.Typography.rowTitleEmphasis)
                            .foregroundStyle(DesignTokens.Palette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if isPinned {
                            Image(systemName: resolveSymbol("pin.fill", fallback: "pin"))
                                .font(.system(size: 9, weight: .bold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(DesignTokens.Palette.accent)
                        }
                    }

                    Text(airPodsStatusLine)
                        .font(DesignTokens.Typography.rowSubtitle)
                        .foregroundStyle(airPodsStatusColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: DesignTokens.Spacing.md)

                if let summary = componentSummaryPercent {
                    BatteryReadout(
                        percent: summary,
                        chargeState: summaryChargeState,
                        color: summaryColor
                    )
                }
            }

            HStack(spacing: 8) {
                Spacer().frame(width: 48) // align under the text
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
        deviceSymbolName(for: .airPods, displayName: name)
    }

    private var airPodsIconBadge: DeviceIconBadge? {
        if components.contains(where: { ($0.percent ?? 100) <= LowBatteryNotifier.threshold }) {
            return .low
        }
        if components.contains(where: { $0.chargeState == .charging || $0.chargeState == .full }) {
            return .charging
        }
        if components.contains(where: { $0.freshness != .fresh }) {
            return .stale
        }
        return nil
    }

    private var componentSummaryPercent: Int? {
        let percents = components.compactMap(\.percent)
        guard !percents.isEmpty else { return nil }
        return percents.min()
    }

    private var summaryChargeState: ChargeState {
        if components.contains(where: { $0.chargeState == .charging || $0.chargeState == .full }) {
            return .charging
        }
        return .unplugged
    }

    private var summaryColor: Color {
        guard let summary = componentSummaryPercent else { return DesignTokens.Palette.secondaryText }
        if summary <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
        if components.contains(where: { $0.freshness != .fresh }) { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.text
    }

    private var airPodsStatusLine: String {
        if components.contains(where: { ($0.percent ?? 100) <= LowBatteryNotifier.threshold }) {
            return "Nearby · component low"
        }
        if components.contains(where: { $0.freshness != .fresh }) {
            return "Nearby · component data stale"
        }
        return "Nearby · components"
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
                    .font(DesignTokens.Typography.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(chipTextColor(percent: percent))

                MiniPill(percent: percent, chargeState: component.chargeState)
            } else {
                Text("–")
                    .font(DesignTokens.Typography.caption)
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
        BatteryGauge(
            percent: percent,
            chargeState: chargeState,
            width: 22,
            height: 11,
            bodyCornerRadius: 3,
            fillCornerRadius: 2,
            fillInset: 2.5,
            terminalWidth: 1.5,
            terminalHeight: 4.5,
            strokeWidth: 1.15,
            boltSize: 6
        )
    }
}

// MARK: - BatteryLevelPill

struct BatteryLevelPill: View {
    let percent: Int
    let chargeState: ChargeState

    var body: some View {
        BatteryGauge(
            percent: percent,
            chargeState: chargeState,
            width: 34,
            height: 18,
            bodyCornerRadius: 5,
            fillCornerRadius: 3,
            fillInset: 4,
            terminalWidth: 2.5,
            terminalHeight: 7,
            strokeWidth: 1.55,
            boltSize: 9
        )
    }
}

private struct BatteryGauge: View {
    let percent: Int
    let chargeState: ChargeState
    let width: CGFloat
    let height: CGFloat
    let bodyCornerRadius: CGFloat
    let fillCornerRadius: CGFloat
    let fillInset: CGFloat
    let terminalWidth: CGFloat
    let terminalHeight: CGFloat
    let strokeWidth: CGFloat
    let boltSize: CGFloat

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: bodyCornerRadius, style: .continuous)
                    .fill(DesignTokens.Palette.controlPill.opacity(0.74))
                    .frame(width: width, height: height)

                RoundedRectangle(cornerRadius: bodyCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: strokeWidth)
                    .frame(width: width, height: height)

                RoundedRectangle(cornerRadius: fillCornerRadius, style: .continuous)
                    .fill(fillColor)
                    .frame(width: fillWidth, height: fillHeight)
                    .padding(.leading, fillInset)
                    .shadow(color: fillColor.opacity(0.35), radius: isCharging ? 2 : 0, x: 0, y: 0)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: boltSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: width, height: height)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                }
            }

            Capsule()
                .fill(borderColor.opacity(0.72))
                .frame(width: terminalWidth, height: terminalHeight)
        }
        .accessibilityLabel("\(percent)%")
    }

    private var isCharging: Bool {
        chargeState == .charging || chargeState == .full
    }

    private var normalizedPercent: CGFloat {
        CGFloat(Swift.max(0, Swift.min(100, percent))) / 100
    }

    private var fillWidth: CGFloat {
        Swift.max(fillInset, (width - (fillInset * 2)) * normalizedPercent)
    }

    private var fillHeight: CGFloat {
        Swift.max(2, height - (fillInset * 1.5))
    }

    private var fillColor: Color {
        if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
        if percent <= 45 { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.healthy
    }

    private var borderColor: Color {
        if isCharging {
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
