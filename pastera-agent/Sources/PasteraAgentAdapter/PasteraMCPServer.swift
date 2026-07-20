import Foundation
import MCP
import PasteraAgentProtocol

// Five complete JSON schemas intentionally stay beside their handlers for auditability.
// swiftlint:disable file_length

#if canImport(System)
import System
#else
import SystemPackage
#endif

public final class PasteraMCPServer: @unchecked Sendable {
    private enum ToolName: String, CaseIterable {
        case status = "vault_status"
        case search = "vault_search"
        case get = "vault_get"
        case paste = "vault_paste"
        case prepareExec = "vault_prepare_exec"
    }

    private let client: any VaultAgentRequesting
    private let serverLock = NSLock()
    private var activeServer: Server?
    private let admissionLock = NSLock()
    private var requestInFlight = false

    public init(client: any VaultAgentRequesting) {
        self.client = client
    }
}

public extension PasteraMCPServer {
    // The five fixed tool contracts are intentionally visible together.
    // swiftlint:disable:next function_body_length
    static func makeTools() -> [Tool] {
        [
            Tool(
                name: ToolName.status.rawValue,
                description: "查看 Pastera 密码箱授权与就绪状态。",
                inputSchema: objectSchema(properties: [:], required: []),
                annotations: .init(
                    readOnlyHint: true,
                    destructiveHint: false,
                    openWorldHint: false
                ),
                outputSchema: outputSchema(successProperties: ["status": statusSchema])
            ),
            Tool(
                name: ToolName.search.rawValue,
                description: "在 Pastera 密码箱中分页搜索元数据，不返回密码或备注。",
                inputSchema: objectSchema(
                    properties: [
                        "query": stringSchema(maximumLength: VaultAgentLimits.maximumQueryBytes),
                        "folder_id": uuidSchema,
                        "limit": [
                            "type": "integer",
                            "minimum": .int(1),
                            "maximum": .int(VaultAgentLimits.maximumPageSize),
                            "default": .int(VaultAgentLimits.defaultPageSize)
                        ],
                        "cursor": stringSchema(maximumLength: VaultAgentLimits.maximumCursorBytes)
                    ],
                    required: []
                ),
                annotations: .init(
                    readOnlyHint: true,
                    destructiveHint: false,
                    openWorldHint: false
                ),
                outputSchema: outputSchema(successProperties: [
                    "entries": [
                        "type": "array",
                        "maxItems": .int(VaultAgentLimits.maximumPageSize),
                        "items": metadataSchema
                    ],
                    "next_cursor": nullable(stringSchema(
                        maximumLength: VaultAgentLimits.maximumCursorBytes
                    ))
                ])
            ),
            Tool(
                name: ToolName.get.rawValue,
                description: "按 ID 读取一条密码箱元数据，不返回密码或备注。",
                inputSchema: objectSchema(
                    properties: ["entry_id": uuidSchema],
                    required: ["entry_id"]
                ),
                annotations: .init(
                    readOnlyHint: true,
                    destructiveHint: false,
                    openWorldHint: false
                ),
                outputSchema: outputSchema(successProperties: ["entry": metadataSchema])
            ),
            Tool(
                name: ToolName.paste.rawValue,
                description: "将用户名或密码安全粘贴到最近的外部目标。",
                inputSchema: objectSchema(
                    properties: [
                        "entry_id": uuidSchema,
                        "field": enumSchema(["username", "password"])
                    ],
                    required: ["entry_id", "field"]
                ),
                annotations: .init(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: false,
                    openWorldHint: true
                ),
                outputSchema: outputSchema(successProperties: [:])
            ),
            Tool(
                name: ToolName.prepareExec.rawValue,
                description: "创建限时单次票据，用 stdin 或继承 fd 向命令注入一个字段。",
                inputSchema: objectSchema(
                    properties: [
                        "entry_id": uuidSchema,
                        "field": enumSchema(["username", "password"]),
                        "mode": enumSchema(["stdin", "fd"])
                    ],
                    required: ["entry_id", "field", "mode"]
                ),
                annotations: .init(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: false,
                    openWorldHint: false
                ),
                outputSchema: outputSchema(successProperties: [
                    "ticket": stringSchema(maximumLength: VaultAgentLimits.maximumTokenBytes),
                    "expires_at": ["type": "string", "format": "date-time"],
                    "command": [
                        "type": "array",
                        "maxItems": .int(VaultAgentLimits.maximumCommandArguments),
                        "items": stringSchema(
                            maximumLength: VaultAgentLimits.maximumCommandArgumentBytes
                        )
                    ]
                ])
            )
        ]
    }

