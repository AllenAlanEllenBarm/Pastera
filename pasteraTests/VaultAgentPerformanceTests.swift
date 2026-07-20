import Darwin
import Foundation
import PasteraAgentProtocol
import Testing

@testable import Pastera

@Suite("Vault agent performance", .serialized)
struct VaultAgentPerformanceTests {
    @Test("10k metadata hot search p95 stays within 50 milliseconds")
    func tenThousandEntryHotSearch() async throws {
        let fixture = try VaultAgentSearchPerformanceFixture(entryCount: 10_000)

        for sequence in 1...10 {
            _ = try await fixture.search(sequence: UInt64(sequence))
        }

        var samples = [TimeInterval]()
        samples.reserveCapacity(100)
        for sequence in 11...110 {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let page = try await fixture.search(sequence: UInt64(sequence))
            samples.append(CFAbsoluteTimeGetCurrent() - startedAt)
            #expect(page.entries.count == VaultAgentLimits.maximumPageSize)
        }

        let sorted = samples.sorted()
        let p50 = sorted[49]
        let p95 = sorted[94]
        let maximum = try #require(sorted.last)
        print(String(
            format: "VaultAgentPerformance 10k hot search: p50=%.3fms p95=%.3fms max=%.3fms",
            p50 * 1_000,
            p95 * 1_000,
            maximum * 1_000
        ))

        #expect(p95 <= 0.050)
    }

    @Test("embedded Helper stays below 30 MB with effectively zero idle CPU", .timeLimit(.minutes(1)))
    func embeddedHelperResourceBoundary() async throws {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/PasteraCodexMCP", isDirectory: false)
        #expect(FileManager.default.isExecutableFile(atPath: helperURL.path))
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = helperURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        try await Task.sleep(for: .seconds(3))
        let stable = try helperSample(process.processIdentifier)
        try await Task.sleep(for: .seconds(10))
        let idle = try helperSample(process.processIdentifier)
        let cpuDelta = idle.cpuSeconds - stable.cpuSeconds
        let maximumRSS = max(stable.residentBytes, idle.residentBytes)
        print(String(
            format: "VaultAgentPerformance helper: rss=%.2fMB idle_cpu_delta=%.4fs",
            Double(maximumRSS) / 1_048_576,
            cpuDelta
        ))

        #expect(maximumRSS <= 30 * 1_024 * 1_024)
        #expect(cpuDelta <= 0.020)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
        #expect(error.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    private func helperSample(_ processID: Int32) throws -> HelperResourceSample {
        var info = proc_taskinfo()
        let expected = MemoryLayout.size(ofValue: info)
        let actual = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(processID, PROC_PIDTASKINFO, 0, $0, Int32(expected))
        }
        guard actual == expected else { throw POSIXError(.ESRCH) }
        return HelperResourceSample(
            residentBytes: UInt64(info.pti_resident_size),
            cpuSeconds: Double(info.pti_total_user + info.pti_total_system) / 1_000_000_000
        )
    }
}

private struct HelperResourceSample {
    let residentBytes: UInt64
    let cpuSeconds: TimeInterval
}

private final class VaultAgentSearchPerformanceFixture {
    private let connectionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let requestID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let identity: VaultAgentPeerIdentity
    private let runtime: VaultAgentRuntime
    private let clock: VaultAgentPerformanceClock

