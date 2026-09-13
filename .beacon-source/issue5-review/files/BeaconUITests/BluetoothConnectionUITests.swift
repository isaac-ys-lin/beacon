import XCTest

/// Existing DEBUG app-process seam: actual controls and windows, fixture observations.
final class BluetoothConnectionUITests: XCTestCase {
    @MainActor
    private func launch(_ scenario: String, settings: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [settings ? "--ui-test-open-settings" : "--ui-test-open-status-menu", "-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launchEnvironment["BEACON_SETUP_SCENARIO"] = "empty"
        app.launchEnvironment["BEACON_CONNECTION_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.windows[settings ? "Beacon Settings" : "Beacon Status Menu"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor
    private func expectState(_ app: XCUIApplication, _ address: String, _ text: String) {
        let state = app.staticTexts["connection.state.\(address)"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR label == %@", text, text), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 8), .completed)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "connection-\(address.suffix(2))-\(text)-fixture-not-hardware"
        image.lifetime = .keepAlways; add(image)
    }
    @MainActor
    func testNoBatterySameNamedHeadphonesConnectAndDisconnectOnlySelectedIdentity() {
        let app = launch("ready"); defer { app.terminate() }
        let first = "aa:bb:cc:dd:ee:01"; let second = "aa:bb:cc:dd:ee:02"
        for suffix in ["01", "02"] {
            let row = app.descendants(matching: .any)["device.row.bluetooth-aa-bb-cc-dd-ee-\(suffix)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.label.contains("No battery report"))
            XCTAssertFalse(row.label.contains("percent"))
        }
        let selected = app.buttons["connection.connect.\(second)"]
        XCTAssertTrue(selected.isEnabled); selected.click()
        XCTAssertFalse(selected.isEnabled)
        XCTAssertTrue(app.buttons["connection.connect.\(first)"].isEnabled)
        expectState(app, second, "Connection confirmed")
        XCTAssertFalse(app.staticTexts["connection.state.\(first)"].exists)
        XCTAssertTrue(app.buttons["connection.disconnect.\(second)"].isEnabled)
        app.buttons["connection.disconnect.\(second)"].click()
        expectState(app, second, "Disconnection confirmed")
        XCTAssertFalse(app.buttons["connection.disconnect.\(second)"].isEnabled)
        XCTAssertFalse(app.staticTexts["connection.state.\(first)"].exists)
    }
    @MainActor
    func testAcceptedConnectionWithoutAudioRemainsUnconfirmedWithRecovery() {
        let app = launch("audio-unverified"); defer { app.terminate() }
        let address = "aa:bb:cc:dd:ee:01"
        app.buttons["connection.connect.\(address)"].click()
        expectState(app, address, "Bluetooth connected; audio not confirmed")
        XCTAssertTrue(app.buttons["connection.check.\(address)"].isEnabled)
        XCTAssertTrue(app.buttons["connection.retry.\(address)"].isEnabled)
        XCTAssertTrue(app.buttons["Sound Settings"].exists)
        XCTAssertFalse(app.staticTexts["Connection confirmed"].exists)
        app.buttons["connection.check.\(address)"].click()
        expectState(app, address, "Bluetooth connected; audio not confirmed")
    }
    @MainActor
    func testPermissionFailureInInspectorKeepsSelectedIdentityAndRetry() {
        let app = launch("denied", settings: true); defer { app.terminate() }
        let address = "aa:bb:cc:dd:ee:02"
        let row = app.buttons["settings.device.bluetooth-aa-bb-cc-dd-ee-02"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click()
        let connect = app.buttons["connection.connect.\(address)"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5)); connect.click()
        expectState(app, address, "Bluetooth permission required")
        XCTAssertTrue(app.buttons["connection.retry.\(address)"].isEnabled)
        XCTAssertTrue(app.buttons["Privacy & Security"].exists)
        XCTAssertFalse(app.staticTexts["connection.state.aa:bb:cc:dd:ee:01"].exists)
    }
    @MainActor
    func testLinkDroppingBeforeConfirmationNeverShowsSuccess() {
        let app = launch("dropped"); defer { app.terminate() }
        let address = "aa:bb:cc:dd:ee:01"
        app.buttons["connection.connect.\(address)"].click()
        expectState(app, address, "Connection change failed")
        XCTAssertTrue(app.buttons["connection.retry.\(address)"].isEnabled)
        XCTAssertFalse(app.staticTexts["Connection confirmed"].exists)
    }
}
