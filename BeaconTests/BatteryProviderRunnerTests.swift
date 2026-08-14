import Darwin
import XCTest
@testable import Beacon

final class BatteryProviderRunnerTests: XCTestCase {
    func testRunnerDrainsStdoutAndStderrWithoutDeadlock() async throws {
        let result = try await BatteryProviderRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "i=0; while [ $i -lt 4000 ]; do echo stdout-$i; echo stderr-$i >&2; i=$((i+1)); done",
            ],
            timeout: .seconds(3)
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertGreaterThan(result.output.count, 20_000)
        XCTAssertGreaterThan(result.errorOutput.count, 20_000)
    }

    func testRunnerEscalatesPastIgnoredTERMAndReapsProcess() async throws {
        let recorder = ProcessLifecycleRecorder()
        let runner = BatteryProviderRunner(lifecycle: { pid, running in
            recorder.record(pid: pid, running: running)
        })

        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do :; done"],
            timeout: .milliseconds(100)
        )

        XCTAssertTrue(result.timedOut)
        let pid = try XCTUnwrap(recorder.startedPID)
        errno = 0
        let processProbe = Darwin.kill(pid, 0)
        let processProbeError = errno
        XCTAssertEqual(processProbe, -1)
        XCTAssertEqual(processProbeError, ESRCH)
        XCTAssertEqual(recorder.finishCount, 1)
    }

    func testCancellationClaimsCancelledReasonAndReapsProcessGroup() async throws {
        let recorder = ProcessLifecycleRecorder()
        let runner = BatteryProviderRunner(lifecycle: { pid, running in
            recorder.record(pid: pid, running: running)
        })
        let task = Task {
            try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; while :; do :; done"],
                timeout: .seconds(5)
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(result.timedOut)
        let pid = try XCTUnwrap(recorder.startedPID)
        errno = 0
        let processGroupProbe = Darwin.kill(-pid, 0)
        let processGroupProbeError = errno
        XCTAssertEqual(processGroupProbe, -1)
        XCTAssertEqual(processGroupProbeError, ESRCH)
        XCTAssertEqual(recorder.finishCount, 1)
    }

    func testRunnerKillsDescendantThatKeepsPipesOpenAfterLeaderExits() async throws {
        let recorder = ProcessLifecycleRecorder()
        let runner = BatteryProviderRunner(lifecycle: { pid, running in
            recorder.record(pid: pid, running: running)
        })
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "(trap '' TERM HUP; while :; do echo held; echo held >&2; sleep 1; done) & exit 0",
            ],
            timeout: .seconds(3)
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(2))
        let pid = try XCTUnwrap(recorder.startedPID)
        errno = 0
        let processGroupProbe = Darwin.kill(-pid, 0)
        let processGroupProbeError = errno
        XCTAssertEqual(processGroupProbe, -1)
        XCTAssertEqual(processGroupProbeError, ESRCH)
        XCTAssertEqual(recorder.finishCount, 1)
    }
}

private final class ProcessLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(pid: Int32, running: Bool)] = []

    var startedPID: Int32? {
        lock.withTestLock {
            events.first(where: { $0.running && $0.pid > 0 })?.pid
        }
    }

    var finishCount: Int {
        lock.withTestLock {
            events.filter { !$0.running }.count
        }
    }

    func record(pid: Int32, running: Bool) {
        lock.withTestLock {
            events.append((pid, running))
        }
    }
}

private extension NSLock {
    func withTestLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
