import Foundation

/// The battery list Beacon shares with its WidgetKit extension through the App Group.
struct BeaconWidgetDevice: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case mac, iPhone, watch, headphones, keyboard, mouse, trackpad, other
    }

    let id: String
    let name: String
    let kind: Kind
    let percent: Int
    let isCharging: Bool

    var symbolName: String {
        switch kind {
        case .mac: return "laptopcomputer"
        case .iPhone: return "iphone"
        case .watch: return "applewatch"
        case .headphones: return "airpods"
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

struct BeaconWidgetPayload: Codable, Equatable, Sendable {
    var devices: [BeaconWidgetDevice]
    var updatedAt: Date

    static let empty = BeaconWidgetPayload(devices: [], updatedAt: .distantPast)
}

enum BeaconWidgetStore {
    static let widgetKind = "BeaconBatteries"
    private static let fileName = "widget-batteries.json"

    /// `$(TeamIdentifierPrefix)com.isaacyslin.Beacon`, resolved at build time into
    /// each target's Info.plist. Unsigned builds (tests) have no group and skip I/O.
    static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BeaconAppGroup") as? String,
              !value.isEmpty, !value.hasPrefix("."), !value.contains("$(")
        else { return nil }
        return value
    }

    static var fileURL: URL? {
        guard let appGroupIdentifier else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func load() -> BeaconWidgetPayload {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(BeaconWidgetPayload.self, from: data)
        else { return .empty }
        return payload
    }

    /// Writes the payload and returns true when the device list changed.
    @discardableResult
    static func save(_ payload: BeaconWidgetPayload) -> Bool {
        guard let url = fileURL else { return false }
        guard load().devices != payload.devices,
              let data = try? JSONEncoder().encode(payload)
        else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// Cross-process requests from Control Center controls (sandboxed extension) to
/// the Beacon app, carried by Darwin notifications plus App Group defaults.
enum BeaconControlSignal {
    static let refreshNotification = "com.isaacyslin.Beacon.control.refresh"
    static let audioLockNotification = "com.isaacyslin.Beacon.control.audioLock"
    static let audioLockStateKey = "control.audioLockEnabled"
    static let audioLockRequestKey = "control.audioLockRequested"
    static let refreshControlKind = "BeaconRefreshControl"
    static let audioLockControlKind = "BeaconAudioLockControl"

    static var sharedDefaults: UserDefaults? {
        BeaconWidgetStore.appGroupIdentifier.flatMap(UserDefaults.init(suiteName:))
    }

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}
