import Foundation
import UserNotifications

enum BatteryAlertKind: Equatable {
    case lowBattery
    case charged
}

struct BatteryAlertEvent: Equatable {
    let kind: BatteryAlertKind
    let deviceID: String
    let displayName: String
    let percent: Int?
}

enum LowBatteryNotifier {
    static let defaultThreshold = 20
    static let thresholdDefaultsKey = "BatteryHub.lowBatteryThreshold"
    static let notificationsEnabledDefaultsKey = "BatteryHub.lowBatteryNotificationsEnabled"
    static let chargedNotificationsEnabledDefaultsKey = "BatteryHub.chargedBatteryNotificationsEnabled"
    static let deviceThresholdDefaultsPrefix = "BatteryHub.lowBatteryThreshold.device."
    static let deviceChargedAlertDefaultsPrefix = "BatteryHub.chargedBatteryAlert.device."

    static var threshold: Int {
        globalThreshold(defaults: .standard)
    }

    static var notificationsEnabled: Bool {
        lowBatteryNotificationsEnabled(defaults: .standard)
    }

    static var chargedNotificationsEnabled: Bool {
        chargedNotificationsEnabled(defaults: .standard)
    }

    static func lowBatteryNotificationsEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: notificationsEnabledDefaultsKey) != nil else {
            return true
        }
        return defaults.bool(forKey: notificationsEnabledDefaultsKey)
    }

    static func chargedNotificationsEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: chargedNotificationsEnabledDefaultsKey) != nil else {
            return true
        }
        return defaults.bool(forKey: chargedNotificationsEnabledDefaultsKey)
    }

    static func threshold(forDeviceID deviceID: String, defaults: UserDefaults = .standard) -> Int {
        if let value = customThreshold(forDeviceID: deviceID, defaults: defaults) {
            return value
        }
        let prefix = airPodsPrefix(for: deviceID)
        if prefix != deviceID, let value = customThreshold(forDeviceID: prefix, defaults: defaults) {
            return value
        }
        return globalThreshold(defaults: defaults)
    }

    static func hasCustomThreshold(forDeviceID deviceID: String, defaults: UserDefaults = .standard) -> Bool {
        customThreshold(forDeviceID: deviceID, defaults: defaults) != nil
    }

    static func setThreshold(_ value: Int, forDeviceID deviceID: String, defaults: UserDefaults = .standard) {
        defaults.set(clampedThreshold(value), forKey: deviceThresholdDefaultsPrefix + deviceID)
    }

    static func resetThreshold(forDeviceID deviceID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: deviceThresholdDefaultsPrefix + deviceID)
    }

    static func isChargedAlertEnabled(forDeviceID deviceID: String, defaults: UserDefaults = .standard) -> Bool {
        if let value = customChargedAlertSetting(forDeviceID: deviceID, defaults: defaults) {
            return value
        }
        let prefix = airPodsPrefix(for: deviceID)
        if prefix != deviceID, let value = customChargedAlertSetting(forDeviceID: prefix, defaults: defaults) {
            return value
        }
        return false
    }

    static func setChargedAlertEnabled(_ isEnabled: Bool, forDeviceID deviceID: String, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: deviceChargedAlertDefaultsPrefix + deviceID)
    }

    static func resetChargedAlert(forDeviceID deviceID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: deviceChargedAlertDefaultsPrefix + deviceID)
    }

    private static let lowBatteryAlertedDefaultsPrefix = "BatteryHub.lowBatteryAlerted."
    private static let chargedAlertedDefaultsPrefix = "BatteryHub.chargedBatteryAlerted."

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @discardableResult
    static func notifyIfNeeded(for snapshots: [BatterySnapshot]) -> [BatteryAlertEvent] {
        let defaults = UserDefaults.standard
        let events = pendingAlertEvents(for: snapshots, defaults: defaults)

        for event in events {
            let content = UNMutableNotificationContent()
            switch event.kind {
            case .lowBattery:
                content.title = "\(event.displayName) needs charging"
                content.body = event.percent.map { "Battery is at \($0)%." } ?? "Battery is low."
            case .charged:
                content.title = "\(event.displayName) is fully charged"
                content.body = event.percent.map { "Battery has reached \($0)%." } ?? "Battery has finished charging."
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: event.notificationIdentifier,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

        return events
    }

    static func pendingAlertEvents(
        for snapshots: [BatterySnapshot],
        defaults: UserDefaults = .standard
    ) -> [BatteryAlertEvent] {
        var events: [BatteryAlertEvent] = []

        for snapshot in snapshots {
            if let event = lowBatteryEvent(for: snapshot, defaults: defaults) {
                events.append(event)
            }
            if let event = chargedEvent(for: snapshot, defaults: defaults) {
                events.append(event)
            }
        }

        return events
    }

    private static func lowBatteryEvent(
        for snapshot: BatterySnapshot,
        defaults: UserDefaults
    ) -> BatteryAlertEvent? {
        let key = lowBatteryAlertedDefaultsPrefix + snapshot.deviceID
        guard lowBatteryNotificationsEnabled(defaults: defaults) else {
            defaults.removeObject(forKey: key)
            return nil
        }

        guard let percent = snapshot.percent else {
            defaults.removeObject(forKey: key)
            return nil
        }

        let snapshotThreshold = threshold(forDeviceID: snapshot.deviceID, defaults: defaults)
        if percent > snapshotThreshold || snapshot.chargeState == .charging || snapshot.chargeState == .full {
            defaults.removeObject(forKey: key)
            return nil
        }

        guard defaults.bool(forKey: key) == false else { return nil }
        defaults.set(true, forKey: key)
        return BatteryAlertEvent(
            kind: .lowBattery,
            deviceID: snapshot.deviceID,
            displayName: snapshot.displayName,
            percent: percent
        )
    }

    private static func chargedEvent(
        for snapshot: BatterySnapshot,
        defaults: UserDefaults
    ) -> BatteryAlertEvent? {
        let key = chargedAlertedDefaultsPrefix + snapshot.deviceID
        guard chargedNotificationsEnabled(defaults: defaults),
              isChargedAlertEnabled(forDeviceID: snapshot.deviceID, defaults: defaults) else {
            defaults.removeObject(forKey: key)
            return nil
        }

        guard isChargeComplete(snapshot) else {
            if shouldResetChargedState(snapshot) {
                defaults.removeObject(forKey: key)
            }
            return nil
        }

        guard defaults.bool(forKey: key) == false else { return nil }
        defaults.set(true, forKey: key)
        return BatteryAlertEvent(
            kind: .charged,
            deviceID: snapshot.deviceID,
            displayName: snapshot.displayName,
            percent: snapshot.percent
        )
    }

    private static func customThreshold(forDeviceID deviceID: String, defaults: UserDefaults) -> Int? {
        let key = deviceThresholdDefaultsPrefix + deviceID
        guard defaults.object(forKey: key) != nil else { return nil }
        return clampedThreshold(defaults.integer(forKey: key))
    }

    private static func customChargedAlertSetting(forDeviceID deviceID: String, defaults: UserDefaults) -> Bool? {
        let key = deviceChargedAlertDefaultsPrefix + deviceID
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    private static func globalThreshold(defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: thresholdDefaultsKey)
        guard value > 0 else { return defaultThreshold }
        return clampedThreshold(value)
    }

    private static func clampedThreshold(_ value: Int) -> Int {
        Swift.max(5, Swift.min(50, value))
    }

    private static func isChargeComplete(_ snapshot: BatterySnapshot) -> Bool {
        snapshot.chargeState == .full || (snapshot.chargeState == .charging && (snapshot.percent ?? 0) >= 100)
    }

    private static func shouldResetChargedState(_ snapshot: BatterySnapshot) -> Bool {
        snapshot.chargeState == .unplugged
            || snapshot.chargeState == .unknown
            || (snapshot.percent ?? 100) < 95
    }
}

private extension BatteryAlertEvent {
    var notificationIdentifier: String {
        switch kind {
        case .lowBattery:
            return "BatteryHub.low.\(deviceID)"
        case .charged:
            return "BatteryHub.charged.\(deviceID)"
        }
    }
}
