import Foundation

public enum BatteryHistoryStore {
    public static let storageKey = "BatteryHub.batteryHistory.samples"
    public static let maximumSamplesPerDevice = 96
    public static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    public static func record(
        _ snapshots: [BatterySnapshot],
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        var samplesByDeviceID = loadAll(from: defaults)
            .mapValues { pruned($0, now: now) }
            .filter { !$0.value.isEmpty }

        for snapshot in snapshots {
            guard let percent = snapshot.percent else { continue }
            let sample = BatteryHistorySample(
                deviceID: snapshot.deviceID,
                percent: percent,
                chargeState: snapshot.chargeState,
                source: snapshot.source,
                recordedAt: snapshot.updatedAt
            )
            var samples = samplesByDeviceID[snapshot.deviceID] ?? []
            guard shouldAppend(sample, after: samples.last) else { continue }
            samples.append(sample)
            samplesByDeviceID[snapshot.deviceID] = pruned(samples, now: now)
        }

        save(samplesByDeviceID, to: defaults)
    }

    public static func samples(
        for deviceID: String,
        defaults: UserDefaults = .standard
    ) -> [BatteryHistorySample] {
        loadAll(from: defaults)[deviceID] ?? []
    }

    public static func summary(
        for deviceID: String,
        defaults: UserDefaults = .standard
    ) -> BatteryHistorySummary? {
        summary(for: samples(for: deviceID, defaults: defaults))
    }

    public static func summary(for samples: [BatteryHistorySample]) -> BatteryHistorySummary? {
        let sortedSamples = samples.sorted { $0.recordedAt < $1.recordedAt }
        guard let first = sortedSamples.first, let latest = sortedSamples.last else { return nil }
        let percents = sortedSamples.map(\.percent)
        return BatteryHistorySummary(
            samples: sortedSamples,
            latestPercent: latest.percent,
            delta: latest.percent - first.percent,
            minimumPercent: percents.min() ?? latest.percent,
            maximumPercent: percents.max() ?? latest.percent
        )
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    private static func shouldAppend(
        _ sample: BatteryHistorySample,
        after previous: BatteryHistorySample?
    ) -> Bool {
        guard let previous else { return true }
        if previous.recordedAt == sample.recordedAt { return false }
        if abs(sample.recordedAt.timeIntervalSince(previous.recordedAt)) < 300,
           previous.percent == sample.percent,
           previous.chargeState == sample.chargeState {
            return false
        }
        return true
    }

    private static func pruned(
        _ samples: [BatteryHistorySample],
        now: Date
    ) -> [BatteryHistorySample] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return Array(samples
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }
            .suffix(maximumSamplesPerDevice))
    }

    private static func loadAll(from defaults: UserDefaults) -> [String: [BatteryHistorySample]] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [BatteryHistorySample]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save(
        _ samplesByDeviceID: [String: [BatteryHistorySample]],
        to defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(samplesByDeviceID) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
