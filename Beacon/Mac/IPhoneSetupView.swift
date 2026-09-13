import AppKit
import SwiftUI

struct IPhoneToolAvailability: Equatable, Sendable {
    let missingCommands: [String]
    var isAvailable: Bool { missingCommands.isEmpty }

    static func inspect(locator: IPhoneLockdownCommandLocator = .init()) -> Self {
        Self(missingCommands: locator.missingCommandNames)
    }
}

enum IPhoneSetupStage: String, Equatable {
    case toolsMissing, ready, notConnected, trustRequired, checking, unavailable, timedOut, noBattery, reported

    static func resolve(tools: IPhoneToolAvailability, isChecking: Bool, enrollment: IPhoneLockdownDiscoveryReport?, hasCurrentReading: Bool, readStatus: BatteryReadStatus? = nil) -> Self {
        guard tools.isAvailable else { return .toolsMissing }
        if isChecking { return .checking }
        guard let enrollment else { return .ready }
        switch enrollment.status {
        case .commandMissing: return .toolsMissing
        case .unauthorized: return .trustRequired
        case .timedOut: return .timedOut
        case .unavailable: return .unavailable
        case .noReport: return .notConnected
        case .reported:
            if hasCurrentReading { return .reported }
            if readStatus == .unauthorized { return .trustRequired }
            if readStatus == .timedOut { return .timedOut }
            if readStatus == .unavailable { return .unavailable }
            return .noBattery
        }
    }

    var title: String {
        let key: String
        switch self {
        case .toolsMissing: key = "Install the iPhone tools first"
        case .ready: key = "Ready to check your iPhone"
        case .notConnected: key = "No reachable iPhone detected"
        case .trustRequired: key = "Unlock your iPhone and review trust"
        case .checking: key = "Checking iPhone access and battery"
        case .unavailable: key = "iPhone access could not be verified"
        case .timedOut: key = "The iPhone check timed out"
        case .noBattery: key = "Added, but no new battery report"
        case .reported: key = "New iPhone battery report received"
        }
        return BeaconL10n.string(key)
    }
}

