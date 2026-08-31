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
                    Text("Pair or connect a supported device. Beacon discovers it automatically after a battery report arrives.")
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
                    actionTitle: "Trust",
                    action: onTrustConnectedIPhone
                )
            }

            if let trustedIPhoneEnrollmentResult {
                TrustedIPhoneStatusLine(
                    status: trustedIPhoneEnrollmentResult.status,
                    message: trustedIPhoneEnrollmentResult.message
                )
            }

            HStack(spacing: 10) {
                Label("Devices appear automatically after Beacon receives a fresh battery report.", systemImage: "arrow.clockwise")
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

struct TrustedIPhoneSettingsCard: View {
    let latestRefreshDiagnostics: BatteryRefreshDiagnostics
    let trustedIPhones: [TrustedIPhone]
    let enrollmentResult: IPhoneLockdownDiscoveryReport?
    let onTrustConnectedIPhone: () -> Void
    let onForgetTrustedIPhone: (String) -> Void

    private var latestIPhoneAttempt: BatteryProviderAttempt? {
        latestRefreshDiagnostics.attempts.last { $0.provider == .ideviceInfo }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: resolveSymbol("iphone.gen3", fallback: "iphone"))
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusColor)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Palette.controlPill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trusted iPhone")
                        .font(DesignTokens.Typography.captionEmphasis)
                    Text("Only enrolled iPhones and iPads can provide battery reports.")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(action: onTrustConnectedIPhone) {
                    Label("Add Paired iPhone", systemImage: "iphone.badge.plus")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 58)

            VStack(alignment: .leading, spacing: 9) {
                if let enrollmentResult {
                    TrustedIPhoneStatusLine(
                        status: enrollmentResult.status,
                        message: enrollmentResult.message
                    )
                }

                if let latestIPhoneAttempt {
                    TrustedIPhoneStatusLine(
                        status: latestIPhoneAttempt.status,
                        message: latestIPhoneAttempt.message
                    )
                } else {
                    Text("No trusted iPhone diagnostic has run yet.")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }

                if trustedIPhones.isEmpty {
                    Text("No trusted iPhones saved.")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Palette.tertiaryText)
                } else {
                    VStack(spacing: 6) {
                        ForEach(trustedIPhones) { phone in
                            HStack(spacing: 10) {
                                Image(systemName: resolveSymbol("iphone.gen3", fallback: "iphone"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(DesignTokens.Palette.accent)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(DesignTokens.Palette.controlPill)
                                    )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(phone.displayName)
                                        .font(DesignTokens.Typography.captionEmphasis)
                                        .lineLimit(1)
                                    Text(phone.udid)
                                        .font(DesignTokens.Typography.caption2)
                                        .foregroundStyle(DesignTokens.Palette.tertiaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 8)

                                Button(role: .destructive) {
                                    onForgetTrustedIPhone(phone.udid)
                                } label: {
                                    Label("Forget", systemImage: "trash")
                                }
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                                    .fill(DesignTokens.Palette.card)
                            )
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: 560, alignment: .topLeading)
        .beaconSettingsCardSurface()
    }

    private var statusColor: Color {
        if let enrollmentResult {
            return color(for: enrollmentResult.status)
        }
        if let latestIPhoneAttempt {
            return color(for: latestIPhoneAttempt.status)
        }
        return DesignTokens.Palette.secondaryText
    }

    private func color(for status: BatteryReadStatus) -> Color {
        switch status {
        case .reported: return DesignTokens.Palette.healthy
        case .noReport: return DesignTokens.Palette.secondaryText
        case .unavailable, .timedOut, .commandMissing: return DesignTokens.Palette.warning
        case .unauthorized: return DesignTokens.Palette.critical
        }
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
                ForEach(presentation.attempts) { attempt in
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

struct SettingsPaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        if pane == .devices {
            BluetoothLogoMark(size: 20)
        } else if pane == .dashboard {
            BeaconLogoMark(size: 20)
        } else {
            Image(systemName: pane.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case devices
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
        case .dashboard: return BeaconSymbols.app
        }
    }
}

struct QuickActionSettingsRow: View {
    let action: BeaconQuickAction
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: BeaconSymbols.resolved(action.systemImage))
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.controlPill)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(action.title)
                        .font(DesignTokens.Typography.captionEmphasis)

                    Text(shortcutText)
                        .font(DesignTokens.Typography.caption2Emphasis)
                        .monospaced()
                        .foregroundStyle(action.isSupported ? DesignTokens.Palette.accent : DesignTokens.Palette.tertiaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DesignTokens.Palette.controlPill)
                        )

                    if action.isSupported {
                        Label("Shortcuts", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(DesignTokens.Typography.caption2Emphasis)
                            .foregroundStyle(DesignTokens.Palette.charging)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DesignTokens.Palette.controlPill)
                            )
                            .help("Available in macOS Shortcuts")
                    }
                }

                Text(action.subtitle)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!action.isSupported)
        }
        .padding(.vertical, 4)
        .opacity(action.isSupported ? 1 : 0.48)
    }

    private var iconColor: Color {
        if !action.isSupported { return DesignTokens.Palette.secondaryText }
        return isEnabled ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText
    }

    private var shortcutText: String {
        action.shortcut?.displayText ?? "Unavailable"
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

struct ActionHUDEventToggle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? color : DesignTokens.Palette.secondaryText)
                .frame(width: 32, height: 32)
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
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

