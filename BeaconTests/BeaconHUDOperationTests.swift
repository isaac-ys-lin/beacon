import AppKit
import XCTest
@testable import Beacon

final class BeaconHUDOperationTests: XCTestCase {
    private func operation(_ phase: BluetoothConnectionPhase = .requesting, address: String = "aa:bb:cc:dd:ee:01") -> BluetoothConnectionOperation {
        .init(id: UUID(), deviceID: address, address: address, displayName: "Same name", action: .connect,
              phase: phase, detail: "Fixture, not physical evidence")
    }
    private var battery: BatteryAlertEvent {
        .init(kind: .lowBattery, deviceID: "keyboard", displayName: "Keyboard", percent: 12)
    }

    func testLateBatteryCannotOverwriteProgressOrFailureAndIsEventuallyShown() {
        var queue = BeaconHUDQueue(); var connection = operation()
        queue.submit(.connection(connection)); queue.submit(.battery(battery))
        XCTAssertEqual(queue.current?.event, .connection(connection))
        connection.phase = .audioUnverified
        queue.submit(.connection(connection))
        XCTAssertEqual(queue.current?.event, .connection(connection))
        XCTAssertEqual(queue.waiting.map(\.event), [.battery(battery)])
        queue.dismiss()
        XCTAssertEqual(queue.current?.event, .battery(battery))
        queue.dismiss(); XCTAssertNil(queue.current)
    }

    func testEveryDeviceResultSurvivesConcurrentProgressAndSameNames() {
        var queue = BeaconHUDQueue()
        var first = operation(); var second = operation(address: "aa:bb:cc:dd:ee:02")
        queue.submit(.battery(battery)); queue.submit(.connection(first))
        queue.submit(.connection(second)); queue.submit(.battery(battery))
        second.phase = .connected; queue.submit(.connection(second))
        first.phase = .timedOut; queue.submit(.connection(first))
        XCTAssertEqual(queue.current?.event, .connection(first))
        queue.dismiss(); XCTAssertEqual(queue.current?.event, .connection(second))
        queue.dismiss(); XCTAssertEqual(queue.current?.event, .battery(battery))
        queue.dismiss(); XCTAssertEqual(queue.current?.event, .battery(battery))
        queue.dismiss(); XCTAssertNil(queue.current)
    }

    func testDismissingProgressDoesNotSuppressItsEventualResult() {
        var queue = BeaconHUDQueue(); var connection = operation()
        queue.submit(.connection(connection)); queue.dismiss()
        connection.phase = .verifyingAudio; queue.submit(.connection(connection))
        XCTAssertNil(queue.current)
        connection.phase = .failed; queue.submit(.connection(connection))
        XCTAssertEqual(queue.current?.event, .connection(connection))
        queue.dismiss(); XCTAssertNil(queue.current)
    }

    @MainActor
    func testCancelledBatteryTimerCannotDismissNewOperationAndResultGetsFullInterval() async throws {
        let suite = "Beacon.HUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BatteryHUDPreferences.showActionHUDKey)
        defaults.set(true, forKey: BatteryHUDPreferences.autoDismissEnabledKey)
        defaults.set(2, forKey: BatteryHUDPreferences.dismissDelaySecondsKey)
        let controller = BeaconHUDController(defaults: defaults)
        controller.show(event: battery)
        let panel = try XCTUnwrap(controller.debugWindow); defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(50))
        var connection = operation()
        controller.show(operation: connection)
        try await Task.sleep(for: .milliseconds(2200))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.debugCurrentEvent, .connection(connection))
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        connection.phase = .connected
        controller.show(operation: connection)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.debugCurrentEvent, .connection(connection))
        try await Task.sleep(for: .milliseconds(2100))
        XCTAssertEqual(controller.debugCurrentEvent, .battery(battery))
        controller.debugDismiss()
    }

    @MainActor
    func testDisabledHUDDoesNotAppearAndPersistentResultRequiresDismissal() async throws {
        let suite = "Beacon.HUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: BatteryHUDPreferences.showActionHUDKey)
        let controller = BeaconHUDController(defaults: defaults)
        let connection = operation(.failed)
        controller.show(operation: connection)
        XCTAssertNil(controller.debugWindow)
        defaults.set(true, forKey: BatteryHUDPreferences.showActionHUDKey)
        defaults.set(false, forKey: BatteryHUDPreferences.autoDismissEnabledKey)
        defaults.set(true, forKey: BatteryHUDPreferences.showDismissButtonKey)
        controller.show(operation: connection)
        let panel = try XCTUnwrap(controller.debugWindow); defer { panel.orderOut(nil) }
        controller.show(event: battery)
        try await Task.sleep(for: .milliseconds(2200))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.debugCurrentEvent, .connection(connection))
        controller.debugDismiss()
        XCTAssertEqual(controller.debugCurrentEvent, .battery(battery))
        defaults.set(false, forKey: BatteryHUDPreferences.showActionHUDKey)
        controller.refreshPreferences()
        XCTAssertNil(controller.debugCurrentEvent)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(panel.isVisible)
    }
}
