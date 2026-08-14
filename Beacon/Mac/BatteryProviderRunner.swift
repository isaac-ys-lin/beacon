import Darwin
import Foundation

struct BatteryProviderProcessResult: Sendable {
    let terminationStatus: Int32
    let output: Data
    let errorOutput: Data
    let timedOut: Bool
    let wasCancelled: Bool

    var succeeded: Bool {
        terminationStatus == 0 && !timedOut && !wasCancelled
    }
}

enum BatteryProviderRunnerError: Error {
    case launchFailed
}

/// Runs command-line providers inside an owned process group.
///
/// The process group lets timeout/cancellation terminate descendants as well as
/// the provider leader. Both pipes are drained while the provider is running;
/// a bounded post-exit fallback cleans up descendants that retain either pipe.
struct BatteryProviderRunner: Sendable {
    static let terminationGrace: Duration = .milliseconds(250)
    private static let pipeDrainGrace: Duration = .milliseconds(250)

    private let lifecycle: @Sendable (Int32, Bool) -> Void

    init(lifecycle: @escaping @Sendable (Int32, Bool) -> Void = { _, _ in }) {
        self.lifecycle = lifecycle
    }

    func run(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> BatteryProviderProcessResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        let outputTask = Self.makeDrainTask(for: outputHandle)
        let errorTask = Self.makeDrainTask(for: errorHandle)

        let pid: pid_t
        do {
            pid = try Self.spawn(
                executableURL: executableURL,
                arguments: arguments,
                outputPipe: outputPipe,
                errorPipe: errorPipe
            )
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            outputHandle.closeFile()
            errorHandle.closeFile()
            throw BatteryProviderRunnerError.launchFailed
        }

        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()
        lifecycle(pid, true)

        let state = BatteryProviderProcessState()
        let waitTask = Task.detached(priority: .utility) {
            let status = Self.waitForProcess(pid)
            state.finish(status: status)
            return status
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
                state.beginStop(reason: .timedOut) {
                    await Self.terminateProcessGroup(pid)
                }
            } catch {
                // Normal completion cancels the deadline task.
            }
        }

        let status = await withTaskCancellationHandler {
            await waitTask.value
        } onCancel: {
            // Claim cancellation synchronously. The lock decides whether normal
            // completion, timeout, or cancellation owns the terminal reason.
            state.beginStop(reason: .cancelled) {
                await Self.terminateProcessGroup(pid)
            }
        }
        timeoutTask.cancel()
        _ = await timeoutTask.value
        await state.waitForStopCompletion()
        lifecycle(pid, false)

        let drains = Task {
            let output = await outputTask.value
            let errorOutput = await errorTask.value
            return (output, errorOutput)
        }
        let drained = await Self.value(of: drains, before: Self.pipeDrainGrace)
        let output: Data
        let errorOutput: Data
        if let drained {
            (output, errorOutput) = drained
        } else {
            // A normally-exited leader can leave descendants holding inherited
            // stdout/stderr. Reap the owned group before force-closing the pipes.
            await Self.terminateProcessGroup(pid)
            outputHandle.closeFile()
            errorHandle.closeFile()
            let finalDrain = await Self.value(of: drains, before: Self.pipeDrainGrace)
            output = finalDrain?.0 ?? Data()
            errorOutput = finalDrain?.1 ?? Data()
        }

