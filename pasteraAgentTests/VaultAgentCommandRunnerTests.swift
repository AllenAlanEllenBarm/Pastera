import Darwin
import Foundation
import PasteraAgentProtocol
import Testing

@testable import PasteraAgentAdapter

// The serialized suite keeps its real-process race probes in one file so their cleanup is auditable.
// swiftlint:disable file_length

@Suite("Vault agent command runner", .serialized)
// swiftlint:disable:next type_body_length
struct VaultAgentCommandRunnerTests {
    private let sentinel = Data("PASTERA_TASK8_SECRET_SENTINEL".utf8)

    @Test("stdin appends exactly one newline and fd passes bytes unchanged", arguments: [3, 255])
    func writesExactSecretBytes(targetFD: Int32) async throws {
        let stdinProbe = VaultRunnerClientProbe(secret: sentinel)
        let stdinStatus = try await VaultAgentCommandRunner(client: stdinProbe).run(
            ticket: "stdin-ticket",
            input: .standardInput,
            command: [fixturePath, "--stdin", "--exit-count"]
        )
        #expect(stdinStatus == sentinel.count + 1)
        #expect(await stdinProbe.operations == [
            .redeemTicket(token: "stdin-ticket", mode: .stdin),
            .completeTicket(receiptID: stdinProbe.receiptID)
        ])

        let fdProbe = VaultRunnerClientProbe(secret: sentinel)
        let fdStatus = try await VaultAgentCommandRunner(client: fdProbe).run(
            ticket: "fd-ticket",
            input: .fileDescriptor(targetFD),
            command: [fixturePath, "--fd", "\(targetFD)", "--exit-count"]
        )
        #expect(fdStatus == sentinel.count)
        #expect(await fdProbe.operations == [
            .redeemTicket(token: "fd-ticket", mode: .fileDescriptor),
            .completeTicket(receiptID: fdProbe.receiptID)
        ])
    }

    @Test("runner preserves redeem spawn write complete order")
    func preservesSecurityEventOrder() async throws {
        let events = VaultRunnerEventProbe()
        let client = VaultRunnerClientProbe(secret: sentinel, onEvent: { events.append($0) })
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.onEvent = { event in
            switch event {
            case .spawned: events.append("spawned")
            case .secretWritten: events.append("secretWritten")
            }
        }
        let runner = VaultAgentCommandRunner(client: client, dependencies: dependencies)

        let status = try await runner.run(
            ticket: "ticket",
            input: .fileDescriptor(9),
            command: [fixturePath, "--fd", "9"]
        )

        #expect(status == 0)
        #expect(events.snapshot == ["redeemed", "spawned", "secretWritten", "completed"])
    }

    @Test("partial writes complete only after all bytes are delivered")
    func handlesPartialWrites() async throws {
        let client = VaultRunnerClientProbe(secret: sentinel)
        let writeProbe = VaultRunnerWriteProbe(maximumChunk: 2)
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.writeChunk = { try writeProbe.write(fileDescriptor: $0, data: $1, offset: $2) }
        let runner = VaultAgentCommandRunner(client: client, dependencies: dependencies)

        let status = try await runner.run(
            ticket: "ticket",
            input: .fileDescriptor(8),
            command: [fixturePath, "--fd", "8", "--exit-count"]
        )

        #expect(status == sentinel.count)
        #expect(writeProbe.callCount > 1)
        #expect(await client.completeCount == 1)
    }

    @Test("cancellation never closes the write descriptor while a write owns it")
    func cancellationSerializesWriteDescriptorClose() async throws {
        let probe = VaultRunnerWriteCloseRaceProbe()
        let childProbe = VaultRunnerPIDProbe()
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.writeChunk = { try probe.write(fileDescriptor: $0, data: $1, offset: $2) }
        dependencies.close = { probe.close(fileDescriptor: $0) }
        dependencies.onEvent = { if case let .spawned(pid) = $0 { childProbe.set(pid) } }
        let runner = VaultAgentCommandRunner(
            client: VaultRunnerClientProbe(secret: sentinel),
            dependencies: dependencies
        )
        let task = Task {
            try await runner.run(
                ticket: "ticket",
                input: .standardInput,
                command: [fixturePath, "--stdin", "--sleep-ms", "60000", "--ignore-term"]
            )
        }

        try await probe.waitUntilWriting()
        task.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!probe.closeOverlappedWrite)
        probe.releaseWrite()

        await #expect(throws: VaultAgentCommandRunnerError.cancelled) { try await task.value }
        #expect(probe.writeDescriptorCloseCount == 1)
        #expect(probe.bytesWrittenToReusedDescriptor.isEmpty)
        #expect(childProbe.wasReaped)
    }

    @Test("spawn and write failures never complete and leave no child")
    func spawnAndWriteFailuresDoNotComplete() async {
        let spawnClient = VaultRunnerClientProbe(secret: sentinel)
        var spawnDependencies = VaultAgentCommandRunner.Dependencies.live
        spawnDependencies.spawn = { _, _, _, _ in throw VaultAgentCommandRunnerError.spawnFailed }
        await #expect(throws: VaultAgentCommandRunnerError.spawnFailed) {
            try await VaultAgentCommandRunner(client: spawnClient, dependencies: spawnDependencies).run(
                ticket: "ticket", input: .standardInput, command: [fixturePath, "--stdin"]
            )
        }
        #expect(await spawnClient.completeCount == 0)

        let childProbe = VaultRunnerPIDProbe()
        let writeClient = VaultRunnerClientProbe(secret: sentinel)
        var writeDependencies = VaultAgentCommandRunner.Dependencies.live
        writeDependencies.onEvent = { if case let .spawned(pid) = $0 { childProbe.set(pid) } }
        writeDependencies.writeChunk = { _, _, _ in throw VaultAgentCommandRunnerError.writeFailed }
        await #expect(throws: VaultAgentCommandRunnerError.writeFailed) {
            try await VaultAgentCommandRunner(client: writeClient, dependencies: writeDependencies).run(
                ticket: "ticket", input: .standardInput,
                command: [fixturePath, "--stdin", "--sleep-ms", "60000", "--ignore-term"]
            )
        }
        #expect(await writeClient.completeCount == 0)
        #expect(childProbe.wasReaped)
    }

    @Test("complete failure is returned only after the child is reaped")
    func completeFailureStillReaps() async {
        let childProbe = VaultRunnerPIDProbe()
        let failure = VaultAgentFailure(
            code: .ticketUsed,
            message: "Ticket unavailable.",
            retryable: false,
            retryAfterMilliseconds: nil
        )
        let client = VaultRunnerClientProbe(secret: sentinel, completeResponse: .failure(failure))
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.onEvent = { if case let .spawned(pid) = $0 { childProbe.set(pid) } }

        await #expect(throws: VaultAgentCommandRunnerError.broker(failure)) {
            try await VaultAgentCommandRunner(client: client, dependencies: dependencies).run(
                ticket: "ticket", input: .standardInput, command: [fixturePath, "--stdin"]
            )
        }
        #expect(childProbe.wasReaped)
    }

    @Test("normal and signal exits map to stable statuses")
    func mapsChildExitStatuses() async throws {
        let normal = try await VaultAgentCommandRunner(client: VaultRunnerClientProbe(secret: sentinel)).run(
            ticket: "ticket", input: .standardInput,
            command: [fixturePath, "--stdin", "--exit", "23"]
        )
        let signaled = try await VaultAgentCommandRunner(client: VaultRunnerClientProbe(secret: sentinel)).run(
            ticket: "ticket", input: .standardInput,
            command: [fixturePath, "--stdin", "--signal", "15"]
        )
        #expect(normal == 23)
        #expect(signaled == 143)
    }

    @Test("waitpid retries EINTR and records reaping before returning")
    func waitRetriesInterruptionBeforeReturning() async throws {
        let waitProbe = VaultRunnerWaitProcessProbe(mode: .interruptOnce)
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.makeWaiter = { processID, onExitObserved, onReaped in
            VaultAgentProcessWaiter(
                processID: processID,
                onExitObserved: onExitObserved,
                onReaped: onReaped,
                waitProcess: waitProbe.wait
            )
        }

        let status = try await VaultAgentCommandRunner(
            client: VaultRunnerClientProbe(secret: sentinel),
            dependencies: dependencies
        ).run(ticket: "ticket", input: .standardInput, command: [fixturePath, "--stdin"])

        #expect(status == 0)
        #expect(waitProbe.callCount == 2)
    }

    @Test("ECHILD confirms reaping but still returns a stable wait failure")
    func confirmedExternalReapReturnsWaitFailure() async {
        let childProbe = VaultRunnerPIDProbe()
        let waitProbe = VaultRunnerWaitProcessProbe(mode: .reapThenReportNoChild)
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.makeWaiter = { processID, onExitObserved, onReaped in
            VaultAgentProcessWaiter(
                processID: processID,
                onExitObserved: onExitObserved,
                onReaped: onReaped,
                waitProcess: waitProbe.wait
            )
        }
        dependencies.onEvent = { if case let .spawned(pid) = $0 { childProbe.set(pid) } }

        await #expect(throws: VaultAgentCommandRunnerError.waitFailed) {
            try await VaultAgentCommandRunner(
                client: VaultRunnerClientProbe(secret: sentinel),
                dependencies: dependencies
            ).run(ticket: "ticket", input: .standardInput, command: [fixturePath, "--stdin"])
        }

        #expect(waitProbe.callCount == 1)
        #expect(childProbe.wasReaped)
    }

    @Test("cancellation terminates and reaps the child")
    func cancellationReapsChild() async throws {
        let childProbe = VaultRunnerPIDProbe()
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.onEvent = { if case let .spawned(pid) = $0 { childProbe.set(pid) } }
        let runner = VaultAgentCommandRunner(
            client: VaultRunnerClientProbe(secret: sentinel),
            dependencies: dependencies
        )
        let task = Task {
            try await runner.run(
                ticket: "ticket", input: .standardInput,
                command: [fixturePath, "--stdin", "--sleep-ms", "60000"]
            )
        }
        try await childProbe.waitUntilSpawned()
        task.cancel()

        await #expect(throws: VaultAgentCommandRunnerError.cancelled) { try await task.value }
        #expect(childProbe.wasReaped)
    }

    @Test("cancellation in the post-spawn window still escalates and reaps")
    func cancellationBeforeProcessAdoptionStillEscalates() async throws {
        let spawn = VaultAgentCommandRunner.Dependencies.live.spawn
        let spawnProbe = VaultRunnerSpawnWindowProbe()
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.spawn = { command, input, pipe, environment in
            let processID = try spawn(command, input, pipe, environment)
            usleep(100_000)
            spawnProbe.hold(processID: processID)
            return processID
        }
        dependencies.kill = { processID in
            spawnProbe.recordKill()
            _ = Darwin.kill(processID, SIGKILL)
        }
        let task = Task {
            try await VaultAgentCommandRunner(
                client: VaultRunnerClientProbe(secret: sentinel),
                dependencies: dependencies
            ).run(
                ticket: "ticket",
                input: .standardInput,
                command: [fixturePath, "--stdin", "--sleep-ms", "60000", "--ignore-term"]
            )
        }

        try await spawnProbe.waitUntilSpawned()
        task.cancel()
        spawnProbe.releaseSpawn()

        await #expect(throws: VaultAgentCommandRunnerError.cancelled) { try await task.value }
        #expect(spawnProbe.killCount == 1)
        #expect(spawnProbe.wasReaped)
    }

    @Test("reaping blocks escalation before a pid can be reused")
    func reapingWinsEscalationRace() async throws {
        let childProbe = VaultRunnerPIDProbe()
        let waitProbe = VaultRunnerWaitProcessProbe(mode: .reapAndBlock)
        let killProbe = VaultRunnerSignalProbe()
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.makeWaiter = { processID, onExitObserved, onReaped in
            VaultAgentProcessWaiter(
                processID: processID,
                onExitObserved: onExitObserved,
                onReaped: onReaped,
                waitProcess: waitProbe.wait
            )
        }
        dependencies.kill = { _ in killProbe.record() }
        dependencies.onEvent = { if case let .spawned(pid) = $0 { childProbe.set(pid) } }
        let task = Task {
            try await VaultAgentCommandRunner(
                client: VaultRunnerClientProbe(secret: sentinel),
                dependencies: dependencies
            ).run(
                ticket: "ticket",
                input: .standardInput,
                command: [fixturePath, "--stdin", "--sleep-ms", "60000"]
            )
        }

        try await childProbe.waitUntilSpawned()
        task.cancel()
        try await waitProbe.waitUntilReaped()
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(killProbe.callCount == 0)
        waitProbe.releaseWait()

        await #expect(throws: VaultAgentCommandRunnerError.cancelled) { try await task.value }
        #expect(childProbe.wasReaped)
    }

    @Test("secret never enters child argv environment or temporary files")
    func secretIsAbsentFromAmbientChannels() async throws {
        let text = String(bytes: sentinel, encoding: .utf8) ?? ""
        #expect(!ProcessInfo.processInfo.environment.values.contains(where: { $0.contains(text) }))
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraRunner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let before = try Set(FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path))
        let psProbe = VaultRunnerStringProbe()
        var dependencies = VaultAgentCommandRunner.Dependencies.live
        dependencies.environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "TMPDIR": temporaryRoot.path
        ]
        dependencies.onEvent = { event in
            guard case let .spawned(pid) = event else { return }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "command=", "-p", "\(pid)"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            psProbe.set(String(bytes: data, encoding: .utf8) ?? "")
        }

        _ = try await VaultAgentCommandRunner(
            client: VaultRunnerClientProbe(secret: sentinel), dependencies: dependencies
        ).run(ticket: "ticket", input: .fileDescriptor(7), command: [fixturePath, "--fd", "7"])

        let after = try Set(FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path))
        #expect(!psProbe.value.contains(text))
        #expect(before == after)
    }

    @Test("maximum stdin payload and delayed reader do not block another runner")
    func maximumPayloadDoesNotBlockSharedQueue() async throws {
        let maximumSecret = Data(repeating: 0x61, count: VaultAgentLimits.maximumSecretBytes)
        let slowTask = Task {
            try await VaultAgentCommandRunner(client: VaultRunnerClientProbe(secret: maximumSecret)).run(
                ticket: "slow", input: .standardInput,
                command: [fixturePath, "--stdin", "--sleep-ms", "500", "--exit-count"]
            )
        }
        try await Task.sleep(for: .milliseconds(50))

        let quick = try await VaultAgentCommandRunner(client: VaultRunnerClientProbe(secret: sentinel)).run(
            ticket: "quick", input: .fileDescriptor(11),
            command: [fixturePath, "--fd", "11", "--exit-count"]
        )

        #expect(quick == sentinel.count)
        #expect(try await slowTask.value == 125)
    }

    @Test("five real runs do not grow the open file descriptor set")
    func repeatedRunsDoNotLeakFDs() async throws {
        let before = openFileDescriptorCount()
        for targetFD in [3, 255, 3, 255, 9] {
            let client = VaultRunnerClientProbe(secret: sentinel)
            _ = try await VaultAgentCommandRunner(client: client).run(
                ticket: "ticket", input: .fileDescriptor(Int32(targetFD)),
                command: [fixturePath, "--fd", "\(targetFD)"]
            )
        }
        #expect(openFileDescriptorCount() <= before + 1)
    }

    private var fixturePath: String {
        Bundle(for: BundleToken.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("PasteraSecretConsumerFixture")
            .path
    }

    private func openFileDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
    }
}

