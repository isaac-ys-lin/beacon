import SwiftUI

@main
struct BatteryHubWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let reporter = WatchBatteryReporter()

    init() {
        reporter.start()
        reporter.sendCurrentBattery()
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .font(.system(size: 30, weight: .regular))
                Text("BatteryHub")
                    .font(.headline)
                Button("Refresh") {
                    reporter.sendCurrentBattery()
                }
            }
            .padding()
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reporter.sendCurrentBattery()
                }
            }
        }
    }
}
