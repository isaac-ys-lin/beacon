import AppKit
import Combine
import Carbon
import Foundation

struct BeaconQuickActionShortcut: Codable, Hashable, Sendable {
    let keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    let modifiers: UInt32
    /// The key's printed label at the time it was recorded (e.g. "B", "F5", "←").
    let keyLabel: String

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel.uppercased()
    }

    var displayText: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    /// Global shortcuts need ⌘, ⌃ or ⌥ so they do not swallow ordinary typing;
    /// function keys are allowed on their own, as in System Settings.
    var isValidGlobalShortcut: Bool {
        let required = UInt32(cmdKey | controlKey | optionKey)
        return modifiers & required != 0 || Self.functionKeyCodes.contains(Int(keyCode))
    }

    static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// Builds a shortcut from a key-down event, or nil for a bare modifier press.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let code = Int(event.keyCode)
        let label = Self.specialKeyLabels[code]
            ?? event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let label, !label.isEmpty else { return nil }
        self.init(keyCode: UInt32(code), modifiers: carbon, keyLabel: label)
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}

enum BeaconQuickAction: String, CaseIterable, Identifiable, Sendable {
    case showDashboard
    case refreshBatteries
    case openSettings
    case addDevice
    case openBluetoothSettings
    case connectNearbyDevice
    case disconnectLowestDevice
    case toggleHeadsetMicrophone
    case toggleAudioInputLock
    case transferToMac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showDashboard: return BeaconL10n.string("Show Dashboard")
        case .refreshBatteries: return BeaconL10n.string("Refresh Batteries")
        case .openSettings: return BeaconL10n.string("Open Settings")
        case .addDevice: return BeaconL10n.string("Set Up a Device")
        case .openBluetoothSettings: return BeaconL10n.string("Open Bluetooth Settings")
        case .connectNearbyDevice: return BeaconL10n.string("Connect Prioritized Device")
        case .disconnectLowestDevice: return BeaconL10n.string("Disconnect Lowest Device")
        case .toggleHeadsetMicrophone: return BeaconL10n.string("Toggle Headset Microphone")
        case .toggleAudioInputLock: return BeaconL10n.string("Toggle Audio Input Lock")
        case .transferToMac: return BeaconL10n.string("Transfer to Another Mac")
        }
    }

    var subtitle: String {
        switch self {
        case .showDashboard:
            return BeaconL10n.string("Show or hide the menu bar battery dashboard.")
        case .refreshBatteries:
            return BeaconL10n.string("Request fresh reports from locally connected devices.")
        case .openSettings:
            return BeaconL10n.string("Open the dedicated Beacon settings window.")
        case .addDevice:
            return BeaconL10n.string("Open the setup guide for pairing or connecting a supported device.")
        case .openBluetoothSettings:
            return BeaconL10n.string("Jump to macOS Bluetooth settings for pairing.")
        case .connectNearbyDevice:
            return BeaconL10n.string("Connect a visible disconnected paired device, prioritizing the lowest reported battery.")
        case .disconnectLowestDevice:
            return BeaconL10n.string("Disconnect the visible connected Bluetooth device with the lowest battery.")
        case .toggleHeadsetMicrophone:
            return BeaconL10n.string("Switch between a Bluetooth headset microphone and the Mac's built-in microphone.")
        case .toggleAudioInputLock:
            return BeaconL10n.string("Turn Audio Input Lock on or off.")
        case .transferToMac:
            return BeaconL10n.string("Excluded from this build by product scope.")
        }
    }

    var systemImage: String {
        switch self {
        case .showDashboard: return resolveSymbol("macwindow", fallback: "rectangle")
        case .refreshBatteries: return "arrow.clockwise"
        case .openSettings: return resolveSymbol("gearshape.2.fill", fallback: "gearshape")
        case .addDevice: return "plus"
        case .openBluetoothSettings: return "dot.radiowaves.left.and.right"
        case .connectNearbyDevice: return "dot.radiowaves.left.and.right"
        case .disconnectLowestDevice: return "bolt.horizontal.circle"
        case .toggleHeadsetMicrophone: return "mic.slash"
        case .toggleAudioInputLock: return "lock"
        case .transferToMac: return resolveSymbol("macbook.and.iphone", fallback: "desktopcomputer")
        }
    }

    var isSupported: Bool {
        self != .transferToMac
    }

    var isEnabledByDefault: Bool {
        switch self {
        case .showDashboard, .refreshBatteries:
            return true
        case .openSettings, .addDevice, .openBluetoothSettings, .connectNearbyDevice,
             .disconnectLowestDevice, .toggleHeadsetMicrophone, .toggleAudioInputLock, .transferToMac:
            return false
        }
    }

    /// Beacon's suggested shortcut; users can change or clear it in Settings.
    var defaultShortcut: BeaconQuickActionShortcut? {
        let modifiers = UInt32(cmdKey | optionKey)
        let key: (Int, String)? = switch self {
        case .showDashboard: (kVK_ANSI_B, "B")
        case .refreshBatteries: (kVK_ANSI_R, "R")
        case .openSettings: (kVK_ANSI_Comma, ",")
        case .addDevice: (kVK_ANSI_A, "A")
        case .openBluetoothSettings: (kVK_ANSI_L, "L")
        case .connectNearbyDevice: (kVK_ANSI_N, "N")
        case .disconnectLowestDevice: (kVK_ANSI_X, "X")
        case .toggleHeadsetMicrophone, .toggleAudioInputLock, .transferToMac: nil
        }
        guard let key else { return nil }
        return BeaconQuickActionShortcut(keyCode: UInt32(key.0), modifiers: modifiers, keyLabel: key.1)
    }

    var shortcut: BeaconQuickActionShortcut? { defaultShortcut }

    var hotKeyID: UInt32 {
        switch self {
        case .showDashboard: return 1
        case .refreshBatteries: return 2
        case .openSettings: return 3
        case .addDevice: return 4
        case .openBluetoothSettings: return 5
        case .connectNearbyDevice: return 6
        case .disconnectLowestDevice: return 7
        case .transferToMac: return 8
        case .toggleHeadsetMicrophone: return 9
        case .toggleAudioInputLock: return 10
        }
    }
}

