import SwiftUI

struct StatusMenuView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let onRefresh: () -> Void

    @AppStorage(LowBatteryNotifier.thresholdDefaultsKey) private var lowBatteryThreshold = LowBatteryNotifier.defaultThreshold
    @AppStorage(LowBatteryNotifier.notificationsEnabledDefaultsKey) private var lowBatteryAlertsEnabled = true
    @State private var isShowingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            header

            if isShowingSettings {
                settingsPanel
            } else if snapshots.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        ForEach(deviceGroups.indices, id: \.self) { index in
                            DeviceGroupCard(snapshots: deviceGroups[index])
                        }
                    }
                }
                .frame(maxHeight: 520)
            }

            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: 378)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                .fill(DesignTokens.Palette.panelTint)
                .overlay(.regularMaterial.opacity(0.72))
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Your Devices")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Palette.accent)

            Spacer()

            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("Refresh")

                Button {
                    withAnimation(.easeInOut(duration: DesignTokens.Motion.quick)) {
                        isShowingSettings.toggle()
                    }
                } label: {
                    Image(systemName: isShowingSettings ? "xmark.circle" : "gearshape")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .help(isShowingSettings ? "Close Settings" : "Settings")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("No connected devices")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Only external devices with a battery percentage are shown.")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var footer: some View {
        HStack {
            Label(footerAlertText, systemImage: lowBatteryAlertsEnabled ? "bell.badge" : "bell.slash")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
            Spacer()
            Text("Best-effort sync")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Toggle("Low battery alerts", isOn: $lowBatteryAlertsEnabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Text("Alert threshold")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(clampedLowBatteryThreshold)%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.accent)
                }

                Slider(value: thresholdSliderValue, in: 5...50, step: 5)
                    .disabled(!lowBatteryAlertsEnabled)
            }
            .opacity(lowBatteryAlertsEnabled ? 1 : 0.45)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var clampedLowBatteryThreshold: Int {
        Swift.max(5, Swift.min(50, lowBatteryThreshold))
    }

    private var thresholdSliderValue: Binding<Double> {
        Binding(
            get: { Double(clampedLowBatteryThreshold) },
            set: { lowBatteryThreshold = Int($0.rounded()) }
        )
    }

    private var footerAlertText: String {
        lowBatteryAlertsEnabled ? "Alerts below \(clampedLowBatteryThreshold)%" : "Alerts off"
    }

    private var deviceGroups: [[DecoratedBatterySnapshot]] {
        snapshots.chunked(into: 3)
    }

    private var cardBackground: some ShapeStyle {
        DesignTokens.Palette.card
            .shadow(.inner(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1))
    }
}

private struct DeviceGroupCard: View {
    let snapshots: [DecoratedBatterySnapshot]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, decorated in
                DeviceBatteryRow(decorated: decorated)

                if index < snapshots.count - 1 {
                    Divider()
                        .overlay(DesignTokens.Palette.separator)
                        .padding(.leading, 58)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Palette.card)
                .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 5)
                .shadow(color: .white.opacity(0.42), radius: 0.5, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
