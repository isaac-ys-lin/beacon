import Charts
import SwiftUI

extension View {
    @ViewBuilder
    func beaconSettingsCardSurface(
        cornerRadius: CGFloat = DesignTokens.Radius.card
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self
                .background {
                    shape
                        .fill(.regularMaterial)
                        .glassEffect(.regular, in: shape)
                        .overlay(shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7))
                }
        } else {
            self
                .background {
                    shape
                        .fill(.regularMaterial)
                        .overlay(shape.stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7))
                }
        }
    }
}

struct AddDeviceGuideView: View {
    let trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport?
    let onOpenBluetoothSettings: () -> Void
    let onTrustConnectedIPhone: () -> Void
    let onDismiss: () -> Void

    init(
        trustedIPhoneEnrollmentResult: IPhoneLockdownDiscoveryReport? = nil,
        onOpenBluetoothSettings: @escaping () -> Void,
        onTrustConnectedIPhone: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.trustedIPhoneEnrollmentResult = trustedIPhoneEnrollmentResult
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
        self.onTrustConnectedIPhone = onTrustConnectedIPhone
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set Up a Device")
                        .font(DesignTokens.Typography.windowTitle)
                    Text("Paired audio devices appear even without a battery report. Other supported devices appear when they report battery levels.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel("Close")
            }

            VStack(spacing: 8) {
                AddDeviceGuideRow(
                    title: "AirPods or Beats",
                    subtitle: "Pair in Bluetooth Settings, then refresh.",
                    systemImage: resolveSymbol("airpodspro", fallback: "headphones"),
                    actionTitle: "Bluetooth",
                    action: onOpenBluetoothSettings
                )

                AddDeviceGuideRow(
                    title: "Keyboard, mouse, or trackpad",
                    subtitle: "Pair the Bluetooth accessory in System Settings, then refresh.",
                    systemImage: resolveSymbol("keyboard", fallback: "rectangle.and.hand.point.up.left"),
                    actionTitle: "Bluetooth",
                    action: onOpenBluetoothSettings
                )

                AddDeviceGuideRow(
                    title: "iPhone or iPad",
                    subtitle: "Connect by USB, unlock, trust this Mac, then add it here.",
                    systemImage: resolveSymbol("iphone", fallback: "mobilephone"),
                    actionTitle: "Set Up",
                    action: onTrustConnectedIPhone
                )
                .accessibilityIdentifier("setup.iphone")
            }

            if let trustedIPhoneEnrollmentResult {
                TrustedIPhoneStatusLine(
                    status: trustedIPhoneEnrollmentResult.status,
                    message: trustedIPhoneEnrollmentResult.message
                )
            }

            HStack(spacing: 10) {
                Label("Refresh after pairing or connecting your device.", systemImage: "arrow.clockwise")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 520)
        .beaconSettingsCardSurface(cornerRadius: DesignTokens.Radius.panel)
    }
}

struct TrustedIPhoneStatusLine: View {
    let status: BatteryReadStatus
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 14, height: 14)

            Text(message)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var symbolName: String {
        switch status {
        case .reported: return "checkmark.circle.fill"
        case .noReport: return "info.circle.fill"
        case .unavailable, .timedOut, .commandMissing: return "exclamationmark.triangle.fill"
        case .unauthorized: return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .reported: return DesignTokens.Palette.healthy
        case .noReport: return DesignTokens.Palette.secondaryText
        case .unavailable, .timedOut, .commandMissing: return DesignTokens.Palette.warning
        case .unauthorized: return DesignTokens.Palette.critical
        }
    }
}