    init(entryCount: Int) throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let clock = VaultAgentPerformanceClock(now: now)
        self.clock = clock
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(
                label: "VaultAgentPerformanceTests.store",
                qos: .userInitiated
            )
        )
        let policy = try VaultAgentAuthorizationPolicy(
            store: VaultAgentPerformanceGrantStore(),
            executor: executor
        )
        identity = VaultAgentPeerIdentity(
            client: .codex,
            helperRequirement: "identifier com.pastera-app.PasteraCodexMCP",
            helperCDHash: Data([0x01]),
            helperIsAdHoc: false,
            helperPath: "/Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP",
            hostRequirement: "identifier com.openai.codex",
            hostCDHash: Data([0x02]),
            hostIsAdHoc: false,
            hostPath: "/Applications/ChatGPT.app/Contents/Resources/codex"
        )
        try policy.authorize(identity: identity, authenticatedAt: now)
        let vault = VaultAgentPerformanceVault(entryCount: entryCount, executor: executor)
        let tickets = VaultAgentTicketStore(
            randomBytes: { Data(repeating: 0xA5, count: 32) },
            commandBuilder: { _, _, _ in ["/usr/bin/true"] }
        )
        runtime = try VaultAgentRuntime(
            executor: executor,
            authorizationPolicy: policy,
            vault: vault,
            pasteTargetTracker: VaultAgentPerformanceTargetTracker(),
            rateLimiter: VaultAgentRateLimiter(),
            ticketStore: tickets,
            auditLogger: VaultAgentPerformanceAuditLogger(),
            now: { clock.now },
            cursorKey: Data(repeating: 0x5A, count: 32)
        )
    }

    func search(sequence: UInt64) async throws -> VaultAgentSearchPage {
        clock.advance(by: 61)
        let envelope = VaultAgentRequestEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: connectionID,
            sequence: sequence,
            requestID: requestID,
            operation: .search(.init(
                query: "mail",
                folderID: nil,
                limit: VaultAgentLimits.maximumPageSize,
                cursor: nil
            ))
        )
        let request = try JSONEncoder().encode(envelope)
        let data = await withCheckedContinuation { continuation in
            runtime.handle(identity: identity, request: request) { result in
                continuation.resume(returning: try? result.get())
            }
        }
        let responseData = try #require(data)
        let response = try JSONDecoder().decode(VaultAgentResponseEnvelope.self, from: responseData)
        guard case let .success(.search(page)) = response.body else {
            throw VaultAgentErrorCode.brokerUnavailable
        }
        return page
    }
}

private final class VaultAgentPerformanceClock {
    private let lock = NSLock()
    private var storedNow: Date

    init(now: Date) {
        storedNow = now
    }

    var now: Date {
        lock.withLock { storedNow }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            storedNow = storedNow.addingTimeInterval(interval)
        }
    }
}

private final class VaultAgentPerformanceGrantStore: VaultAgentGrantStoring {
    private var grants = [VaultAgentClientKind: VaultAgentGrant]()

    func load() -> [VaultAgentClientKind: VaultAgentGrant] { grants }
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) { self.grants = grants }
}

private final class VaultAgentPerformanceVault: PasswordVaultAgentAccess {
    let agentVaultReady = true

    private let executor: VaultAgentSerialExecutor
    private let folder: PasswordVaultFolder
    private let entries: [PasswordVaultEntry]

    init(entryCount: Int, executor: VaultAgentSerialExecutor) {
        self.executor = executor
        let folderID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        folder = PasswordVaultFolder(
            id: folderID,
            name: "Performance",
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        entries = (0..<entryCount).map { index in
            let suffix = String(format: "%012x", index)
            return PasswordVaultEntry(
                id: UUID(uuidString: "30000000-0000-0000-0000-\(suffix)")!,
                folderID: folderID,
                title: String(format: "Mail entry %05d", index),
                website: "https://mail.example/\(index)",
                username: "user-\(index)",
                note: "",
                createdAt: .distantPast,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }

    func ensureReadyForAgent(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        completion(.success(()))
    }

    func agentMetadata(
        completion: @escaping (
            Result<([PasswordVaultFolder], [PasswordVaultEntry]), PasswordVaultError>
        ) -> Void
    ) {
        executor.async { completion(.success(([self.folder], self.entries))) }
    }

    func agentPaste(
        entryID: UUID,
        field: VaultAgentSecretField,
        target: PasteTargetContext,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        completion(.failure(.entryNotFound))
    }

    func agentCopy(
        entryID: UUID,
        field: VaultAgentSecretField,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        completion(.failure(.entryNotFound))
    }

    func agentSecret(
        entryID: UUID,
        field: VaultAgentSecretField,
        completion: @escaping (Result<Data, PasswordVaultError>) -> Void
    ) {
        completion(.failure(.entryNotFound))
    }

    func disableAutomationUnlockForAgent() throws {}
}

private final class VaultAgentPerformanceTargetTracker: VaultAgentPasteTargetTracking {
    func resolve() throws -> PasteTargetContext { throw VaultAgentPasteTargetError.unavailable }
}

private final class VaultAgentPerformanceAuditLogger: VaultAgentAuditLogging {
    // swiftlint:disable:next function_parameter_count
    func record(
        client: VaultAgentClientKind,
        action: VaultAgentAuditAction,
        entryID: UUID?,
        result: VaultAgentErrorCode?,
        latencyBucket: VaultAgentLatencyBucket,
        at date: Date
    ) {}
}