private final class BundleToken {}

private actor VaultRunnerClientProbe: VaultAgentRequesting {
    let receiptID = UUID(uuidString: "30303030-3030-3030-3030-303030303030")!
    private let secret: Data
    private let completeResponse: VaultAgentResponseBody
    private let onEvent: @Sendable (String) -> Void
    private(set) var operations: [VaultAgentOperation] = []
    private(set) var completeCount = 0

    init(
        secret: Data,
        completeResponse: VaultAgentResponseBody = .success(.status(.init(
            client: .cli,
            installed: true,
            authorized: true,
            vaultReady: true,
            idleExpiresAt: nil,
            hardExpiresAt: nil,
            protocolVersion: VaultAgentLimits.protocolVersion
        ))),
        onEvent: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.secret = secret
        self.completeResponse = completeResponse
        self.onEvent = onEvent
    }

    func request(_ operation: VaultAgentOperation) async throws -> VaultAgentResponseBody {
        operations.append(operation)
        switch operation {
        case .redeemTicket:
            onEvent("redeemed")
            return .success(.secretDelivery(.init(receiptID: receiptID, bytes: secret)))
        case .completeTicket:
            completeCount += 1
            onEvent("completed")
            return completeResponse
        default:
            return .failure(.init(
                code: .invalidRequest,
                message: "Invalid request.",
                retryable: false,
                retryAfterMilliseconds: nil
            ))
        }
    }
}