struct AddDeviceGuideRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let actionTitle: LocalizedStringKey
    var isEnabled = true
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Typography.captionEmphasis)
                        .foregroundStyle(isEnabled ? DesignTokens.Palette.text : DesignTokens.Palette.secondaryText)
                    Text(subtitle)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Text(actionTitle)
                    .font(DesignTokens.Typography.captionEmphasis)
                    .foregroundStyle(isEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.tertiaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )
            }
            .padding(10)
            .contentShape(Rectangle())
            .beaconSettingsCardSurface(cornerRadius: DesignTokens.Radius.row)
            .opacity(isEnabled ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct RefreshHealthDisclosureView: View {
    let diagnostics: BatteryRefreshDiagnostics

    @State private var isExpanded = false

    var body: some View {
        let presentation = batteryRefreshDiagnosticsPresentation(diagnostics)

        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(presentation.attempts.enumerated()), id: \.offset) { _, attempt in
                    RefreshHealthAttemptRow(attempt: attempt)
                }

                if presentation.attempts.isEmpty {
                    Text("Run Refresh to check Bluetooth accessories and iPhone USB access.")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: refreshHealthSymbol(for: presentation.tone))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(refreshHealthColor(for: presentation.tone))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.title)
                        .font(DesignTokens.Typography.captionEmphasis)
                    Text(refreshHealthSummary(presentation))
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
        .font(DesignTokens.Typography.caption)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .beaconSettingsCardSurface(cornerRadius: DesignTokens.Radius.row)
    }

    private func refreshHealthSummary(_ presentation: BatteryRefreshDiagnosticsPresentation) -> String {
        guard !presentation.attempts.isEmpty else {
            return BeaconL10n.string("No completed refresh yet")
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return BeaconL10n.format(
            "%1$@ · %2$@",
            presentation.summary,
            relative.localizedString(for: presentation.refreshedAt, relativeTo: Date())
        )
    }

    private func refreshHealthSymbol(for tone: BatteryRefreshHealthTone) -> String {
        switch tone {
        case .success: return "checkmark.circle.fill"
        case .neutral: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func refreshHealthColor(for tone: BatteryRefreshHealthTone) -> Color {
        switch tone {
        case .success: return DesignTokens.Palette.charging
        case .neutral: return DesignTokens.Palette.secondaryText
        case .warning: return DesignTokens.Palette.warning
        case .error: return DesignTokens.Palette.critical
        }
    }
}

private struct RefreshHealthAttemptRow: View {
    let attempt: BatteryRefreshAttemptPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: statusSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(attempt.providerTitle)
                        .font(DesignTokens.Typography.caption2Emphasis)
                    Text(attempt.statusTitle)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(statusColor)
                    if attempt.candidateCount > 0 {
                        Text(BeaconL10n.format(
                            attempt.candidateCount == 1 ? "· %d result" : "· %d results",
                            attempt.candidateCount
                        ))
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(DesignTokens.Palette.tertiaryText)
                    }
                    Text(BeaconL10n.format("· tried %@", attemptAgeText))
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.tertiaryText)
                }

                Text(attempt.explanation)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(attempt.nextStep)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        switch attempt.status {
        case .reported: return "checkmark.circle.fill"
        case .noReport: return "minus.circle"
        case .unavailable: return "questionmark.circle"
        case .timedOut: return "clock.badge.exclamationmark"
        case .unauthorized: return "lock.trianglebadge.exclamationmark"
        case .commandMissing: return "wrench.and.screwdriver"
        }
    }

    private var attemptAgeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: attempt.attemptedAt, relativeTo: Date())
    }

    private var statusColor: Color {
        switch attempt.status {
        case .reported: return DesignTokens.Palette.charging
        case .noReport, .unavailable: return DesignTokens.Palette.secondaryText
        case .timedOut: return DesignTokens.Palette.warning
        case .unauthorized, .commandMissing: return DesignTokens.Palette.critical
        }
    }
}

struct SettingsEmptyStateCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    var tint = DesignTokens.Palette.accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: resolveSymbol(systemImage, fallback: "info.circle"))
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(DesignTokens.Palette.text)
                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .beaconSettingsCardSurface()
    }
}

/// A System Settings–style sidebar icon: a white glyph on a tinted rounded square.
struct SettingsPaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.sidebarSymbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(pane.sidebarTint.gradient)
            )
            .accessibilityHidden(true)
    }
}

extension SettingsPane {
    var sidebarSymbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .devices: return resolveSymbol("headphones", fallback: "dot.radiowaves.left.and.right")
        case .alerts: return "bell.badge.fill"
        case .actionHUD: return resolveSymbol("rectangle.inset.topright.filled", fallback: "rectangle.fill")
        case .quickActions: return "command"
        case .audio: return "mic.fill"
        case .dashboard: return resolveSymbol("square.grid.2x2.fill", fallback: "square.grid.2x2")
        }
    }

    var sidebarTint: Color {
        switch self {
        case .general: return .gray
        case .devices: return .blue
        case .alerts: return .red
        case .actionHUD: return .indigo
        case .quickActions: return .orange
        case .audio: return .pink
        case .dashboard: return .green
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case devices
    case audio
    case alerts
    case actionHUD
    case quickActions
    case dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return BeaconL10n.string("General")
        case .devices: return BeaconL10n.string("Devices")
        case .alerts: return BeaconL10n.string("Alerts")
        case .actionHUD: return BeaconL10n.string("Action HUD")
        case .quickActions: return BeaconL10n.string("Quick Actions")
        case .audio: return BeaconL10n.string("Audio Input")
        case .dashboard: return BeaconL10n.string("Dashboard")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .devices: return BeaconSymbols.bluetooth
        case .alerts: return "bell.badge"
        case .actionHUD: return "sparkles"
        case .quickActions: return "keyboard"
        case .audio: return "mic"
        case .dashboard: return BeaconSymbols.app
        }
    }
}

