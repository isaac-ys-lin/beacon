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

enum BatteryHubSymbols {
    static let appIconAsset = "BatteryHubAppIcon"
    static let headerLogoAsset = "BatteryHubHeaderLogo"

    static var app: String {
        resolveSymbol("rectangle.grid.2x2", fallback: "rectangle.grid.3x2")
    }

    static var bluetooth: String {
        resolveSymbol(
            "antenna.radiowaves.left.and.right",
            fallback: "dot.radiowaves.left.and.right"
        )
    }

    static func resolved(_ systemImage: String, fallback: String = "circle") -> String {
        switch systemImage {
        case "antenna.radiowaves.left.and.right", "dot.radiowaves.left.and.right":
            return bluetooth
        default:
            return resolveSymbol(systemImage, fallback: fallback)
        }
    }
}

struct BatteryHubLogoMark: View {
    var size: CGFloat = 28
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: BatteryHubStatusIconImage.make(size: NSSize(width: size, height: size)))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(1, contentMode: .fit)
            .foregroundStyle(theme.textPrimary)
            .frame(width: size, height: size)
            .accessibilityLabel("BatteryHub")
    }

    private var theme: BeaconThemePalette {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }
}

struct BluetoothLogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: BatteryHubSymbols.bluetooth)
            .font(.system(size: max(15, size * 0.70), weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.primary.opacity(0.68))
            .frame(width: size, height: size)
        .frame(width: size, height: size)
        .accessibilityLabel("Bluetooth")
    }
}

struct BatteryHubHeaderSettingsIcon: View {
    let color: Color
    var glyphSize: CGFloat = 13
    var frameSize: CGFloat = 28

    var body: some View {
        Image(systemName: resolveSymbol("gearshape", fallback: "gearshape.fill"))
            .font(.system(size: glyphSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: frameSize, height: frameSize)
            .accessibilityLabel("Open BatteryHub Settings")
    }
}

struct BatteryHubHeaderRefreshIcon: View {
    let color: Color
    var glyphSize: CGFloat = 13
    var frameSize: CGFloat = 28

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: frameSize, height: frameSize)
            .accessibilityLabel("Refresh")
    }
}

struct BluetoothSettingsIcon: View {
    let color: Color
    var glyphSize: CGFloat = 18
    var frameSize: CGFloat = 28

    var body: some View {
        Group {
            if let template = bluetoothTemplateImage {
                Image(nsImage: template)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: BatteryHubSymbols.bluetooth)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .foregroundStyle(color)
        .frame(width: glyphSize, height: glyphSize)
        .frame(width: frameSize, height: frameSize)
    }

    private var bluetoothTemplateImage: NSImage? {
        guard let image = NSImage(named: NSImage.Name("NSBluetoothTemplate"))?.copy() as? NSImage else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}

struct BatteryHubUtilityIconButtonStyle: ButtonStyle {
    let theme: BeaconThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.textMuted)
            .background(
                Circle()
                    .fill(configuration.isPressed ? theme.hover : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: DesignTokens.Motion.quick), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

struct BatteryHubHeaderControls: View {
    let theme: BeaconThemePalette
    let onOpenSettings: () -> Void
    var frameSize: CGFloat = 28
    var settingsGlyphSize: CGFloat = 13
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            Button(action: onOpenSettings) {
                BatteryHubHeaderSettingsIcon(
                    color: theme.textPrimary,
                    glyphSize: settingsGlyphSize,
                    frameSize: frameSize
                )
            }
            .buttonStyle(BatteryHubUtilityIconButtonStyle(theme: theme))
            .help("Open BatteryHub Settings")
        }
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
        return BatteryHubSymbols.bluetooth
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
        case .connected: return "checkmark.circle.fill"
        case .charging: return "bolt.circle.fill"
        case .low: return "exclamationmark.circle.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .disconnected: return "xmark.circle.fill"
        }
    }

    func color(in theme: BeaconThemePalette) -> Color {
        switch self {
        case .connected: return theme.statusOK
        case .charging: return theme.statusOK
        case .low: return theme.statusLow
        case .stale: return DesignTokens.Palette.stale
        case .disconnected: return theme.statusOffline
        }
    }
}

struct DeviceIconPlate: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 34
    var badge: DeviceIconBadge?
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

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
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.active.opacity(0.54))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.hairlineSubtle, lineWidth: 0.6)
                )

            Image(systemName: symbolName)
                .font(.system(size: max(12, size * 0.54), weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: size * 0.72, height: size * 0.72)
                .accessibilityHidden(true)

            if let badge {
                Image(systemName: resolveSymbol(badge.symbolName, fallback: "circle.fill"))
                    .font(.system(size: max(9, size * 0.27), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(badge.color(in: theme))
                    .frame(width: max(13, size * 0.36), height: max(13, size * 0.36))
                    .offset(x: size * 0.31, y: -size * 0.31)
            }
        }
        .frame(width: size, height: size)
    }

    private var theme: BeaconThemePalette {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }
}

