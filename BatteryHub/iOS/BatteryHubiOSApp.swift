import SwiftUI

@main
struct BatteryHubiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let reporter: iPhoneBatteryReporter
    private let relay: WatchBatteryRelay

    init() {
        let reporter = iPhoneBatteryReporter()
        self.reporter = reporter
        self.relay = WatchBatteryRelay(reporter: reporter)
        self.relay.start()
        Task { @MainActor in
            try? reporter.publishCurrentBattery()
        }
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "battery.75percent")
                    .font(.system(size: 48, weight: .regular))
                Text("BatteryHub")
                    .font(.headline)
                Text("Open this app to refresh iPhone and Apple Watch battery snapshots for your Mac.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding()
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    try? reporter.publishCurrentBattery()
                }
            }
        }
    }
}