struct BeaconQuickActionPreferences: Equatable, Sendable {
    static let enabledActionIDsKey = "Beacon.quickActions.enabledActionIDs"
    static let shortcutsKey = "Beacon.quickActions.shortcuts"

    /// A stored override: a recorded shortcut, or `nil` when the user cleared it.
    private struct StoredShortcut: Codable, Equatable, Sendable {
        let shortcut: BeaconQuickActionShortcut?
    }

    let enabledActionIDs: Set<String>
    private let overrides: [String: StoredShortcut]

    static var defaultEnabledActionIDs: Set<String> {
        Set(BeaconQuickAction.allCases
            .filter { $0.isSupported && $0.isEnabledByDefault }
            .map(\.id))
    }

    init(enabledActionIDs: Set<String> = Self.defaultEnabledActionIDs) {
        self.init(enabledActionIDs: enabledActionIDs, overrides: [:])
    }

    private init(enabledActionIDs: Set<String>, overrides: [String: StoredShortcut]) {
        self.enabledActionIDs = enabledActionIDs
        self.overrides = overrides
    }

    static func load(from defaults: UserDefaults = .standard) -> BeaconQuickActionPreferences {
        let supportedIDs = Set(BeaconQuickAction.allCases.filter(\.isSupported).map(\.id))
        let enabledIDs = defaults.stringArray(forKey: enabledActionIDsKey)
            .map { Set($0).intersection(supportedIDs) } ?? defaultEnabledActionIDs
        var overrides: [String: StoredShortcut] = [:]
        if let data = defaults.data(forKey: shortcutsKey),
           let decoded = try? JSONDecoder().decode([String: StoredShortcut].self, from: data) {
            overrides = decoded.filter { supportedIDs.contains($0.key) }
        }
        return BeaconQuickActionPreferences(enabledActionIDs: enabledIDs, overrides: overrides)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(enabledActionIDs.sorted(), forKey: Self.enabledActionIDsKey)
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.shortcutsKey)
        } else if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Self.shortcutsKey)
        }
    }

    func isEnabled(_ action: BeaconQuickAction) -> Bool {
        action.isSupported && enabledActionIDs.contains(action.id)
    }

    func shortcut(for action: BeaconQuickAction) -> BeaconQuickActionShortcut? {
        guard action.isSupported else { return nil }
        if let stored = overrides[action.id] { return stored.shortcut }
        return action.defaultShortcut
    }

    func isCustomized(_ action: BeaconQuickAction) -> Bool {
        overrides[action.id] != nil
    }

    /// The other action already using `shortcut`, if any.
    func action(using shortcut: BeaconQuickActionShortcut, excluding action: BeaconQuickAction) -> BeaconQuickAction? {
        BeaconQuickAction.allCases.first { candidate in
            candidate != action && self.shortcut(for: candidate).map(\.combination) == shortcut.combination
        }
    }

    func setting(_ isEnabled: Bool, for action: BeaconQuickAction) -> BeaconQuickActionPreferences {
        guard action.isSupported else { return self }
        var nextIDs = enabledActionIDs
        if isEnabled {
            nextIDs.insert(action.id)
        } else {
            nextIDs.remove(action.id)
        }
        return BeaconQuickActionPreferences(enabledActionIDs: nextIDs, overrides: overrides)
    }

    func settingShortcut(_ shortcut: BeaconQuickActionShortcut?, for action: BeaconQuickAction) -> BeaconQuickActionPreferences {
        guard action.isSupported else { return self }
        var next = overrides
        next[action.id] = StoredShortcut(shortcut: shortcut)
        return BeaconQuickActionPreferences(enabledActionIDs: enabledActionIDs, overrides: next)
    }

    func resettingShortcut(for action: BeaconQuickAction) -> BeaconQuickActionPreferences {
        var next = overrides
        next[action.id] = nil
        return BeaconQuickActionPreferences(enabledActionIDs: enabledActionIDs, overrides: next)
    }
}

