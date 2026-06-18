import AppKit
import SwiftUI

// MARK: - NSVisualEffectView wrapper (real vibrancy)

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - StatusMenuView

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
                        ForEach(sections.indices, id: \.self) { index in
                            DeviceSectionCard(section: sections[index])
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
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel))
        }
    }

    // MARK: - Computed sections

    private var sections: [DeviceSection] {
        groupedDeviceItems(snapshots)
    }

    // MARK: - Header

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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("No connected devices")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Connect Bluetooth devices to see their battery levels here.")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Footer

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

    // MARK: - Settings panel

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

    // MARK: - Helpers

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

    private var cardBackground: some ShapeStyle {
        DesignTokens.Palette.card
            .shadow(.inner(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1))
    }
}

// MARK: - DeviceSectionCard

private struct DeviceSectionCard: View {
    let section: DeviceSection

    var body: some View {
        VStack(spacing: 0) {
            ForEach(section.items.indices, id: \.self) { index in
                itemView(for: section.items[index])

                if index < section.items.count - 1 {
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

    @ViewBuilder
    private func itemView(for item: DeviceListItem) -> some View {
        switch item {
        case .device(let decorated):
            DeviceBatteryRow(decorated: decorated)
        case .airPods(let name, let id, let components):
            AirPodsBatteryRow(name: name, id: id, components: components)
        }
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

private let previewSnapshots: [DecoratedBatterySnapshot] = [
    // Mac section
    mockDecorated(id: "mac1", name: "Mac mini",         kind: .macBook,   percent: nil),
    mockDecorated(id: "kbd1", name: "Magic Keyboard",   kind: .keyboard,  percent: 95),
    mockDecorated(id: "mse1", name: "Magic Mouse",      kind: .mouse,     percent: 62),
    // Mobile + audio section
    mockDecorated(id: "iph1", name: "Isaac's iPhone",   kind: .iPhone,    percent: 42, chargeState: .charging),
    mockDecorated(id: "wtc1", name: "Apple Watch",      kind: .appleWatch, percent: 18),
    // AirPods 3-component
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-case",  name: "John's AirPods Pro Case",  kind: .airPods, percent: 90),
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-left",  name: "John's AirPods Pro Left",  kind: .airPods, percent: 75),
    mockDecorated(id: "AA-BB-CC-DD-EE-FF-right", name: "John's AirPods Pro Right", kind: .airPods, percent: 80),
]

private let previewSnapshotsEdge: [DecoratedBatterySnapshot] = [
    // Critical battery
    mockDecorated(id: "iph2", name: "Low iPhone",       kind: .iPhone,    percent: 8),
    // Stale data
    mockDecorated(id: "bt1",  name: "BT Speaker",       kind: .bluetoothPeripheral, percent: 30, freshness: .stale),
    // AirPods with nil case + low buds
    mockDecorated(id: "11-22-33-44-55-66-case",  name: "AirPods Case",  kind: .airPods, percent: nil),
    mockDecorated(id: "11-22-33-44-55-66-left",  name: "AirPods Left",  kind: .airPods, percent: 12),
    mockDecorated(id: "11-22-33-44-55-66-right", name: "AirPods Right", kind: .airPods, percent: 15, freshness: .stale),
]

#Preview("StatusMenuView — full (light)") {
    StatusMenuView(snapshots: previewSnapshots, onRefresh: {})
}

#Preview("StatusMenuView — full (dark)") {
    StatusMenuView(snapshots: previewSnapshots, onRefresh: {})
        .preferredColorScheme(.dark)
}

#Preview("StatusMenuView — edge cases (light)") {
    StatusMenuView(snapshots: previewSnapshotsEdge, onRefresh: {})
}

#Preview("StatusMenuView — edge cases (dark)") {
    StatusMenuView(snapshots: previewSnapshotsEdge, onRefresh: {})
        .preferredColorScheme(.dark)
}

#Preview("StatusMenuView — empty") {
    StatusMenuView(snapshots: [], onRefresh: {})
}
#endif
