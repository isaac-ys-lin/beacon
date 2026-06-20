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

public struct CompanionSyncDiagnostics: Equatable, Sendable {
    public struct Report: Equatable, Sendable {
        public let displayName: String?
        public let percent: Int?
        public let updatedAt: Date?
        public let source: BatterySource?

        public var hasReport: Bool {
            percent != nil
        }

        public static let missing = Report(
            displayName: nil,
            percent: nil,
            updatedAt: nil,
            source: nil
        )
    }

    public let envelopePublishedAt: Date?
    public let loadErrorDescription: String?
    public let iPhone: Report
    public let appleWatch: Report

    public init(
        snapshots: [BatterySnapshot],
        envelope: SyncEnvelope? = nil,
        loadErrorDescription: String? = nil
    ) {
        envelopePublishedAt = envelope?.publishedAt
        self.loadErrorDescription = loadErrorDescription
        iPhone = Self.latestReport(
            in: snapshots,
            matching: { $0.kind == .iPhone }
        )
        appleWatch = Self.latestReport(
            in: snapshots,
            matching: { $0.kind == .appleWatch }
        )
    }

    public static let empty = CompanionSyncDiagnostics(snapshots: [])

    private static func latestReport(
        in snapshots: [BatterySnapshot],
        matching predicate: (BatterySnapshot) -> Bool
    ) -> Report {
        guard let snapshot = snapshots
            .filter(predicate)
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first
        else {
            return .missing
        }
        return Report(
            displayName: snapshot.displayName,
            percent: snapshot.percent,
            updatedAt: snapshot.updatedAt,
            source: snapshot.source
        )
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

    @discardableResult
    public func publish(_ snapshots: [BatterySnapshot], now: Date = Date()) throws -> Bool {
        let envelope = SyncEnvelope(snapshots: snapshots, publishedAt: now)
        let data = try JSONEncoder.batteryHub.encode(envelope)
        store.set(data, forKey: Self.storageKey)
        return store.synchronize()
    }

    @discardableResult
    public func clear() -> Bool {
        store.removeObject(forKey: Self.storageKey)
        return store.synchronize()
    }

    public func load() throws -> SyncEnvelope? {
        guard let data = store.data(forKey: Self.storageKey) else {
            return nil
        }
        return try JSONDecoder.batteryHub.decode(SyncEnvelope.self, from: data)
    }
}
#endif
