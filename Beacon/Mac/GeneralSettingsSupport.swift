import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLoginServiceStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
}

final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginServiceStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LaunchAtLoginSettingsModel: ObservableObject {
    @Published private(set) var status: LaunchAtLoginServiceStatus
    @Published private(set) var errorMessage: String?

    private let service: LaunchAtLoginServicing

    init(service: LaunchAtLoginServicing = SystemLaunchAtLoginService()) {
        self.service = service
        status = service.status
    }

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    var title: String {
        switch status {
        case .enabled:
            return BeaconL10n.string("Enabled")
        case .requiresApproval:
            return BeaconL10n.string("Needs Approval")
        case .notRegistered:
            return BeaconL10n.string("Disabled")
        case .notFound:
            return BeaconL10n.string("Unavailable")
        }
    }

    var subtitle: String {
        switch status {
        case .enabled:
            return BeaconL10n.string("Beacon will open automatically after you sign in.")
        case .requiresApproval:
            return BeaconL10n.string("Allow Beacon in System Settings > General > Login Items.")
        case .notRegistered:
            return BeaconL10n.string("Beacon opens only when you launch it yourself.")
        case .notFound:
            return BeaconL10n.string("macOS could not find this app's login item registration.")
        }
    }

    func refresh() {
        status = service.status
        errorMessage = nil
    }

    func setEnabled(_ isEnabled: Bool) {
        errorMessage = nil
        do {
            if isEnabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        status = service.status
    }
}

enum BeaconPreferencesResetter {
    static let keyPrefix = "Beacon."

    @discardableResult
    static func resetAppPreferences(
        defaults: UserDefaults = .standard,
        preservingBatteryHistory: Bool = true
    ) -> Int {
        let preservedKeys = preservingBatteryHistory ? Set([BatteryHistoryStore.storageKey]) : []
        let keys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(keyPrefix) && !preservedKeys.contains($0)
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        return keys.count
    }
}

struct BeaconVersionInfo: Equatable, Sendable {
    let version: String
    let build: String

    var displayText: String {
        BeaconL10n.format("Version %1$@ (%2$@)", version, build)
    }

    static func current(bundle: Bundle = .main) -> BeaconVersionInfo {
        from(infoDictionary: bundle.infoDictionary ?? [:])
    }

    static func from(infoDictionary: [String: Any]) -> BeaconVersionInfo {
        BeaconVersionInfo(
            version: infoDictionary["CFBundleShortVersionString"] as? String ?? "Unknown",
            build: infoDictionary["CFBundleVersion"] as? String ?? "Unknown"
        )
    }
}

enum BatteryHistoryExportPanel {
    @MainActor
    static func present(csvData: Data, defaultFilename: String = "Beacon Battery History.csv") throws -> Bool {
        let panel = NSSavePanel()
        panel.title = BeaconL10n.string("Export Battery History")
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try csvData.write(to: url, options: .atomic)
        return true
    }
}

enum BeaconGeneralSystemActions {
    static func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
