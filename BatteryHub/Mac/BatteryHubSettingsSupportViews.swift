import SwiftUI

struct AddDeviceGuideView: View {
    let onOpenBluetoothSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add New Device")
                        .font(DesignTokens.Typography.windowTitle)
                    Text("Choose the kind of device you want BatteryHub to monitor.")
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
                    title: "AirPods or Beats Device",
                    subtitle: "Pair in Bluetooth Settings, then refresh.",
                    systemImage: resolveSymbol("airpodspro", fallback: "headphones"),
                    actionTitle: "Bluetooth",
                    action: onOpenBluetoothSettings
                )

                AddDeviceGuideRow(
                    title: "Another Mac",
                    subtitle: "Cross-Mac transfer stays disabled.",
                    systemImage: resolveSymbol("macbook.and.iphone", fallback: "desktopcomputer"),
                    actionTitle: "Unavailable",
                    isEnabled: false
                )
            }

            HStack(spacing: 10) {
                Label("Devices appear automatically after BatteryHub receives a fresh battery report.", systemImage: "arrow.clockwise")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.secondaryText)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
                .fill(DesignTokens.Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.8)
                )
        )
    }
}

struct AddDeviceGuideRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String
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
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(DesignTokens.Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                            .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                    )
            )
            .opacity(isEnabled ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct SettingsPaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        if pane == .devices {
            BluetoothLogoMark(size: 20)
        } else if pane == .dashboard {
            BatteryHubLogoMark(size: 20)
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
    case devices
    case alerts
    case actionHUD
    case quickActions
    case dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return "Devices"
        case .alerts: return "Alerts"
        case .actionHUD: return "Action HUD"
        case .quickActions: return "Quick Actions"
        case .dashboard: return "Dashboard"
        }
    }

    var systemImage: String {
        switch self {
        case .devices: return BatteryHubSymbols.bluetooth
        case .alerts: return "bell.badge"
        case .actionHUD: return "sparkles"
        case .quickActions: return "keyboard"
        case .dashboard: return BatteryHubSymbols.app
        }
    }
}

struct QuickActionSettingsRow: View {
    let action: BatteryHubQuickAction
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: BatteryHubSymbols.resolved(action.systemImage))
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
                            .font(DesignTokens.Typography.caption2Emphasis)
                            .foregroundStyle(DesignTokens.Palette.charging)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DesignTokens.Palette.controlPill)
                            )
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
        ("Connect", BatteryHubSymbols.bluetooth),
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
                            .font(DesignTokens.Typography.caption2Emphasis)
                            .lineLimit(1)
                            .foregroundStyle(DesignTokens.Palette.text.opacity(0.82))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.62))
                            )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct ActionHUDEventToggle: View {
    let title: String
    let subtitle: String
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
                Text("AirPods")
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

            Picker("Listening Mode", selection: listeningModeBinding) {
                ForEach(AirPodsListeningModePreference.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Microphone", selection: microphoneBinding) {
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
                    Label("Bluetooth", systemImage: BatteryHubSymbols.bluetooth)
                }

                Spacer()
            }
            .font(DesignTokens.Typography.captionEmphasis)

            Text("BatteryHub keeps your preferred AirPods audio choices here; macOS applies the actual listening mode and mic switch from Sound Settings.")
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Palette.controlPill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.Palette.glassStroke, lineWidth: 0.7)
                )
        )
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
    let title: String
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
                    systemImage: BatteryHubSymbols.bluetooth,
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
    }

    private var settingsGroupBackground: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
            )
    }

    private var batteryText: String {
        switch item {
        case .device(let decorated):
            return decorated.snapshot.percent.map { "\($0)%" } ?? "No report"
        case .airPods(_, _, let components):
            let percents = components.compactMap(\.percent)
            guard let lowest = percents.min() else { return "No report" }
            return "\(lowest)% low"
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
            return sourceLabel(for: decorated.snapshot.source)
        case .airPods:
            return "Bluetooth"
        }
    }

    private var reportText: String {
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
        switch reportText {
        case "Reporting": return "checkmark.circle.fill"
        case "No report": return "minus.circle"
        case "Stale", "Expired": return "clock.badge.exclamationmark"
        default: return "clock"
        }
    }

    private var reportColor: Color {
        switch reportText {
        case "Reporting": return DesignTokens.Palette.charging
        case "Stale", "Expired": return DesignTokens.Palette.stale
        default: return DesignTokens.Palette.secondaryText
        }
    }

    private var connectionText: String {
        item.connectionState == .disconnected ? "Disconnected" : "Connected"
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
            if interval < 60 { return "Now" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: decorated.snapshot.updatedAt, relativeTo: Date())
        case .airPods:
            return "Grouped"
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
        guard let historySummary else { return "Collecting" }
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
            return "BatteryHub will build a trend as reports arrive."
        }
        return "Range \(historySummary.minimumPercent)% - \(historySummary.maximumPercent)% across \(historySummary.samples.count) reports."
    }

    private func sourceLabel(for source: BatterySource) -> String {
        switch source {
        case .macPowerSource: return "Local Mac"
        case .ioRegistry: return "IORegistry"
        case .coreBluetooth, .ioBluetooth: return "Bluetooth"
        case .systemProfiler: return "System"
        case .bluetoothUnsupported: return "Bluetooth"
        }
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
    let title: String
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
    @AppStorage(BatteryHubAppearanceTheme.defaultsKey) private var appearanceThemeRawValue = BatteryHubAppearanceTheme.system.rawValue
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
    }

    private var theme: BeaconThemePalette {
        BatteryHubAppearanceTheme.resolved(rawValue: appearanceThemeRawValue)
            .palette(resolvedSystemScheme: colorScheme)
    }

    private var rowSubtitle: String {
        if item.isUserHidden { return "Hidden · \(alertSummary)" }
        if item.isUnavailable { return "Hidden until connected · \(alertSummary)" }
        if item.isPinned { return "Pinned · \(alertSummary)" }
        return "Visible · \(alertSummary)"
    }
}

struct SettingsDetailToggle: View {
    let title: String
    let subtitle: String
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
    let title: String
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
