import Darwin
import Dispatch
import Foundation
import PasteraAgentProtocol

// This file keeps the pipe, process and cancellation state machine together for auditability.
// swiftlint:disable file_length

public enum VaultAgentCommandRunnerError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    LocalizedError {
    case broker(VaultAgentFailure)
    case invalidResponse
    case spawnFailed
    case writeFailed
    case waitFailed
    case transportFailure
    case cancelled

    public var description: String { stableDescription }
    public var debugDescription: String { stableDescription }
    public var errorDescription: String? { stableDescription }

    private var stableDescription: String {
        switch self {
        case let .broker(failure): "broker(\(failure.code.rawValue))"
        case .invalidResponse: "invalidResponse"
        case .spawnFailed: "spawnFailed"
        case .writeFailed: "writeFailed"
        case .waitFailed: "waitFailed"
        case .transportFailure: "transportFailure"
        case .cancelled: "cancelled"
        }
    }
}

public struct VaultAgentCommandRunner: Sendable {
    enum Event: Sendable {
        case spawned(pid_t)
        case secretWritten
    }

    struct PipeEndpoints: Sendable {
        let read: Int32
        let write: Int32
    }

    struct Dependencies: @unchecked Sendable {
        var makePipe: @Sendable () throws -> PipeEndpoints
        var spawn: @Sendable ([String], VaultAgentCommandInput, PipeEndpoints, [String: String]) throws -> pid_t
        var writeChunk: @Sendable (Int32, Data, Int) throws -> Int
        var makeWaiter: @Sendable (
            pid_t,
            @escaping @Sendable () -> Void,
            @escaping @Sendable () -> Void
        ) -> any VaultAgentProcessWaiting
        var close: @Sendable (Int32) -> Void
        var terminate: @Sendable (pid_t) -> Void
        var kill: @Sendable (pid_t) -> Void
        var environment: [String: String]
        var onEvent: @Sendable (Event) -> Void

        static let live = Self(
            makePipe: VaultAgentCommandRunner.makePipe,
            spawn: VaultAgentCommandRunner.spawn,
            writeChunk: VaultAgentCommandRunner.writeChunk,
            makeWaiter: {
                VaultAgentProcessWaiter(
                    processID: $0,
                    onExitObserved: $1,
                    onReaped: $2
                )
            },
            close: { _ = Darwin.close($0) },
            terminate: { _ = Darwin.kill($0, SIGTERM) },
            kill: { _ = Darwin.kill($0, SIGKILL) },
            environment: ProcessInfo.processInfo.environment,
            onEvent: { _ in }
        )
    }

    private static let workQueue = DispatchQueue(
        label: "com.pastera-app.agent.command-runner",
        qos: .userInitiated
    )

    private let client: any VaultAgentRequesting
    private let dependencies: Dependencies

    public init(client: any VaultAgentRequesting) {
        self.client = client
        dependencies = .live
    }

    init(client: any VaultAgentRequesting, dependencies: Dependencies) {
        self.client = client
        self.dependencies = dependencies
    }