private final class VaultRunnerEventProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) { lock.withLock { storage.append(value) } }

    var snapshot: [String] { lock.withLock { storage } }
}

private final class VaultRunnerWriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumChunk: Int
    private var calls = 0

    init(maximumChunk: Int) { self.maximumChunk = maximumChunk }

    func write(fileDescriptor: Int32, data: Data, offset: Int) throws -> Int {
        lock.withLock { calls += 1 }
        let count = min(maximumChunk, data.count - offset)
        return try data.withUnsafeBytes { bytes in
            let pointer = bytes.baseAddress!.advanced(by: offset)
            let result = Darwin.write(fileDescriptor, pointer, count)
            guard result >= 0 else { throw VaultAgentCommandRunnerError.writeFailed }
            return result
        }
    }

    var callCount: Int { lock.withLock { calls } }
}

private final class VaultRunnerWriteCloseRaceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let writeStarted = DispatchSemaphore(value: 0)
    private let writeRelease = DispatchSemaphore(value: 0)
    private var writeFD: Int32?
    private var activeWriteFD: Int32?
    private var reusedReadFD: Int32?
    private var reusedWriteFD: Int32?
    private var overlap = false
    private var closeCount = 0

    func write(fileDescriptor: Int32, data: Data, offset: Int) throws -> Int {
        lock.withLock {
            writeFD = fileDescriptor
            activeWriteFD = fileDescriptor
        }
        writeStarted.signal()
        writeRelease.wait()
        defer { lock.withLock { activeWriteFD = nil } }
        return try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return 0 }
            let result = Darwin.write(
                fileDescriptor,
                baseAddress.advanced(by: offset),
                data.count - offset
            )
            guard result >= 0 else { throw VaultAgentCommandRunnerError.writeFailed }
            return result
        }
    }

    func close(fileDescriptor: Int32) {
        let shouldReuse = lock.withLock { () -> Bool in
            if writeFD == fileDescriptor { closeCount += 1 }
            guard activeWriteFD == fileDescriptor else { return false }
            overlap = true
            return true
        }
        _ = Darwin.close(fileDescriptor)
        if shouldReuse { installReusePipe(at: fileDescriptor) }
    }

    func waitUntilWriting() async throws {
        try await wait(for: writeStarted)
    }

    func releaseWrite() { writeRelease.signal() }

    var closeOverlappedWrite: Bool { lock.withLock { overlap } }

    var writeDescriptorCloseCount: Int { lock.withLock { closeCount } }

    var bytesWrittenToReusedDescriptor: Data {
        let descriptors = lock.withLock { () -> (Int32, Int32)? in
            guard let read = reusedReadFD, let write = reusedWriteFD else { return nil }
            reusedReadFD = nil
            reusedWriteFD = nil
            return (read, write)
        }
        guard let descriptors else { return Data() }
        _ = Darwin.close(descriptors.1)
        var buffer = [UInt8](repeating: 0, count: VaultAgentLimits.maximumSecretBytes + 1)
        let count = Darwin.read(descriptors.0, &buffer, buffer.count)
        _ = Darwin.close(descriptors.0)
        return count > 0 ? Data(buffer.prefix(count)) : Data()
    }

    private func installReusePipe(at fileDescriptor: Int32) {
        var pipeFDs = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&pipeFDs) == 0 else { return }
        let readFD: Int32
        if pipeFDs[0] == fileDescriptor {
            readFD = Darwin.fcntl(pipeFDs[0], F_DUPFD_CLOEXEC, 256)
        } else {
            readFD = pipeFDs[0]
        }
        guard readFD >= 0, Darwin.dup2(pipeFDs[1], fileDescriptor) == fileDescriptor else {
            if readFD >= 0 { _ = Darwin.close(readFD) }
            if pipeFDs[0] != readFD { _ = Darwin.close(pipeFDs[0]) }
            _ = Darwin.close(pipeFDs[1])
            return
        }
        if pipeFDs[0] != readFD, pipeFDs[0] != fileDescriptor {
            _ = Darwin.close(pipeFDs[0])
        }
        if pipeFDs[1] != fileDescriptor { _ = Darwin.close(pipeFDs[1]) }
        let flags = Darwin.fcntl(readFD, F_GETFL)
        if flags >= 0 { _ = Darwin.fcntl(readFD, F_SETFL, flags | O_NONBLOCK) }
        lock.withLock {
            reusedReadFD = readFD
            reusedWriteFD = fileDescriptor
        }
    }

    private func wait(for semaphore: DispatchSemaphore) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if semaphore.wait(timeout: .now() + .seconds(2)) == .success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: VaultAgentCommandRunnerError.waitFailed)
                }
            }
        }
    }
}

