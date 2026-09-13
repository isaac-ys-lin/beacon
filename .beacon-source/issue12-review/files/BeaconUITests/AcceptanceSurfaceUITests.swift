import Foundation
import XCTest

/// Native windows and controls with explicitly synthetic process input.
/// Not VoiceOver, real-device, signing or clean-Mac acceptance evidence.
final class AcceptanceSurfaceUITests: XCTestCase {
    @MainActor
    private func app(arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launchEnvironment["BEACON_SETUP_SCENARIO"] = "empty"
        app.launchEnvironment["BEACON_SETTINGS_MINIMUM_SIZE"] = "1"
        return app
    }

    @MainActor
    private func absent(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed)
    }

    @MainActor
    private func evidence(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name + "-fixture-not-hardware"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testNativeExportCancelDoesNotClaimSuccessThenSaveWritesReadableCSV() throws {
        let app = app(arguments: ["--ui-test-open-settings"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("beacon-export-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        app.launch()
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings.pane.general"].click()
        let export = window.buttons["general.history.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.click()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        evidence(app.windows.firstMatch, name: "native-history-save-panel")
        cancel.click()
        absent(cancel)
        XCTAssertFalse(window.staticTexts["Battery history exported."].exists)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        export.click()
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // Exercise the standard save panel's Go to Folder UI, not an injected output URL.
        app.typeKey("g", modifierFlags: [.command, .shift])
        let go = app.buttons["Go"].firstMatch
        XCTAssertTrue(go.waitForExistence(timeout: 5))
        app.typeKey("a", modifierFlags: .command)
        app.typeText(directory.path)
        go.click()
        absent(go)
        XCTAssertTrue(save.isEnabled)
        save.click()
        absent(save)
        let file = directory.appendingPathComponent("Beacon Battery History.csv")
        let written = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: file.path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [written], timeout: 5), .completed)
        let csv = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(csv.hasPrefix("device_id,recorded_at,percent,charge_state,source\n"))
        XCTAssertTrue(csv.hasSuffix("\n"))
        let result = window.staticTexts["general.operation-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.value as? String ?? result.label, "Battery history exported.")
        evidence(window, name: "native-history-export-confirmed")
    }

    @MainActor
    func testSettingsCommandWClosesTheActualWindow() {
        let app = app(arguments: ["--ui-test-open-settings"])
        app.launch(); defer { app.terminate() }
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings.pane.general"].click()
        app.typeKey("w", modifierFlags: .command)
        absent(window)
    }

    @MainActor func testNativeDesktopCompactRoutesToDashboard() { checkDesktop(style: "compact", width: 256) }
    @MainActor func testNativeDesktopExpandedRoutesToDashboard() { checkDesktop(style: "expanded", width: 318) }

    @MainActor
    private func checkDesktop(style: String, width: CGFloat) {
        let app = app(arguments: ["--ui-test-show-desktop", "-Beacon.desktopWidget.show", "YES",
                                  "-Beacon.desktopWidget.style", style])
        app.launch(); defer { app.terminate() }
        let widget = app.windows["Beacon Desktop Widget"]
        XCTAssertTrue(widget.waitForExistence(timeout: 10))
        XCTAssertEqual(widget.frame.width, width, accuracy: 2)
        let reportTime = widget.staticTexts["desktop.report-time"]
        XCTAssertTrue(reportTime.waitForExistence(timeout: 5))
        XCTAssertEqual(reportTime.value as? String ?? reportTime.label, "No reports")
        let settings = widget.buttons["Open Beacon Settings"]
        XCTAssertTrue(settings.isHittable)
        evidence(widget, name: "native-desktop-" + style)
        settings.click()
        let window = app.windows["Beacon Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let provenance = window.staticTexts["dashboard.preview.provenance"]
        XCTAssertTrue(provenance.waitForExistence(timeout: 5))
        XCTAssertEqual(provenance.value as? String ?? provenance.label, "Sample Preview")
        XCTAssertTrue(widget.exists)
    }
}
