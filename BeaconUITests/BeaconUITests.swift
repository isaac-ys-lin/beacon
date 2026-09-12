import XCTest

/// Exercises the real app using the existing process-level preview fixture.
final class BeaconUITests: XCTestCase {
    @MainActor
    func testGeneralRecoveryAndSupportEntrypoints() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-settings", "-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launch()
        defer { app.terminate() }
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["General"].click()
        let refresh = window.buttons["general.launch-at-login.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["general.launch-at-login.settings"].exists)
        refresh.click()
        let status = window.staticTexts["general.launch-at-login.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(["Disabled", "Enabled", "Needs Approval", "Unavailable"].contains(status.value as? String ?? status.label))
        for identifier in ["general.releases", "general.support", "general.local-data"] {
            XCTAssertTrue(window.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists)
        }
        let evidence = XCTAttachment(screenshot: window.screenshot())
        evidence.name = "general-recovery-and-support"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testSettingsSmoke() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-settings"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launch()
        defer { app.terminate() }
        let settingsWindow = app.windows["Beacon Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(settingsWindow.staticTexts["Preview data is active"].waitForExistence(timeout: 5))
        let refreshButton = settingsWindow.buttons["settings.refresh"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
        XCTAssertTrue(refreshButton.isEnabled)
        refreshButton.click()
        XCTAssertTrue(settingsWindow.exists)
    }

    @MainActor
    func testStatusMenuClosesWithEscape() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-status-menu"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launch()
        defer { app.terminate() }
        let statusMenu = app.windows["Beacon Status Menu"]
        XCTAssertTrue(statusMenu.waitForExistence(timeout: 10))
        app.typeKey(.escape, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: statusMenu)
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
        let hud = app.windows["Beacon HUD Preview"]
        XCTAssertTrue(hud.waitForExistence(timeout: 10))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hud)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
    }

    @MainActor
    func testQuickActionSettingSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = dailySettingsApp(language: "en", theme: "light")
        app.launch()
        var originalValue: String?
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                let window = app.windows.firstMatch
                window.buttons["settings.pane.quickActions"].click()
                let toggle = window.descendants(matching: .any).matching(identifier: "quickActions.refreshBatteries").firstMatch
                if toggle.exists, let originalValue, String(describing: toggle.value ?? "") != originalValue {
                    toggle.click()
                }
                app.terminate()
            }
        }
        var window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings.pane.quickActions"].click()
        var toggle = window.descendants(matching: .any).matching(identifier: "quickActions.refreshBatteries").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Refresh Batteries")
        originalValue = String(describing: try XCTUnwrap(toggle.value))
        toggle.click()
        let changedValue = String(describing: try XCTUnwrap(toggle.value))
        XCTAssertNotEqual(changedValue, originalValue)
        XCTAssertFalse(window.descendants(matching: .any).matching(identifier: "quickActions.transferToMac").firstMatch.exists)
        app.terminate()
        app.launch()
        window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings.pane.quickActions"].click()
        toggle = window.descendants(matching: .any).matching(identifier: "quickActions.refreshBatteries").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(String(describing: try XCTUnwrap(toggle.value)), changedValue)
    }

    @MainActor func testDailySettingsEnglishLight() { checkDailySettings(language: "en", theme: "light") }
    @MainActor func testDailySettingsEnglishDark() { checkDailySettings(language: "en", theme: "dark") }
    @MainActor func testDailySettingsTraditionalChineseLight() { checkDailySettings(language: "zh-Hant-TW", theme: "light") }
    @MainActor func testDailySettingsTraditionalChineseDark() { checkDailySettings(language: "zh-Hant-TW", theme: "dark") }

    @MainActor
    private func dailySettingsApp(language: String, theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-settings", "-AppleLanguages", "(\(language))", "-Beacon.appearanceTheme", theme]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        return app
    }

    @MainActor
    private func checkDailySettings(language: String, theme: String) {
        continueAfterFailure = false
        let app = dailySettingsApp(language: language, theme: theme)
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let isChinese = language == "zh-Hant-TW"
        for pane in ["quickActions", "alerts", "actionHUD", "dashboard"] {
            let button = window.buttons["settings.pane.\(pane)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.click()
            switch pane {
            case "quickActions":
                let toggle = window.descendants(matching: .any).matching(identifier: "quickActions.showDashboard").firstMatch
                XCTAssertTrue(toggle.waitForExistence(timeout: 5))
                XCTAssertEqual(toggle.label, isChinese ? "顯示儀表板" : "Show Dashboard")
                XCTAssertFalse(window.staticTexts[isChinese ? "傳送到另一台 Mac" : "Transfer to Another Mac"].exists)
            case "alerts":
                XCTAssertTrue(window.descendants(matching: .any).matching(identifier: "alerts.global.low").firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(window.staticTexts[isChinese ? "所有裝置" : "All Devices"].exists)
            case "actionHUD":
                let toggle = window.descendants(matching: .any).matching(identifier: "hud.settings.low-battery").firstMatch
                XCTAssertTrue(toggle.waitForExistence(timeout: 5))
                XCTAssertEqual(toggle.label, isChinese ? "低電量" : "Low battery")
            default:
                let provenance = window.staticTexts["dashboard.preview.provenance"]
                XCTAssertTrue(provenance.waitForExistence(timeout: 5))
                XCTAssertEqual(provenance.value as? String ?? provenance.label, isChinese ? "範例預覽" : "Sample Preview")
            }
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = "daily-settings-\(language)-\(theme)-\(pane)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