private final class VaultRunnerWaitProcessProbe: @unchecked Sendable {
    enum Mode {
        case interruptOnce
        case reapThenReportNoChild
        case reapAndBlock
    }

    private let lock = NSLock()
    private let mode: Mode
    private let reaped = DispatchSemaphore(value: 0)
    private let waitRelease = DispatchSemaphore(value: 0)
    private var calls = 0

    init(mode: Mode) { self.mode = mode }

    func wait(
        processID: pid_t,
        status: UnsafeMutablePointer<Int32>?,
        options: Int32
    ) -> pid_t {
        let invocation = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        switch mode {
        case .interruptOnce where invocation == 1:
            errno = EINTR
            return -1
        case .reapThenReportNoChild:
            _ = Darwin.waitpid(processID, status, options)
            errno = ECHILD
            return -1
        case .reapAndBlock:
            let result = Darwin.waitpid(processID, status, options)
            reaped.signal()
            waitRelease.wait()
            return result
        default:
            return Darwin.waitpid(processID, status, options)
        }
    }

    var callCount: Int { lock.withLock { calls } }

    func waitUntilReaped() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if self.reaped.wait(timeout: .now() + .seconds(2)) == .success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: VaultAgentCommandRunnerError.waitFailed)
                }
            }
        }
    }

    func releaseWait() { waitRelease.signal() }
}