struct AutomationShortcutsBanner: View {
    private let actions = [
        ("Battery Summary", "list.bullet.rectangle"),
        ("Lowest Battery", "battery.25"),
        ("Low List", "exclamationmark.triangle"),
        ("Battery Trends", "chart.xyaxis.line"),
        ("Connect", BeaconSymbols.bluetooth),
        ("Disconnect", "bolt.horizontal.circle")
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: resolveSymbol("sparkles.rectangle.stack", fallback: "sparkles"))
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Palette.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text("Automation Shortcuts")
                        .font(DesignTokens.Typography.captionEmphasis)
                        .foregroundStyle(DesignTokens.Palette.text)
                    Label("Actions", systemImage: "checkmark.circle.fill")
                        .font(DesignTokens.Typography.caption2Emphasis)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(DesignTokens.Palette.charging)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DesignTokens.Palette.controlPill)
                        )
                }

                HStack(spacing: 6) {
                    ForEach(actions, id: \.0) { action in
                        Label(action.0, systemImage: action.1)
                            .labelStyle(.iconOnly)
                            .font(DesignTokens.Typography.caption2Emphasis)
                            .lineLimit(1)
                            .foregroundStyle(DesignTokens.Palette.text.opacity(0.82))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DesignTokens.Palette.controlPill.opacity(0.92))
                            )
                            .help(action.0)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct AirPodsAudioControlsCard: View {
    let deviceID: String
    let onOpenSoundSettings: () -> Void
    let onOpenBluetoothSettings: () -> Void

    init(
        deviceID: String,
        onOpenSoundSettings: @escaping () -> Void,
        onOpenBluetoothSettings: @escaping () -> Void
    ) {
        self.deviceID = deviceID
        self.onOpenSoundSettings = onOpenSoundSettings
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Audio Controls", systemImage: "waveform")
                    .font(DesignTokens.Typography.captionEmphasis)
                Spacer()
            }

            Text(BeaconL10n.string("Choose audio output and input in Sound Settings. Change AirPods listening modes in Control Center or Bluetooth Settings."))
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    onOpenSoundSettings()
                } label: {
                    Label("Sound Settings", systemImage: "speaker.wave.2")
                }
                .accessibilityIdentifier("airpods.audio-controls.sound-settings")

                Button {
                    onOpenBluetoothSettings()
                } label: {
                    Label("Bluetooth", systemImage: BeaconSymbols.bluetooth)
                }
                .accessibilityIdentifier("airpods.audio-controls.bluetooth-settings")

                Spacer()
            }
            .font(DesignTokens.Typography.captionEmphasis)
        }
        .padding(12)
        .beaconSettingsCardSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("airpods.audio-controls")
    }
}

struct DeviceCurrentStatsCard: View {
    let item: DeviceListItem
    let historySamples: [BatteryHistorySample]
    @ObservedObject private var deviceDetails = BluetoothDeviceDetailsStore.shared

    private var presentation: DeviceBatteryPresentation { .init(item: item) }

    private var firmwareVersion: String? {
        deviceDetails.details(forDeviceID: item.id)?.firmwareVersion
    }

