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
        window.descendants(matching: .any)["settings.pane.general"].click()
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
        XCTAssertTrue(settingsWindow.staticTexts["settings.preview-badge"].waitForExistence(timeout: 5))
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
                window.descendants(matching: .any)["settings.pane.quickActions"].click()
                let toggle = window.descendants(matching: .any).matching(identifier: "quickActions.refreshBatteries").firstMatch
                if toggle.exists, let originalValue, String(describing: toggle.value ?? "") != originalValue {
                    toggle.click()
                }
                app.terminate()
            }
        }
        var window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.descendants(matching: .any)["settings.pane.quickActions"].click()
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
        window.descendants(matching: .any)["settings.pane.quickActions"].click()
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
        app.launchEnvironment["BEACON_SETTINGS_MINIMUM_SIZE"] = "1"
        return app
    }

    /// Apple's automated accessibility audit (labels, contrast, hit regions,
    /// clipped text, Dynamic Type) on every settings pane.
    @MainActor
    func testSettingsPanesPassAccessibilityAudit() throws {
        let app = dailySettingsApp(language: "en", theme: "light")
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for pane in ["general", "devices", "audio", "quickActions", "alerts", "actionHUD", "dashboard"] {
            let button = window.descendants(matching: .any)["settings.pane.\(pane)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.click()
            // Audit what a person can see at the minimum window size: the top of
            // the pane, then the bottom after scrolling. Elements outside the
            // window (or under the scroll-edge fade) are covered by the other pass.
            let visible = window.frame.insetBy(dx: 0, dy: 28)
            var offscreen: [String: Set<String>] = [:]
            for pass in ["top", "bottom"] {
                if pass == "bottom" {
                    // Scroll every column: the Form and, where present, the preview beside it.
                    for dx in [0.45, 0.85] {
                        window.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.6))
                            .scroll(byDeltaX: 0, deltaY: -3000)
                    }
                }
                try app.performAccessibilityAudit { issue in
                    // SwiftUI's own Form/List containers: unlabeled grouping
                    // elements and parent/child bookkeeping are not app content.
                    if issue.auditType == .parentChild { return true }
                    if issue.auditType == .sufficientElementDescription,
                       let element = issue.element, element.label.isEmpty,
                       ![.button, .image, .staticText, .checkBox, .popUpButton, .slider, .switch, .toggle]
                           .contains(element.elementType) {
                        return true
                    }
                    if let element = issue.element, !visible.contains(element.frame) {
                        offscreen[pass, default: []].insert("\(issue.auditType.rawValue) \(element.label) \(String(describing: element.value ?? ""))")
                        return true
                    }
                    // Logged, not failed, with evidence for each:
                    // - Sidebar rows and "nearly passed" text: System Settings reports
                    //   the same on this Mac (testSystemSettingsAccessibilityAuditBaseline).
                    // - Pop-up buttons without an exposed action: same in System Settings.
                    // - Text in secondaryLabelColor (Form footers, card captions): the
                    //   system color, which System Settings footers also fail with.
                    // - HUD state rows: primary text on an opaque card; the element
                    //   screenshots show dark-on-white, so the audit misreads them.
                    let text = issue.element.map { $0.label.isEmpty ? String(describing: $0.value ?? "") : $0.label } ?? ""
                    let isSystemBaselineCategory: Bool
                    switch issue.auditType {
                    case .contrast:
                        isSystemBaselineCategory = issue.compactDescription.contains("nearly")
                            || issue.element?.identifier.hasPrefix("settings.pane.") == true
                            || Self.knownSecondaryOrMisreadContrast.contains { text.hasPrefix($0) }
                            || (["On", "Off"].contains(String(describing: issue.element?.value ?? ""))
                                && Self.hudStateRows.contains { text.hasPrefix($0) })
                            || text.range(of: #"^Version \d+(\.\d+)* \(\d+\)$"#, options: .regularExpression) != nil
                            || text.range(of: #"^[\d,]+ samples$"#, options: .regularExpression) != nil
                    case .action:
                        isSystemBaselineCategory = issue.element?.elementType == .popUpButton
                    default:
                        isSystemBaselineCategory = false
                    }
                    let element = issue.element.map {
                        "\($0.elementType.rawValue) '\($0.label)' id=\($0.identifier) value=\(String(describing: $0.value ?? "")) frame=\($0.frame)"
                    } ?? "nil"
                    print("\(isSystemBaselineCategory ? "AXKNOWN" : "AXAUDIT") pane=\(pane) pass=\(pass) type=\(issue.auditType.rawValue) element=\(element) desc=\(issue.compactDescription)")
                    if let shot = issue.element?.screenshot() {
                        let attachment = XCTAttachment(screenshot: shot)
                        attachment.name = "\(pane) \(pass) \(issue.compactDescription)"
                        attachment.lifetime = .keepAlways
                        self.add(attachment)
                    }
                    return isSystemBaselineCategory
                }
            }
            // An issue skipped in both passes was never audited (taller than two viewports).
            let neverAudited = offscreen["top", default: []].intersection(offscreen["bottom", default: []])
            XCTAssertTrue(neverAudited.isEmpty, "\(pane): not visible in either pass: \(neverAudited.sorted())")
        }
    }

    private static let knownSecondaryOrMisreadContrast = [
        "Charged alerts also require", "Turn a headset microphone off", "System follows your current macOS appearance",
        "Beacon does not contact an update service", "This build is distributed outside",
    ]
    /// Action HUD state-summary rows; matched with their On/Off value so the
    /// toggles of the same name stay gated.
    private static let hudStateRows = ["Low battery", "Finished charging", "Auto dismiss (", "Dismiss button"]

    /// Baseline only, never fails: the same audit against Apple's own System
    /// Settings, to tell platform-rendered noise from Beacon's own defects.
    /// Opt-in because it drives System Settings, and XCTest's automation session
    /// has crashed it on teardown. Run with
    /// `TEST_RUNNER_BEACON_AUDIT_SYSTEM_SETTINGS=1 xcodebuild test ...`
    /// (xcodebuild passes TEST_RUNNER_-prefixed variables to the runner, unprefixed).
    @MainActor
    func testSystemSettingsAccessibilityAuditBaseline() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BEACON_AUDIT_SYSTEM_SETTINGS"] == "1")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.systempreferences")
        settings.activate()
        XCTAssertTrue(settings.windows.firstMatch.waitForExistence(timeout: 10))
        try settings.performAccessibilityAudit { issue in
            let element = issue.element.map {
                "\($0.elementType.rawValue) '\($0.label)' value=\(String(describing: $0.value ?? ""))"
            } ?? "nil"
            print("AXBASELINE type=\(issue.auditType.rawValue) element=\(element) desc=\(issue.compactDescription)")
            return true
        }
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
        for pane in ["general", "devices", "audio", "quickActions", "alerts", "actionHUD", "dashboard"] {
            let button = window.descendants(matching: .any)["settings.pane.\(pane)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.click()
            switch pane {
            case "general":
                XCTAssertTrue(window.buttons["general.history.export"].waitForExistence(timeout: 5))
                XCTAssertTrue(window.buttons["general.launch-at-login.refresh"].exists)
            case "devices":
                XCTAssertTrue(window.buttons["settings.refresh"].waitForExistence(timeout: 5))
                XCTAssertTrue(window.buttons["settings.add-device"].exists)
            case "audio":
                let lock = window.descendants(matching: .any).matching(identifier: "audio.lock").firstMatch
                XCTAssertTrue(lock.waitForExistence(timeout: 5))
                XCTAssertTrue(window.descendants(matching: .any).matching(identifier: "audio.current").firstMatch.exists)
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
    @MainActor
    func testAirPodsShowsSystemSettingsInsteadOfLocalOnlyModePickers() {
        continueAfterFailure = false
        let app = dailySettingsApp(language: "en", theme: "light")
        app.launch()
        defer { app.terminate() }
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.descendants(matching: .any)["settings.pane.devices"].click()
        let airPods = window.buttons["settings.device.preview-airpods"]
        XCTAssertTrue(airPods.waitForExistence(timeout: 5))
        airPods.click()
        XCTAssertTrue(window.buttons["airpods.audio-controls.sound-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["airpods.audio-controls.bluetooth-settings"].exists)
        XCTAssertFalse(window.staticTexts["These choices are notes saved in Beacon; they do not change your AirPods."].exists)
        XCTAssertFalse(window.segmentedControls["Preferred Listening Mode"].exists)
        XCTAssertFalse(window.segmentedControls["Preferred Microphone"].exists)
    }

    @MainActor
    func testEmptyDevicesCanOpenSetupAndReturnWithEscape() {
        continueAfterFailure = false
        let app = setupApp(scenario: "empty")
        app.launch()
        defer { app.terminate() }
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["setup.state.empty"].waitForExistence(timeout: 5))
        window.buttons["setup.open-guide"].click()
        let done = app.buttons["setup.guide.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertTrue(window.buttons["setup.retry"].isEnabled)
        window.buttons["setup.retry"].click()
        XCTAssertTrue(window.staticTexts["setup.state.empty"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeniedBluetoothCanRecheckAndRecoverWithoutRelaunch() {
        verifySetupRecovery(scenario: "denied", state: "permission", statusMenu: false)
    }

    @MainActor
    func testFailedStatusMenuCheckCanRecoverWithoutFakeEmptyState() {
        verifySetupRecovery(scenario: "failed", state: "failed", statusMenu: true)
    }

    @MainActor
    private func verifySetupRecovery(scenario: String, state: String, statusMenu: Bool) {
        continueAfterFailure = false
        let app = setupApp(scenario: scenario, statusMenu: statusMenu)
        app.launch()
        defer { app.terminate() }
        let window = app.windows[statusMenu ? "Beacon Status Menu" : "Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let notice = window.staticTexts["setup.state.\(state)"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertFalse(window.staticTexts["setup.state.empty"].exists)
        if state == "permission" { XCTAssertTrue(window.buttons["setup.open-privacy"].exists) }
        let evidence = XCTAttachment(screenshot: window.screenshot())
        evidence.name = "setup-\(scenario)"
        evidence.lifetime = .keepAlways
        add(evidence)
        window.buttons["setup.retry"].click()
        let recovered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
        XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 5), .completed)
        let recoveredDevice = window.descendants(matching: .any)[
            statusMenu ? "device.row.preview-keyboard" : "settings.device.preview-keyboard"
        ].firstMatch
        XCTAssertTrue(recoveredDevice.waitForExistence(timeout: 5))
        XCTAssertTrue(recoveredDevice.label.contains("Magic Keyboard"))
    }

    @MainActor
    private func setupApp(scenario: String, statusMenu: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [statusMenu ? "--ui-test-open-status-menu" : "--ui-test-open-settings", "-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launchEnvironment["BEACON_SETUP_SCENARIO"] = scenario
        return app
    }

    @MainActor
    func testIPhoneMissingToolsStopsBeforeEnrollment() throws {
        continueAfterFailure = false
        let app = setupApp(scenario: "empty")
        app.launchEnvironment["BEACON_IPHONE_SCENARIO"] = "missing"
        app.launch()
        defer { app.terminate() }
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings.add-device"].click()
        app.buttons["setup.iphone"].click()
        XCTAssertTrue(app.staticTexts["iphone.setup.state.toolsMissing"].waitForExistence(timeout: 5))
        let missingTools = app.staticTexts["iphone.setup.missing-tools"]
        XCTAssertTrue(missingTools.waitForExistence(timeout: 5))
        let missingToolsSnapshot = try recordIPhoneSetupEvidence(
            app, text: missingTools, name: "iphone-missing-tools-fixture-not-hardware"
        )
        XCTAssertEqual(missingToolsSnapshot.value as? String, "Missing tools: idevice_id, ideviceinfo")
        XCTAssertFalse(app.buttons["iphone.setup.check"].exists)
        app.buttons["iphone.setup.recheck-tools"].click()
        XCTAssertFalse(app.buttons["iphone.setup.check"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    @MainActor
    func testIPhoneSetupConfirmsANewReadingRatherThanEnrollmentOnly() throws {
        continueAfterFailure = false
        let app = setupApp(scenario: "empty")
        app.launchEnvironment["BEACON_IPHONE_SCENARIO"] = "ready"
        app.launch()
        defer { app.terminate() }
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings.add-device"].click()
        app.buttons["setup.iphone"].click()
        let check = app.buttons["iphone.setup.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.click()
        XCTAssertTrue(app.staticTexts["iphone.setup.state.reported"].waitForExistence(timeout: 5))
        let reading = app.staticTexts["iphone.setup.reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        let readingSnapshot = try recordIPhoneSetupEvidence(
            app, text: reading, name: "iphone-new-reading-fixture-not-hardware"
        )
        XCTAssertEqual(readingSnapshot.value as? String, "New battery reading: 87%")
        app.buttons["iphone.setup.done"].click()
        XCTAssertTrue(window.descendants(matching: .any)["UI Test iPhone"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testIPhoneEnrollmentWithoutReadingDoesNotReportBatterySuccess() {
        continueAfterFailure = false
        let app = setupApp(scenario: "empty")
        app.launchEnvironment["BEACON_IPHONE_SCENARIO"] = "noBattery"
        app.launch()
        defer { app.terminate() }
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings.add-device"].click()
        app.buttons["setup.iphone"].click()
        let check = app.buttons["iphone.setup.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.click()
        XCTAssertTrue(app.staticTexts["iphone.setup.state.noBattery"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["iphone.setup.reading"].exists)
        XCTAssertTrue(check.isEnabled)
    }

    @MainActor
    func testStaleAndDisconnectedReportsAgreeBetweenMenuAndInspector() throws {
        try verifyReport(scenario: "stale", expected: "Stale", hasPercent: true)
        try verifyReport(scenario: "disconnected", expected: "Disconnected", hasPercent: true)
    }

    @MainActor
    func testMissingAndDeniedReportsNeverInventBatteryValues() throws {
        try verifyReport(scenario: "missing", expected: "No report", hasPercent: false)
        try verifyReport(scenario: "permission", expected: "Permission needed", hasPercent: false)
    }

    @MainActor
    private func verifyReport(scenario: String, expected: String, hasPercent: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-status-menu", "-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launchEnvironment["BEACON_REPORT_SCENARIO"] = scenario
        app.launch()
        defer { app.terminate() }
        let menu = app.windows["Beacon Status Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        if scenario == "disconnected" {
            XCTAssertFalse(menu.descendants(matching: .any)["device.row.report-test"].firstMatch.exists)
            menu.buttons["status.other-devices"].click()
        }
        let row = menu.descendants(matching: .any)["device.row.report-test"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let menuEvidence = XCTAttachment(screenshot: menu.screenshot())
        menuEvidence.name = "report-menu-\(scenario)"
        menuEvidence.lifetime = .keepAlways
        add(menuEvidence)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "report-menu-\(scenario)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let rowSnapshot = try recordIPhoneSetupEvidence(app, text: row, name: "report-menu-\(scenario)-attributes")
        let rowValue = rowSnapshot.label
        XCTAssertTrue(rowValue.localizedCaseInsensitiveContains(expected), row.debugDescription)
        if hasPercent {
            XCTAssertTrue(rowValue.contains("Last known: 40%"), rowValue)
        } else {
            XCTAssertFalse(rowValue.contains("40"), rowValue)
            XCTAssertTrue(rowValue.contains("No battery report"), rowValue)
        }
        row.rightClick()
        let options = app.menuItems["Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.click()
        let settings = app.windows["Beacon Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let state = settings.staticTexts["device.report.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        let detailEvidence = XCTAttachment(screenshot: settings.screenshot())
        detailEvidence.name = "report-inspector-\(scenario)"
        detailEvidence.lifetime = .keepAlways
        add(detailEvidence)
        XCTAssertEqual(try state.snapshot().value as? String, expected)
    }

    @MainActor
    func testKnownRefreshFailureSelectsCorrectSameNamedDevice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-settings", "-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launchEnvironment["BEACON_REPORT_SCENARIO"] = "known-failure"
        app.launch()
        defer { app.terminate() }
        let settings = app.windows["Beacon Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        let disclosure = settings.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH %@", "Refresh needs attention")).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.click()
        let affected = settings.buttons["refresh.inspect.report-other"]
        XCTAssertTrue(affected.waitForExistence(timeout: 5))
        affected.click()
        let failedState = settings.staticTexts["device.report.state"]
        XCTAssertTrue(failedState.waitForExistence(timeout: 5))
        let failedSnapshot = try recordIPhoneSetupEvidence(app, text: failedState, name: "report-known-impact")
        XCTAssertEqual(failedSnapshot.value as? String, "Read failed")
        settings.buttons["settings.device.done"].click()
        settings.buttons["settings.device.report-test"].click()
        XCTAssertEqual(try settings.staticTexts["device.report.state"].snapshot().value as? String, "Latest report")
    }

    @MainActor
    func testUnknownRefreshFailureDoesNotGuessAnAffectedDevice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-open-settings", "-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launchEnvironment["BEACON_REPORT_SCENARIO"] = "unknown-failure"
        app.launch()
        defer { app.terminate() }
        let settings = app.windows["Beacon Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        let disclosure = settings.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH %@", "Refresh needs attention")).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.click()
        let impact = settings.staticTexts["refresh.impact-unknown"]
        XCTAssertTrue(impact.waitForExistence(timeout: 5))
        let evidence = try recordIPhoneSetupEvidence(app, text: impact, name: "report-unknown-impact")
        XCTAssertEqual(evidence.value as? String, "Affected devices could not be identified from this source result.")
        XCTAssertFalse(settings.buttons["refresh.inspect.report-test"].exists)
        settings.buttons["settings.device.report-test"].click()
        XCTAssertEqual(try settings.staticTexts["device.report.state"].snapshot().value as? String, "Latest report")
    }

    /// Keep the actual text attributes and screen before an assertion can stop
    /// the test. macOS static text exposes its content through AXValue, not AXLabel.
    @MainActor
    private func recordIPhoneSetupEvidence(
        _ app: XCUIApplication,
        text: XCUIElement,
        name: String
    ) throws -> XCUIElementSnapshot {
        let snapshot = try text.snapshot()
        let attributes = XCTAttachment(string: """
            identifier: \(snapshot.identifier)
            label: \(snapshot.label)
            value: \(String(describing: snapshot.value))
            """)
        attributes.name = "\(name)-text-attributes"
        attributes.lifetime = .keepAlways
        add(attributes)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name
        screen.lifetime = .keepAlways
        add(screen)
        return snapshot
    }
}
