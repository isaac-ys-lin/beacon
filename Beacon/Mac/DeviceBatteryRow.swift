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

enum BeaconSymbols {
    static let appIconAsset = "BeaconAppIcon"
    static let headerLogoAsset = "BeaconHeaderLogo"

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

struct BeaconLogoMark: View {
    var size: CGFloat = 28
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: BeaconStatusIconImage.make(size: NSSize(width: size, height: size)))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(1, contentMode: .fit)
            .foregroundStyle(theme.textPrimary)
            .frame(width: size, height: size)
            .accessibilityLabel("Beacon")
    }

    private var theme: BeaconThemePalette {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }
}

struct BeaconHeaderSettingsIcon: View {
    let color: Color
    var glyphSize: CGFloat = 13
    var frameSize: CGFloat = 28

    var body: some View {
        Image(systemName: resolveSymbol("gearshape", fallback: "gearshape.fill"))
            .font(.system(size: glyphSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: frameSize, height: frameSize)
            .accessibilityLabel("Open Beacon Settings")
    }
}

struct BeaconHeaderRefreshIcon: View {
    let color: Color
    var glyphSize: CGFloat = 13
    var frameSize: CGFloat = 28
    var isRefreshing = false

    var body: some View {
        Group {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: glyphSize, height: glyphSize)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityLabel(isRefreshing ? "Refreshing" : "Refresh")
    }
}

struct BeaconUtilityIconButtonStyle: ButtonStyle {
    let theme: BeaconThemePalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.textMuted)
            .background(
                Circle()
                    .fill(configuration.isPressed ? theme.hover : Color.clear)
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .animation(
                reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.quick),
                value: configuration.isPressed
            )
            .contentShape(Circle())
    }
}

struct BeaconHeaderControls: View {
    let theme: BeaconThemePalette
    /// Nil hides the gear: the menu panel opens settings from its footer row.
    let onOpenSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var isRefreshing = false
    var frameSize: CGFloat = 28
    var settingsGlyphSize: CGFloat = 13
    var refreshGlyphSize: CGFloat = 13
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            if let onRefresh {
                Button(action: onRefresh) {
                    BeaconHeaderRefreshIcon(
                        color: isRefreshing ? theme.accent : theme.textPrimary,
                        glyphSize: refreshGlyphSize,
                        frameSize: frameSize,
                        isRefreshing: isRefreshing
                    )
                }
                .buttonStyle(BeaconUtilityIconButtonStyle(theme: theme))
                .disabled(isRefreshing)
                .accessibilityLabel(isRefreshing ? "Refreshing Batteries" : "Refresh Batteries")
                .help(isRefreshing ? "Refreshing Batteries" : "Refresh Batteries")
            }

            if let onOpenSettings {
            Button(action: onOpenSettings) {
                BeaconHeaderSettingsIcon(
                    color: theme.textPrimary,
                    glyphSize: settingsGlyphSize,
                    frameSize: frameSize
                )
            }
            .buttonStyle(BeaconUtilityIconButtonStyle(theme: theme))
            .accessibilityLabel("Open Beacon Settings")
            .help("Open Beacon Settings")
            }

            if let onQuit {
                Button(action: onQuit) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: frameSize, height: frameSize)
                        .contentShape(Circle())
                }
                .buttonStyle(BeaconUtilityIconButtonStyle(theme: theme))
                .accessibilityLabel("Quit Beacon")
                .help("Quit Beacon")
            }
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
        return BeaconSymbols.bluetooth
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

/// The battery glyph the system Bluetooth menu shows beside a percentage.
struct BatteryLevelGlyph: View {
    let percent: Int
    var isCharging = false
    let color: Color

