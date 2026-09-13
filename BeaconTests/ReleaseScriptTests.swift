import Foundation
import XCTest

/// Runs injected Python boundary tests in the existing BeaconMac suite.
/// This is not signing, notarization, Gatekeeper or installation evidence.
final class ReleaseScriptTests: XCTestCase {
    func testReleaseVerificationFailsClosedAndSeparatesEvidence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "-v", "test_release_checks.py"]
        process.currentDirectoryURL = root.appendingPathComponent("script")
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("Ran 14 tests"), text)
        XCTAssertTrue(text.contains("OK"), text)
    }
}
