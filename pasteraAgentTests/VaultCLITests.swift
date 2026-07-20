import Foundation
import PasteraAgentProtocol
import Testing

@testable import PasteraAgentAdapter

@Suite("Vault CLI")
struct VaultCLITests {
    private let entryID = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
    private let folderID = UUID(uuidString: "20202020-2020-2020-2020-202020202020")!

    @Test("parses the complete public command tree")
    func parsesCompleteCommandTree() throws {
        #expect(try VaultCLICommand.parse(["integration", "status"]) == .integrationStatus(host: nil, json: false))
        #expect(try VaultCLICommand.parse(["integration", "status", "codex", "--json"]) == .integrationStatus(host: .codex, json: true))
        #expect(try VaultCLICommand.parse(["integration", "install", "claude"]) == .integrationInstall(host: .claude))
        #expect(try VaultCLICommand.parse(["integration", "uninstall", "codex"]) == .integrationUninstall(host: .codex))
        #expect(try VaultCLICommand.parse(["vault", "status", "--json"]) == .status(json: true))
        #expect(try VaultCLICommand.parse([
            "vault", "search", "mail", "--folder", folderID.uuidString,
            "--limit", "50", "--cursor", "next", "--json"
        ]) == .search(query: "mail", folderID: folderID, limit: 50, cursor: "next", json: true))
        #expect(try VaultCLICommand.parse(["vault", "search"]) == .search(query: nil, folderID: nil, limit: 20, cursor: nil, json: false))
        #expect(try VaultCLICommand.parse(["vault", "get", entryID.uuidString]) == .get(entryID: entryID, json: false))
        #expect(try VaultCLICommand.parse(["vault", "paste", entryID.uuidString, "--field", "password"]) == .paste(entryID: entryID, field: .password))
        #expect(try VaultCLICommand.parse(["vault", "copy", entryID.uuidString, "--field", "username"]) == .copy(entryID: entryID, field: .username))
        #expect(try VaultCLICommand.parse(["exec", "--ticket", "ticket", "--stdin", "--", "/usr/bin/true"]) == .exec(ticket: "ticket", input: .standardInput, command: ["/usr/bin/true"]))
        #expect(try VaultCLICommand.parse(["exec", "--ticket", "ticket", "--fd", "255", "--", "tool", "arg"]) == .exec(ticket: "ticket", input: .fileDescriptor(255), command: ["tool", "arg"]))
    }

    @Test("rejects missing duplicate unknown and malformed arguments", arguments: [
        [String](),
        ["unknown"],
        ["integration", "install"],
        ["integration", "install", "other"],
        ["integration", "status", "codex", "claude"],
        ["integration", "status", "--json", "--json"],
        ["vault", "status", "extra"],
        ["vault", "search", "one", "two"],
        ["vault", "search", "--folder", "not-a-uuid"],
        ["vault", "search", "--limit", "0"],
        ["vault", "search", "--limit", "51"],
        ["vault", "search", "--limit", "1", "--limit", "2"],
        ["vault", "search", "--unknown"],
        ["vault", "get", "not-a-uuid"],
        ["vault", "paste", "10101010-1010-1010-1010-101010101010", "--field", "note"],
        ["vault", "copy", "10101010-1010-1010-1010-101010101010", "--field", "password", "--field", "username"],
        ["exec", "--ticket", "ticket", "--", "tool"],
        ["exec", "--ticket", "ticket", "--stdin", "tool"],
        ["exec", "--ticket", "ticket", "--stdin", "--fd", "3", "--", "tool"],
        ["exec", "--ticket", "", "--stdin", "--", "tool"],
        ["exec", "--ticket", "ticket", "--fd", "2", "--", "tool"],
        ["exec", "--ticket", "ticket", "--fd", "256", "--", "tool"],
        ["exec", "--ticket", "ticket", "--stdin", "--", "tool", "--", "arg"]
    ])
    func rejectsInvalidArguments(arguments: [String]) {
        #expect(throws: VaultCLIError.invalidArguments) {
            try VaultCLICommand.parse(arguments)
        }
    }

    @Test("rejects every UTF-8 byte and argument count overflow")
    func rejectsByteAndCountLimits() {
        let oversizedQuery = String(repeating: "界", count: 171)
        let oversizedCursor = String(repeating: "x", count: VaultAgentLimits.maximumCursorBytes + 1)
        let oversizedTicket = String(repeating: "t", count: VaultAgentLimits.maximumTokenBytes + 1)
        let oversizedArgument = String(repeating: "a", count: VaultAgentLimits.maximumCommandArgumentBytes + 1)
        let tooManyArguments = Array(repeating: "x", count: VaultAgentLimits.maximumCommandArguments + 1)

        let invalidCommands = [
            ["vault", "search", oversizedQuery],
            ["vault", "search", "--cursor", oversizedCursor],
            ["exec", "--ticket", oversizedTicket, "--stdin", "--", "tool"],
            ["exec", "--ticket", "ticket", "--stdin", "--", oversizedArgument],
            ["exec", "--ticket", "ticket", "--stdin", "--"] + tooManyArguments
        ]
        for command in invalidCommands {
            #expect(throws: VaultCLIError.invalidArguments) {
                try VaultCLICommand.parse(command)
            }
        }
    }

    @Test("JSON failure uses one stable compact envelope")
    func rendersStableFailureEnvelope() throws {
        let sentinel = "PASTERA-RENDERER-\(UUID().uuidString)"
        let withoutRetry = try VaultCLIJSONRenderer.render(.failure(.init(
            code: .grantExpired,
            message: sentinel,
            retryable: false,
            retryAfterMilliseconds: nil
        )))
        let withRetry = try VaultCLIJSONRenderer.render(.failure(.init(
            code: .rateLimited,
            message: sentinel,
            retryable: true,
            retryAfterMilliseconds: 250
        )))

        #expect(withoutRetry == #"{"ok":false,"error":{"code":"GRANT_EXPIRED","message":"Authorization has expired.","retryable":false}}"#)
        #expect(withRetry == #"{"ok":false,"error":{"code":"RATE_LIMITED","message":"Too many requests.","retry_after_ms":250,"retryable":true}}"#)
        #expect(!withoutRetry.contains(sentinel))
        #expect(!withRetry.contains(sentinel))
    }

    @Test("JSON success is stable uses ISO dates and omits protocol tags")
    func rendersStableSuccessEnvelope() throws {
        let response = VaultAgentResponseBody.success(.status(.init(
            client: .cli,
            installed: true,
            authorized: true,
            vaultReady: true,
            idleExpiresAt: Date(timeIntervalSince1970: 0),
            hardExpiresAt: nil,
            protocolVersion: 1
        )))

        let output = try VaultCLIJSONRenderer.render(response)

        #expect(output == #"{"ok":true,"data":{"authorized":true,"client":"cli","idleExpiresAt":"1970-01-01T00:00:00Z","installed":true,"protocolVersion":1,"vaultReady":true}}"#)
        #expect(!output.contains(#""type""#))
    }

    @Test("JSON renderer rejects ticket secret delivery and secret sentinel")
    func rejectsSecretBearingPayloads() {
        let sentinel = "PASTERA_TASK8_SECRET_SENTINEL"
        let ticket = VaultAgentPreparedTicket(
            token: sentinel,
            expiresAt: Date(timeIntervalSince1970: 1),
            command: ["pastera", "exec", "--ticket", sentinel]
        )
        let delivery = VaultAgentSecretDelivery(
            receiptID: UUID(),
            bytes: Data(sentinel.utf8)
        )

        #expect(throws: VaultCLIError.unsafeResponse) {
            try VaultCLIJSONRenderer.render(.success(.ticket(ticket)))
        }
        #expect(throws: VaultCLIError.unsafeResponse) {
            try VaultCLIJSONRenderer.render(.success(.secretDelivery(delivery)))
        }
    }

    @Test("JSON output enforces the 32 KiB boundary")
    func rejectsOversizedJSON() {
        let entry = VaultAgentEntryMetadata(
            id: entryID,
            folderID: folderID,
            folderName: String(repeating: "f", count: 2_048),
            title: String(repeating: "t", count: 2_048),
            website: String(repeating: "w", count: 2_048),
            username: String(repeating: "u", count: 2_048),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let page = VaultAgentSearchPage(entries: Array(repeating: entry, count: 5), nextCursor: nil)

        #expect(throws: VaultCLIError.outputTooLarge) {
            try VaultCLIJSONRenderer.render(.success(.search(page)))
        }
    }

    @Test("application maps every human command to the Broker")
    func applicationMapsCommands() async throws {
        let status = VaultAgentStatus(
            client: .cli,
            installed: true,
            authorized: true,
            vaultReady: true,
            idleExpiresAt: nil,
            hardExpiresAt: nil,
            protocolVersion: 1
        )
        let client = VaultCLIClientProbe(responses: [
            .success(.status(status)),
            .success(.search(.init(entries: [], nextCursor: nil))),
            .success(.entry(.init(
                id: entryID,
                folderID: folderID,
                folderName: "Work",
                title: "Mail",
                website: "https://example.test",
                username: "alice",
                updatedAt: Date(timeIntervalSince1970: 0)
            ))),
            .success(.empty),
            .success(.empty),
            .success(.integrationStatus(.init(hosts: []))),
            .success(.empty),
            .success(.empty)
        ])
        let application = VaultCLIApplication(client: client, runCommand: { _, _, _ in 0 })
        let commands = [
            ["vault", "status", "--json"],
            ["vault", "search", "mail", "--folder", folderID.uuidString, "--limit", "5"],
            ["vault", "get", entryID.uuidString],
            ["vault", "paste", entryID.uuidString, "--field", "password"],
            ["vault", "copy", entryID.uuidString, "--field", "username"],
            ["integration", "status"],
            ["integration", "install", "codex"],
            ["integration", "uninstall", "claude"]
        ]

        for command in commands {
            let result = await application.run(arguments: command)
            #expect(result.exitCode == 0)
            #expect(result.stderr.isEmpty)
        }
        #expect(await client.operations == [
            .status,
            .search(.init(query: "mail", folderID: folderID, limit: 5, cursor: nil)),
            .get(entryID: entryID),
            .paste(entryID: entryID, field: .password),
            .copy(entryID: entryID, field: .username),
            .integrationStatus(host: nil),
            .integrationInstall(host: .codex),
            .integrationUninstall(host: .claude)
        ])
    }

    @Test("application emits one stable secret-free JSON failure line")
    func applicationRendersJSONFailureLine() async {
        let sentinel = "PASTERA-CLI-\(UUID().uuidString)"
        let client = VaultCLIClientProbe(responses: [.failure(.init(
            code: .grantExpired,
            message: sentinel,
            retryable: false,
            retryAfterMilliseconds: nil
        ))])

        let result = await VaultCLIApplication(client: client, runCommand: { _, _, _ in 0 })
            .run(arguments: ["vault", "status", "--json"])

        #expect(result.exitCode == 1)
        #expect(result.stdout == #"{"ok":false,"error":{"code":"GRANT_EXPIRED","message":"Authorization has expired.","retryable":false}}"# + "\n")
        #expect(!result.stdout.contains(sentinel))
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.filter { $0 == "\n" }.count == 1)
    }

    @Test("exec preserves child status and adds no output")
    func execOnlyReturnsChildStatus() async {
        let runner = VaultCLIRunnerProbe(exitCode: 47)
        let application = VaultCLIApplication(client: VaultCLIClientProbe(responses: [])) {
            try await runner.run(ticket: $0, input: $1, command: $2)
        }

        let result = await application.run(arguments: [
            "exec", "--ticket", "ticket", "--fd", "7", "--", "tool", "arg"
        ])

        #expect(result == .init(exitCode: 47, stdout: "", stderr: ""))
        #expect(runner.snapshot == .init(ticket: "ticket", input: .fileDescriptor(7), command: ["tool", "arg"]))
    }

    @Test("parse local and unsafe response failures are bounded and secret free")
    func applicationSanitizesLocalFailures() async {
        let sentinel = "PASTERA_TASK8_RESPONSE_SECRET"
        let unsafeClient = VaultCLIClientProbe(responses: [.success(.secretDelivery(.init(
            receiptID: UUID(),
            bytes: Data(sentinel.utf8)
        )))])
        let invalid = await VaultCLIApplication(client: unsafeClient, runCommand: { _, _, _ in 0 })
            .run(arguments: ["vault", "get", entryID.uuidString, "--unknown"])
        let unsafe = await VaultCLIApplication(client: unsafeClient, runCommand: { _, _, _ in 0 })
            .run(arguments: ["vault", "get", entryID.uuidString, "--json"])

        #expect(invalid == .init(exitCode: 2, stdout: "", stderr: "INVALID_REQUEST\n"))
        #expect(unsafe.exitCode == 1)
        #expect(!unsafe.stdout.contains(sentinel))
        #expect(!unsafe.stderr.contains(sentinel))
        #expect(unsafe.stdout.utf8.count <= VaultAgentLimits.maximumResponseBytes + 1)
        #expect(unsafe.stderr.utf8.count <= VaultAgentLimits.maximumResponseBytes + 1)
    }
}

private actor VaultCLIClientProbe: VaultAgentRequesting {
    private var responses: [VaultAgentResponseBody]
    private(set) var operations: [VaultAgentOperation] = []

    init(responses: [VaultAgentResponseBody]) { self.responses = responses }

    func request(_ operation: VaultAgentOperation) async throws -> VaultAgentResponseBody {
        operations.append(operation)
        guard !responses.isEmpty else { throw VaultCLIError.brokerFailure }
        return responses.removeFirst()
    }
}

private final class VaultCLIRunnerProbe: @unchecked Sendable {
    struct Snapshot: Equatable {
        let ticket: String
        let input: VaultAgentCommandInput
        let command: [String]
    }

    private let lock = NSLock()
    private let exitCode: Int
    private var storage: Snapshot?

    init(exitCode: Int) { self.exitCode = exitCode }

    func run(ticket: String, input: VaultAgentCommandInput, command: [String]) async throws -> Int {
        lock.withLock { storage = .init(ticket: ticket, input: input, command: command) }
        return exitCode
    }

    var snapshot: Snapshot? { lock.withLock { storage } }
}