    var body: some View {
        Image(systemName: resolveSymbol(symbolName, fallback: "battery.100"))
            .font(.system(size: 15, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// The round device icon of the system Bluetooth menu: a white disc with an
/// accent glyph while the device reports, a faint gray disc otherwise.
struct DeviceIconPlate: View {
    let symbolName: String
    var isActive = true
    var size: CGFloat = 26
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.white : theme.active)

            Image(systemName: symbolName)
                .font(.system(size: max(11, size * 0.46), weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : theme.textMuted)
                .frame(width: size * 0.72, height: size * 0.72)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
    }

    private var theme: BeaconThemePalette {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
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
    let reportState: DeviceBatteryTrust

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
        airPodsComponents: [AirPodsComponent] = [],
        reportState: DeviceBatteryTrust? = nil
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
        self.reportState = reportState ?? DeviceBatteryPresentation(percent: percent, freshness: freshness).state
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
        let presentation = DeviceBatteryPresentation(item: item)
        switch item {
        case .device(let decorated):
            self.init(
                id: decorated.id,
                displayName: decorated.snapshot.displayName,
                kind: decorated.snapshot.kind,
                percent: presentation.percent,
                chargeState: decorated.snapshot.chargeState,
                freshness: decorated.freshness,
                source: decorated.snapshot.source,
                provider: decorated.snapshot.provider,
                updatedAt: decorated.snapshot.updatedAt,
                isPinned: isPinned,
                reportState: presentation.state
            )
        case .airPods(let name, let id, let components):
            let activeComponents = activeAirPodsComponents(components)
            let chargeState: ChargeState
            if activeComponents.contains(where: { $0.chargeState == .charging }) {
                chargeState = .charging
            } else if !activeComponents.isEmpty,
                      activeComponents.allSatisfy({ $0.chargeState == .full || $0.percent == 100 }) {
                chargeState = .full
            } else {
                chargeState = .unplugged
            }
            let freshness: Freshness = activeComponents.isEmpty
                ? .expired
                : (activeComponents.contains { $0.freshness == .stale } ? .stale : .fresh)
            let updatedAt = activeComponents.map(\.updatedAt).max() ?? .distantPast
            self.init(
                id: id,
                displayName: name,
                kind: .airPods,
                percent: presentation.percent,
                chargeState: chargeState,
                freshness: freshness,
                source: .coreBluetooth,
                provider: .coreBluetoothBatteryService,
                updatedAt: updatedAt,
                isPinned: isPinned,
                airPodsComponents: activeComponents,
                reportState: presentation.state
            )
        }
    }
}

func batteryProviderLabel(source: BatterySource, provider: BatteryProvider) -> String {
    switch provider {
    case .macPowerSource: return BeaconL10n.string("Local Mac")
    case .ioRegistry: return "IORegistry"
    case .coreBluetoothBatteryService: return BeaconL10n.string("Bluetooth Battery Service")
    case .ioBluetooth: return "Bluetooth"
    case .systemProfiler: return BeaconL10n.string("System")
    case .bluetoothUnsupported: return "Bluetooth"
    case .ideviceInfo: return BeaconL10n.string("Trusted iPhone")
    }
}

func batteryRelativeAgeText(updatedAt: Date, now: Date = Date()) -> String {
    let age = max(0, now.timeIntervalSince(updatedAt))
    if age < 60 { return BeaconL10n.string("Now") }
    if age < 3_600 { return BeaconL10n.format("%dm ago", Int(age / 60)) }
    if age < 86_400 { return BeaconL10n.format("%dh ago", Int(age / 3_600)) }
    return BeaconL10n.format("%dd ago", Int(age / 86_400))
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
    if percent == nil { return BeaconL10n.string("No report") }
    if freshness == .expired { return BeaconL10n.string("Expired") }
    if freshness == .stale { return batteryRelativeAgeText(updatedAt: updatedAt, now: now) }
    if chargeState == .charging { return BeaconL10n.string("Charging") }
    if chargeState == .full { return BeaconL10n.string("Full") }
    if isLow { return BeaconL10n.string("Low") }
    if showsAirPodsComponents { return BeaconL10n.string("Parts") }
    return BeaconL10n.string("Battery")
}

struct DashboardBatteryDeviceRow: View {
    let device: DashboardBatteryDevice
    var lowBatteryThreshold = LowBatteryNotifier.threshold
    var iconSize: CGFloat = 26
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 3
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Same anatomy as a row in the system Bluetooth menu: icon, name,
        // then the battery on the trailing edge. The name may truncate; the
        // battery never does.
        HStack(spacing: 10) {
            DeviceIconPlate(
                symbolName: deviceSymbolName(for: device.kind, displayName: device.displayName),
                isActive: device.reportState == .current,
                size: iconSize
            )

            HStack(spacing: 4) {
                Text(device.displayName)
                    .font(.body)
                    .foregroundStyle(device.reportState == .current ? theme.textPrimary : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if device.isPinned {
                    Image(systemName: resolveSymbol("pin.fill", fallback: "pin"))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            Spacer(minLength: 8)

            trailingBattery
                .fixedSize()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        // The row has no background, so the whole row must stay hit-testable
        // for the context menu.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("device.row.\(device.id)")
    }

    @ViewBuilder
    private var trailingBattery: some View {
        if showsAirPodsComponents {
            HStack(spacing: 10) {
                ForEach(device.airPodsComponents, id: \.slot.rawValue) { component in
                    AirPodsDashboardComponentChip(component: component)
                }
            }
        } else if device.reportState == .current, let percent = device.percent {
            HStack(spacing: 5) {
                Text("\(percent)%")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(isLow ? statusColor : theme.textMuted)
                BatteryLevelGlyph(
                    percent: percent,
                    isCharging: device.chargeState == .charging || device.chargeState == .full,
                    color: statusColor
                )
            }
        } else {
            // Only exceptions are spelled out, as the system menu greys a
            // device that is not connected.
            Text(device.percent.map { "\($0)% · \(statusText)" } ?? statusText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var isLow: Bool {
        guard device.reportState == .current, let percent = device.percent else { return false }
        return percent <= lowBatteryThreshold
            && device.chargeState != .charging
            && device.chargeState != .full
    }

    private var showsAirPodsComponents: Bool {
        device.kind == .airPods && device.airPodsComponents.count > 1
    }

    /// Neutral unless the battery says something: green charging, orange low,
    /// red critical.
    private var statusColor: Color {
        guard device.reportState == .current else { return theme.textTertiary }
        if isLow {
            guard let percent = device.percent else { return theme.statusLow }
            return percent <= 10 ? theme.statusCritical : theme.statusLow
        }
        if device.chargeState == .charging || device.chargeState == .full {
            return theme.statusOK
        }
        return theme.textMuted
    }

    private var statusText: String {
        device.reportState.title
    }

    private var accessibilityValue: String {
        dashboardBatteryAccessibilityValue(
            for: device,
            statusText: statusText
        )
    }

    private var theme: BeaconThemePalette {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }
}

func dashboardBatteryAccessibilityValue(
    for device: DashboardBatteryDevice,
    statusText: String
) -> String {
    var parts: [String]
    if device.kind == .airPods, !device.airPodsComponents.isEmpty {
        parts = device.airPodsComponents.map(airPodsComponentAccessibilityDescription)
    } else if let percent = device.percent {
        parts = [device.reportState == .current || device.reportState == .partial
            ? BeaconL10n.format("%d percent", percent) : BeaconL10n.format("Last known: %d%%", percent)]
    } else {
        parts = [BeaconL10n.string("No battery report")]
    }

    if statusText != BeaconL10n.string("Battery"),
       statusText != BeaconL10n.string("Parts") {
        parts.append(statusText)
    }
    if device.isPinned {
        parts.append(BeaconL10n.string("Pinned"))
    }
    return parts.joined(separator: ", ")
}

private func airPodsComponentAccessibilityDescription(_ component: AirPodsComponent) -> String {
    let name: String
    switch component.slot {
    case .case:
        name = BeaconL10n.string("Charging case")
    case .left:
        name = BeaconL10n.string("Left AirPod")
    case .right:
        name = BeaconL10n.string("Right AirPod")
    }

    let trust = DeviceBatteryPresentation(component: component)
    var parts = [name]
    if let percent = trust.percent {
        parts.append(trust.state == .current
            ? BeaconL10n.format("%d percent", percent)
            : BeaconL10n.format("Last known: %d%%", percent))
    } else {
        parts.append(BeaconL10n.string("no battery report"))
    }
    switch trust.state == .current ? component.chargeState : .unknown {
    case .charging:
        parts.append(BeaconL10n.string("charging"))
    case .full:
        parts.append(BeaconL10n.string("full"))
    case .unknown, .unplugged:
        break
    }
    switch component.freshness {
    case .fresh:
        break
    case .stale:
        parts.append(BeaconL10n.string("stale"))
    case .expired:
        parts.append(BeaconL10n.string("expired"))
    }
    if ![.current, .stale, .expired].contains(trust.state) { parts.append(trust.state.title) }
    return parts.joined(separator: " ")
}

private struct AirPodsDashboardComponentChip: View {
    let component: AirPodsComponent
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Text(slotLabel)
                .font(.callout)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Text(percentText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(chipColor)
                .lineLimit(1)
        }
        .accessibilityLabel(accessibilityLabel)
        .help(airPodsComponentAccessibilityDescription(component))
    }

    private var percentText: String {
        guard let percent = DeviceBatteryPresentation(component: component).percent else { return "–" }
        return "\(percent)%"
    }

    private var chipColor: Color {
        guard DeviceBatteryPresentation(component: component).state == .current else { return DesignTokens.Palette.secondaryText }
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
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }

    private var slotLabel: String {
        switch component.slot {
        case .case:
            return BeaconL10n.string("Case")
        case .left:
            return BeaconL10n.string("L")
        case .right:
            return BeaconL10n.string("R")
        }
    }

    private var accessibilityLabel: String {
        switch component.slot {
        case .case:
            return BeaconL10n.format("Charging case %@", percentText)
        case .left:
            return BeaconL10n.format("Left AirPod %@", percentText)
        case .right:
            return BeaconL10n.format("Right AirPod %@", percentText)
        }
    }
}

/// A menu item's hover highlight: a rounded fill the width of the menu, as in
/// the system menus. Only for rows that act on click.
struct MenuItemButtonStyle: ButtonStyle {
    let theme: BeaconThemePalette

    func makeBody(configuration: Configuration) -> some View {
        MenuItemBody(configuration: configuration, theme: theme)
    }

    private struct MenuItemBody: View {
        let configuration: ButtonStyle.Configuration
        let theme: BeaconThemePalette
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(configuration.isPressed ? theme.active : (isHovering ? theme.hover : Color.clear))
                )
                .onHover { isHovering = $0 }
        }
    }
}