    func run(
        inputFileDescriptor: Int32 = STDIN_FILENO,
        outputFileDescriptor: Int32 = STDOUT_FILENO
    ) async throws {
        let server = Server(
            name: "pastera-vault",
            version: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "1",
            capabilities: .init(tools: .init(listChanged: false)),
            configuration: .strict
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.makeTools())
        }
        await server.withMethodHandler(CallTool.self) { [self] parameters in
            await call(name: parameters.name, arguments: parameters.arguments)
        }
        serverLock.withLock { activeServer = server }
        let transport = StdioTransport(
            input: FileDescriptor(rawValue: inputFileDescriptor),
            output: FileDescriptor(rawValue: outputFileDescriptor),
            logger: nil
        )
        do {
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
            await stop()
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        let server = serverLock.withLock { () -> Server? in
            defer { activeServer = nil }
            return activeServer
        }
        await server?.stop()
    }
}

extension PasteraMCPServer {
    func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        guard let tool = ToolName(rawValue: name) else { return invalidRequest() }
        let operation: VaultAgentOperation
        do {
            operation = try parse(tool: tool, arguments: arguments ?? [:])
        } catch {
            return invalidRequest()
        }
        guard acquireAdmission() else { return failure(Self.busyFailure) }
        defer { releaseAdmission() }

