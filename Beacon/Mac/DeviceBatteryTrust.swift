import Foundation
import SwiftUI

/// One interpretation of a report is shared by the menu, inspector and accessibility value.
enum DeviceBatteryTrust: String, Equatable, Sendable {
    case current, partial, stale, expired, disconnected, noReport, permission, unavailable, unconfirmed

    var title: String {
        let key: String
        switch self {
        case .current: key = "Latest report"
        case .partial: key = "Partial report"
        case .stale: key = "Stale"
        case .expired: key = "Expired"
        case .disconnected: key = "Disconnected"
        case .noReport: key = "No report"
        case .permission: key = "Permission needed"
        case .unavailable: key = "Read failed"
        case .unconfirmed: key = "Connection unconfirmed"
        }
        return BeaconL10n.string(key)
    }
}

struct DeviceBatteryPresentation: Equatable, Sendable {
    let state: DeviceBatteryTrust
    let percent: Int?
    let updatedAt: Date

    init(percent: Int?, chargeState: ChargeState = .unknown, freshness: Freshness,
         connectionState: ConnectionState = .connected, readStatus: BatteryReadStatus = .reported,
         updatedAt: Date = .distantPast) {
        let valid = percent.flatMap { (0...100).contains($0) ? $0 : nil }
        self.percent = [.unauthorized, .noReport].contains(readStatus) ? nil : valid
        self.updatedAt = updatedAt
        if readStatus == .unauthorized { state = .permission }
        else if connectionState == .disconnected { state = .disconnected }
        else if [.unavailable, .timedOut, .commandMissing].contains(readStatus) { state = .unavailable }
        else if valid == nil || readStatus == .noReport { state = .noReport }
        else if freshness == .expired { state = .expired }
        else if freshness == .stale { state = .stale }
        else if connectionState == .unknown { state = .unconfirmed }
        else { state = .current }
    }

    init(component: AirPodsComponent) {
        self.init(percent: component.percent, chargeState: component.chargeState, freshness: component.freshness,
                  connectionState: component.connectionState, readStatus: component.readStatus, updatedAt: component.updatedAt)
    }

    init(item: DeviceListItem) {
        switch item {
        case .device(let d):
            self.init(percent: d.snapshot.percent, chargeState: d.snapshot.chargeState, freshness: d.freshness,
                      connectionState: d.snapshot.connectionState, readStatus: d.snapshot.readStatus, updatedAt: d.snapshot.updatedAt)
        case .airPods(_, _, let allComponents):
            let active = activeAirPodsComponents(allComponents)
            let components = active.isEmpty ? allComponents : active
            let reports = components.map(Self.init(component:))
            let levels = reports.compactMap(\.percent)
            let state: DeviceBatteryTrust
            if reports.contains(where: { $0.state == .permission }) { state = .permission }
            else if !components.isEmpty && components.allSatisfy({ $0.connectionState == .disconnected }) { state = .disconnected }
            else if reports.contains(where: { $0.state == .unavailable }) { state = .unavailable }
            else if levels.isEmpty { state = .noReport }
            else if reports.allSatisfy({ $0.state == .expired }) { state = .expired }
            else if reports.contains(where: { [.stale, .expired, .disconnected, .unconfirmed].contains($0.state) }) { state = .stale }
            else if levels.count < components.count { state = .partial }
            else { state = .current }
            self.init(state: state, percent: state == .permission || active.isEmpty ? nil : levels.min(),
                      updatedAt: reports.map(\.updatedAt).min() ?? .distantPast)
        }
    }

    private init(state: DeviceBatteryTrust, percent: Int?, updatedAt: Date) {
        self.state = state; self.percent = percent; self.updatedAt = updatedAt
    }

    var valueText: String {
        guard let percent else { return BeaconL10n.string("No battery report") }
        if state == .current { return "\(percent)%" }
        if state == .partial { return BeaconL10n.format("Reported minimum: %d%%", percent) }
        return BeaconL10n.format("Last known: %d%%", percent)
    }
}

/// Failed source-wide reads do not identify which device failed. Only explicit provider IDs
/// may annotate a cached snapshot; names and transport type are never used as evidence.
func batterySnapshotsWithKnownFailures(_ snapshots: [DecoratedBatterySnapshot], diagnostics: BatteryRefreshDiagnostics) -> [DecoratedBatterySnapshot] {
    snapshots.map { d in
        let s = d.snapshot
        guard let failure = diagnostics.attempts.filter({
            $0.status != .reported && $0.affectedDeviceIDs?.contains(s.id) == true && $0.attemptedAt >= s.updatedAt
        }).max(by: { $0.attemptedAt < $1.attemptedAt }) else { return d }
        return DecoratedBatterySnapshot(snapshot: BatterySnapshot(
            deviceID: s.deviceID, displayName: s.displayName, kind: s.kind, percent: s.percent,
            chargeState: s.chargeState, connectionState: s.connectionState, source: s.source,
            provider: s.provider, readStatus: failure.status, confidence: s.confidence,
            identityStrength: s.identityStrength, updatedAt: s.updatedAt
        ), freshness: d.freshness)
    }
}

struct RefreshRecoveryView: View {
    let diagnostics: BatteryRefreshDiagnostics
    let snapshots: [DecoratedBatterySnapshot]
    let isRefreshing: Bool
    let onInspect: (String) -> Void
    let onRefresh: () -> Void
    @State private var isExpanded = false

    var body: some View {
        let problems = diagnostics.attempts.filter {
            $0.status != .reported && ($0.status != .noReport || $0.affectedDeviceIDs != nil)
        }
        if !problems.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, attempt in
                        let presentation = BatteryRefreshAttemptPresentation(provider: attempt.provider,
                            status: attempt.status, candidateCount: attempt.candidateCount, attemptedAt: attempt.attemptedAt)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(presentation.providerTitle + ": " + presentation.statusTitle).font(.caption.bold())
                            if let ids = attempt.affectedDeviceIDs, !ids.isEmpty {
                                ForEach(Array(Set(ids)).sorted(), id: \.self) { id in
                                    if let device = snapshots.first(where: { $0.id == id }) {
                                        Button(device.snapshot.displayName) { onInspect(id) }
                                            .accessibilityIdentifier("refresh.inspect.\(id)")
                                    } else {
                                        Text("An affected device is no longer in the list.").font(.caption)
                                    }
                                }
                            } else {
                                Text("Affected devices could not be identified from this source result.")
                                    .font(.caption).accessibilityIdentifier("refresh.impact-unknown")
                            }
                            Text(presentation.nextStep).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button("Check Again", action: onRefresh).disabled(isRefreshing)
                }.padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Refresh needs attention", systemImage: "exclamationmark.triangle").font(.caption.bold())
                    let ids = Set(problems.flatMap { $0.affectedDeviceIDs ?? [] })
                    let names = snapshots.filter { ids.contains($0.id) }.map { $0.snapshot.displayName }
                    if !names.isEmpty { Text(names.joined(separator: ", ")).font(.caption) }
                    if problems.contains(where: { $0.affectedDeviceIDs == nil }) {
                        Text("Affected devices could not be identified from this source result.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("refresh.recovery")
            .padding(10).beaconSettingsCardSurface()
        }
    }
}