struct AirPodsAudioControlsCard: View {
    let deviceID: String
    let onOpenSoundSettings: () -> Void
    let onOpenBluetoothSettings: () -> Void

    @State private var preferences: AirPodsAudioPreferences

    init(
        deviceID: String,
        onOpenSoundSettings: @escaping () -> Void,
        onOpenBluetoothSettings: @escaping () -> Void
    ) {
        self.deviceID = deviceID
        self.onOpenSoundSettings = onOpenSoundSettings
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
        _preferences = State(initialValue: AirPodsAudioPreferences.load(for: deviceID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Audio Controls", systemImage: "waveform")
                    .font(DesignTokens.Typography.captionEmphasis)
                Spacer()
                Text("Reference only")
                    .font(DesignTokens.Typography.caption2Emphasis)
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule(style: .continuous).fill(DesignTokens.Palette.controlPill))
            }

            HStack(spacing: 8) {
                AudioPreferenceTile(
                    title: "Listening",
                    value: preferences.listeningMode.title,
                    systemImage: preferences.listeningMode.systemImage,
                    color: DesignTokens.Palette.accent
                )
                AudioPreferenceTile(
                    title: "Mic Input",
                    value: preferences.microphone.title,
                    systemImage: "mic",
                    color: DesignTokens.Palette.charging
                )
            }

            Text("These choices are notes saved in Beacon; they do not change your AirPods.")
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Preferred Listening Mode", selection: listeningModeBinding) {
                ForEach(AirPodsListeningModePreference.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Preferred Microphone", selection: microphoneBinding) {
                ForEach(AirPodsMicrophonePreference.allCases) { microphone in
                    Text(microphone.shortTitle).tag(microphone)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button {
                    onOpenSoundSettings()
                } label: {
                    Label("Sound Settings", systemImage: "speaker.wave.2")
                }

                Button {
                    onOpenBluetoothSettings()
                } label: {
                    Label("Bluetooth", systemImage: BeaconSymbols.bluetooth)
                }

                Spacer()
            }
            .font(DesignTokens.Typography.captionEmphasis)

            Text("Use Sound Settings to apply the actual listening mode or microphone change.")
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .beaconSettingsCardSurface()
        .onChange(of: deviceID) { _, nextDeviceID in
            preferences = AirPodsAudioPreferences.load(for: nextDeviceID)
        }
    }

    private var listeningModeBinding: Binding<AirPodsListeningModePreference> {
        Binding(
            get: { preferences.listeningMode },
            set: { mode in
                preferences = preferences.settingListeningMode(mode)
                preferences.save(for: deviceID)
            }
        )
    }

    private var microphoneBinding: Binding<AirPodsMicrophonePreference> {
        Binding(
            get: { preferences.microphone },
            set: { microphone in
                preferences = preferences.settingMicrophone(microphone)
                preferences.save(for: deviceID)
            }
        )
    }
}

struct AudioPreferenceTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: resolveSymbol(systemImage, fallback: "circle.fill"))
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignTokens.Palette.card.opacity(0.72))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(DesignTokens.Typography.captionEmphasis)
                    .foregroundStyle(DesignTokens.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(title)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DesignTokens.Palette.card.opacity(0.72))
        )
    }
}

struct DeviceCurrentStatsCard: View {
    let item: DeviceListItem
    let historySamples: [BatteryHistorySample]

    private var historySummary: BatteryHistorySummary? {
        BatteryHistoryStore.summary(for: historySamples)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Current Stats", systemImage: "chart.bar.xaxis")
                    .font(DesignTokens.Typography.captionEmphasis)
                Spacer()
                Text(connectionText)
                    .font(DesignTokens.Typography.caption2Emphasis)
                    .foregroundStyle(connectionColor)
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
                    title: "Source",
                    value: sourceText,
                    systemImage: BeaconSymbols.bluetooth,
                    color: DesignTokens.Palette.accent
                )

                Divider().padding(.leading, 40)