private extension BeaconQuickActionShortcut {
    struct Combination: Equatable { let keyCode: UInt32; let modifiers: UInt32 }
    var combination: Combination { Combination(keyCode: keyCode, modifiers: modifiers) }
}

extension Notification.Name {
    /// Posted with `userInfo["isRecording"]` while a shortcut field is capturing keys,
    /// so Beacon's own global shortcuts do not fire during recording.
    static let beaconShortcutRecordingDidChange = Notification.Name("Beacon.shortcutRecordingDidChange")
}

/// Registration results the Settings pane shows next to each shortcut.
@MainActor
final class BeaconShortcutStatus: ObservableObject {
    static let shared = BeaconShortcutStatus()
    @Published var registrationFailures: Set<BeaconQuickAction> = []
}

@MainActor
final class BeaconShortcutController {
    typealias Registrar = (_ keyCode: UInt32, _ modifiers: UInt32, _ hotKeyID: UInt32) -> OSStatus

    private let signature = OSType(0x42485542) // BHUB
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actionByHotKeyID: [UInt32: BeaconQuickAction] = [:]
    private var actionHandler: ((BeaconQuickAction) -> Void)?
    private let registrar: Registrar?
    private var lastPreferences = BeaconQuickActionPreferences()
    private var isSuspended = false

    /// Enabled actions whose shortcut macOS refused (usually already taken by
    /// another app or the system).
    private(set) var registrationFailures: Set<BeaconQuickAction> = []
    var onRegistrationFailuresChange: ((Set<BeaconQuickAction>) -> Void)?

    /// `registrar` replaces Carbon registration in tests.
    init(registrar: Registrar? = nil) {
        self.registrar = registrar
    }

    @discardableResult
    func registerEnabledShortcuts(
        preferences: BeaconQuickActionPreferences = .load(),
        handler: @escaping (BeaconQuickAction) -> Void
    ) -> Set<BeaconQuickAction> {
        actionHandler = handler
        lastPreferences = preferences
        unregisterAll()
        guard !isSuspended else { return registrationFailures }
        if registrar == nil { installEventHandlerIfNeeded() }

        var failures: Set<BeaconQuickAction> = []
        for action in BeaconQuickAction.allCases where preferences.isEnabled(action) {
            guard let shortcut = preferences.shortcut(for: action) else { continue }
            if !register(action, shortcut: shortcut) { failures.insert(action) }
        }
        registrationFailures = failures
        onRegistrationFailuresChange?(failures)
        return failures
    }

    /// Temporarily releases every hotkey while a shortcut field is recording.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            unregisterAll()
        } else if let actionHandler {
            registerEnabledShortcuts(preferences: lastPreferences, handler: actionHandler)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let controller = Unmanaged<BeaconShortcutController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            controller.handle(event: event)
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            eventHandler = nil
        }
    }

    private func register(_ action: BeaconQuickAction, shortcut: BeaconQuickActionShortcut) -> Bool {
        if let registrar {
            let status = registrar(shortcut.keyCode, shortcut.modifiers, action.hotKeyID)
            guard status == noErr else { return false }
            actionByHotKeyID[action.hotKeyID] = action
            return true
        }
        guard eventHandler != nil else { return false }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: action.hotKeyID)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else { return false }
        hotKeyRefs.append(hotKeyRef)
        actionByHotKeyID[action.hotKeyID] = action
        return true
    }

    private func handle(event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              let action = actionByHotKeyID[hotKeyID.id] else {
            return
        }
        actionHandler?(action)
    }

    private func unregisterAll() {
        for hotKeyRef in hotKeyRefs {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
        hotKeyRefs.removeAll()
        actionByHotKeyID.removeAll()
    }
}