struct DashboardBatteryDevice: Identifiable, Equatable {
    let id: String
    let displayName: String
    let kind: DeviceKind
    let percent: Int?
    let chargeState: ChargeState
    let freshness: Freshness
    let source: BatterySource
    let provider: BatteryProvider
    let updatedAt: Date
    let isPinned: Bool
    let airPodsComponents: [AirPodsComponent]

    init(
        id: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState,
        freshness: Freshness,
        source: BatterySource = .bluetoothUnsupported,
        provider: BatteryProvider = .bluetoothUnsupported,
        updatedAt: Date = .distantPast,
        isPinned: Bool = false,
        airPodsComponents: [AirPodsComponent] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.percent = percent
        self.chargeState = chargeState
        self.freshness = freshness
        self.source = source
        self.provider = provider
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.airPodsComponents = airPodsComponents
    }

    init(_ device: BatteryOverviewDevice, isPinned: Bool = false) {
        self.init(
            id: device.id,
            displayName: device.displayName,
            kind: device.kind,
            percent: device.percent,
            chargeState: device.chargeState,
            freshness: device.freshness,
            source: device.source,
            provider: device.provider,
            updatedAt: device.updatedAt,
            isPinned: isPinned
        )
    }

    init(item: DeviceListItem, isPinned: Bool = false) {
        switch item {
        case .device(let decorated):
            self.init(
                id: decorated.id,
                displayName: decorated.snapshot.displayName,
                kind: decorated.snapshot.kind,
                percent: decorated.snapshot.percent,
                chargeState: decorated.snapshot.chargeState,
                freshness: decorated.freshness,
                source: decorated.snapshot.source,
                provider: decorated.snapshot.provider,
                updatedAt: decorated.snapshot.updatedAt,
                isPinned: isPinned
            )
        case .airPods(let name, let id, let components):
            let percents = components.compactMap(\.percent)
            let chargeState: ChargeState
            if components.contains(where: { $0.chargeState == .charging }) {
                chargeState = .charging
            } else if !components.isEmpty,
                      components.allSatisfy({ $0.chargeState == .full || $0.percent == 100 }) {
                chargeState = .full
            } else {
                chargeState = .unplugged
            }
            let freshness: Freshness = components.contains { $0.freshness == .expired }
                ? .expired
                : (components.contains { $0.freshness == .stale } ? .stale : .fresh)
            let updatedAt = components.map(\.updatedAt).max() ?? .distantPast
            self.init(
                id: id,
                displayName: name,
                kind: .airPods,
                percent: percents.min(),
                chargeState: chargeState,
                freshness: freshness,
                source: .coreBluetooth,
                provider: .coreBluetoothBatteryService,
                updatedAt: updatedAt,
                isPinned: isPinned,
                airPodsComponents: components
            )
        }
    }
}

func batteryProviderLabel(source: BatterySource, provider: BatteryProvider) -> String {
    switch provider {
    case .macPowerSource: return "Local Mac"
    case .ioRegistry: return "IORegistry"
    case .coreBluetoothBatteryService: return "Bluetooth Battery Service"
    case .ioBluetooth: return "Bluetooth"
    case .systemProfiler: return "System"
    case .bluetoothUnsupported: return "Bluetooth"
    case .ideviceInfo: return "USB iPhone"
    }
}

func batteryRelativeAgeText(updatedAt: Date, now: Date = Date()) -> String {
    let age = max(0, now.timeIntervalSince(updatedAt))
    if age < 60 { return "Now" }
    if age < 3_600 { return "\(Int(age / 60))m ago" }
    if age < 86_400 { return "\(Int(age / 3_600))h ago" }
    return "\(Int(age / 86_400))d ago"
}

func dashboardBatteryStatusText(
    percent: Int?,
    chargeState: ChargeState,
    freshness: Freshness,
    isLow: Bool,
    showsAirPodsComponents: Bool,
    updatedAt: Date,
    now: Date = Date()
) -> String {
    if percent == nil { return "No report" }
    if freshness == .expired { return "Expired" }
    if freshness == .stale { return batteryRelativeAgeText(updatedAt: updatedAt, now: now) }
    if chargeState == .charging { return "Charging" }
    if chargeState == .full { return "Full" }
    if isLow { return "Low" }
    if showsAirPodsComponents { return "Parts" }
    return "Battery"
}

struct DashboardBatteryProgressBar: View {
    let percent: Int
    let color: Color
    var height: CGFloat = 5
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var ratio: CGFloat {
        CGFloat(max(0, min(100, percent))) / 100
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.active.opacity(0.78))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(theme.hairlineSubtle, lineWidth: 0.6)
                    )
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: max(height, proxy.size.width * ratio))
                    .shadow(color: color.opacity(0.42), radius: 8, x: 0, y: 0)
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(percent)%")
    }

    private var theme: BeaconThemePalette {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }
}

private struct BeaconStatusDot: View {
    let color: Color
    var isCharging: Bool = false
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(pulsing ? 0.72 : 0.36), radius: pulsing ? 9 : 5, x: 0, y: 0)
            .animation(
                isCharging ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default,
                value: pulsing
            )
            .onAppear { pulsing = isCharging }
            .onChange(of: isCharging) { _, v in pulsing = v }
            .accessibilityHidden(true)
    }
}

