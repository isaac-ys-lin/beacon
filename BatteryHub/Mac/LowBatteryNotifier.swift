import Foundation
import UserNotifications

enum LowBatteryNotifier {
    static let defaultThreshold = 20
    static let thresholdDefaultsKey = "BatteryHub.lowBatteryThreshold"
    static let notificationsEnabledDefaultsKey = "BatteryHub.lowBatteryNotificationsEnabled"

    static var threshold: Int {
        let value = UserDefaults.standard.integer(forKey: thresholdDefaultsKey)
        guard value > 0 else { return defaultThreshold }
        return Swift.max(5, Swift.min(50, value))
    }

    static var notificationsEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: notificationsEnabledDefaultsKey) != nil else {
            return true
        }
        return defaults.bool(forKey: notificationsEnabledDefaultsKey)
    }

    private static let defaultsPrefix = "BatteryHub.lowBatteryAlerted."

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyIfNeeded(for snapshots: [BatterySnapshot]) {
        guard notificationsEnabled else { return }
        let defaults = UserDefaults.standard

        for snapshot in snapshots {
            let key = defaultsPrefix + snapshot.deviceID

            guard let percent = snapshot.percent else {
                defaults.removeObject(forKey: key)
                continue
            }

            if percent > threshold || snapshot.chargeState == .charging || snapshot.chargeState == .full {
                defaults.removeObject(forKey: key)
                continue
            }

            guard defaults.bool(forKey: key) == false else { continue }
            defaults.set(true, forKey: key)

            let content = UNMutableNotificationContent()
            content.title = "\(snapshot.displayName) needs charging"
            content.body = "Battery is at \(percent)%."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "BatteryHub.low.\(snapshot.deviceID)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
