import AppKit
import XCTest
@testable import Beacon

final class WindowAccessibilityTests: XCTestCase {
    @MainActor
    func testHUDUsesNonactivatingPanelWithoutBecomingKey() throws {
        let defaults = UserDefaults.standard
        let enabledKey = BatteryHUDPreferences.showActionHUDKey
        let autoDismissKey = BatteryHUDPreferences.autoDismissEnabledKey
        let originalEnabled = defaults.object(forKey: enabledKey)
        let originalAutoDismiss = defaults.object(forKey: autoDismissKey)
        defaults.set(true, forKey: enabledKey)
        defaults.set(false, forKey: autoDismissKey)
        defer {
            restore(originalEnabled, forKey: enabledKey, in: defaults)
            restore(originalAutoDismiss, forKey: autoDismissKey, in: defaults)
        }

        let controller = BeaconHUDController()
        controller.show(
            event: BatteryAlertEvent(
                kind: .lowBattery,
                deviceID: "test-watch",
                displayName: "Test Watch",
                percent: 18
            )
        )

        let panel = try XCTUnwrap(controller.debugWindow)
        defer { panel.orderOut(nil) }
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.isKeyWindow)
    }

    @MainActor
    func testHUDPreviewBypassesDisabledPreferenceWithoutBecomingKey() throws {
        let defaults = UserDefaults.standard
        let enabledKey = BatteryHUDPreferences.showActionHUDKey
        let originalEnabled = defaults.object(forKey: enabledKey)
        defaults.set(false, forKey: enabledKey)
        defer { restore(originalEnabled, forKey: enabledKey, in: defaults) }

        let controller = BeaconHUDController()
        controller.showForUITesting(
            event: BatteryAlertEvent(
                kind: .lowBattery,
                deviceID: "preview-keyboard",
                displayName: "Preview Keyboard",
                percent: 12
            )
        )

        let panel = try XCTUnwrap(controller.debugWindow)
        defer { panel.orderOut(nil) }
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
    }

    @MainActor
    func testSettingsUsesContentMinimumAndRebuildsHostForExplicitRoute() throws {
        let defaults = UserDefaults.standard
        let frameKey = "NSWindow Frame Beacon.SettingsWindow"
        let originalFrame = defaults.object(forKey: frameKey)
        defaults.removeObject(forKey: frameKey)
        defer { restore(originalFrame, forKey: frameKey, in: defaults) }

        let controller = BeaconSettingsWindowController(model: BeaconModel(environment: [:]))
        controller.showWindow(initialPane: .devices)
        let firstHost = try XCTUnwrap(controller.debugHostingControllerIdentifier)
        let window = try XCTUnwrap(controller.debugWindow)
        defer { window.close() }

        controller.showWindow(initialPane: .dashboard)

        XCTAssertNotEqual(controller.debugHostingControllerIdentifier, firstHost)
        XCTAssertEqual(window.contentMinSize.width, 900, accuracy: 0.5)
        XCTAssertEqual(window.contentMinSize.height, 620, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(window.contentRect(forFrameRect: window.frame).height, 620)
    }

    @MainActor
    func testDesktopWidgetUsesLiveFrameAndReusesHostingController() throws {
        let defaults = UserDefaults.standard
        let showKey = DesktopWidgetPreferences.showDesktopWidgetKey
        let styleKey = DesktopWidgetPreferences.widgetStyleKey
        let frameKey = "NSWindow Frame \(DesktopWidgetPreferences.frameAutosaveName)"
        let originalShow = defaults.object(forKey: showKey)
        let originalStyle = defaults.object(forKey: styleKey)
        let originalFrame = defaults.object(forKey: frameKey)
        defaults.set(true, forKey: showKey)
        defaults.set(DesktopWidgetStyle.compact.rawValue, forKey: styleKey)
        defer {
            restore(originalShow, forKey: showKey, in: defaults)
            restore(originalStyle, forKey: styleKey, in: defaults)
            restore(originalFrame, forKey: frameKey, in: defaults)
        }

        let controller = BeaconDesktopWidgetController()
        controller.update(snapshots: [], onOpenSettings: {})
        let firstFrame = try XCTUnwrap(controller.debugWindowFrame)
        let firstHostingController = try XCTUnwrap(controller.debugHostingControllerIdentifier)
        let visibleFrame = DesktopWidgetWindowPlacement.bestVisibleFrame(
            for: firstFrame,
            among: NSScreen.screens.map(\.visibleFrame),
            fallback: NSScreen.main?.visibleFrame ?? firstFrame
        )
        let movedFrame = DesktopWidgetWindowPlacement.clampedFrame(
            firstFrame.offsetBy(dx: -24, dy: -24),
            in: visibleFrame
        )
        controller.debugSetWindowFrame(movedFrame)

        controller.update(snapshots: [], onOpenSettings: {})

        let updatedFrame = try XCTUnwrap(controller.debugWindowFrame)
        XCTAssertEqual(controller.debugHostingControllerIdentifier, firstHostingController)
        XCTAssertEqual(updatedFrame.origin.x, movedFrame.origin.x, accuracy: 0.5)
        XCTAssertEqual(updatedFrame.origin.y, movedFrame.origin.y, accuracy: 0.5)
        controller.close()
    }

    @MainActor
    func testDesktopWidgetRestoresSavedFrameInANewController() throws {
        let defaults = UserDefaults.standard
        let showKey = DesktopWidgetPreferences.showDesktopWidgetKey
        let styleKey = DesktopWidgetPreferences.widgetStyleKey
        let frameKey = "NSWindow Frame \(DesktopWidgetPreferences.frameAutosaveName)"
        let originalShow = defaults.object(forKey: showKey)
        let originalStyle = defaults.object(forKey: styleKey)
        let originalFrame = defaults.object(forKey: frameKey)
        defaults.set(true, forKey: showKey)
        defaults.set(DesktopWidgetStyle.compact.rawValue, forKey: styleKey)
        defaults.removeObject(forKey: frameKey)
        defer {
            restore(originalShow, forKey: showKey, in: defaults)
            restore(originalStyle, forKey: styleKey, in: defaults)
            restore(originalFrame, forKey: frameKey, in: defaults)
        }

        var firstController: BeaconDesktopWidgetController? = BeaconDesktopWidgetController()
        firstController?.update(snapshots: [], onOpenSettings: {})
        let initialFrame = try XCTUnwrap(firstController?.debugWindowFrame)
        let visibleFrame = DesktopWidgetWindowPlacement.bestVisibleFrame(
            for: initialFrame,
            among: NSScreen.screens.map(\.visibleFrame),
            fallback: NSScreen.main?.visibleFrame ?? initialFrame
        )
        let savedFrame = DesktopWidgetWindowPlacement.clampedFrame(
            initialFrame.offsetBy(dx: -36, dy: -36),
            in: visibleFrame
        )
        firstController?.debugSetWindowFrame(savedFrame)
        firstController?.close()
        firstController = nil

        let restoredController = BeaconDesktopWidgetController()
        restoredController.update(snapshots: [], onOpenSettings: {})
        let restoredFrame = try XCTUnwrap(restoredController.debugWindowFrame)
        XCTAssertEqual(restoredFrame.origin.x, savedFrame.origin.x, accuracy: 0.5)
        XCTAssertEqual(restoredFrame.origin.y, savedFrame.origin.y, accuracy: 0.5)
        restoredController.close()
    }

    func testDesktopWidgetChoosesIntersectingDisplayAndFallsBackAfterDisconnect() {
        let primary = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let secondary = NSRect(x: -1_280, y: 0, width: 1_280, height: 800)
        let secondaryWidget = NSRect(x: -320, y: 420, width: 256, height: 232)

        XCTAssertEqual(
            DesktopWidgetWindowPlacement.bestVisibleFrame(
                for: secondaryWidget,
                among: [primary, secondary],
                fallback: primary
            ),
            secondary
        )
        XCTAssertEqual(
            DesktopWidgetWindowPlacement.bestVisibleFrame(
                for: secondaryWidget,
                among: [primary],
                fallback: primary
            ),
            primary
        )

        let clamped = DesktopWidgetWindowPlacement.clampedFrame(secondaryWidget, in: primary)
        XCTAssertGreaterThanOrEqual(clamped.minX, primary.minX)
        XCTAssertGreaterThanOrEqual(clamped.minY, primary.minY)
        XCTAssertLessThanOrEqual(clamped.maxX, primary.maxX)
        XCTAssertLessThanOrEqual(clamped.maxY, primary.maxY)
    }

    @MainActor
    func testDesktopWidgetReclampsWhenScreenParametersChange() async throws {
        let defaults = UserDefaults.standard
        let showKey = DesktopWidgetPreferences.showDesktopWidgetKey
        let frameKey = "NSWindow Frame \(DesktopWidgetPreferences.frameAutosaveName)"
        let originalShow = defaults.object(forKey: showKey)
        let originalFrame = defaults.object(forKey: frameKey)
        defaults.set(true, forKey: showKey)
        defer {
            restore(originalShow, forKey: showKey, in: defaults)
            restore(originalFrame, forKey: frameKey, in: defaults)
        }

        let controller = BeaconDesktopWidgetController()
        controller.update(snapshots: [], onOpenSettings: {})
        let currentFrame = try XCTUnwrap(controller.debugWindowFrame)
        controller.debugSetWindowFrame(currentFrame.offsetBy(dx: 100_000, dy: 100_000))

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: NSApp
        )
        await Task.yield()

        let clampedFrame = try XCTUnwrap(controller.debugWindowFrame)
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        XCTAssertTrue(visibleFrames.contains { $0.intersects(clampedFrame) })
        controller.close()
    }

    @MainActor
    func testStatusPanelCancelRequestsCoordinatedClose() throws {
        let controller = StatusMenuPanelController()
        var closeRequestCount = 0
        controller.onRequestClose = {
            closeRequestCount += 1
        }
        controller.install(
            rootView: StatusMenuView(snapshots: [], onRefresh: {}),
            contentSize: NSSize(width: 386, height: 330)
        )

        let panel = try XCTUnwrap(controller.panel)
        panel.cancelOperation(nil)

        XCTAssertEqual(closeRequestCount, 1)
    }

    func testDashboardAccessibilityValueSummarizesCompositeRowOnce() {
        let regularDevice = DashboardBatteryDevice(
            id: "iphone",
            displayName: "Test iPhone",
            kind: .iPhone,
            percent: 64,
            chargeState: .charging,
            freshness: .fresh,
            isPinned: true
        )
        XCTAssertEqual(
            dashboardBatteryAccessibilityValue(for: regularDevice, statusText: "Charging"),
            "64 percent, Charging, Pinned"
        )

        let now = Date(timeIntervalSince1970: 1_000)
        let airPods = DashboardBatteryDevice(
            id: "airpods",
            displayName: "Test AirPods",
            kind: .airPods,
            percent: 68,
            chargeState: .charging,
            freshness: .fresh,
            airPodsComponents: [
                AirPodsComponent(
                    slot: .left,
                    percent: 72,
                    chargeState: .unplugged,
                    freshness: .fresh,
                    connectionState: .connected,
                    updatedAt: now
                ),
                AirPodsComponent(
                    slot: .right,
                    percent: 68,
                    chargeState: .charging,
                    freshness: .fresh,
                    connectionState: .connected,
                    updatedAt: now
                ),
                AirPodsComponent(
                    slot: .case,
                    percent: 90,
                    chargeState: .full,
                    freshness: .fresh,
                    connectionState: .connected,
                    updatedAt: now
                ),
            ]
        )
        XCTAssertEqual(
            dashboardBatteryAccessibilityValue(for: airPods, statusText: "Parts"),
            "Left AirPod 72 percent, Right AirPod 68 percent charging, Charging case 90 percent full"
        )
    }

    @MainActor
    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
