import XCTest

/// Actual separate HUD and inspector windows; Bluetooth/audio observations remain fixtures.
final class ConnectionHUDUITests: XCTestCase {
    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-show-hud", "-AppleLanguages", "(en)", "-Beacon.showActionHUD", "YES"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launchEnvironment["BEACON_SETUP_SCENARIO"] = "empty"
        app.launchEnvironment["BEACON_CONNECTION_SCENARIO"] = scenario
        app.launchEnvironment["BEACON_HUD_SCENARIO"] = "connection-events"
        app.launch()
        XCTAssertTrue(app.windows["Beacon HUD Preview"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor
    private func expect(_ element: XCUIElement, _ text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR label == %@", text, text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }
    @MainActor
    func testConfirmedResultPrecedesLateBatteryAndDismissRevealsQueuedReminder() {
        let app = launch("ready"); defer { app.terminate() }
        let hud = app.windows["Beacon HUD Preview"]
        expect(hud.staticTexts["hud.connection.state"], "Connection confirmed")
        expect(hud.staticTexts["hud.connection.device"], "Test Headphones")
        XCTAssertFalse(hud.staticTexts["Queued Keyboard is running low"].exists)
        let evidence = XCTAttachment(screenshot: hud.screenshot())
        evidence.name = "confirmed-HUD-before-queued-battery-fixture"; evidence.lifetime = .keepAlways; add(evidence)
        hud.buttons["hud.dismiss"].click()
        XCTAssertTrue(hud.staticTexts["Queued Keyboard is running low"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testUnconfirmedHUDRoutesToExactSameNamedDeviceRecovery() {
        let app = launch("audio-unverified"); defer { app.terminate() }
        let hud = app.windows["Beacon HUD Preview"]
        expect(hud.staticTexts["hud.connection.state"], "Bluetooth connected; audio not confirmed")
        XCTAssertFalse(hud.staticTexts["Connection confirmed"].exists)
        XCTAssertFalse(hud.staticTexts["Queued Keyboard is running low"].exists)
        hud.buttons["hud.connection.review"].click()
        let settings = app.windows["Beacon Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let selected = settings.staticTexts["connection.state.aa:bb:cc:dd:ee:02"]
        expect(selected, "Bluetooth connected; audio not confirmed")
        XCTAssertTrue(settings.buttons["connection.retry.aa:bb:cc:dd:ee:02"].exists)
        XCTAssertFalse(settings.staticTexts["connection.state.aa:bb:cc:dd:ee:01"].exists)
    }
}
