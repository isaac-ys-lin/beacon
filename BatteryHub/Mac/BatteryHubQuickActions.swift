import Carbon
import Foundation

struct BatteryHubQuickActionShortcut: Equatable, Sendable {
    let displayText: String
    let keyCode: UInt32
    let modifiers: UInt32
}

enum BatteryHubQuickAction: String, CaseIterable, Identifiable, Sendable {
    case showDashboard
    case refreshBatteries
    case openSettings
    case addDevice
    case openBluetoothSettings
    case connectNearbyDevice
    case disconnectLowestDevice
    case transferToMac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showDashboard: return "Show Dashboard"
        case .refreshBatteries: return "Refresh Batteries"
        case .openSettings: return "Open Settings"
        case .addDevice: return "Add New Device"
        case .openBluetoothSettings: return "Open Bluetooth Settings"
        case .connectNearbyDevice: return "Connect Nearby Device"
        case .disconnectLowestDevice: return "Disconnect Lowest Device"
        case .transferToMac: return "Transfer to Another Mac"
        }
    }

    var subtitle: String {
        switch self {
        case .showDashboard:
            return "Show or hide the menu bar battery dashboard."
        case .refreshBatteries:
            return "Request fresh reports from local and synced devices."
        case .openSettings:
            return "Open the dedicated BatteryHub settings window."
        case .addDevice:
            return "Open the add-device guide without digging through menus."
        case .openBluetoothSettings:
            return "Jump to macOS Bluetooth settings for pairing."
        case .connectNearbyDevice:
            return "Connect the first visible paired device that is currently disconnected."
        case .disconnectLowestDevice:
            return "Disconnect the visible connected Bluetooth device with the lowest battery."
        case .transferToMac:
            return "Excluded from this build by product scope."
        }
    }

    var systemImage: String {
        switch self {
        case .showDashboard: return resolveSymbol("macwindow", fallback: "rectangle")
        case .refreshBatteries: return "arrow.clockwise"
        case .openSettings: return "gearshape"
        case .addDevice: return "plus"
        case .openBluetoothSettings: return "dot.radiowaves.left.and.right"
        case .connectNearbyDevice: return "dot.radiowaves.left.and.right"
        case .disconnectLowestDevice: return "bolt.horizontal.circle"
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
             .disconnectLowestDevice, .transferToMac:
            return false
        }
    }

    var shortcut: BatteryHubQuickActionShortcut? {
        let modifiers = UInt32(cmdKey | optionKey)
        switch self {
        case .showDashboard:
            return BatteryHubQuickActionShortcut(displayText: "⌥⌘B", keyCode: UInt32(kVK_ANSI_B), modifiers: modifiers)
        case .refreshBatteries:
            return BatteryHubQuickActionShortcut(displayText: "⌥⌘R", keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers)
        case .openSettings:
            return BatteryHubQuickActionShortcut(displayText: "⌥⌘,", keyCode: UInt32(kVK_ANSI_Comma), modifiers: modifiers)
        case .addDevice:
            return BatteryHubQuickActionShortcut(displayText: "⌥⌘A", keyCode: UInt32(kVK_ANSI_A), modifiers: modifiers)
        case .openBluetoothSettings:
            return BatteryHubQuickActionShortcut(displayText: "⌥⌘L", keyCode: UInt32(kVK_ANSI_L), modifiers: modifiers)
        case .connectNearbyDevice:
            return BatteryHubQuickActionShortcut(displayText: "⌥⌘N", keyCode: UInt32(kVK_ANSI_N), modifiers: modifiers)
        case .disconnectLowestDevice:
            return BatteryHubQuickActionShortcut(displayText: "⌥⌘X", keyCode: UInt32(kVK_ANSI_X), modifiers: modifiers)
        case .transferToMac:
            return nil
        }
    }

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
        }
    }
}

struct BatteryHubQuickActionPreferences: Equatable, Sendable {
    static let enabledActionIDsKey = "BatteryHub.quickActions.enabledActionIDs"

    let enabledActionIDs: Set<String>

    static var defaultEnabledActionIDs: Set<String> {
        Set(BatteryHubQuickAction.allCases
            .filter { $0.isSupported && $0.isEnabledByDefault }
            .map(\.id))
    }

    init(enabledActionIDs: Set<String> = Self.defaultEnabledActionIDs) {
        self.enabledActionIDs = enabledActionIDs
    }

    static func load(from defaults: UserDefaults = .standard) -> BatteryHubQuickActionPreferences {
        guard let savedIDs = defaults.stringArray(forKey: enabledActionIDsKey) else {
            return BatteryHubQuickActionPreferences()
        }

        let supportedIDs = Set(BatteryHubQuickAction.allCases.filter(\.isSupported).map(\.id))
        return BatteryHubQuickActionPreferences(enabledActionIDs: Set(savedIDs).intersection(supportedIDs))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(enabledActionIDs.sorted(), forKey: Self.enabledActionIDsKey)
    }

    func isEnabled(_ action: BatteryHubQuickAction) -> Bool {
        action.isSupported && enabledActionIDs.contains(action.id)
    }

    func setting(_ isEnabled: Bool, for action: BatteryHubQuickAction) -> BatteryHubQuickActionPreferences {
        guard action.isSupported else { return self }
        var nextIDs = enabledActionIDs
        if isEnabled {
            nextIDs.insert(action.id)
        } else {
            nextIDs.remove(action.id)
        }
        return BatteryHubQuickActionPreferences(enabledActionIDs: nextIDs)
    }
}

@MainActor
final class BatteryHubShortcutController {
    private let signature = OSType(0x42485542) // BHUB
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actionByHotKeyID: [UInt32: BatteryHubQuickAction] = [:]
    private var actionHandler: ((BatteryHubQuickAction) -> Void)?

    func registerEnabledShortcuts(
        preferences: BatteryHubQuickActionPreferences = .load(),
        handler: @escaping (BatteryHubQuickAction) -> Void
    ) {
        actionHandler = handler
        unregisterAll()
        installEventHandlerIfNeeded()

        for action in BatteryHubQuickAction.allCases where preferences.isEnabled(action) {
            register(action)
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
            let controller = Unmanaged<BatteryHubShortcutController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            controller.handle(event: event)
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func register(_ action: BatteryHubQuickAction) {
        guard let shortcut = action.shortcut else { return }
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

        guard status == noErr else { return }
        hotKeyRefs.append(hotKeyRef)
        actionByHotKeyID[action.hotKeyID] = action
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