struct DashboardBatteryDeviceRow: View {
    let device: DashboardBatteryDevice
    var lowBatteryThreshold = LowBatteryNotifier.threshold
    var iconSize: CGFloat = 30
    var horizontalPadding: CGFloat = 9
    var verticalPadding: CGFloat = 9
    var statusWidth: CGFloat = 58
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            DeviceIconPlate(
                symbolName: deviceSymbolName(for: device.kind, displayName: device.displayName),
                color: iconColor,
                size: iconSize,
                badge: iconBadge
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    BeaconStatusDot(color: statusColor, isCharging: device.chargeState == .charging)

                    Text(device.displayName)
                        .font(DesignTokens.Typography.controlLabelEmphasis)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if device.isPinned {
                        Image(systemName: resolveSymbol("pin.fill", fallback: "pin"))
                            .font(.system(size: 8, weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.statusOK)
                    }

                    Spacer(minLength: 0)

                    if let percent = device.percent {
                        Text("\(percent)%")
                            .font(DesignTokens.Typography.percentSmall)
                            .monospacedDigit()
                            .foregroundStyle(statusColor)
                    }
                }

                HStack(spacing: 8) {
                    if showsAirPodsComponents {
                        HStack(spacing: 6) {
                            ForEach(device.airPodsComponents, id: \.slot.rawValue) { component in
                                AirPodsDashboardComponentChip(component: component)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let percent = device.percent {
                        DashboardBatteryProgressBar(percent: percent, color: statusColor)
                    } else {
                        Capsule(style: .continuous)
                            .fill(theme.active.opacity(0.58))
                            .frame(height: 5)
                    }

                    Text(statusText)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(statusTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: statusWidth, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: NativeMacStyle.dashboardRowCornerRadius, style: .continuous)
                .fill(theme.raised.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: NativeMacStyle.dashboardRowCornerRadius, style: .continuous)
                        .stroke(theme.hairlineSubtle, lineWidth: 0.7)
                )
        )
    }

    private var isLow: Bool {
        guard let percent = device.percent else { return false }
        return percent <= lowBatteryThreshold
            && device.chargeState != .charging
            && device.chargeState != .full
    }

    private var showsAirPodsComponents: Bool {
        device.kind == .airPods && device.airPodsComponents.count > 1
    }

    private var statusColor: Color {
        if isLow {
            guard let percent = device.percent else { return theme.statusLow }
            return percent <= 10 ? theme.statusCritical : theme.statusLow
        }
        if device.chargeState == .charging || device.chargeState == .full {
            return theme.statusOK
        }
        if device.freshness != .fresh { return DesignTokens.Palette.stale }
        return theme.statusOK
    }

    private var statusTextColor: Color {
        switch (isLow, device.chargeState, device.freshness) {
        case (true, _, _):
            return statusColor
        case (_, .charging, _), (_, .full, _):
            return theme.statusOK
        case (_, _, .stale), (_, _, .expired):
            return DesignTokens.Palette.stale
        default:
            return theme.textMuted
        }
    }

    private var iconColor: Color {
        if device.kind == .keyboard {
            return theme.textMuted
        }
        return statusColor
    }

    private var iconBadge: DeviceIconBadge? {
        if isLow { return .low }
        if device.chargeState == .charging || device.chargeState == .full {
            return .charging
        }
        if device.freshness != .fresh { return .stale }
        return nil
    }

    private var statusText: String {
        dashboardBatteryStatusText(
            percent: device.percent,
            chargeState: device.chargeState,
            freshness: device.freshness,
            isLow: isLow,
            showsAirPodsComponents: showsAirPodsComponents,
            updatedAt: device.updatedAt
        )
    }

    private var theme: BeaconThemePalette {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }
}

private struct AirPodsDashboardComponentChip: View {
    let component: AirPodsComponent
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Text(slotLabel)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Text(percentText)
                .font(DesignTokens.Typography.caption2)
                .monospacedDigit()
                .foregroundStyle(chipColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .frame(height: 19)
        .background(
            Capsule(style: .continuous)
                .fill(theme.hover.opacity(0.66))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(theme.hairlineSubtle, lineWidth: 0.6)
                )
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var percentText: String {
        guard let percent = component.percent else { return "–" }
        return "\(percent)%"
    }

    private var chipColor: Color {
        guard let percent = component.percent else { return DesignTokens.Palette.tertiaryText }
        if percent <= LowBatteryNotifier.threshold {
            return percent <= 10 ? theme.statusCritical : theme.statusLow
        }
        if component.chargeState == .charging || component.chargeState == .full {
            return theme.statusOK
        }
        if component.freshness != .fresh { return DesignTokens.Palette.stale }
        return theme.textMuted
    }

    private var theme: BeaconThemePalette {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }

    private var slotLabel: String {
        switch component.slot {
        case .case:
            return "Case"
        case .left:
            return "L"
        case .right:
            return "R"
        }
    }

    private var accessibilityLabel: String {
        switch component.slot {
        case .case:
            return "Charging case \(percentText)"
        case .left:
            return "Left AirPod \(percentText)"
        case .right:
            return "Right AirPod \(percentText)"
        }
    }
}
