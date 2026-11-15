import Carbon
import SwiftUI

struct QuickActionsSettingsPane: View {
    @Binding var preferences: BeaconQuickActionPreferences
    @ObservedObject private var status = BeaconShortcutStatus.shared

    var body: some View {
        Form {
            Section {
                ForEach(quickActionSettingsSummary(for: preferences).supportedActions) { action in
                    actionSetting(for: action)
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Click a shortcut to record a new one. Press Delete to clear it or Esc to cancel. Enabled shortcuts work in any app while Beacon is running.")
            }

            Section {
                LabeledContent {
                    Button("Open Shortcuts") {
                        if let url = URL(string: "shortcuts://") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    Text("Shortcuts App")
                    Text("Battery summary, lowest battery, low-battery list, trends, connect and disconnect are available as Shortcuts actions.")
                }
            } header: {
                Text("Automation")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func actionSetting(for action: BeaconQuickAction) -> some View {
        let isEnabled = preferences.isEnabled(action)
        return VStack(alignment: .leading, spacing: 6) {
            // Same layout as System Settings > Keyboard > Keyboard Shortcuts: a labelled
            // checkbox for the action, the shortcut on the trailing edge.
            HStack(alignment: .center, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { preferences.isEnabled(action) },
                    set: { setQuickActionEnabled($0, for: action) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(action.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
                // VoiceOver reads the action name; the subtitle is the hint.
                .accessibilityLabel(Text(action.title))
                .accessibilityHint(Text(action.subtitle))
                .accessibilityIdentifier("quickActions.\(action.id)")
                Spacer(minLength: 8)
                ShortcutRecorderField(
                    shortcut: preferences.shortcut(for: action),
                    actionTitle: action.title,
                    onChange: { setShortcut($0, for: action) },
                    conflictingAction: { preferences.action(using: $0, excluding: action) }
                )
                .disabled(!isEnabled)
                .accessibilityIdentifier("quickActions.\(action.id).shortcut")
            }
            if isEnabled, status.registrationFailures.contains(action) {
                Label(
                    "macOS did not accept this shortcut. Another app or a system shortcut may already use it; record a different one.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quickActions.\(action.id).conflict")
            }
        }
        .padding(.vertical, 2)
    }

    private func setQuickActionEnabled(_ isEnabled: Bool, for action: BeaconQuickAction) {
        let nextPreferences = preferences.setting(isEnabled, for: action)
        preferences = nextPreferences
        nextPreferences.save()
    }

    private func setShortcut(_ shortcut: BeaconQuickActionShortcut?, for action: BeaconQuickAction) {
        let nextPreferences = preferences.settingShortcut(shortcut, for: action)
        preferences = nextPreferences
        nextPreferences.save()
    }
}

/// A click-to-record shortcut field modelled on System Settings > Keyboard Shortcuts.
struct ShortcutRecorderField: View {
    let shortcut: BeaconQuickActionShortcut?
    let actionTitle: String
    let onChange: (BeaconQuickActionShortcut?) -> Void
    let conflictingAction: (BeaconQuickActionShortcut) -> BeaconQuickAction?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(label)
                    .monospacedDigit()
                    .frame(minWidth: 84)
                    .foregroundStyle(isRecording || shortcut == nil ? .secondary : .primary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Text(BeaconL10n.format("Shortcut for %@", actionTitle)))
            .accessibilityValue(Text(isRecording ? BeaconL10n.string("Recording") : (shortcut?.displayText ?? BeaconL10n.string("None"))))
            .help(BeaconL10n.string("Click to record a shortcut"))
            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return BeaconL10n.string("Type Shortcut") }
        return shortcut?.displayText ?? BeaconL10n.string("Record Shortcut")
    }

    private func startRecording() {
        message = nil
        isRecording = true
        NotificationCenter.default.post(name: .beaconShortcutRecordingDidChange, object: nil, userInfo: ["isRecording": true])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording || monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        NotificationCenter.default.post(name: .beaconShortcutRecordingDidChange, object: nil, userInfo: ["isRecording": false])
    }

    private func handle(_ event: NSEvent) {
        let plainFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if plainFlags.isEmpty, Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return
        }
        if plainFlags.isEmpty, [kVK_Delete, kVK_ForwardDelete].contains(Int(event.keyCode)) {
            onChange(nil)
            stopRecording()
            return
        }
        guard let recorded = BeaconQuickActionShortcut(event: event) else { return }
        guard recorded.isValidGlobalShortcut else {
            message = BeaconL10n.string("Include ⌘, ⌥ or ⌃.")
            NSSound.beep()
            return
        }
        if let other = conflictingAction(recorded) {
            message = BeaconL10n.format("Already used by %@.", other.title)
            NSSound.beep()
            return
        }
        onChange(recorded)
        stopRecording()
    }
}

struct QuickActionSettingsSummary: Equatable {
    let supportedActions: [BeaconQuickAction]
    let enabledSupportedActions: [BeaconQuickAction]
    let disabledSupportedActions: [BeaconQuickAction]
    let unsupportedActions: [BeaconQuickAction]
    let defaultEnabledActionCount: Int

    var supportedActionCount: Int { supportedActions.count }
}

func quickActionSettingsSummary(
    for preferences: BeaconQuickActionPreferences
) -> QuickActionSettingsSummary {
    let supportedActions = BeaconQuickAction.allCases.filter(\.isSupported)
    let enabledSupportedActions = supportedActions.filter { preferences.isEnabled($0) }
    let disabledSupportedActions = supportedActions.filter { !preferences.isEnabled($0) }
    let unsupportedActions = BeaconQuickAction.allCases.filter { !$0.isSupported }
    let defaultEnabledActionCount = supportedActions.filter(\.isEnabledByDefault).count

    return QuickActionSettingsSummary(
        supportedActions: supportedActions,
        enabledSupportedActions: enabledSupportedActions,
        disabledSupportedActions: disabledSupportedActions,
        unsupportedActions: unsupportedActions,
        defaultEnabledActionCount: defaultEnabledActionCount
    )
}