    private var historySummary: BatteryHistorySummary? {
        BatteryHistoryStore.summary(for: historySamples)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Current Stats", systemImage: "chart.bar.xaxis")
                    .font(DesignTokens.Typography.captionEmphasis)
                Spacer()
                Text(presentation.state.title)
                    .accessibilityIdentifier("device.report.state")
                    .font(DesignTokens.Typography.caption2Emphasis)
                    .foregroundStyle(DesignTokens.Palette.text)
                    .overlay(alignment: .leading) {
                        Circle().fill(reportColor).frame(width: 6, height: 6).offset(x: -10)
                            .accessibilityHidden(true)
                    }
                    .padding(.leading, 8)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule(style: .continuous).fill(DesignTokens.Palette.controlPill))
            }

            VStack(spacing: 0) {
                SettingsInfoRow(
                    title: "Battery",
                    value: batteryText,
                    systemImage: batteryIcon,
                    color: batteryColor
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Report",
                    value: reportText,
                    systemImage: reportIcon,
                    color: reportColor
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Connection",
                    value: connectionText,
                    systemImage: connectionIcon,
                    color: connectionColor
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Updated",
                    value: updatedText,
                    systemImage: "clock",
                    color: updatedColor
                )

                if let firmwareVersion {
                    Divider().padding(.leading, 40)

                    SettingsInfoRow(
                        title: "Firmware",
                        value: firmwareVersion,
                        systemImage: "cpu",
                        color: .secondary
                    )
                    .accessibilityIdentifier("device.report.firmware")
                }
            }
            .background(settingsGroupBackground)

            DisclosureGroup("Technical Details") {
                Text(sourceText).font(.caption)
                Text(item.id).font(.caption.monospaced()).textSelection(.enabled)
            }
            .font(.caption)
            .accessibilityIdentifier("device.report.diagnostics")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Battery Trend")
                        .font(DesignTokens.Typography.caption2Emphasis)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                    Spacer()
                    Text(trendText)
                        .font(DesignTokens.Typography.caption2Emphasis)
                        .foregroundStyle(trendColor)
                }

                if (historySummary?.samples.count ?? 0) >= 2 {
                    BatteryHistorySparkline(samples: historySummary?.samples ?? [])
                        .frame(height: 96)
                }

                Text(rangeText)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .lineLimit(1)
            }
            .padding(12)
            .background(settingsGroupBackground)
        }
        .padding(12)
        .beaconSettingsCardSurface()
    }

    private var settingsGroupBackground: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
            .fill(DesignTokens.Palette.controlPill.opacity(0.62))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
            )
    }

    private var batteryText: String { presentation.valueText }

    private var batteryIcon: String {
        guard presentation.state == .current else { return "battery.100" }
        switch item {
        case .device(let decorated):
            if decorated.snapshot.chargeState == .charging { return "battery.100.bolt" }
            return "battery.100"
        case .airPods:
            return "battery.100"
        }
    }

    private var batteryColor: Color {
        guard presentation.state == .current else { return DesignTokens.Palette.secondaryText }
        switch item {
        case .device(let decorated):
            guard let percent = decorated.snapshot.percent else { return DesignTokens.Palette.secondaryText }
            if percent <= LowBatteryNotifier.threshold { return DesignTokens.Palette.critical }
            if decorated.snapshot.chargeState == .charging || decorated.snapshot.chargeState == .full {
                return DesignTokens.Palette.charging
            }
            return DesignTokens.Palette.accent
        case .airPods(_, _, let components):
            let percents = components.compactMap(\.percent)
            if let lowest = percents.min(), lowest <= LowBatteryNotifier.threshold {
                return DesignTokens.Palette.critical
            }
            if components.contains(where: { $0.chargeState == .charging || $0.chargeState == .full }) {
                return DesignTokens.Palette.charging
            }
            return DesignTokens.Palette.accent
        }
    }

    private var sourceText: String {
        switch item {
        case .device(let decorated):
            return batteryProviderLabel(
                source: decorated.snapshot.source,
                provider: decorated.snapshot.provider
            )
        case .airPods:
            return "Bluetooth"
        }
    }

    private var reportText: String { presentation.state.title }
    private var reportKey: String { presentation.state == .current ? "Reporting" : presentation.state.title }

    private var reportIcon: String {
        switch presentation.state {
        case .current: return "checkmark.circle.fill"
        case .permission, .unavailable: return "exclamationmark.triangle"
        case .noReport: return "minus.circle"
        default: return "clock.badge.exclamationmark"
        }
    }

    private var reportColor: Color {
        presentation.state == .current ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText
    }

    private var connectionText: String {
        switch item.connectionState {
        case .connected: return BeaconL10n.string("Connected")
        case .disconnected: return BeaconL10n.string("Disconnected")
        case .unknown: return BeaconL10n.string("Connection unconfirmed")
        }
    }

    private var connectionColor: Color {
        item.connectionState == .connected ? DesignTokens.Palette.charging : DesignTokens.Palette.secondaryText
    }

    private var connectionIcon: String {
        item.connectionState == .connected ? "link.circle.fill" : "questionmark.circle"
    }

    private var updatedText: String {
        guard presentation.updatedAt != .distantPast else { return BeaconL10n.string("No report") }
        return batteryRelativeAgeText(updatedAt: presentation.updatedAt)
    }

    private var updatedColor: Color {
        switch item {
        case .device(let decorated):
            return decorated.freshness == .fresh ? DesignTokens.Palette.accent : DesignTokens.Palette.stale
        case .airPods(_, _, let components):
            return components.contains { $0.freshness != .fresh } ? DesignTokens.Palette.stale : DesignTokens.Palette.accent
        }
    }

    private var trendText: String {
        guard let historySummary else { return BeaconL10n.string("Collecting") }
        return historySummary.trendDescription
    }

    private var trendColor: Color {
        guard let historySummary else { return DesignTokens.Palette.secondaryText }
        if historySummary.delta > 0 { return DesignTokens.Palette.charging }
        if historySummary.delta < 0 { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.secondaryText
    }

    private var rangeText: String {
        guard let historySummary else {
            return BeaconL10n.string("Beacon will build a trend as reports arrive.")
        }
        return BeaconL10n.format(
            "Range %1$d%% - %2$d%% across %3$d reports.",
            historySummary.minimumPercent,
            historySummary.maximumPercent,
            historySummary.samples.count
        )
    }

}

