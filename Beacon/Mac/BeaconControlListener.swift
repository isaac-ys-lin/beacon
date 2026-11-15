import Foundation
import WidgetKit

/// Receives requests from Beacon's Control Center controls (macOS 26+), which run
/// in the sandboxed widget extension and cannot read devices themselves.
@MainActor
enum BeaconControlListener {
    private static var onRefresh: (@MainActor () -> Void)?
    private static var onAudioLock: (@MainActor (Bool) -> Void)?
    private static var isStarted = false

    static func start(
        onRefresh: @escaping @MainActor () -> Void,
        onAudioLock: @escaping @MainActor (Bool) -> Void
    ) {
        self.onRefresh = onRefresh
        self.onAudioLock = onAudioLock
        guard !isStarted, BeaconControlSignal.sharedDefaults != nil else { return }
        isStarted = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in [BeaconControlSignal.refreshNotification, BeaconControlSignal.audioLockNotification] {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                guard let raw = name?.rawValue as String? else { return }
                Task { @MainActor in BeaconControlListener.handle(raw) }
            }, name as CFString, nil, .deliverImmediately)
        }
    }

    /// Mirrors the real lock state so the control shows it, then refreshes the control.
    static func publishAudioLockState(_ isEnabled: Bool) {
        guard let defaults = BeaconControlSignal.sharedDefaults else { return }
        defaults.set(isEnabled, forKey: BeaconControlSignal.audioLockStateKey)
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: BeaconControlSignal.audioLockControlKind)
        }
    }

    private static func handle(_ name: String) {
        switch name {
        case BeaconControlSignal.refreshNotification:
            onRefresh?()
        case BeaconControlSignal.audioLockNotification:
            guard let requested = BeaconControlSignal.sharedDefaults?
                .object(forKey: BeaconControlSignal.audioLockRequestKey) as? Bool else { return }
            onAudioLock?(requested)
        default:
            break
        }
    }
}
