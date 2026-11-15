import AppIntents
import SwiftUI
import WidgetKit

@available(macOS 26.0, *)
struct RefreshBeaconFromControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Batteries"
    static let description = IntentDescription("Ask Beacon to read battery levels now.")

    func perform() async throws -> some IntentResult {
        BeaconControlSignal.post(BeaconControlSignal.refreshNotification)
        return .result()
    }
}

@available(macOS 26.0, *)
struct SetBeaconAudioLockFromControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Audio Input Lock"

    @Parameter(title: "Locked")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let defaults = BeaconControlSignal.sharedDefaults
        defaults?.set(value, forKey: BeaconControlSignal.audioLockRequestKey)
        // Optimistic state for the control; Beacon confirms or corrects it.
        defaults?.set(value, forKey: BeaconControlSignal.audioLockStateKey)
        BeaconControlSignal.post(BeaconControlSignal.audioLockNotification)
        return .result()
    }
}

@available(macOS 26.0, *)
struct BeaconRefreshControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: BeaconControlSignal.refreshControlKind) {
            ControlWidgetButton(action: RefreshBeaconFromControlIntent()) {
                Label("Refresh Batteries", systemImage: "arrow.clockwise")
            }
        }
        .displayName("Refresh Batteries")
        .description("Read battery levels with Beacon.")
    }
}

@available(macOS 26.0, *)
struct BeaconAudioLockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: BeaconControlSignal.audioLockControlKind, provider: AudioLockValueProvider()) { isLocked in
            ControlWidgetToggle(
                "Audio Input Lock",
                isOn: isLocked,
                action: SetBeaconAudioLockFromControlIntent()
            ) { isOn in
                Label(isOn ? "Locked" : "Unlocked", systemImage: isOn ? "mic.badge.lock" : "mic")
            }
        }
        .displayName("Audio Input Lock")
        .description("Keep your preferred microphone selected.")
    }
}

@available(macOS 26.0, *)
struct AudioLockValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        BeaconControlSignal.sharedDefaults?.bool(forKey: BeaconControlSignal.audioLockStateKey) ?? false
    }
}