    public func run(
        ticket: String,
        input: VaultAgentCommandInput,
        command: [String]
    ) async throws -> Int {
        guard Self.isValid(ticket: ticket, input: input, command: command) else {
            throw VaultAgentCommandRunnerError.invalidResponse
        }
        let state = VaultAgentCommandState(
            dependencies: dependencies,
            operationQueue: Self.workQueue
        )
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let delivery = try await redeem(ticket: ticket, mode: input.injectionMode)
                guard delivery.bytes.count <= VaultAgentLimits.maximumSecretBytes else {
                    throw VaultAgentCommandRunnerError.invalidResponse
                }
                try Task.checkCancellation()
                let waiter = try await spawn(command: command, input: input, state: state)
                do {
                    var bytes = delivery.bytes
                    if input == .standardInput { bytes.append(0x0a) }
                    try await VaultAgentPipeWriter(
                        data: bytes,
                        state: state,
                        dependencies: dependencies,
                        queue: Self.workQueue
                    ).write()
                    try Task.checkCancellation()
                    let completeResult = await complete(receiptID: delivery.receiptID)
                    let exitResult = await waitForExit(waiter, state: state)
                    try Task.checkCancellation()
                    if let completeError = completeResult { throw completeError }
                    return try exitResult.get()
                } catch {
                    state.cancelProcess()
                    _ = await waitForExit(waiter, state: state)
                    throw normalized(error)
                }
            } catch {
                throw normalized(error)
            }
        } onCancel: {
            state.cancelProcess()
        }
    }

    private func redeem(
        ticket: String,
        mode: VaultAgentInjectionMode
    ) async throws -> VaultAgentSecretDelivery {
        let response: VaultAgentResponseBody
        do {
            response = try await client.request(.redeemTicket(token: ticket, mode: mode))
        } catch {
            throw normalized(error)
        }
        switch response {
        case let .success(.secretDelivery(delivery)): return delivery
        case let .failure(failure): throw VaultAgentCommandRunnerError.broker(failure)
        default: throw VaultAgentCommandRunnerError.invalidResponse
        }
    }

    private func complete(receiptID: UUID) async -> VaultAgentCommandRunnerError? {
        do {
            switch try await client.request(.completeTicket(receiptID: receiptID)) {
            case .success(.status): return nil
            case let .failure(failure): return .broker(failure)
            default: return .invalidResponse
            }
        } catch {
            return normalized(error)
        }
    }

    private func spawn(
        command: [String],
        input: VaultAgentCommandInput,
        state: VaultAgentCommandState
    ) async throws -> any VaultAgentProcessWaiting {
        try await withCheckedThrowingContinuation { continuation in
            Self.workQueue.async {
                do {
                    try state.checkCancellation()
                    let pipe = try dependencies.makePipe()
                    guard state.adoptWrite(pipe.write) else {
                        dependencies.close(pipe.read)
                        throw VaultAgentCommandRunnerError.cancelled
                    }
                    let processID: pid_t
                    do {
                        processID = try dependencies.spawn(command, input, pipe, dependencies.environment)
                    } catch {
                        dependencies.close(pipe.read)
                        state.closeWrite()
                        throw error
                    }
                    dependencies.close(pipe.read)
                    state.adoptProcess(processID)
                    let waiter = dependencies.makeWaiter(
                        processID,
                        state.markExitObserved,
                        state.markReaped
                    )
                    dependencies.onEvent(.spawned(processID))
                    continuation.resume(returning: waiter)
                } catch {
                    continuation.resume(throwing: normalized(error))
                }
            }
        }
    }

    private func waitForExit(
        _ waiter: any VaultAgentProcessWaiting,
        state: VaultAgentCommandState
    ) async -> Result<Int, VaultAgentCommandRunnerError> {
        do {
            let status = try await waiter.wait()
            return .success(status)
        } catch {
            return .failure(normalized(error))
        }
    }

    private static func makePipe() throws -> PipeEndpoints {
        var raw = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&raw) == 0 else { throw VaultAgentCommandRunnerError.spawnFailed }
        guard Darwin.fcntl(raw[0], F_SETFD, FD_CLOEXEC) == 0,
              Darwin.fcntl(raw[1], F_SETFD, FD_CLOEXEC) == 0 else {
            Darwin.close(raw[0])
            Darwin.close(raw[1])
            throw VaultAgentCommandRunnerError.spawnFailed
        }

        let highRead = Darwin.fcntl(raw[0], F_DUPFD_CLOEXEC, 256)
        let highWrite = Darwin.fcntl(raw[1], F_DUPFD_CLOEXEC, 256)
        Darwin.close(raw[0])
        Darwin.close(raw[1])
        guard highRead >= 256, highWrite >= 256 else {
            if highRead >= 0 { Darwin.close(highRead) }
            if highWrite >= 0 { Darwin.close(highWrite) }
            throw VaultAgentCommandRunnerError.spawnFailed
        }
        let flags = Darwin.fcntl(highWrite, F_GETFL)
        guard flags >= 0,
              Darwin.fcntl(highWrite, F_SETFL, flags | O_NONBLOCK) == 0,
              Darwin.fcntl(highWrite, F_SETNOSIGPIPE, 1) == 0 else {
            Darwin.close(highRead)
            Darwin.close(highWrite)
            throw VaultAgentCommandRunnerError.spawnFailed
        }
        return PipeEndpoints(read: highRead, write: highWrite)
    }

    private static func spawn(
        command: [String],
        input: VaultAgentCommandInput,
        pipe: PipeEndpoints,
        environment: [String: String]
    ) throws -> pid_t {
        guard let executable = command.first else { throw VaultAgentCommandRunnerError.spawnFailed }
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            throw VaultAgentCommandRunnerError.spawnFailed
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw VaultAgentCommandRunnerError.spawnFailed
        }
        defer { posix_spawnattr_destroy(&attributes) }
        var defaultSignals = sigset_t()
        var signalMask = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGTERM)
        sigaddset(&defaultSignals, SIGPIPE)
        sigemptyset(&signalMask)
        let spawnFlags = Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        guard posix_spawnattr_setsigdefault(&attributes, &defaultSignals) == 0,
              posix_spawnattr_setsigmask(&attributes, &signalMask) == 0,
              posix_spawnattr_setflags(&attributes, spawnFlags) == 0 else {
            throw VaultAgentCommandRunnerError.spawnFailed
        }
        let target: Int32
        switch input {
        case .standardInput: target = STDIN_FILENO
        case let .fileDescriptor(value): target = value
        }
        guard posix_spawn_file_actions_adddup2(&actions, pipe.read, target) == 0,
              posix_spawn_file_actions_addclose(&actions, pipe.read) == 0,
              posix_spawn_file_actions_addclose(&actions, pipe.write) == 0 else {
            throw VaultAgentCommandRunnerError.spawnFailed
        }

        let environmentValues = environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }
        return try withCStringArray(command) { arguments in
            try withCStringArray(environmentValues) { environmentPointers in
                var processID: pid_t = 0
                let result = executable.withCString { path in
                    posix_spawnp(
                        &processID,
                        path,
                        &actions,
                        &attributes,
                        arguments,
                        environmentPointers
                    )
                }
                guard result == 0 else { throw VaultAgentCommandRunnerError.spawnFailed }
                return processID
            }
        }
    }

    private static func writeChunk(
        fileDescriptor: Int32,
        data: Data,
        offset: Int
    ) throws -> Int {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return 0 }
            let result = Darwin.write(
                fileDescriptor,
                baseAddress.advanced(by: offset),
                data.count - offset
            )
            if result >= 0 { return result }
            if errno == EINTR { throw VaultAgentCommandWriteError.interrupted }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw VaultAgentCommandWriteError.wouldBlock
            }
            throw VaultAgentCommandRunnerError.writeFailed
        }
    }

    private static func isValid(
        ticket: String,
        input: VaultAgentCommandInput,
        command: [String]
    ) -> Bool {
        let ticketBytes = ticket.utf8.count
        guard ticketBytes > 0, ticketBytes <= VaultAgentLimits.maximumTokenBytes,
              !ticket.contains("\0"),
              !command.isEmpty,
              command.count <= VaultAgentLimits.maximumCommandArguments,
              command.first?.isEmpty == false else { return false }
        if case let .fileDescriptor(value) = input, !(3...255).contains(value) { return false }
        return command.allSatisfy {
            $0.utf8.count <= VaultAgentLimits.maximumCommandArgumentBytes && !$0.contains("\0")
        }
    }
}

