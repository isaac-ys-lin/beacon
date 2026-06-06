import Foundation

public struct SyncEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let snapshots: [BatterySnapshot]
    public let publishedAt: Date

    public init(schemaVersion: Int = 1, snapshots: [BatterySnapshot], publishedAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.snapshots = snapshots
        self.publishedAt = publishedAt
    }
}

public extension JSONEncoder {
    static var batteryHub: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var batteryHub: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

#if os(macOS) || os(iOS)
public final class CloudBatterySync {
    public static let storageKey = "BatteryHub.SyncEnvelope.v1"
    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func publish(_ snapshots: [BatterySnapshot], now: Date = Date()) throws {
        let envelope = SyncEnvelope(snapshots: snapshots, publishedAt: now)
        let data = try JSONEncoder.batteryHub.encode(envelope)
        store.set(data, forKey: Self.storageKey)
        store.synchronize()
    }

    public func load() throws -> SyncEnvelope? {
        guard let data = store.data(forKey: Self.storageKey) else {
            return nil
        }
        return try JSONDecoder.batteryHub.decode(SyncEnvelope.self, from: data)
    }
}
#endif
