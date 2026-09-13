import XCTest

final class StatusMenuSnapshotTests: XCTestCase {
    @MainActor
    func testMenuBarAppLaunches() {
        let app = XCUIApplication()
        // A menu-bar-only app stays in the background. Expose the actual status
        // window through the existing UI-test seam instead of requiring Dock activation.
        app.launchArguments = ["--ui-test-open-status-menu", "-AppleLanguages", "(en)"]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["Beacon Status Menu"].waitForExistence(timeout: 10))
    }
}
