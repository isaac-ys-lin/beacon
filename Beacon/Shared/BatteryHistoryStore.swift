import Foundation

public enum BatteryHistoryStore {
    public static let storageKey = "Beacon.batteryHistory.samples"
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

    /// Heuristic charging detection for devices that expose no hardware charge
    /// signal (BLE/HID peripherals): true when the most recent observed battery
    /// change was an increase, and that increase is recent enough to still be
    /// happening. A drop, a flat-too-long trend, or stale history all read as
    /// not charging — so the pulse stops within `maxStepAge` of unplugging.
    public static func isChargingByTrend(
        for deviceID: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        maxStepAge: TimeInterval = 600
    ) -> Bool {
        isChargingByTrend(
            samples: samples(for: deviceID, defaults: defaults),
            now: now,
            maxStepAge: maxStepAge
        )
    }

    public static func isChargingByTrend(
        samples: [BatteryHistorySample],
        now: Date,
        maxStepAge: TimeInterval = 600
    ) -> Bool {
        let sorted = samples.sorted { $0.recordedAt < $1.recordedAt }
        guard sorted.count >= 2 else { return false }
        let latest = sorted[sorted.count - 1]
        let previous = sorted[sorted.count - 2]
        guard latest.percent > previous.percent else { return false }
        // The rise must be recent...
        guard now.timeIntervalSince(latest.recordedAt) <= maxStepAge else { return false }
        // ...and the two readings that show it must be close together in time.
        // A large gap means they straddle a sleep/disconnect window: the first
        // reading after wake sitting a point above the pre-sleep reading is
        // recalibration/jitter, not active charging — so a flat device left
        // overnight must not light up as charging the moment the Mac wakes.
        return latest.recordedAt.timeIntervalSince(previous.recordedAt) <= maxStepAge
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
