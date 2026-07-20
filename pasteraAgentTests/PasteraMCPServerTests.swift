import Darwin
import Foundation
import MCP
import PasteraAgentProtocol
import Testing

#if canImport(System)
import System
#else
import SystemPackage
#endif

@testable import PasteraAgentAdapter

@Suite("Pastera MCP server", .serialized)
struct PasteraMCPServerTests {
    @Test("MCP publishes exactly five bounded tools")
    func publishesFiveTools() throws {
        let tools = PasteraMCPServer.makeTools()

        #expect(tools.map(\.name) == [
            "vault_status",
            "vault_search",
            "vault_get",
            "vault_paste",
            "vault_prepare_exec"
        ])
        #expect(tools.allSatisfy { $0.inputSchema.objectValue?["additionalProperties"]?.boolValue == false })
        #expect(tools.allSatisfy { $0.outputSchema?.objectValue?["additionalProperties"]?.boolValue == false })
        #expect(tools[0].annotations.readOnlyHint == true)
        #expect(tools[1].annotations.readOnlyHint == true)
        #expect(tools[2].annotations.readOnlyHint == true)
        #expect(tools[3].annotations.readOnlyHint == false)
        #expect(tools[4].annotations.readOnlyHint == false)
        #expect(tools[3].annotations.openWorldHint == true)
        #expect(tools[4].annotations.openWorldHint == false)

        for tool in tools {
            let output = try #require(tool.outputSchema?.objectValue)
            let variants = try #require(output["oneOf"]?.arrayValue)
            #expect(variants.count == 2)
            #expect(variants.allSatisfy {
                $0.objectValue?["additionalProperties"]?.boolValue == false
            })
            #expect(variants[0].objectValue?["properties"]?.objectValue?["ok"]?
                .objectValue?["const"]?.boolValue == true)
            #expect(variants[1].objectValue?["properties"]?.objectValue?["ok"]?
                .objectValue?["const"]?.boolValue == false)
        }

        let searchInput = try #require(tools[1].inputSchema.objectValue)
        let searchProperties = try #require(searchInput["properties"]?.objectValue)
        #expect(searchProperties["limit"]?.objectValue?["minimum"]?.intValue == 1)
        #expect(searchProperties["limit"]?.objectValue?["maximum"]?.intValue == 50)
        #expect(searchProperties["limit"]?.objectValue?["default"]?.intValue == 20)
    }

    @Test("all five tools map bounded inputs and stable structured successes")
    func mapsEveryToolOperationAndSuccess() async throws {
        let entryID = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let folderID = UUID(uuidString: "20202020-2020-2020-2020-202020202020")!
        let entry = VaultAgentEntryMetadata(
            id: entryID,
            folderID: folderID,
            folderName: "Work",
            title: "Mail",
            website: "https://example.test",
            username: "alice",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let status = VaultAgentStatus(
            client: .codex,
            installed: true,
            authorized: true,
            vaultReady: true,
            idleExpiresAt: nil,
            hardExpiresAt: nil,
            protocolVersion: VaultAgentLimits.protocolVersion
        )
        let requester = VaultAgentRequestProbe(responses: [
            .success(.status(status)),
            .success(.search(.init(entries: [entry], nextCursor: "next"))),
            .success(.entry(entry)),
            .success(.empty),
            .success(.ticket(.init(
                token: "single-use-ticket",
                expiresAt: Date(timeIntervalSince1970: 2),
                command: ["pastera", "exec", "--ticket", "single-use-ticket"]
            )))
        ])
        let handler = PasteraMCPServer(client: requester)

        let results = [
            await handler.call(name: "vault_status", arguments: [:]),
            await handler.call(name: "vault_search", arguments: [
                "query": "mail",
                "folder_id": .string(folderID.uuidString.lowercased()),
                "limit": 10,
                "cursor": "cursor"
            ]),
            await handler.call(name: "vault_get", arguments: [
                "entry_id": .string(entryID.uuidString.lowercased())
            ]),
            await handler.call(name: "vault_paste", arguments: [
                "entry_id": .string(entryID.uuidString.lowercased()),
                "field": "password"
            ]),
            await handler.call(name: "vault_prepare_exec", arguments: [
                "entry_id": .string(entryID.uuidString.lowercased()),
                "field": "username",
                "mode": "fd"
            ])
        ]
        let operations = await requester.operationsSnapshot()

        #expect(operations == [
            .status,
            .search(.init(query: "mail", folderID: folderID, limit: 10, cursor: "cursor")),
            .get(entryID: entryID),
            .paste(entryID: entryID, field: .password),
            .prepareExec(entryID: entryID, field: .username, mode: .fileDescriptor)
        ])
        #expect(results.allSatisfy { $0.isError == false })
        #expect(results.allSatisfy { $0.structuredContent?.objectValue?["ok"]?.boolValue == true })
        let textData = try JSONEncoder().encode(results.map(\.content))
        let textJSON = try #require(String(data: textData, encoding: .utf8))
        #expect(!textJSON.contains("mail"))
        #expect(!textJSON.contains("single-use-ticket"))
        #expect(!textJSON.contains("--ticket"))
    }

    @Test("MCP structured metadata never contains a password or note field")
    func structuredResultOmitsSecretFields() async throws {
        let entry = VaultAgentEntryMetadata(
            id: UUID(uuidString: "10101010-1010-1010-1010-101010101010")!,
            folderID: UUID(uuidString: "20202020-2020-2020-2020-202020202020")!,
            folderName: "Work",
            title: "Mail",
            website: "https://example.test",
            username: "alice",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let requester = VaultAgentRequestProbe(responses: [.success(.entry(entry))])
        let handler = PasteraMCPServer(client: requester)

        let result = await handler.call(
            name: "vault_get",
            arguments: ["entry_id": .string(entry.id.uuidString)]
        )
        let data = try JSONEncoder().encode(try #require(result.structuredContent))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.localizedCaseInsensitiveContains("password"))
        #expect(!json.localizedCaseInsensitiveContains("note"))
        #expect(json.contains("alice"))
    }

    @Test("search validates the bounded limit before calling Broker")
    func rejectsSearchLimitAboveMaximum() async throws {
        let requester = VaultAgentRequestProbe(responses: [])
        let handler = PasteraMCPServer(client: requester)

        let result = await handler.call(
            name: "vault_search",
            arguments: ["limit": .int(51)]
        )
        let structured = try #require(result.structuredContent?.objectValue)
        let error = try #require(structured["error"]?.objectValue)

        #expect(result.isError == true)
        #expect(error["code"]?.stringValue == "INVALID_REQUEST")
        let operations = await requester.operationsSnapshot()
        #expect(operations.isEmpty)
    }

    @Test("invalid types, UUIDs, enums, extra fields, and byte bounds never reach Broker")
    func rejectsInvalidInputsBeforeBroker() async throws {
        let requester = VaultAgentRequestProbe(responses: [])
        let handler = PasteraMCPServer(client: requester)
        let invalidCalls: [(String, [String: Value])] = [
            ("vault_status", ["unexpected": true]),
            ("vault_search", ["limit": "20"]),
            ("vault_search", ["query": .string(String(repeating: "界", count: 171))]),
            ("vault_search", ["cursor": .string(String(repeating: "x", count: 2_049))]),
            ("vault_get", ["entry_id": "not-a-uuid"]),
            ("vault_paste", [
                "entry_id": "10101010-1010-1010-1010-101010101010",
                "field": "note"
            ]),
            ("vault_prepare_exec", [
                "entry_id": "10101010-1010-1010-1010-101010101010",
                "field": "password",
                "mode": "environment"
            ]),
            ("unknown_tool", [:])
        ]

        for (name, arguments) in invalidCalls {
            let result = await handler.call(name: name, arguments: arguments)
            let code = result.structuredContent?.objectValue?["error"]?
                .objectValue?["code"]?.stringValue
            #expect(result.isError == true)
            #expect(code == "INVALID_REQUEST")
        }
        let operations = await requester.operationsSnapshot()
        #expect(operations.isEmpty)
    }

    @Test("wire failures retain only stable fields")
    func mapsWireFailure() async throws {
        let requester = VaultAgentRequestProbe(responses: [
            .failure(.init(
                code: .authorizationRequired,
                message: "Authorization required.",
                retryable: false,
                retryAfterMilliseconds: nil
            ))
        ])
        let handler = PasteraMCPServer(client: requester)

        let result = await handler.call(name: "vault_status", arguments: nil)
        let encodedData = try JSONEncoder().encode(try #require(result.structuredContent))
        let encoded = try #require(String(data: encodedData, encoding: .utf8))

        #expect(result.isError == true)
        #expect(encoded.contains("AUTHORIZATION_REQUIRED"))
        #expect(!encoded.contains("Swift"))
        #expect(!encoded.contains("POSIX"))
    }

    @Test("oversized or local failures collapse to a bounded secret-free result")
    func boundsAndSanitizesFailures() async throws {
        let sentinel = "PASTERA_SECRET_SENTINEL_7C89"
        let oversizedRequester = VaultAgentRequestProbe(responses: [
            .failure(.init(
                code: .vaultBusy,
                message: sentinel + String(repeating: "x", count: VaultAgentLimits.maximumResponseBytes),
                retryable: true,
                retryAfterMilliseconds: 20
            ))
        ])
        let oversized = await PasteraMCPServer(client: oversizedRequester).call(
            name: "vault_status",
            arguments: nil
        )
        let oversizedData = try JSONEncoder().encode(try #require(oversized.structuredContent))
        let oversizedJSON = try #require(String(data: oversizedData, encoding: .utf8))

        #expect(oversizedData.count <= VaultAgentLimits.maximumResponseBytes)
        #expect(!oversizedJSON.contains(sentinel))
        #expect(oversized.structuredContent?.objectValue?["error"]?
            .objectValue?["code"]?.stringValue == "BROKER_UNAVAILABLE")

        let local = await PasteraMCPServer(
            client: VaultAgentThrowingRequester(sentinel: sentinel)
        ).call(name: "vault_status", arguments: nil)
        let localData = try JSONEncoder().encode(try #require(local.structuredContent))
        let localJSON = try #require(String(data: localData, encoding: .utf8))

        #expect(!localJSON.contains(sentinel))
        #expect(local.structuredContent?.objectValue?["error"]?
            .objectValue?["code"]?.stringValue == "BROKER_UNAVAILABLE")
    }

    @Test("real dual pipes initialize, list, call, and stop cleanly on EOF", .timeLimit(.minutes(1)))
    func stdioLifecycleThroughRealPipes() async throws {
        let status = VaultAgentStatus(
            client: .codex,
            installed: true,
            authorized: true,
            vaultReady: true,
            idleExpiresAt: nil,
            hardExpiresAt: nil,
            protocolVersion: VaultAgentLimits.protocolVersion
        )
        let requester = VaultAgentRequestProbe(responses: [.success(.status(status))])
        let server = PasteraMCPServer(client: requester)
        let pipes = try MCPDuplexPipes()
        let runTask = Task {
            try await server.run(
                inputFileDescriptor: pipes.serverInput,
                outputFileDescriptor: pipes.serverOutput
            )
        }
        let transport = StdioTransport(
            input: FileDescriptor(rawValue: pipes.clientInput),
            output: FileDescriptor(rawValue: pipes.clientOutput),
            logger: nil
        )
        let client = Client(name: "PasteraTask7Tests", version: "1")

        let initialization = try await client.connect(transport: transport)
        let tools = try await client.listTools().tools
        let call = try await client.callTool(name: "vault_status", arguments: [:])

        #expect(initialization.serverInfo.name == "pastera-vault")
        #expect(tools.map(\.name) == [
            "vault_status",
            "vault_search",
            "vault_get",
            "vault_paste",
            "vault_prepare_exec"
        ])
        #expect(call.isError == false)
        let operations = await requester.operationsSnapshot()
        #expect(operations == [.status])

        await client.disconnect()
        pipes.closeClientOutput()
        try await withTask7Timeout { try await runTask.value }
    }

    @Test("external stop ends an idle stdio server without waiting for EOF", .timeLimit(.minutes(1)))
    func externalStopEndsIdleServer() async throws {
        let server = PasteraMCPServer(client: VaultAgentRequestProbe(responses: []))
        let pipes = try MCPDuplexPipes()
        let runTask = Task {
            try await server.run(
                inputFileDescriptor: pipes.serverInput,
                outputFileDescriptor: pipes.serverOutput
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        await server.stop()
        try await withTask7Timeout { try await runTask.value }
    }
}

private actor VaultAgentRequestProbe: VaultAgentRequesting {
    private(set) var operations: [VaultAgentOperation] = []
    private var responses: [VaultAgentResponseBody]

    init(responses: [VaultAgentResponseBody]) {
        self.responses = responses
    }

    func request(_ operation: VaultAgentOperation) async throws -> VaultAgentResponseBody {
        operations.append(operation)
        guard !responses.isEmpty else { throw VaultAgentClientError.unavailable }
        return responses.removeFirst()
    }

    func operationsSnapshot() -> [VaultAgentOperation] { operations }
}

private struct VaultAgentThrowingRequester: VaultAgentRequesting {
    struct SentinelError: Error { let value: String }

    let sentinel: String

    func request(_ operation: VaultAgentOperation) async throws -> VaultAgentResponseBody {
        throw SentinelError(value: sentinel)
    }
}

private final class MCPDuplexPipes: @unchecked Sendable {
    private let lock = NSLock()
    private var openDescriptors: Set<Int32>
    let serverInput: Int32
    let clientOutput: Int32
    let clientInput: Int32
    let serverOutput: Int32

    init() throws {
        var clientToServer = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&clientToServer) == 0 else {
            throw POSIXError(.EMFILE)
        }
        var serverToClient = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&serverToClient) == 0 else {
            Darwin.close(clientToServer[0])
            Darwin.close(clientToServer[1])
            throw POSIXError(.EMFILE)
        }
        serverInput = clientToServer[0]
        clientOutput = clientToServer[1]
        clientInput = serverToClient[0]
        serverOutput = serverToClient[1]
        openDescriptors = Set(clientToServer + serverToClient)
    }

    deinit {
        let descriptors = lock.withLock { () -> [Int32] in
            defer { openDescriptors.removeAll() }
            return Array(openDescriptors)
        }
        for descriptor in descriptors { Darwin.close(descriptor) }
    }

    func closeClientOutput() {
        close(clientOutput)
    }

    private func close(_ descriptor: Int32) {
        let shouldClose = lock.withLock { openDescriptors.remove(descriptor) != nil }
        if shouldClose { Darwin.close(descriptor) }
    }
}

private enum Task7TimeoutError: Error { case elapsed }

private func withTask7Timeout<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(2))
            throw Task7TimeoutError.elapsed
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}