private enum VaultAgentCommandWriteError: Error {
    case interrupted
    case wouldBlock
}

protocol VaultAgentProcessWaiting: Sendable {
    func wait() async throws -> Int
}

typealias VaultAgentWaitProcess = @Sendable (
    pid_t,
    UnsafeMutablePointer<Int32>?,
    Int32
) -> pid_t

final class VaultAgentProcessWaiter: VaultAgentProcessWaiting, @unchecked Sendable {
    private static let waitQueue = DispatchQueue(
        label: "com.pastera-app.agent.command-wait",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private let source: DispatchSourceProcess
    private let onExitObserved: @Sendable () -> Void
    private let onReaped: @Sendable () -> Void
    private let waitProcess: VaultAgentWaitProcess
    private var result: Result<Int, VaultAgentCommandRunnerError>?
    private var continuation: CheckedContinuation<Int, Error>?

    init(
        processID: pid_t,
        onExitObserved: @escaping @Sendable () -> Void,
        onReaped: @escaping @Sendable () -> Void,
        waitProcess: @escaping VaultAgentWaitProcess = { Darwin.waitpid($0, $1, $2) }
    ) {
        self.onExitObserved = onExitObserved
        self.onReaped = onReaped
        self.waitProcess = waitProcess
        source = DispatchSource.makeProcessSource(
            identifier: processID,
            eventMask: .exit,
            queue: Self.waitQueue
        )
        source.setEventHandler { [weak self] in self?.processExited(processID) }
        source.resume()
    }

    func wait() async throws -> Int {
        try await withCheckedThrowingContinuation { newContinuation in
            let existing = lock.withLock { () -> Result<Int, VaultAgentCommandRunnerError>? in
                if let result { return result }
                continuation = newContinuation
                return nil
            }
            if let existing { newContinuation.resume(with: existing.mapError { $0 as Error }) }
        }
    }

    private func processExited(_ processID: pid_t) {
        onExitObserved()
        var rawStatus: Int32 = 0
        var waited: pid_t
        var waitError: Int32
        repeat {
            waited = waitProcess(processID, &rawStatus, 0)
            waitError = errno
        } while waited == -1 && waitError == EINTR
        let outcome: Result<Int, VaultAgentCommandRunnerError>
        if waited == processID {
            onReaped()
            let signal = Int(rawStatus & 0x7f)
            outcome = signal == 0
                ? .success(Int((rawStatus >> 8) & 0xff))
                : .success(128 + signal)
        } else if waited == -1, waitError == ECHILD {
            onReaped()
            outcome = .failure(.waitFailed)
        } else {
            outcome = .failure(.waitFailed)
        }
        let pending = lock.withLock { () -> CheckedContinuation<Int, Error>? in
            guard result == nil else { return nil }
            result = outcome
            let pending = continuation
            continuation = nil
            return pending
        }
        source.cancel()
        if let pending { pending.resume(with: outcome.mapError { $0 as Error }) }
    }
}

private final class VaultAgentPipeWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private let state: VaultAgentCommandState
    private let dependencies: VaultAgentCommandRunner.Dependencies
    private let queue: DispatchQueue
    private let source: DispatchSourceWrite
    private var offset = 0
    private var finished = false
    private var continuation: CheckedContinuation<Void, Error>?