                SettingsInfoRow(
                    title: "Updated",
                    value: updatedText,
                    systemImage: "clock",
                    color: updatedColor
                )
            }
            .background(settingsGroupBackground)

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

                BatteryHistorySparkline(samples: historySummary?.samples ?? [])
                    .frame(height: 34)

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

    private var batteryText: String {
        switch item {
        case .device(let decorated):
            return decorated.snapshot.percent.map { "\($0)%" }
                ?? BeaconL10n.string("No report")
        case .airPods(_, _, let components):
            let percents = components.compactMap(\.percent)
            guard let lowest = percents.min() else {
                return BeaconL10n.string("No report")
            }
            return BeaconL10n.format("%d%% low", lowest)
        }
    }

    private var batteryIcon: String {
        switch item {
        case .device(let decorated):
            if decorated.snapshot.chargeState == .charging { return "battery.100.bolt" }
            return "battery.100"
        case .airPods:
            return "battery.100"
        }
    }

    private var batteryColor: Color {
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

    private var reportText: String {
        BeaconL10n.string(reportKey)
    }

    private var reportKey: String {
        switch item {
        case .device(let decorated):
            guard decorated.snapshot.percent != nil else { return "No report" }
            switch decorated.freshness {
            case .fresh: return "Reporting"
            case .stale: return "Stale"
            case .expired: return "Expired"
            }
        case .airPods(_, _, let components):
            guard components.contains(where: { $0.percent != nil }) else { return "No report" }
            if components.contains(where: { $0.freshness == .expired }) { return "Expired" }
            if components.contains(where: { $0.freshness == .stale }) { return "Stale" }
            return "Reporting"
        }
    }

    private var reportIcon: String {
        switch reportKey {
        case "Reporting": return "checkmark.circle.fill"
        case "No report": return "minus.circle"
        case "Stale", "Expired": return "clock.badge.exclamationmark"
        default: return "clock"
        }
    }

    private var reportColor: Color {
        switch reportKey {
        case "Reporting": return DesignTokens.Palette.charging
        case "Stale", "Expired": return DesignTokens.Palette.stale
        default: return DesignTokens.Palette.secondaryText
        }
    }

    private var connectionText: String {
        BeaconL10n.string(item.connectionState == .disconnected ? "Disconnected" : "Connected")
    }

    private var connectionColor: Color {
        item.connectionState == .disconnected ? DesignTokens.Palette.stale : DesignTokens.Palette.charging
    }

    private var connectionIcon: String {
        item.connectionState == .disconnected ? "xmark.circle" : "link.circle.fill"
    }

    private var updatedText: String {
        switch item {
        case .device(let decorated):
            let interval = abs(decorated.snapshot.updatedAt.timeIntervalSinceNow)
            if interval < 60 { return BeaconL10n.string("Now") }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: decorated.snapshot.updatedAt, relativeTo: Date())
        case .airPods:
            return BeaconL10n.string("Grouped")
        }
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

struct BatteryHistorySparkline: View {
    let samples: [BatteryHistorySample]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.Palette.card.opacity(0.58))

                if samples.count >= 2 {
                    sparkPath(in: proxy.size)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Palette.accent,
                                    trendColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                        )
                        .padding(7)
                } else {
                    HStack(spacing: 5) {
                        ForEach(0..<8, id: \.self) { _ in
                            Capsule(style: .continuous)
                                .fill(DesignTokens.Palette.separator.opacity(0.55))
                                .frame(width: 16, height: 4)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private var sortedSamples: [BatteryHistorySample] {
        samples.sorted { $0.recordedAt < $1.recordedAt }
    }

    private var trendColor: Color {
        guard let first = sortedSamples.first, let last = sortedSamples.last else {
            return DesignTokens.Palette.secondaryText
        }
        if last.percent > first.percent { return DesignTokens.Palette.charging }
        if last.percent < first.percent { return DesignTokens.Palette.warning }
        return DesignTokens.Palette.accent
    }

    private func sparkPath(in size: CGSize) -> Path {
        let points = sortedSamples
        guard points.count >= 2 else { return Path() }
        let width = max(size.width - 14, 1)
        let height = max(size.height - 14, 1)
        let minPercent = Double(points.map(\.percent).min() ?? 0)
        let maxPercent = Double(points.map(\.percent).max() ?? 100)
        let denominator = max(maxPercent - minPercent, 1)

        var path = Path()
        for (index, sample) in points.enumerated() {
            let x = CGFloat(index) / CGFloat(points.count - 1) * width
            let normalized = (Double(sample.percent) - minPercent) / denominator
            let y = height - CGFloat(normalized) * height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
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

            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Palette.text)

            Spacer(minLength: 12)

            Text(value)
                .font(DesignTokens.Typography.captionEmphasis)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
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

struct SettingsDetailToggle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? DesignTokens.Palette.accent : DesignTokens.Palette.secondaryText)
                .frame(width: 28, height: 28)
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
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
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
