import Foundation
import os
import UserNotifications

enum BatteryAlertKind: Equatable, Sendable {
    case lowBattery
    case charged
}

struct BatteryAlertEvent: Equatable, Sendable {
    let kind: BatteryAlertKind
    let deviceID: String
    let displayName: String
    let percent: Int?
}

enum NotificationCenterAuthorizationState: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional

    static func from(_ status: UNAuthorizationStatus) -> NotificationCenterAuthorizationState {
        from(
            authorizationStatus: status,
            alertSetting: .enabled,
            notificationCenterSetting: .enabled
        )
    }

    static func from(
        authorizationStatus: UNAuthorizationStatus,
        alertSetting: UNNotificationSetting,
        notificationCenterSetting: UNNotificationSetting
    ) -> NotificationCenterAuthorizationState {
        switch authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return deliverySettingsAreEnabled(
                alertSetting: alertSetting,
                notificationCenterSetting: notificationCenterSetting
            ) ? .authorized : .denied
        case .provisional:
            return deliverySettingsAreEnabled(
                alertSetting: alertSetting,
                notificationCenterSetting: notificationCenterSetting
            ) ? .provisional : .denied
        @unknown default:
            return .unknown
        }
    }

    private static func deliverySettingsAreEnabled(
        alertSetting: UNNotificationSetting,
        notificationCenterSetting: UNNotificationSetting
    ) -> Bool {
        alertSetting == .enabled && notificationCenterSetting == .enabled
    }

    var title: String {
        switch self {
        case .unknown:
            return "Checking"
        case .notDetermined:
            return "Needs Permission"
        case .denied:
            return "Disabled"
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Limited"
        }
    }

    var subtitle: String {
        switch self {
        case .unknown:
            return "Checking macOS notification permission."
        case .notDetermined:
            return "Allow Beacon to show system notifications."
        case .denied:
            return "Enable Beacon in macOS Notifications settings."
        case .authorized:
            return "System notifications can appear in Notification Center."
        case .provisional:
            return "System notifications are allowed with limited delivery."
        }
    }

    var canRequestPermission: Bool {
        self == .notDetermined
    }

    var canOpenSystemSettings: Bool {
        switch self {
        case .denied, .authorized, .provisional:
            return true
        case .unknown, .notDetermined:
            return false
        }
    }

    var canSendTestNotification: Bool {
        switch self {
        case .authorized, .provisional:
            return true
        case .unknown, .notDetermined, .denied:
            return false
        }
    }
}

struct NotificationCenterDeliveryResult: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case failed
    }

    let state: State
    let title: String
    let subtitle: String

    static func queued(_ notificationTitle: String) -> NotificationCenterDeliveryResult {
        NotificationCenterDeliveryResult(
            state: .queued,
            title: "Queued",
            subtitle: notificationTitle
        )
    }

    static func failed(_ message: String) -> NotificationCenterDeliveryResult {
        NotificationCenterDeliveryResult(
            state: .failed,
            title: "Could not send",
            subtitle: message
        )
    }
}