    init(
        data: Data,
        state: VaultAgentCommandState,
        dependencies: VaultAgentCommandRunner.Dependencies,
        queue: DispatchQueue
    ) throws {
        guard let fileDescriptor = state.writeFileDescriptor else {
            throw VaultAgentCommandRunnerError.writeFailed
        }
        self.data = data
        self.state = state
        self.dependencies = dependencies
        self.queue = queue
        source = DispatchSource.makeWriteSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.writeAvailable() }
    }

    func write() async throws {
        try await withCheckedThrowingContinuation { newContinuation in
            continuation = newContinuation
            let registered = state.registerWriterCancellation { [weak self] in
                self?.cancel()
            }
            source.resume()
            if !registered { queue.async { [weak self] in self?.cancel() } }
        }
    }

    private func writeAvailable() {
        do {
            while offset < data.count {
                try state.checkCancellation()
                guard let fileDescriptor = state.writeFileDescriptor else {
                    throw VaultAgentCommandRunnerError.writeFailed
                }
                do {
                    let count = try dependencies.writeChunk(fileDescriptor, data, offset)
                    guard count > 0, count <= data.count - offset else {
                        throw VaultAgentCommandRunnerError.writeFailed
                    }
                    offset += count
                } catch VaultAgentCommandWriteError.interrupted {
                    continue
                } catch VaultAgentCommandWriteError.wouldBlock {
                    return
                }
            }
            finish(.success(()))
        } catch {
            finish(.failure(normalized(error)))
        }
    }

    private func cancel() { finish(.failure(.cancelled)) }

    private func finish(_ result: Result<Void, VaultAgentCommandRunnerError>) {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !finished else { return nil }
            finished = true
            let pending = continuation
            continuation = nil
            return pending
        }
        guard let pending else { return }
        source.cancel()
        state.clearWriterCancellation()
        state.closeWrite()
        if case .success = result { dependencies.onEvent(.secretWritten) }
        pending.resume(with: result.mapError { $0 as Error })
    }
}