private final class VaultRunnerSignalProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func record() { lock.withLock { calls += 1 } }

    var callCount: Int { lock.withLock { calls } }
}

private final class VaultRunnerSpawnWindowProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let spawned = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private var processID: pid_t?
    private var kills = 0

    func hold(processID: pid_t) {
        lock.withLock { self.processID = processID }
        spawned.signal()
        release.wait()
    }

    func waitUntilSpawned() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if self.spawned.wait(timeout: .now() + .seconds(2)) == .success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: VaultAgentCommandRunnerError.spawnFailed)
                }
            }
        }
    }

    func releaseSpawn() { release.signal() }

    func recordKill() { lock.withLock { kills += 1 } }

    var killCount: Int { lock.withLock { kills } }

    var wasReaped: Bool {
        guard let processID = lock.withLock({ processID }) else { return false }
        errno = 0
        let result = Darwin.waitpid(processID, nil, WNOHANG)
        return result == -1 && errno == ECHILD
    }
}

private final class VaultRunnerPIDProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: pid_t?

    func set(_ pid: pid_t) { lock.withLock { storage = pid } }

    func waitUntilSpawned() async throws {
        for _ in 0..<100 {
            if lock.withLock({ storage != nil }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw VaultAgentCommandRunnerError.spawnFailed
    }

    var wasReaped: Bool {
        guard let pid = lock.withLock({ storage }) else { return false }
        errno = 0
        let result = Darwin.waitpid(pid, nil, WNOHANG)
        return result == -1 && errno == ECHILD
    }
}

private final class VaultRunnerStringProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func set(_ value: String) { lock.withLock { storage = value } }

    var value: String { lock.withLock { storage } }
}
