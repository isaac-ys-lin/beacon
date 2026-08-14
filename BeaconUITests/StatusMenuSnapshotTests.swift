import XCTest

final class StatusMenuSnapshotTests: XCTestCase {
    @MainActor
    func testMenuBarAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