struct IPhoneSetupView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let trustedIPhones: [TrustedIPhone]
    let enrollmentResult: IPhoneLockdownDiscoveryReport?
    let diagnostics: BatteryRefreshDiagnostics
    let previewTools: IPhoneToolAvailability?
    let isPreviewingData: Bool
    let onCheck: () async -> Void
    let onForget: (String) -> Void
    let onBack: () -> Void
    let onDismiss: () -> Void

    @State private var tools = IPhoneToolAvailability(missingCommands: ["idevice_id", "ideviceinfo"])
    @State private var isChecking = false
    @State private var phoneToRemove: TrustedIPhone?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("iPhone and iPad Setup").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Done", action: onDismiss).keyboardShortcut(.cancelAction).accessibilityIdentifier("iphone.setup.done")
            }
            if isPreviewingData { Text("Sample devices, not live Bluetooth.").font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(stage.title).font(.headline).accessibilityIdentifier("iphone.setup.state.\(stage.rawValue)")
                    if isChecking { ProgressView().controlSize(.small).accessibilityLabel("Checking iPhone access and battery") }
                    toolSection
                    if tools.isAvailable {
                        Text("Connect by USB, unlock the iPhone or iPad, and review Trust This Computer on the device. Previously trusted Wi-Fi devices may also be reachable. Beacon does not change your Wi-Fi sync settings.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("A device being added is not proof that a battery value was read. Only new reports from this check appear below.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Check Access and Read Battery") {
                            tools = previewTools ?? .inspect()
                            guard tools.isAvailable, !isChecking else { return }
                            isChecking = true
                            Task { await onCheck(); isChecking = false }
                        }
                        .disabled(isChecking)
                        .accessibilityIdentifier("iphone.setup.check")
                    }
                    if enrollmentResult != nil {
                        if stage == .trustRequired {
                            Text("Beacon could not access the iPhone. Unlock it, review the trust prompt, and check again. Do not reset existing pairing records.")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        } else if [.unavailable, .timedOut].contains(stage) {
                            Text("Keep the iPhone awake and reachable, then retry. The result does not establish whether trust or the connection caused the failure.")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !trustedIPhones.isEmpty {
                        Divider()
                        Text("Devices Added to Beacon").font(.headline)
                        ForEach(trustedIPhones) { phone in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(phone.displayName).fontWeight(.medium)
                                    Spacer()
                                    Button("Remove from Beacon", role: .destructive) { phoneToRemove = phone }
                                        .controlSize(.small)
                                }
                                if let reading = currentReading(for: phone), let percent = reading.snapshot.percent {
                                    Text(BeaconL10n.format("New battery reading: %d%%", percent))
                                        .accessibilityIdentifier("iphone.setup.reading")
                                    Text(reading.snapshot.updatedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("No new battery reading from this check.").font(.caption).foregroundStyle(.secondary)
                                }
                                DisclosureGroup("Device identifier") {
                                    Text(phone.udid).font(.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                            .padding(10).beaconSettingsCardSurface()
                        }
                    }
                    DisclosureGroup("Technical Details") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("idevice_id / ideviceinfo").font(.caption.monospaced())
                            Text(IPhoneLockdownCommandLocator.defaultSearchPaths.joined(separator: "\n"))
                                .font(.caption.monospaced()).textSelection(.enabled)
                            if let enrollmentResult { Text(enrollmentResult.message).font(.caption).textSelection(.enabled) }
                            ForEach(Array(diagnostics.attempts.filter { $0.provider == .ideviceInfo }.enumerated()), id: \.offset) { _, attempt in
                                Text(attempt.message).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(1)
            }
            HStack {
                Button("Back to Device Setup", action: onBack)
                Spacer()
                Button("Recheck Tools") { tools = previewTools ?? .inspect() }
                    .disabled(isChecking).accessibilityIdentifier("iphone.setup.recheck-tools")
            }
        }
        .padding(24).frame(width: 560, height: 560)
        .task { tools = previewTools ?? .inspect() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tools = previewTools ?? .inspect()
        }
        .onExitCommand(perform: onDismiss)
        .confirmationDialog("Remove this device from Beacon?", isPresented: Binding(
            get: { phoneToRemove != nil }, set: { if !$0 { phoneToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remove from Beacon", role: .destructive) {
                if let phoneToRemove { onForget(phoneToRemove.udid) }
                phoneToRemove = nil
            }
            Button("Cancel", role: .cancel) { phoneToRemove = nil }
        } message: {
            Text("This only removes Beacon's enrollment. macOS pairing and trust are not changed.")
        }
    }

    private var stage: IPhoneSetupStage {
        .resolve(tools: tools, isChecking: isChecking, enrollment: enrollmentResult,
                 hasCurrentReading: trustedIPhones.contains { currentReading(for: $0) != nil },
                 readStatus: diagnostics.attempts.last {
                     $0.provider == .ideviceInfo && $0.attemptedAt >= (enrollmentResult?.attempts.first?.attemptedAt ?? .distantFuture)
                 }?.status)
    }

    private var toolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iPhone battery reads require the external libimobiledevice tools. Mac and Bluetooth accessory features do not require them.")
                .font(.caption).foregroundStyle(.secondary)
            if !tools.isAvailable {
                Text(BeaconL10n.format("Missing tools: %@", tools.missingCommands.joined(separator: ", ")))
                    .font(.callout).accessibilityIdentifier("iphone.setup.missing-tools")
                Text("Install Homebrew using its official guide, then run this command in Terminal. Beacon does not install software automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("brew install libimobiledevice").font(.callout.monospaced()).textSelection(.enabled)
                HStack {
                    Link("Homebrew Guide", destination: URL(string: "https://brew.sh/")!)
                    Link("iPhone Tools Guide", destination: URL(string: "https://formulae.brew.sh/formula/libimobiledevice")!)
                }
                .font(.callout)
            }
        }
        .padding(12).beaconSettingsCardSurface()
    }

    private func currentReading(for phone: TrustedIPhone) -> DecoratedBatterySnapshot? {
        guard let enrollmentResult, enrollmentResult.devices.contains(where: { $0.udid == phone.udid }),
              let since = enrollmentResult.attempts.first?.attemptedAt else { return nil }
        return snapshots.first {
            $0.id == "trusted-iphone-\(phone.udid)" && $0.snapshot.percent != nil
                && $0.snapshot.readStatus == .reported && $0.snapshot.connectionState == .connected
                && $0.freshness == .fresh && $0.snapshot.updatedAt >= since
        }
    }
}