/// Battery level over time, drawn with Swift Charts on a real time axis and a
/// fixed 0–100% scale (as in System Settings > Battery), so uneven sampling or
/// a 2% wobble is not exaggerated.
struct BatteryHistorySparkline: View {
    let samples: [BatteryHistorySample]

    var body: some View {
        if sortedSamples.count >= 2 {
            Chart(sortedSamples) { sample in
                AreaMark(
                    x: .value("Time", sample.recordedAt),
                    y: .value("Battery", sample.percent)
                )
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Time", sample.recordedAt),
                    y: .value("Battery", sample.percent)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Int.self) { Text("\(percent)%") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour())
                }
            }
            .accessibilityLabel(Text("Battery Trend"))
        }
    }

    private var sortedSamples: [BatteryHistorySample] {
        samples.sorted { $0.recordedAt < $1.recordedAt }
    }
}

struct SettingsInfoRow: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: resolveSymbol(systemImage, fallback: "circle"))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.text)

            Spacer(minLength: 12)

            // Status colour stays on the icon; text keeps system contrast.
            Text(value)
                .font(DesignTokens.Typography.captionEmphasis)
                .foregroundStyle(DesignTokens.Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsDeviceSidebarRow: View {
    let item: DeviceInspectorItem
    let isSelected: Bool
    let symbolName: String
    let iconColor: Color
    let iconBadge: DeviceIconBadge?
    let alertSummary: String
    let action: () -> Void
    @AppStorage(BeaconAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BeaconAppearanceTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)
                    .overlay(alignment: .bottomTrailing) {
                        if let iconBadge {
                            Image(systemName: iconBadge.symbolName)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(iconBadge.color(in: theme))
                                .offset(x: 5, y: 4)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(DesignTokens.Typography.captionEmphasis)
                        .foregroundStyle(item.isHidden ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.text)
                        .lineLimit(1)
                    Text(rowSubtitle)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: NativeMacStyle.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? NativeMacStyle.rowSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(rowSubtitle)
        .accessibilityHint("Selects this device")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Keep the row's position in the VoiceOver traversal stable while the
        // selected trait changes after a click.
        .accessibilitySortPriority(0)
    }

    private var theme: BeaconThemePalette {
        BeaconAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }

    private var rowSubtitle: String {
        let visibility: String
        if item.isUserHidden {
            visibility = BeaconL10n.string("Hidden")
        } else if item.isUnavailable {
            visibility = BeaconL10n.string("Hidden until connected")
        } else if item.isPinned {
            visibility = BeaconL10n.string("Pinned")
        } else {
            visibility = BeaconL10n.string("Visible")
        }
        return BeaconL10n.format("%1$@ · %2$@", visibility, alertSummary)
    }
}

struct SettingsAlertPreview: View {
    let title: LocalizedStringKey
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.captionEmphasis)
                Text(subtitle)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Palette.controlPill.opacity(0.62))
        )
    }
}
