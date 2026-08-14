import XCTest

/// End-to-end smoke coverage for the accessory app's recoverable UI path.
///
/// The app owns the `--ui-test-open-settings` hook and the preview-data
/// fixture. Keeping the fixture at the process boundary makes this test
/// independent of Bluetooth permissions and attached hardware while still
/// exercising the real Settings window and controls.
final class BeaconUITests: XCTestCase {
    @MainActor
    func testSettingsSmoke() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-settings"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launch()
        defer { app.terminate() }

        let settingsWindow = app.windows["Beacon Settings"]
        XCTAssertTrue(
            settingsWindow.waitForExistence(timeout: 10),
            "The UI-test launch hook should open the Beacon Settings window."
        )

        XCTAssertTrue(
            settingsWindow.staticTexts["Preview data is active"].waitForExistence(timeout: 5),
            "Settings should use deterministic preview data during UI tests."
        )

        let refreshButton = settingsWindow.buttons["settings.refresh"]
        XCTAssertTrue(
            refreshButton.waitForExistence(timeout: 5),
            "Settings should expose a stable accessibility identifier for Refresh."
        )
        XCTAssertTrue(refreshButton.isEnabled, "Refresh should be enabled after the preview fixture loads.")
        refreshButton.click()
        XCTAssertTrue(settingsWindow.exists, "Refreshing should keep Settings open.")
    }

    @MainActor
    func testStatusMenuClosesWithEscape() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-status-menu"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launch()
        defer { app.terminate() }

        let statusMenu = app.otherElements["status.menu"]
        XCTAssertTrue(
            statusMenu.waitForExistence(timeout: 10),
            "The UI-test launch hook should open the real status panel."
        )

        app.typeKey(.escape, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: statusMenu
        )
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    @MainActor
    func testHUDPreviewAppearsAndAutoDismisses() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-show-hud"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launch()
        defer { app.terminate() }

        let hud = app.otherElements["hud.preview"]
        XCTAssertTrue(
            hud.waitForExistence(timeout: 10),
            "The deterministic UI-test hook should present the real HUD."
        )

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: hud
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }
}
