import AppKit
import SwiftUI
import os

enum DesktopWidgetPreferences {
    static let showDesktopWidgetKey = "BatteryHub.desktopWidget.show"
    static let widgetStyleKey = "BatteryHub.desktopWidget.style"
}

enum DesktopWidgetStyle: String, CaseIterable, Identifiable {
    case compact
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .expanded: return "Expanded"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .compact: return "Compact widget"
        case .expanded: return "Expanded widget"
        }
    }

    var symbolName: String {
        switch self {
        case .compact:
            return resolveSymbol("rectangle.grid.1x2", fallback: "rectangle")
        case .expanded:
            return resolveSymbol("rectangle.grid.3x2", fallback: "rectangle.grid.2x2")
        }
    }

    var width: CGFloat {
        switch self {
        case .compact: return 256
        case .expanded: return 318
        }
    }

    var maxDeviceCount: Int {
        switch self {
        case .compact: return 3
        case .expanded: return 5
        }
    }

    var height: CGFloat {
        switch self {
        case .compact: return 232
        case .expanded: return 336
        }
    }

    var size: NSSize {
        NSSize(width: width, height: height)
    }
}

enum DesktopWidgetWindowPlacement {
    static let defaultTrailingInset: CGFloat = 28
    static let defaultTopInset: CGFloat = 72

    static func reusedFrame(currentFrame: NSRect, style: DesktopWidgetStyle) -> NSRect {
        let targetSize = style.size
        guard !isSameSize(currentFrame.size, targetSize) else { return currentFrame }
        return NSRect(
            x: currentFrame.maxX - targetSize.width,
            y: currentFrame.maxY - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )
    }

    static func initialFrame(for style: DesktopWidgetStyle, in visibleFrame: NSRect) -> NSRect {
        let size = style.size
        return NSRect(
            x: visibleFrame.maxX - size.width - defaultTrailingInset,
            y: visibleFrame.maxY - size.height - defaultTopInset,
            width: size.width,
            height: size.height
        )
    }

    private static func isSameSize(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}

private struct DesktopWidgetBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct BatteryDesktopWidgetView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let style: DesktopWidgetStyle
    var onOpenSettings: (() -> Void)?
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var sections: [DeviceSection] {
        configuredDeviceSections(snapshots, preferences: .load())
    }

    private var summary: BatteryOverviewSummary {
        batteryOverviewSummary(for: sections, lowBatteryThreshold: LowBatteryNotifier.threshold)
    }

    private var devices: [BatteryOverviewDevice] {
        batteryOverviewDevices(for: sections, limit: style.maxDeviceCount)
    }

    private var latestUpdateText: String {
        guard let latest = snapshots.map(\.snapshot.updatedAt).max() else { return "No reports" }
        let interval = abs(latest.timeIntervalSinceNow)
        if interval < 60 { return "Updated now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: latest, relativeTo: Date()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if devices.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(devices) { device in
                        DashboardBatteryDeviceRow(device: DashboardBatteryDevice(device))
                    }
                }
            }
        }
        .padding(14)
        .frame(width: style.width, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: NativeMacStyle.widgetCornerRadius, style: .continuous)
            DesktopWidgetBackground()
                .clipShape(shape)
                .overlay(shape.fill(theme.panel.opacity(0.66)))
                .overlay(shape.stroke(theme.hairlineDefault, lineWidth: 0.8))
        }
        .clipShape(RoundedRectangle(cornerRadius: NativeMacStyle.widgetCornerRadius, style: .continuous))
        .shadow(color: theme.shadow, radius: 18, x: 0, y: 10)
        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BatteryHubLogoMark(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Batteries")
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(theme.textPrimary)
                Text(latestUpdateText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(theme.textMuted)
            }

            Spacer(minLength: 0)

            if let lowest = summary.lowestPercent {
                Text("\(lowest)%")
                    .font(DesignTokens.Typography.percentSmall)
                    .monospacedDigit()
                    .foregroundStyle(summary.lowBatteryItemCount > 0 ? theme.statusLow : theme.statusOK)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.raised.opacity(0.70))
                    )
            }

            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    BatteryHubHeaderSettingsIcon(color: theme.textPrimary)
                }
                .buttonStyle(BatteryHubUtilityIconButtonStyle(theme: theme))
                .help("Open Dashboard Settings")
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            BatteryHubLogoMark(size: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.raised.opacity(0.72))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("No battery reports")
                    .font(DesignTokens.Typography.controlLabelEmphasis)
                    .foregroundStyle(theme.textPrimary)
                Text("Refresh or pair a nearby device.")
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
                    RoundedRectangle(cornerRadius: NativeMacStyle.dashboardRowCornerRadius, style: .continuous)
                        .fill(theme.raised.opacity(0.70))
                )
    }

    private var appearanceTheme: BatteryHubAppearanceTheme {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
    }

    private var theme: BeaconThemePalette {
        appearanceTheme.palette(resolvedSystemScheme: colorScheme)
    }
}

@MainActor
final class BatteryHubDesktopWidgetController {
    private let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "widget")
    private var window: NSPanel?

    func update(
        snapshots: [DecoratedBatterySnapshot],
        onOpenSettings: @escaping () -> Void
    ) {
        guard UserDefaults.standard.bool(forKey: DesktopWidgetPreferences.showDesktopWidgetKey) else {
            close()
            return
        }

        let style = DesktopWidgetStyle(
            rawValue: UserDefaults.standard.string(forKey: DesktopWidgetPreferences.widgetStyleKey) ?? ""
        ) ?? .compact
        let wasVisible = window?.isVisible == true
        let window = existingOrNewWindow(for: style)
        let hostingController = NSHostingController(
            rootView: BatteryDesktopWidgetView(
                snapshots: snapshots,
                style: style,
                onOpenSettings: onOpenSettings
            )
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = NativeMacStyle.widgetCornerRadius
        hostingController.view.layer?.masksToBounds = false
        window.contentViewController = hostingController
        positionIfNeeded(window, style: style)
        window.orderFrontRegardless()
        if !wasVisible {
            logger.info("Desktop widget shown style=\(style.rawValue, privacy: .public)")
        }
    }

    func close() {
        let wasVisible = window?.isVisible == true
        window?.orderOut(nil)
        if wasVisible {
            logger.info("Desktop widget hidden")
        }
    }

    private func existingOrNewWindow(for style: DesktopWidgetStyle) -> NSPanel {
        if let window {
            let targetFrame = DesktopWidgetWindowPlacement.reusedFrame(
                currentFrame: window.frame,
                style: style
            )
            if targetFrame != window.frame {
                window.setFrame(targetFrame, display: true)
            }
            return window
        }

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: style.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = NativeMacStyle.widgetCornerRadius
        window.contentView?.layer?.masksToBounds = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.window = window
        return window
    }

    private func positionIfNeeded(_ window: NSPanel, style: DesktopWidgetStyle) {
        guard window.frame.origin == .zero else { return }
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrame(
            DesktopWidgetWindowPlacement.initialFrame(for: style, in: frame),
            display: true
        )
    }
}