        do {
            switch try await client.request(operation) {
            case let .success(payload): return success(payload: payload, for: tool)
            case let .failure(failure): return self.failure(failure)
            }
        } catch {
            return failure(Self.localUnavailableFailure)
        }
    }

    private func acquireAdmission() -> Bool {
        admissionLock.withLock {
            guard !requestInFlight else { return false }
            requestInFlight = true
            return true
        }
    }

    private func releaseAdmission() {
        admissionLock.withLock { requestInFlight = false }
    }

    private func parse(
        tool: ToolName,
        arguments: [String: Value]
    ) throws -> VaultAgentOperation {
        switch tool {
        case .status:
            try requireKeys(arguments, allowed: [])
            return .status
        case .search:
            try requireKeys(arguments, allowed: ["query", "folder_id", "limit", "cursor"])
            let query = try optionalString(
                arguments["query"],
                maximumBytes: VaultAgentLimits.maximumQueryBytes
            )
            let folderID = try optionalUUID(arguments["folder_id"])
            let limit: Int
            if let value = arguments["limit"] {
                guard let decoded = value.intValue else {
                    throw VaultAgentClientError.protocolFailure
                }
                limit = decoded
            } else {
                limit = VaultAgentLimits.defaultPageSize
            }
            guard (1...VaultAgentLimits.maximumPageSize).contains(limit) else {
                throw VaultAgentClientError.protocolFailure
            }
            let cursor = try optionalString(
                arguments["cursor"],
                maximumBytes: VaultAgentLimits.maximumCursorBytes
            )
            return .search(.init(
                query: query,
                folderID: folderID,
                limit: limit,
                cursor: cursor
            ))
        case .get:
            try requireKeys(arguments, allowed: ["entry_id"])
            return .get(entryID: try requiredUUID(arguments["entry_id"]))
        case .paste:
            try requireKeys(arguments, allowed: ["entry_id", "field"])
            return .paste(
                entryID: try requiredUUID(arguments["entry_id"]),
                field: try requiredField(arguments["field"])
            )
        case .prepareExec:
            try requireKeys(arguments, allowed: ["entry_id", "field", "mode"])
            return .prepareExec(
                entryID: try requiredUUID(arguments["entry_id"]),
                field: try requiredField(arguments["field"]),
                mode: try requiredMode(arguments["mode"])
            )
        }
    }

    private func success(
        payload: VaultAgentResponsePayload,
        for tool: ToolName
    ) -> CallTool.Result {
        let value: Value
        switch (tool, payload) {
        case let (.status, .status(status)):
            value = ["ok": true, "status": Self.statusValue(status)]
        case let (.search, .search(page)):
            value = [
                "ok": true,
                "entries": .array(page.entries.map(Self.metadataValue)),
                "next_cursor": page.nextCursor.map(Value.string) ?? .null
            ]
        case let (.get, .entry(entry)):
            value = ["ok": true, "entry": Self.metadataValue(entry)]
        case (.paste, .empty):
            value = ["ok": true]
        case let (.prepareExec, .ticket(ticket)):
            value = [
                "ok": true,
                "ticket": .string(ticket.token),
                "expires_at": .string(Self.dateString(ticket.expiresAt)),
                "command": .array(ticket.command.map(Value.string))
            ]
        default:
            return failure(Self.localUnavailableFailure)
        }
        return boundedResult(
            structuredContent: value,
            text: "操作成功。",
            isError: false
        )
    }

    private func failure(_ failure: VaultAgentFailure) -> CallTool.Result {
        var error: [String: Value] = [
            "code": .string(failure.code.rawValue),
            "message": .string(failure.message),
            "retryable": .bool(failure.retryable)
        ]
        if let retryAfter = failure.retryAfterMilliseconds {
            error["retry_after_ms"] = .int(retryAfter)
        }
        return boundedResult(
            structuredContent: ["ok": false, "error": .object(error)],
            text: "请求未完成。",
            isError: true
        )
    }

    private func invalidRequest() -> CallTool.Result {
        failure(.init(
            code: .invalidRequest,
            message: "Request is invalid.",
            retryable: false,
            retryAfterMilliseconds: nil
        ))
    }

    private func boundedResult(
        structuredContent: Value,
        text: String,
        isError: Bool
    ) -> CallTool.Result {
        guard let encoded = try? JSONEncoder().encode(structuredContent),
              encoded.count <= VaultAgentLimits.maximumResponseBytes else {
            if isError { return Self.minimumUnavailableResult }
            return failure(Self.localUnavailableFailure)
        }
        return CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: Optional.some(structuredContent),
            isError: isError
        )
    }

    private func requireKeys(
        _ arguments: [String: Value],
        allowed: Set<String>
    ) throws {
        guard Set(arguments.keys).isSubset(of: allowed) else {
            throw VaultAgentClientError.protocolFailure
        }
    }

    private func optionalString(_ value: Value?, maximumBytes: Int) throws -> String? {
        guard let value else { return nil }
        guard let string = value.stringValue,
              string.lengthOfBytes(using: .utf8) <= maximumBytes else {
            throw VaultAgentClientError.protocolFailure
        }
        return string
    }

    private func requiredUUID(_ value: Value?) throws -> UUID {
        guard let raw = value?.stringValue,
              raw.utf8.count == 36,
              let uuid = UUID(uuidString: raw),
              uuid.uuidString.lowercased() == raw.lowercased() else {
            throw VaultAgentClientError.protocolFailure
        }
        return uuid
    }

    private func optionalUUID(_ value: Value?) throws -> UUID? {
        guard value != nil else { return nil }
        return try requiredUUID(value)
    }

    private func requiredField(_ value: Value?) throws -> VaultAgentSecretField {
        guard let raw = value?.stringValue,
              let field = VaultAgentSecretField(rawValue: raw) else {
            throw VaultAgentClientError.protocolFailure
        }
        return field
    }

    private func requiredMode(_ value: Value?) throws -> VaultAgentInjectionMode {
        switch value?.stringValue {
        case "stdin": return .stdin
        case "fd": return .fileDescriptor
        default: throw VaultAgentClientError.protocolFailure
        }
    }

    private static func metadataValue(_ entry: VaultAgentEntryMetadata) -> Value {
        [
            "id": .string(entry.id.uuidString.lowercased()),
            "folder_id": .string(entry.folderID.uuidString.lowercased()),
            "folder_name": .string(entry.folderName),
            "title": .string(entry.title),
            "website": .string(entry.website),
            "username": .string(entry.username),
            "updated_at": .string(dateString(entry.updatedAt))
        ]
    }

    private static func statusValue(_ status: VaultAgentStatus) -> Value {
        [
            "client": .string(status.client.rawValue),
            "installed": .bool(status.installed),
            "authorized": .bool(status.authorized),
            "vault_ready": .bool(status.vaultReady),
            "idle_expires_at": status.idleExpiresAt.map { .string(dateString($0)) } ?? .null,
            "hard_expires_at": status.hardExpiresAt.map { .string(dateString($0)) } ?? .null,
            "protocol_version": .int(status.protocolVersion)
        ]
    }

    private static func dateString(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    private static let localUnavailableFailure = VaultAgentFailure(
        code: .brokerUnavailable,
        message: "Broker is unavailable.",
        retryable: false,
        retryAfterMilliseconds: nil
    )

    private static let busyFailure = VaultAgentFailure(
        code: .vaultBusy,
        message: "Vault is busy.",
        retryable: true,
        retryAfterMilliseconds: 50
    )

    private static let minimumUnavailableResult = CallTool.Result(
        content: [.text(text: "请求未完成。", annotations: nil, _meta: nil)],
        structuredContent: [
            "ok": false,
            "error": [
                "code": "BROKER_UNAVAILABLE",
                "message": "Broker is unavailable.",
                "retryable": false
            ]
        ],
        isError: true
    )
}