private final class VaultAgentCommandState: @unchecked Sendable {
    private struct CancellationValues {
        let fileDescriptor: Int32?
        let processID: pid_t?
        let writerCancellation: (@Sendable () -> Void)?
    }

    private static let escalationQueue = DispatchQueue(label: "com.pastera-app.agent.command-kill")
    private let lock = NSLock()
    private let dependencies: VaultAgentCommandRunner.Dependencies
    private let operationQueue: DispatchQueue
    private var writeFD: Int32?
    private var processID: pid_t?
    private var cancelled = false
    private var cancellationScheduled = false
    private var terminationRequested = false
    private var exitObserved = false
    private var reaped = false
    private var writerCancellation: (@Sendable () -> Void)?

    init(
        dependencies: VaultAgentCommandRunner.Dependencies,
        operationQueue: DispatchQueue
    ) {
        self.dependencies = dependencies
        self.operationQueue = operationQueue
    }

    var writeFileDescriptor: Int32? { lock.withLock { writeFD } }

    func checkCancellation() throws {
        guard !lock.withLock({ cancelled }) else { throw VaultAgentCommandRunnerError.cancelled }
    }

    func adoptWrite(_ fileDescriptor: Int32) -> Bool {
        lock.withLock {
            guard !cancelled else {
                dependencies.close(fileDescriptor)
                return false
            }
            writeFD = fileDescriptor
            return true
        }
    }

    func adoptProcess(_ processID: pid_t) {
        lock.withLock { self.processID = processID }
    }

    func closeWrite() {
        let fileDescriptor = lock.withLock { () -> Int32? in
            defer { writeFD = nil }
            return writeFD
        }
        if let fileDescriptor { dependencies.close(fileDescriptor) }
    }

    func registerWriterCancellation(_ cancellation: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            writerCancellation = cancellation
            return true
        }
    }

    func clearWriterCancellation() {
        lock.withLock { writerCancellation = nil }
    }

    func cancelProcess() {
        let shouldSchedule = lock.withLock { () -> Bool in
            cancelled = true
            guard !cancellationScheduled else { return false }
            cancellationScheduled = true
            return true
        }
        if shouldSchedule {
            operationQueue.async { [weak self] in self?.performCancellation() }
        }
    }

    private func performCancellation() {
        let values = lock.withLock { () -> CancellationValues in
            let cancellation = writerCancellation
            writerCancellation = nil
            let fileDescriptor = cancellation == nil ? writeFD : nil
            if cancellation == nil { writeFD = nil }
            let cancellableProcessID: pid_t?
            if !reaped, !terminationRequested, let processID {
                terminationRequested = true
                cancellableProcessID = processID
            } else {
                cancellableProcessID = nil
            }
            return CancellationValues(
                fileDescriptor: fileDescriptor,
                processID: cancellableProcessID,
                writerCancellation: cancellation
            )
        }
        values.writerCancellation?()
        if let fileDescriptor = values.fileDescriptor { dependencies.close(fileDescriptor) }
        if let processID = values.processID {
            dependencies.terminate(processID)
            Self.escalationQueue.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                self?.escalateIfNeeded(processID)
            }
        }
    }

    func markReaped() {
        lock.withLock {
            reaped = true
            processID = nil
        }
    }

    func markExitObserved() {
        lock.withLock { exitObserved = true }
    }

    private func escalateIfNeeded(_ expectedProcessID: pid_t) {
        let shouldKill = lock.withLock {
            !exitObserved && !reaped && processID == expectedProcessID
        }
        if shouldKill { dependencies.kill(expectedProcessID) }
    }
}

private func withCStringArray<ResultValue>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> ResultValue
) throws -> ResultValue {
    var storage = strings.map { strdup($0) }
    guard storage.allSatisfy({ $0 != nil }) else {
        storage.forEach { free($0) }
        throw VaultAgentCommandRunnerError.spawnFailed
    }
    defer { storage.forEach { free($0) } }
    storage.append(nil)
    return try storage.withUnsafeMutableBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else {
            throw VaultAgentCommandRunnerError.spawnFailed
        }
        return try body(baseAddress)
    }
}

private func normalized(_ error: Error) -> VaultAgentCommandRunnerError {
    if Task.isCancelled || error is CancellationError { return .cancelled }
    return (error as? VaultAgentCommandRunnerError) ?? .transportFailure
}