enum LowBatteryNotifier {
    private static let logger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "notifications")

    static let defaultThreshold = 20
    static let thresholdDefaultsKey = "Beacon.lowBatteryThreshold"
    static let notificationsEnabledDefaultsKey = "Beacon.lowBatteryNotificationsEnabled"
    static let chargedNotificationsEnabledDefaultsKey = "Beacon.chargedBatteryNotificationsEnabled"
    static let deviceThresholdDefaultsPrefix = "Beacon.lowBatteryThreshold.device."
    static let deviceChargedAlertDefaultsPrefix = "Beacon.chargedBatteryAlert.device."
    static let nameChargedAlertDefaultsPrefix = "Beacon.chargedBatteryAlert.name."
    static let chargedAlertedStateVersionDefaultsKey = "Beacon.chargedBatteryAlertedStateVersion"

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

    static func isChargedAlertEnabled(
        forDeviceID deviceID: String,
        displayName: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if isChargedAlertEnabled(forDeviceID: deviceID, defaults: defaults) {
            return true
        }
        return customChargedAlertSetting(forDisplayName: displayName, defaults: defaults) ?? false
    }

    static func isChargedAlertEnabled(for snapshot: BatterySnapshot, defaults: UserDefaults = .standard) -> Bool {
        isChargedAlertEnabled(
            forDeviceID: snapshot.deviceID,
            displayName: snapshot.displayName,
            defaults: defaults
        )
    }

    static func setChargedAlertEnabled(_ isEnabled: Bool, forDeviceID deviceID: String, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: deviceChargedAlertDefaultsPrefix + deviceID)
        if isEnabled {
            resetChargedAlerted(forDeviceID: deviceID, defaults: defaults)
        }
    }

    static func setChargedAlertEnabled(
        _ isEnabled: Bool,
        forDeviceID deviceID: String,
        displayName: String,
        defaults: UserDefaults = .standard
    ) {
        setChargedAlertEnabled(isEnabled, forDeviceID: deviceID, defaults: defaults)
        defaults.set(isEnabled, forKey: nameChargedAlertDefaultsPrefix + normalizedAlertName(displayName))
    }

    static func resetChargedAlert(forDeviceID deviceID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: deviceChargedAlertDefaultsPrefix + deviceID)
    }

    private static let lowBatteryAlertedDefaultsPrefix = "Beacon.lowBatteryAlerted."
    private static let chargedAlertedDefaultsPrefix = "Beacon.chargedBatteryAlerted."
    private static let currentChargedAlertedStateVersion = 2

    static func currentAuthorizationState() async -> NotificationCenterAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationCenterAuthorizationState.from(
            authorizationStatus: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            notificationCenterSetting: settings.notificationCenterSetting
        )
    }

    static func requestAuthorization(
        completion: (@Sendable (NotificationCenterAuthorizationState, NotificationCenterDeliveryResult?) -> Void)? = nil
    ) {
        migrateChargedAlertedStateIfNeeded(defaults: .standard)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
                resetAllChargedAlertedStates(defaults: .standard)
                completion?(.denied, .failed(error.localizedDescription))
            } else {
                logger.info("Notification authorization granted=\(granted)")
                if !granted {
                    resetAllChargedAlertedStates(defaults: .standard)
                }
                Task {
                    let state = await currentAuthorizationState()
                    completion?(state, nil)
                }
            }
        }
    }

    @discardableResult
    static func notifyIfNeeded(
        for snapshots: [BatterySnapshot],
        deliveryHandler: @escaping @Sendable (NotificationCenterDeliveryResult) -> Void = { _ in }
    ) -> [BatteryAlertEvent] {
        let defaults = UserDefaults.standard
        let events = pendingAlertEvents(for: snapshots, defaults: defaults, markAsQueued: false)
        logger.info("Notification check snapshots=\(snapshots.count) events=\(events.count)")

        for event in events {
            logger.info("Queueing \(String(describing: event.kind)) notification for \(event.displayName, privacy: .public) id=\(event.deviceID, privacy: .public) percent=\(event.percent ?? -1)")
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
            let notificationTitle = content.title

            let request = UNNotificationRequest(
                identifier: event.notificationIdentifier,
                content: content,
                trigger: nil
            )
            let requestIdentifier = request.identifier
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    logger.error("Notification add failed id=\(requestIdentifier, privacy: .public): \(error.localizedDescription)")
                    deliveryHandler(.failed(error.localizedDescription))
                } else {
                    markAlerted(event, defaults: .standard)
                    logger.info("Notification add succeeded id=\(requestIdentifier, privacy: .public)")
                    deliveryHandler(.queued(notificationTitle))
                }
            }
        }

        return events
    }

    static func sendTestNotification(
        deliveryHandler: @escaping @Sendable (NotificationCenterDeliveryResult) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Beacon Test Notification"
        content.body = "System notifications are working."
        content.sound = .default
        let notificationTitle = content.title

        let request = UNNotificationRequest(
            identifier: "batteryhub-test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Test notification add failed: \(error.localizedDescription)")
                deliveryHandler(.failed(error.localizedDescription))
            } else {
                logger.info("Test notification add succeeded")
                deliveryHandler(.queued(notificationTitle))
            }
        }
    }

    static func pendingAlertEvents(
        for snapshots: [BatterySnapshot],
        defaults: UserDefaults = .standard
    ) -> [BatteryAlertEvent] {
        pendingAlertEvents(for: snapshots, defaults: defaults, markAsQueued: true)
    }

    static func pendingAlertEventsWithoutMarking(
        for snapshots: [BatterySnapshot],
        defaults: UserDefaults = .standard
    ) -> [BatteryAlertEvent] {
        pendingAlertEvents(for: snapshots, defaults: defaults, markAsQueued: false)
    }

    private static func pendingAlertEvents(
        for snapshots: [BatterySnapshot],
        defaults: UserDefaults,
        markAsQueued: Bool
    ) -> [BatteryAlertEvent] {
        migrateChargedAlertedStateIfNeeded(defaults: defaults)
        var events: [BatteryAlertEvent] = []

        for snapshot in snapshots {
            rememberChargedAlertAliases(for: snapshot, defaults: defaults)
            if let event = lowBatteryEvent(for: snapshot, defaults: defaults, markAsQueued: markAsQueued) {
                events.append(event)
            }
            if let event = chargedEvent(for: snapshot, defaults: defaults, markAsQueued: markAsQueued) {
                events.append(event)
            }
        }

        return events
    }

    private static func lowBatteryEvent(
        for snapshot: BatterySnapshot,
        defaults: UserDefaults,
        markAsQueued: Bool
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
        let event = BatteryAlertEvent(
            kind: .lowBattery,
            deviceID: snapshot.deviceID,
            displayName: snapshot.displayName,
            percent: percent
        )
        if markAsQueued {
            markAlerted(event, defaults: defaults)
        }
        return event
    }

    private static func chargedEvent(
        for snapshot: BatterySnapshot,
        defaults: UserDefaults,
        markAsQueued: Bool
    ) -> BatteryAlertEvent? {
        let key = chargedAlertedDefaultsPrefix + snapshot.deviceID
        let globallyEnabled = chargedNotificationsEnabled(defaults: defaults)
        let deviceEnabled = isChargedAlertEnabled(for: snapshot, defaults: defaults)
        let complete = isChargeComplete(snapshot)
        let alreadyAlerted = defaults.bool(forKey: key)

        guard globallyEnabled, deviceEnabled else {
            defaults.removeObject(forKey: key)
            return nil
        }

        guard complete else {
            if shouldResetChargedState(snapshot) {
                defaults.removeObject(forKey: key)
            }
            return nil
        }

        guard alreadyAlerted == false else { return nil }
        let event = BatteryAlertEvent(
            kind: .charged,
            deviceID: snapshot.deviceID,
            displayName: snapshot.displayName,
            percent: snapshot.percent
        )
        if markAsQueued {
            markAlerted(event, defaults: defaults)
        }
        return event
    }

    private static func markAlerted(_ event: BatteryAlertEvent, defaults: UserDefaults) {
        switch event.kind {
        case .lowBattery:
            defaults.set(true, forKey: lowBatteryAlertedDefaultsPrefix + event.deviceID)
        case .charged:
            defaults.set(true, forKey: chargedAlertedDefaultsPrefix + event.deviceID)
        }
    }

    private static func resetChargedAlerted(forDeviceID deviceID: String, defaults: UserDefaults) {
        defaults.removeObject(forKey: chargedAlertedDefaultsPrefix + deviceID)
    }

    private static func resetAllChargedAlertedStates(defaults: UserDefaults) {
        let keys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(chargedAlertedDefaultsPrefix)
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func migrateChargedAlertedStateIfNeeded(defaults: UserDefaults) {
        guard defaults.integer(forKey: chargedAlertedStateVersionDefaultsKey) < currentChargedAlertedStateVersion else {
            return
        }
        resetAllChargedAlertedStates(defaults: defaults)
        defaults.set(currentChargedAlertedStateVersion, forKey: chargedAlertedStateVersionDefaultsKey)
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

    private static func customChargedAlertSetting(forDisplayName displayName: String, defaults: UserDefaults) -> Bool? {
        let key = nameChargedAlertDefaultsPrefix + normalizedAlertName(displayName)
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
        snapshot.chargeState == .full || (snapshot.percent ?? 0) >= 100
    }

    private static func shouldResetChargedState(_ snapshot: BatterySnapshot) -> Bool {
        snapshot.chargeState == .unplugged
            || snapshot.chargeState == .unknown
            || (snapshot.percent ?? 100) < 95
    }

    private static func rememberChargedAlertAliases(for snapshot: BatterySnapshot, defaults: UserDefaults) {
        guard let value = customChargedAlertSetting(forDeviceID: snapshot.deviceID, defaults: defaults) else {
            return
        }
        defaults.set(value, forKey: nameChargedAlertDefaultsPrefix + normalizedAlertName(snapshot.displayName))
    }

    private static func normalizedAlertName(_ displayName: String) -> String {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private extension BatteryAlertEvent {
    var notificationIdentifier: String {
        switch kind {
        case .lowBattery:
            return "Beacon.low.\(deviceID)"
        case .charged:
            return "Beacon.charged.\(deviceID)"
        }
    }
}
