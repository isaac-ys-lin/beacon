import Foundation

public struct TrustedIPhone: Codable, Equatable, Identifiable, Sendable {
    public var id: String { udid }

    public let udid: String
    public let displayName: String
    public let trustedAt: Date

    public init(udid: String, displayName: String, trustedAt: Date) {
        self.udid = udid
        self.displayName = displayName
        self.trustedAt = trustedAt
    }
}

public struct TrustedIPhoneRegistry: Codable, Equatable, Sendable {
    public static let storageKey = "BatteryHub.trustedIPhones.devices"

    public private(set) var devices: [TrustedIPhone]

    public init(devices: [TrustedIPhone] = []) {
        self.devices = devices
    }

    public func isTrusted(udid: String) -> Bool {
        devices.contains { $0.udid == udid }
    }

    public func displayName(for udid: String) -> String? {
        devices.first { $0.udid == udid }?.displayName
    }

    public func trusting(_ device: TrustedIPhone) -> TrustedIPhoneRegistry {
        var updatedDevices = devices
        if let existingIndex = updatedDevices.firstIndex(where: { $0.udid == device.udid }) {
            updatedDevices[existingIndex] = device
        } else {
            updatedDevices.append(device)
        }
        return TrustedIPhoneRegistry(devices: updatedDevices)
    }

    public func removing(udid: String) -> TrustedIPhoneRegistry {
        TrustedIPhoneRegistry(devices: devices.filter { $0.udid != udid })
    }

    public static func load(from defaults: UserDefaults = .standard) -> TrustedIPhoneRegistry {
        guard let data = defaults.data(forKey: storageKey),
              let registry = try? JSONDecoder().decode(TrustedIPhoneRegistry.self, from: data)
        else {
            return TrustedIPhoneRegistry()
        }
        return registry
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
