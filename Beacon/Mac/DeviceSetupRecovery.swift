import AppKit
import SwiftUI

/// Recovery is based on completed provider outcomes, never on an invented battery value.
enum DeviceSetupRecoveryState: String, Equatable {
    case ready, checking, empty, permission, failed

    static func resolve(visibleCount: Int, isRefreshing: Bool, diagnostics: BatteryRefreshDiagnostics) -> Self {
        let bluetooth = diagnostics.attempts.filter {
            [.coreBluetoothBatteryService, .ioBluetooth, .systemProfiler, .bluetoothUnsupported].contains($0.provider)
        }
        if bluetooth.contains(where: { $0.status == .unauthorized }) { return .permission }
        guard visibleCount == 0 else { return .ready }
        if isRefreshing || diagnostics.attempts.isEmpty { return .checking }
        if diagnostics.attempts.contains(where: {
            $0.provider != .ideviceInfo && [.unavailable, .timedOut, .commandMissing].contains($0.status)
        }) { return .failed }
        return .empty
    }

    var title: String {
        switch self {
        case .ready: return ""
        case .checking: return BeaconL10n.string("Checking for devices")
        case .empty: return BeaconL10n.string("No visible devices yet")
        case .permission: return BeaconL10n.string("Bluetooth access needs attention")
        case .failed: return BeaconL10n.string("Device check could not finish")
        }
    }

    var explanation: String {
        switch self {
        case .ready: return ""
        case .checking: return BeaconL10n.string("Beacon is checking local device reports. You can open the setup guide while it checks.")
        case .empty: return BeaconL10n.string("Set up a device, or open Devices in Settings to restore a hidden device. Then check again.")
        case .permission: return BeaconL10n.string("Beacon uses Bluetooth access to read accessory status. In System Settings, open Privacy & Security > Bluetooth and allow Beacon, then check again. A managed Mac may require administrator help.")
        case .failed: return BeaconL10n.string("A local device source did not respond. This does not mean there are no devices. Keep your devices awake and check again.")
        }
    }
}

struct DeviceSetupRecoveryCard: View {
    let state: DeviceSetupRecoveryState
    let isRefreshing: Bool
    let onSetUp: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        if state != .ready {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    if state == .checking || isRefreshing {
                        ProgressView().controlSize(.small).accessibilityLabel("Checking for devices")
                    } else {
                        Image(systemName: state == .empty ? "plus.circle" : "exclamationmark.triangle")
                            .accessibilityHidden(true)
                    }
                    Text(state.title).font(.headline)
                        .accessibilityIdentifier("setup.state.\(state.rawValue)")
                }
                Text(state.explanation).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { actions }
                    VStack(alignment: .leading, spacing: 8) { actions }
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .beaconSettingsCardSurface()
        }
    }

    @ViewBuilder private var actions: some View {
        Button("Set Up a Device", action: onSetUp).accessibilityIdentifier("setup.open-guide")
        if state == .permission {
            Button("Privacy & Security", action: DeviceSetupSystemActions.openPrivacySettings)
                .accessibilityIdentifier("setup.open-privacy")
        }
        Button("Check Again", action: onRefresh)
            .disabled(isRefreshing)
            .accessibilityIdentifier("setup.retry")
    }
}

/// Uses the existing setup rows, plus an explicit permission/recheck path.
struct DeviceSetupGuide: View {
    let enrollmentResult: IPhoneLockdownDiscoveryReport?
    let onOpenBluetoothSettings: () -> Void
    let onTrustConnectedIPhone: () -> Void
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddDeviceGuideView(
                trustedIPhoneEnrollmentResult: enrollmentResult,
                onOpenBluetoothSettings: onOpenBluetoothSettings,
                onTrustConnectedIPhone: onTrustConnectedIPhone,
                onDismiss: onDismiss
            )
            VStack(alignment: .leading, spacing: 10) {
                Text("Bluetooth access lets Beacon read accessory status. If access was denied, allow Beacon in System Settings > Privacy & Security > Bluetooth, then check again.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Privacy & Security", action: DeviceSetupSystemActions.openPrivacySettings)
                    Button("Check Again") { onRefresh(); onDismiss() }
                        .accessibilityIdentifier("setup.guide.retry")
                    Spacer()
                    Button("Done", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("setup.guide.done")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .frame(width: 520)
        .onExitCommand(perform: onDismiss)
    }
}

enum DeviceSetupSystemActions {
    @MainActor static func openPrivacySettings() {
        // The text path remains available if a macOS version does not honor the deep link.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

enum BeaconSetupIntroduction {
    static let presentedKey = "Beacon.setup.introductionPresented"

    static func shouldPresent(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: presentedKey) == nil else { return false }
        // An upgrade must not reset or reinterpret existing device or alert preferences.
        return !defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("Beacon.") || $0.hasPrefix("BatteryHub.")
        }
    }
}
