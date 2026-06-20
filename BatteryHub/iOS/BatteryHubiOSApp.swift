import SwiftUI
import os

@main
struct BatteryHubiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let reporter: iPhoneBatteryReporter
    private let relay: WatchBatteryRelay
    private let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.ios", category: "sync")

    init() {
        let reporter = iPhoneBatteryReporter()
        self.reporter = reporter
        self.relay = WatchBatteryRelay(reporter: reporter)
        self.relay.start()
    }

    var body: some Scene {
        WindowGroup {
            BatteryHubiOSStatusView(reporter: reporter, logger: logger)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { @MainActor in
                        do {
                            try BatteryHubiOSSyncLogger.publish(reporter: reporter, logger: logger)
                        } catch {
                            logger.error("Failed to publish iPhone battery snapshot on activation: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

private struct BatteryHubiOSStatusView: View {
    let reporter: iPhoneBatteryReporter
    let logger: Logger

    @State private var status = "Waiting to publish"
    @State private var detail = "Open this app to refresh iPhone and Apple Watch battery snapshots for your Mac."
    @State private var isRefreshing = false
    @State private var lastResult: IPhoneBatteryPublishResult?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.blue)

            Text("BatteryHub")
                .font(.headline)

            VStack(spacing: 6) {
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)

                Text(detail)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Button(action: publish) {
                if isRefreshing {
                    ProgressView()
                } else {
                    Label("Refresh iPhone Battery", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
        }
        .padding()
        .task {
            publish()
        }
    }

    private var statusColor: Color {
        if lastResult != nil {
            return .green
        }
        if status.hasPrefix("Could not") {
            return .red
        }
        return .secondary
    }

    private func publish() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try BatteryHubiOSSyncLogger.publish(reporter: reporter, logger: logger)
            lastResult = result
            let percentText = result.snapshot.percent.map { "\($0)%" } ?? "No battery report"
            status = "Published \(percentText)"
            detail = "\(result.snapshot.displayName) · iCloud sync \(result.synchronizeAccepted ? "accepted" : "queued locally") · Watch reports \(result.watchSnapshotCount)"
        } catch {
            lastResult = nil
            status = "Could not publish"
            detail = error.localizedDescription
        }
    }
}

@MainActor
private enum BatteryHubiOSSyncLogger {
    @discardableResult
    static func publish(
        reporter: iPhoneBatteryReporter,
        logger: Logger
    ) throws -> IPhoneBatteryPublishResult {
        let result = try reporter.publishCurrentBattery()
        logger.info(
            "Published iPhone battery snapshot percent=\(result.snapshot.percent ?? -1) syncAccepted=\(result.synchronizeAccepted) watchSnapshots=\(result.watchSnapshotCount)"
        )
        return result
    }
}
