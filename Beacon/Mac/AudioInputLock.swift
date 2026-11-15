import CoreAudio
import Foundation
import os

private let audioInputLogger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "audio-input")

struct AudioInputDevice: Equatable, Hashable, Identifiable, Sendable {
    enum Transport: Equatable, Sendable {
        case builtIn
        case bluetooth
        case usb
        case other
    }

    let uid: String
    let name: String
    let transport: Transport

    var id: String { uid }
}

/// Preferences for keeping macOS on a chosen microphone.
struct AudioInputLockPreferences: Equatable, Sendable {
    static let enabledKey = "Beacon.audioInput.lockEnabled"
    static let preferredUIDKey = "Beacon.audioInput.preferredUID"
    static let fallbackUIDKey = "Beacon.audioInput.fallbackUID"
    static let notifiesKey = "Beacon.audioInput.notifiesOnRestore"

    var isEnabled = false
    var preferredUID: String?
    var fallbackUID: String?
    var notifiesOnRestore = true

    static func load(from defaults: UserDefaults = .standard) -> AudioInputLockPreferences {
        AudioInputLockPreferences(
            isEnabled: defaults.bool(forKey: enabledKey),
            preferredUID: defaults.string(forKey: preferredUIDKey),
            fallbackUID: defaults.string(forKey: fallbackUIDKey),
            notifiesOnRestore: defaults.object(forKey: notifiesKey) as? Bool ?? true
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(preferredUID, forKey: Self.preferredUIDKey)
        defaults.set(fallbackUID, forKey: Self.fallbackUIDKey)
        defaults.set(notifiesOnRestore, forKey: Self.notifiesKey)
    }
}

enum AudioInputLockPolicy {
    /// The input the lock wants selected, or nil when nothing should change.
    static func targetUID(
        preferences: AudioInputLockPreferences,
        devices: [AudioInputDevice],
        currentUID: String?
    ) -> String? {
        guard preferences.isEnabled else { return nil }
        let available = Set(devices.map(\.uid))
        let wanted: String? = if let preferred = preferences.preferredUID, available.contains(preferred) {
            preferred
        } else if let fallback = preferences.fallbackUID, available.contains(fallback) {
            fallback
        } else {
            nil
        }
        guard let wanted, wanted != currentUID else { return nil }
        return wanted
    }
}

enum HeadsetMicrophonePolicy {
    /// Toggling the headset microphone: when a Bluetooth headset is the input,
    /// move to the built-in (or another wired) microphone, which also lets the
    /// headset return to its high-quality playback codec; otherwise switch to
    /// the connected Bluetooth headset microphone.
    static func targetUID(devices: [AudioInputDevice], currentUID: String?) -> String? {
        let current = devices.first { $0.uid == currentUID }
        if current?.transport == .bluetooth {
            return (devices.first { $0.transport == .builtIn } ?? devices.first { $0.transport != .bluetooth })?.uid
        }
        return devices.first { $0.transport == .bluetooth }?.uid
    }
}

/// The Core Audio surface Beacon uses, replaceable in tests.
@MainActor
protocol AudioInputSystem: AnyObject {
    func inputDevices() -> [AudioInputDevice]
    func defaultInputUID() -> String?
    @discardableResult func setDefaultInput(uid: String) -> Bool
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
}

@MainActor
final class AudioInputController: ObservableObject {
    static let shared = AudioInputController(system: CoreAudioInputSystem())

    struct Restoration: Equatable {
        let restoredName: String
        let blockedName: String?
    }

    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var currentUID: String?
    /// Set when the lock switches the input back; observed by the Action HUD.
    @Published private(set) var lastRestoration: Restoration?

    private let system: AudioInputSystem
    private let defaults: UserDefaults
    private var isStarted = false
    private var isApplying = false

    init(system: AudioInputSystem, defaults: UserDefaults = .standard) {
        self.system = system
        self.defaults = defaults
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        system.startObserving { [weak self] in self?.systemDidChange() }
        systemDidChange()
    }

    var preferences: AudioInputLockPreferences {
        AudioInputLockPreferences.load(from: defaults)
    }

    func update(_ preferences: AudioInputLockPreferences) {
        preferences.save(to: defaults)
        enforceLock()
    }

    @discardableResult
    func toggleLock() -> Bool {
        var next = preferences
        next.isEnabled.toggle()
        if next.isEnabled, next.preferredUID == nil {
            next.preferredUID = system.defaultInputUID()
        }
        update(next)
        return next.isEnabled
    }

    /// Returns the name of the newly selected microphone, or nil if nothing changed.
    @discardableResult
    func toggleHeadsetMicrophone() -> String? {
        refreshState()
        guard let target = HeadsetMicrophonePolicy.targetUID(devices: devices, currentUID: currentUID),
              system.setDefaultInput(uid: target)
        else { return nil }
        // Keep an active lock consistent with the user's explicit choice.
        var prefs = preferences
        if prefs.isEnabled {
            prefs.preferredUID = target
            prefs.save(to: defaults)
        }
        refreshState()
        return devices.first { $0.uid == target }?.name
    }

    private func systemDidChange() {
        refreshState()
        enforceLock()
    }

    private func refreshState() {
        devices = system.inputDevices()
        currentUID = system.defaultInputUID()
    }

    private func enforceLock() {
        guard !isApplying else { return }
        refreshState()
        let prefs = preferences
        guard let target = AudioInputLockPolicy.targetUID(
            preferences: prefs, devices: devices, currentUID: currentUID
        ) else { return }
        let blockedName = devices.first { $0.uid == currentUID }?.name
        isApplying = true
        let didSet = system.setDefaultInput(uid: target)
        isApplying = false
        refreshState()
        guard didSet, currentUID == target else {
            audioInputLogger.error("Audio input lock could not restore the preferred input")
            return
        }
        audioInputLogger.info("Audio input lock restored the preferred input")
        if prefs.notifiesOnRestore, let name = devices.first(where: { $0.uid == target })?.name {
            lastRestoration = Restoration(restoredName: name, blockedName: blockedName)
        }
    }
}

@MainActor
final class CoreAudioInputSystem: AudioInputSystem {
    private var listenerBlocks: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { device in
            guard hasInputStreams(device),
                  uint(device, kAudioDevicePropertyDeviceIsAlive) == 1,
                  let uid = string(device, kAudioDevicePropertyDeviceUID),
                  let name = string(device, kAudioObjectPropertyName)
            else { return nil }
            return AudioInputDevice(uid: uid, name: name, transport: transport(device))
        }
    }

    func defaultInputUID() -> String? {
        guard let device = uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice),
              device != kAudioObjectUnknown
        else { return nil }
        return string(device, kAudioDevicePropertyDeviceUID)
    }

    func setDefaultInput(uid: String) -> Bool {
        guard var device = allDeviceIDs().first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }) else {
            return false
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &device
        )
        return status == noErr && defaultInputUID() == uid
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in onChange() }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                listenerBlocks.append((address, block))
            }
        }
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr ? devices : []
    }

    private func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private func transport(_ device: AudioDeviceID) -> AudioInputDevice.Transport {
        switch uint(device, kAudioDevicePropertyTransportType) {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        default: return .other
        }
    }

    private func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value
        else { return nil }
        return value.takeRetainedValue() as String
    }
}
