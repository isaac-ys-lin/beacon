import XCTest

final class StatusMenuSnapshotTests: XCTestCase {
    func testMenuBarAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