        return BatteryProviderProcessResult(
            terminationStatus: status,
            output: output,
            errorOutput: errorOutput,
            timedOut: state.stopReason == .timedOut,
            wasCancelled: state.stopReason == .cancelled
        )
    }

    private static func spawn(
        executableURL: URL,
        arguments: [String],
        outputPipe: Pipe,
        errorPipe: Pipe
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw BatteryProviderRunnerError.launchFailed
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        let outputRead = outputPipe.fileHandleForReading.fileDescriptor
        let outputWrite = outputPipe.fileHandleForWriting.fileDescriptor
        let errorRead = errorPipe.fileHandleForReading.fileDescriptor
        let errorWrite = errorPipe.fileHandleForWriting.fileDescriptor
        posix_spawn_file_actions_addclose(&fileActions, outputRead)
        posix_spawn_file_actions_addclose(&fileActions, errorRead)
        posix_spawn_file_actions_adddup2(&fileActions, outputWrite, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errorWrite, STDERR_FILENO)
        if outputWrite != STDOUT_FILENO {
            posix_spawn_file_actions_addclose(&fileActions, outputWrite)
        }
        if errorWrite != STDERR_FILENO {
            posix_spawn_file_actions_addclose(&fileActions, errorWrite)
        }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw BatteryProviderRunnerError.launchFailed
        }
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        guard posix_spawnattr_setflags(&attributes, flags) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0
        else {
            throw BatteryProviderRunnerError.launchFailed
        }

        let executablePath = executableURL.path
        var argv = ([executablePath] + arguments).map { strdup($0) } + [nil]
        defer {
            for case let pointer? in argv {
                free(pointer)
            }
        }

        var pid: pid_t = 0
        let spawnStatus = argv.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(
                &pid,
                executablePath,
                &fileActions,
                &attributes,
                buffer.baseAddress!,
                environ
            )
        }
        guard spawnStatus == 0, pid > 0 else {
            throw BatteryProviderRunnerError.launchFailed
        }
        return pid
    }

    private static func makeDrainTask(for handle: FileHandle) -> Task<Data, Never> {
        Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }
    }

    private static func waitForProcess(_ pid: pid_t) -> Int32 {
        var rawStatus: Int32 = 0
        while waitpid(pid, &rawStatus, 0) == -1 {
            guard errno == EINTR else { return -1 }
        }
        let signal = rawStatus & 0x7f
        return signal == 0 ? (rawStatus >> 8) & 0xff : signal
    }

    private static func terminateProcessGroup(_ processGroupID: pid_t) async {
        guard processGroupID > 0, processGroupExists(processGroupID) else { return }
        Darwin.kill(-processGroupID, SIGTERM)
        try? await Task.sleep(for: terminationGrace)
        if processGroupExists(processGroupID) {
            Darwin.kill(-processGroupID, SIGKILL)
        }
        // Descendants are reparented when the leader exits. Give launchd a
        // bounded window to reap them so no empty/zombie process group leaks
        // past the runner boundary.
        for _ in 0..<25 where processGroupExists(processGroupID) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func processGroupExists(_ processGroupID: pid_t) -> Bool {
        errno = 0
        return Darwin.kill(-processGroupID, 0) == 0 || errno == EPERM
    }

    private static func value<Value: Sendable>(
        of task: Task<Value, Never>,
        before timeout: Duration
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            let gate = BatteryProviderValueGate<Value>(continuation: continuation)
            Task {
                gate.resume(returning: await task.value)
            }
            Task {
                do {
                    try await Task.sleep(for: timeout)
                    gate.resume(returning: nil)
                } catch {
                    // The race tasks are intentionally short-lived and local.
                }
            }
        }
    }
}

private enum BatteryProviderStopReason: Sendable {
    case timedOut
    case cancelled
}

private final class BatteryProviderProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var completedStatus: Int32?
    private var reason: BatteryProviderStopReason?
    private var stopTask: Task<Void, Never>?

    var stopReason: BatteryProviderStopReason? {
        lock.withLock { reason }
    }

    func finish(status: Int32) {
        lock.withLock {
            guard completedStatus == nil else { return }
            completedStatus = status
        }
    }

    @discardableResult
    func beginStop(
        reason: BatteryProviderStopReason,
        action: @escaping @Sendable () async -> Void
    ) -> Bool {
        lock.withLock {
            guard completedStatus == nil, self.reason == nil else { return false }
            self.reason = reason
            stopTask = Task { await action() }
            return true
        }
    }

    func waitForStopCompletion() async {
        let task = lock.withLock { stopTask }
        await task?.value
    }
}

private final class BatteryProviderValueGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value?, Never>? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