private extension PasteraMCPServer {
    static let uuidSchema: Value = [
        "type": "string",
        "format": "uuid",
        "minLength": 36,
        "maxLength": 36
    ]

    static let metadataSchema: Value = objectSchema(
        properties: [
            "id": uuidSchema,
            "folder_id": uuidSchema,
            "folder_name": stringSchema(maximumLength: VaultAgentLimits.maximumMetadataFieldBytes),
            "title": stringSchema(maximumLength: VaultAgentLimits.maximumMetadataFieldBytes),
            "website": stringSchema(maximumLength: VaultAgentLimits.maximumMetadataFieldBytes),
            "username": stringSchema(maximumLength: VaultAgentLimits.maximumMetadataFieldBytes),
            "updated_at": ["type": "string", "format": "date-time"]
        ],
        required: [
            "id", "folder_id", "folder_name", "title", "website", "username", "updated_at"
        ]
    )

    static let statusSchema: Value = objectSchema(
        properties: [
            "client": enumSchema(VaultAgentClientKind.allCases.map(\.rawValue)),
            "installed": ["type": "boolean"],
            "authorized": ["type": "boolean"],
            "vault_ready": ["type": "boolean"],
            "idle_expires_at": nullable(["type": "string", "format": "date-time"]),
            "hard_expires_at": nullable(["type": "string", "format": "date-time"]),
            "protocol_version": [
                "type": "integer",
                "const": .int(VaultAgentLimits.protocolVersion)
            ]
        ],
        required: [
            "client", "installed", "authorized", "vault_ready",
            "idle_expires_at", "hard_expires_at", "protocol_version"
        ]
    )

    static let errorSchema: Value = objectSchema(
        properties: [
            "code": enumSchema(VaultAgentErrorCode.allCases.map(\.rawValue)),
            "message": stringSchema(maximumLength: VaultAgentLimits.maximumErrorMessageBytes),
            "retryable": ["type": "boolean"],
            "retry_after_ms": ["type": "integer", "minimum": 0, "maximum": 60_000]
        ],
        required: ["code", "message", "retryable"]
    )

    static func outputSchema(successProperties: [String: Value]) -> Value {
        var properties = successProperties
        properties["ok"] = ["type": "boolean"]
        properties["error"] = errorSchema
        var successfulProperties = successProperties
        successfulProperties["ok"] = ["type": "boolean", "const": true]
        let failedProperties: [String: Value] = [
            "ok": ["type": "boolean", "const": false],
            "error": errorSchema
        ]
        let successRequired = ["ok"] + successProperties.keys.sorted()
        return [
            "type": "object",
            "properties": .object(properties),
            "required": ["ok"],
            "additionalProperties": false,
            "oneOf": [
                objectSchema(properties: successfulProperties, required: successRequired),
                objectSchema(properties: failedProperties, required: ["ok", "error"])
            ]
        ]
    }

    static func objectSchema(
        properties: [String: Value],
        required: [String]
    ) -> Value {
        [
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map(Value.string)),
            "additionalProperties": false
        ]
    }

    static func stringSchema(maximumLength: Int) -> Value {
        ["type": "string", "maxLength": .int(maximumLength)]
    }

    static func enumSchema(_ values: [String]) -> Value {
        ["type": "string", "enum": .array(values.map(Value.string))]
    }

    static func nullable(_ schema: Value) -> Value {
        ["anyOf": .array([schema, ["type": "null"]])]
    }
}
