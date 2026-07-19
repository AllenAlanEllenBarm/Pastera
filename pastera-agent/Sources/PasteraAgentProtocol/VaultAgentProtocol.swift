import Foundation

public enum VaultAgentLimits {
    public static let protocolVersion = 1
    public static let maximumFrameBytes = 65_536
    public static let maximumQueryBytes = 512
    public static let maximumPageSize = 50
    public static let defaultPageSize = 20
    public static let maximumResponseBytes = 32 * 1_024
    public static let maximumMetadataFieldBytes = 2_048
    public static let maximumCursorBytes = 2_048
    public static let maximumTokenBytes = 1_024
    public static let maximumPathBytes = 4_096
    public static let maximumCommandArguments = 64
    public static let maximumCommandArgumentBytes = 4_096
    public static let maximumErrorMessageBytes = 1_024
    public static let maximumSecretBytes = 16 * 1_024
    public static let publicKeyBytes = 32
    public static let nonceBytes = 32
}

public enum VaultAgentProtocolError: Error, Equatable, Sendable {
    case frameTooLarge
    case malformedFrame
    case limitExceeded
    case invalidValue
    case replayedFrame
    case outOfOrderFrame
    case connectionMismatch
    case authenticationFailed
    case sequenceExhausted
    case protocolMismatch
}

public enum VaultAgentClientKind: String, Codable, CaseIterable, Hashable, Sendable {
    case codex
    case claude
    case cli

    public init(from decoder: Decoder) throws { self = try decodeRawEnum(Self.self, from: decoder) }
    public func encode(to encoder: Encoder) throws { try encodeRawEnum(self, to: encoder) }
}

public enum VaultAgentSecretField: String, Codable, Sendable {
    case username
    case password

    public init(from decoder: Decoder) throws { self = try decodeRawEnum(Self.self, from: decoder) }
    public func encode(to encoder: Encoder) throws { try encodeRawEnum(self, to: encoder) }
}

public enum VaultAgentInjectionMode: String, Codable, Sendable {
    case stdin
    case fileDescriptor

    public init(from decoder: Decoder) throws { self = try decodeRawEnum(Self.self, from: decoder) }
    public func encode(to encoder: Encoder) throws { try encodeRawEnum(self, to: encoder) }
}

public enum VaultAgentHostKind: String, Codable, Sendable {
    case codex
    case claude

    public init(from decoder: Decoder) throws { self = try decodeRawEnum(Self.self, from: decoder) }
    public func encode(to encoder: Encoder) throws { try encodeRawEnum(self, to: encoder) }
}

public struct VaultAgentEntryMetadata: Codable, Equatable, Sendable {
    public let id: UUID
    public let folderID: UUID
    public let folderName: String
    public let title: String
    public let website: String
    public let username: String
    public let updatedAt: Date

    public init(id: UUID, folderID: UUID, folderName: String, title: String, website: String, username: String, updatedAt: Date) {
        self.id = id
        self.folderID = folderID
        self.folderName = folderName
        self.title = title
        self.website = website
        self.username = username
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let folderName = try values.decode(String.self, forKey: .folderName)
        let title = try values.decode(String.self, forKey: .title)
        let website = try values.decode(String.self, forKey: .website)
        let username = try values.decode(String.self, forKey: .username)
        try validateMetadataField(folderName)
        try validateMetadataField(title)
        try validateMetadataField(website)
        try validateMetadataField(username)
        id = try values.decode(UUID.self, forKey: .id)
        folderID = try values.decode(UUID.self, forKey: .folderID)
        self.folderName = folderName
        self.title = title
        self.website = website
        self.username = username
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

public struct VaultAgentSearchRequest: Codable, Equatable, Sendable {
    public let query: String?
    public let folderID: UUID?
    public let limit: Int
    public let cursor: String?

    public init(query: String?, folderID: UUID?, limit: Int, cursor: String?) {
        self.query = query
        self.folderID = folderID
        self.limit = limit
        self.cursor = cursor
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let query = try values.decodeIfPresent(String.self, forKey: .query)
        let limit = try values.decode(Int.self, forKey: .limit)
        let cursor = try values.decodeIfPresent(String.self, forKey: .cursor)
        try validateOptionalUTF8(query, maximum: VaultAgentLimits.maximumQueryBytes)
        try validate(limit: limit, in: 1...VaultAgentLimits.maximumPageSize)
        try validateOptionalUTF8(cursor, maximum: VaultAgentLimits.maximumCursorBytes)
        self.query = query
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        self.limit = limit
        self.cursor = cursor
    }
}

public struct VaultAgentSearchPage: Codable, Equatable, Sendable {
    public let entries: [VaultAgentEntryMetadata]
    public let nextCursor: String?

    public init(entries: [VaultAgentEntryMetadata], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try values.decode([VaultAgentEntryMetadata].self, forKey: .entries)
        let nextCursor = try values.decodeIfPresent(String.self, forKey: .nextCursor)
        guard entries.count <= VaultAgentLimits.maximumPageSize else {
            throw VaultAgentProtocolError.limitExceeded
        }
        try validateOptionalUTF8(nextCursor, maximum: VaultAgentLimits.maximumCursorBytes)
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

public struct VaultAgentStatus: Codable, Equatable, Sendable {
    public let client: VaultAgentClientKind
    public let installed: Bool
    public let authorized: Bool
    public let vaultReady: Bool
    public let idleExpiresAt: Date?
    public let hardExpiresAt: Date?
    public let protocolVersion: Int

    public init(client: VaultAgentClientKind, installed: Bool, authorized: Bool, vaultReady: Bool, idleExpiresAt: Date?, hardExpiresAt: Date?, protocolVersion: Int) {
        self.client = client
        self.installed = installed
        self.authorized = authorized
        self.vaultReady = vaultReady
        self.idleExpiresAt = idleExpiresAt
        self.hardExpiresAt = hardExpiresAt
        self.protocolVersion = protocolVersion
    }
}

public struct VaultAgentPreparedTicket: Codable, Equatable, Sendable {
    public let token: String
    public let expiresAt: Date
    public let command: [String]

    public init(token: String, expiresAt: Date, command: [String]) {
        self.token = token
        self.expiresAt = expiresAt
        self.command = command
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let token = try values.decode(String.self, forKey: .token)
        let command = try values.decode([String].self, forKey: .command)
        try validateUTF8(token, maximum: VaultAgentLimits.maximumTokenBytes)
        guard command.count <= VaultAgentLimits.maximumCommandArguments else {
            throw VaultAgentProtocolError.limitExceeded
        }
        for argument in command {
            try validateUTF8(argument, maximum: VaultAgentLimits.maximumCommandArgumentBytes)
        }
        self.token = token
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        self.command = command
    }
}

public struct VaultAgentSecretDelivery: Codable, Equatable, Sendable {
    public let receiptID: UUID
    public let bytes: Data

    public init(receiptID: UUID, bytes: Data) {
        self.receiptID = receiptID
        self.bytes = bytes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let bytes = try values.decode(Data.self, forKey: .bytes)
        guard bytes.count <= VaultAgentLimits.maximumSecretBytes else {
            throw VaultAgentProtocolError.limitExceeded
        }
        receiptID = try values.decode(UUID.self, forKey: .receiptID)
        self.bytes = bytes
    }
}

public enum VaultAgentOperation: Codable, Equatable, Sendable {
    case status
    case search(VaultAgentSearchRequest)
    case get(entryID: UUID)
    case paste(entryID: UUID, field: VaultAgentSecretField)
    case copy(entryID: UUID, field: VaultAgentSecretField)
    case prepareExec(entryID: UUID, field: VaultAgentSecretField, mode: VaultAgentInjectionMode)
    case redeemTicket(token: String, mode: VaultAgentInjectionMode)
    case completeTicket(receiptID: UUID)
    case integrationStatus(host: VaultAgentHostKind?)
    case integrationInstall(host: VaultAgentHostKind)
    case integrationUninstall(host: VaultAgentHostKind)

    private enum CodingKeys: String, CodingKey { case type, payload }
    private enum WireType: String { case status, search, get, paste, copy, prepareExec = "prepare_exec", redeemTicket = "redeem_ticket", completeTicket = "complete_ticket", integrationStatus = "integration_status", integrationInstall = "integration_install", integrationUninstall = "integration_uninstall" }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = WireType(rawValue: try values.decode(String.self, forKey: .type)) else {
            throw VaultAgentProtocolError.invalidValue
        }
        switch type {
        case .status: self = .status
        case .search: self = .search(try values.decode(VaultAgentSearchRequest.self, forKey: .payload))
        case .get: self = .get(entryID: try values.decode(EntryIDPayload.self, forKey: .payload).entryID)
        case .paste:
            let payload = try values.decode(EntryFieldPayload.self, forKey: .payload)
            self = .paste(entryID: payload.entryID, field: payload.field)
        case .copy:
            let payload = try values.decode(EntryFieldPayload.self, forKey: .payload)
            self = .copy(entryID: payload.entryID, field: payload.field)
        case .prepareExec:
            let payload = try values.decode(EntryFieldModePayload.self, forKey: .payload)
            self = .prepareExec(entryID: payload.entryID, field: payload.field, mode: payload.mode)
        case .redeemTicket:
            let payload = try values.decode(TokenModePayload.self, forKey: .payload)
            try validateUTF8(payload.token, maximum: VaultAgentLimits.maximumTokenBytes)
            self = .redeemTicket(token: payload.token, mode: payload.mode)
        case .completeTicket: self = .completeTicket(receiptID: try values.decode(ReceiptPayload.self, forKey: .payload).receiptID)
        case .integrationStatus: self = .integrationStatus(host: try values.decodeIfPresent(HostPayload.self, forKey: .payload)?.host)
        case .integrationInstall: self = .integrationInstall(host: try values.decode(HostPayload.self, forKey: .payload).host)
        case .integrationUninstall: self = .integrationUninstall(host: try values.decode(HostPayload.self, forKey: .payload).host)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .status: try values.encode(WireType.status.rawValue, forKey: .type)
        case let .search(request): try values.encode(WireType.search.rawValue, forKey: .type); try values.encode(request, forKey: .payload)
        case let .get(entryID): try values.encode(WireType.get.rawValue, forKey: .type); try values.encode(EntryIDPayload(entryID: entryID), forKey: .payload)
        case let .paste(entryID, field): try values.encode(WireType.paste.rawValue, forKey: .type); try values.encode(EntryFieldPayload(entryID: entryID, field: field), forKey: .payload)
        case let .copy(entryID, field): try values.encode(WireType.copy.rawValue, forKey: .type); try values.encode(EntryFieldPayload(entryID: entryID, field: field), forKey: .payload)
        case let .prepareExec(entryID, field, mode): try values.encode(WireType.prepareExec.rawValue, forKey: .type); try values.encode(EntryFieldModePayload(entryID: entryID, field: field, mode: mode), forKey: .payload)
        case let .redeemTicket(token, mode): try values.encode(WireType.redeemTicket.rawValue, forKey: .type); try values.encode(TokenModePayload(token: token, mode: mode), forKey: .payload)
        case let .completeTicket(receiptID): try values.encode(WireType.completeTicket.rawValue, forKey: .type); try values.encode(ReceiptPayload(receiptID: receiptID), forKey: .payload)
        case let .integrationStatus(host): try values.encode(WireType.integrationStatus.rawValue, forKey: .type); try values.encodeIfPresent(host.map(HostPayload.init), forKey: .payload)
        case let .integrationInstall(host): try values.encode(WireType.integrationInstall.rawValue, forKey: .type); try values.encode(HostPayload(host: host), forKey: .payload)
        case let .integrationUninstall(host): try values.encode(WireType.integrationUninstall.rawValue, forKey: .type); try values.encode(HostPayload(host: host), forKey: .payload)
        }
    }
}

public enum VaultAgentErrorCode: String, Codable, CaseIterable, Error, Sendable {
    case authorizationRequired = "AUTHORIZATION_REQUIRED"
    case grantExpired = "GRANT_EXPIRED"
    case grantRevoked = "GRANT_REVOKED"
    case vaultNotConfigured = "VAULT_NOT_CONFIGURED"
    case automationUnlockUnavailable = "AUTOMATION_UNLOCK_UNAVAILABLE"
    case brokerUnavailable = "BROKER_UNAVAILABLE"
    case vaultBusy = "VAULT_BUSY"
    case rateLimited = "RATE_LIMITED"
    case entryNotFound = "ENTRY_NOT_FOUND"
    case targetUnavailable = "TARGET_UNAVAILABLE"
    case ticketExpired = "TICKET_EXPIRED"
    case ticketUsed = "TICKET_USED"
    case protocolMismatch = "PROTOCOL_MISMATCH"
    case invalidRequest = "INVALID_REQUEST"

    public init(from decoder: Decoder) throws { self = try decodeRawEnum(Self.self, from: decoder) }
    public func encode(to encoder: Encoder) throws { try encodeRawEnum(self, to: encoder) }
}

public struct VaultAgentFailure: Codable, Equatable, Sendable {
    public let code: VaultAgentErrorCode
    public let message: String
    public let retryable: Bool
    public let retryAfterMilliseconds: Int?

    public init(code: VaultAgentErrorCode, message: String, retryable: Bool, retryAfterMilliseconds: Int?) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.retryAfterMilliseconds = retryAfterMilliseconds
    }

    private enum CodingKeys: String, CodingKey { case code, message, retryable, retryAfterMilliseconds = "retry_after_ms" }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let message = try values.decode(String.self, forKey: .message)
        try validateUTF8(message, maximum: VaultAgentLimits.maximumErrorMessageBytes)
        code = try values.decode(VaultAgentErrorCode.self, forKey: .code)
        self.message = message
        retryable = try values.decode(Bool.self, forKey: .retryable)
        retryAfterMilliseconds = try values.decodeIfPresent(Int.self, forKey: .retryAfterMilliseconds)
    }
}

public struct VaultAgentHostIntegrationStatus: Codable, Equatable, Sendable {
    public let host: VaultAgentHostKind
    public let hostDetected: Bool
    public let hostExecutablePath: String?
    public let mcpInstalled: Bool
    public let skillInstalled: Bool
    public let installedVersion: String?
    public let authorized: Bool
    public let idleExpiresAt: Date?
    public let hardExpiresAt: Date?

    public init(host: VaultAgentHostKind, hostDetected: Bool, hostExecutablePath: String?, mcpInstalled: Bool, skillInstalled: Bool, installedVersion: String?, authorized: Bool, idleExpiresAt: Date?, hardExpiresAt: Date?) {
        self.host = host
        self.hostDetected = hostDetected
        self.hostExecutablePath = hostExecutablePath
        self.mcpInstalled = mcpInstalled
        self.skillInstalled = skillInstalled
        self.installedVersion = installedVersion
        self.authorized = authorized
        self.idleExpiresAt = idleExpiresAt
        self.hardExpiresAt = hardExpiresAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let hostExecutablePath = try values.decodeIfPresent(String.self, forKey: .hostExecutablePath)
        let installedVersion = try values.decodeIfPresent(String.self, forKey: .installedVersion)
        try validateOptionalUTF8(hostExecutablePath, maximum: VaultAgentLimits.maximumPathBytes)
        try validateOptionalUTF8(installedVersion, maximum: VaultAgentLimits.maximumMetadataFieldBytes)
        host = try values.decode(VaultAgentHostKind.self, forKey: .host)
        hostDetected = try values.decode(Bool.self, forKey: .hostDetected)
        self.hostExecutablePath = hostExecutablePath
        mcpInstalled = try values.decode(Bool.self, forKey: .mcpInstalled)
        skillInstalled = try values.decode(Bool.self, forKey: .skillInstalled)
        self.installedVersion = installedVersion
        authorized = try values.decode(Bool.self, forKey: .authorized)
        idleExpiresAt = try values.decodeIfPresent(Date.self, forKey: .idleExpiresAt)
        hardExpiresAt = try values.decodeIfPresent(Date.self, forKey: .hardExpiresAt)
    }
}

public struct VaultAgentIntegrationStatus: Codable, Equatable, Sendable {
    public let hosts: [VaultAgentHostIntegrationStatus]

    public init(hosts: [VaultAgentHostIntegrationStatus]) {
        self.hosts = hosts
    }

    public init(from decoder: Decoder) throws {
        let hosts = try decoder.container(keyedBy: CodingKeys.self).decode([VaultAgentHostIntegrationStatus].self, forKey: .hosts)
        guard hosts.count <= 2 else {
            throw VaultAgentProtocolError.limitExceeded
        }
        self.hosts = hosts
    }
}

public enum VaultAgentResponsePayload: Codable, Equatable, Sendable {
    case empty
    case status(VaultAgentStatus)
    case search(VaultAgentSearchPage)
    case entry(VaultAgentEntryMetadata)
    case ticket(VaultAgentPreparedTicket)
    case secretDelivery(VaultAgentSecretDelivery)
    case integrationStatus(VaultAgentIntegrationStatus)

    private enum CodingKeys: String, CodingKey { case type, payload }
    private enum WireType: String { case empty, status, search, entry, ticket, secretDelivery = "secret_delivery", integrationStatus = "integration_status" }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = WireType(rawValue: try values.decode(String.self, forKey: .type)) else {
            throw VaultAgentProtocolError.invalidValue
        }
        switch type {
        case .empty: self = .empty
        case .status: self = .status(try values.decode(VaultAgentStatus.self, forKey: .payload))
        case .search: self = .search(try values.decode(VaultAgentSearchPage.self, forKey: .payload))
        case .entry: self = .entry(try values.decode(VaultAgentEntryMetadata.self, forKey: .payload))
        case .ticket: self = .ticket(try values.decode(VaultAgentPreparedTicket.self, forKey: .payload))
        case .secretDelivery: self = .secretDelivery(try values.decode(VaultAgentSecretDelivery.self, forKey: .payload))
        case .integrationStatus: self = .integrationStatus(try values.decode(VaultAgentIntegrationStatus.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty: try values.encode(WireType.empty.rawValue, forKey: .type)
        case let .status(status): try values.encode(WireType.status.rawValue, forKey: .type); try values.encode(status, forKey: .payload)
        case let .search(page): try values.encode(WireType.search.rawValue, forKey: .type); try values.encode(page, forKey: .payload)
        case let .entry(entry): try values.encode(WireType.entry.rawValue, forKey: .type); try values.encode(entry, forKey: .payload)
        case let .ticket(ticket): try values.encode(WireType.ticket.rawValue, forKey: .type); try values.encode(ticket, forKey: .payload)
        case let .secretDelivery(delivery): try values.encode(WireType.secretDelivery.rawValue, forKey: .type); try values.encode(delivery, forKey: .payload)
        case let .integrationStatus(status): try values.encode(WireType.integrationStatus.rawValue, forKey: .type); try values.encode(status, forKey: .payload)
        }
    }
}

public enum VaultAgentResponseBody: Codable, Equatable, Sendable {
    case success(VaultAgentResponsePayload)
    case failure(VaultAgentFailure)

    private enum CodingKeys: String, CodingKey { case type, payload }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "success": self = .success(try values.decode(VaultAgentResponsePayload.self, forKey: .payload))
        case "failure": self = .failure(try values.decode(VaultAgentFailure.self, forKey: .payload))
        default: throw VaultAgentProtocolError.invalidValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .success(payload): try values.encode("success", forKey: .type); try values.encode(payload, forKey: .payload)
        case let .failure(failure): try values.encode("failure", forKey: .type); try values.encode(failure, forKey: .payload)
        }
    }
}

public struct VaultAgentRequestEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let connectionID: UUID
    public let sequence: UInt64
    public let requestID: UUID
    public let operation: VaultAgentOperation

    public init(protocolVersion: Int, connectionID: UUID, sequence: UInt64, requestID: UUID, operation: VaultAgentOperation) {
        self.protocolVersion = protocolVersion
        self.connectionID = connectionID
        self.sequence = sequence
        self.requestID = requestID
        self.operation = operation
    }
}

public struct VaultAgentResponseEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let connectionID: UUID
    public let sequence: UInt64
    public let requestID: UUID
    public let body: VaultAgentResponseBody

    public init(protocolVersion: Int, connectionID: UUID, sequence: UInt64, requestID: UUID, body: VaultAgentResponseBody) {
        self.protocolVersion = protocolVersion
        self.connectionID = connectionID
        self.sequence = sequence
        self.requestID = requestID
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        let storage = try VaultAgentResponseEnvelopeStorage(from: decoder)
        protocolVersion = storage.protocolVersion
        connectionID = storage.connectionID
        sequence = storage.sequence
        requestID = storage.requestID
        body = storage.body
    }

    public func encode(to encoder: Encoder) throws {
        let storage = VaultAgentResponseEnvelopeStorage(
            protocolVersion: protocolVersion,
            connectionID: connectionID,
            sequence: sequence,
            requestID: requestID,
            body: body
        )
        guard try JSONEncoder().encode(storage).count <= VaultAgentLimits.maximumResponseBytes else {
            throw VaultAgentProtocolError.limitExceeded
        }
        try storage.encode(to: encoder)
    }
}

private struct EntryIDPayload: Codable, Equatable, Sendable { let entryID: UUID }
private struct EntryFieldPayload: Codable, Equatable, Sendable { let entryID: UUID; let field: VaultAgentSecretField }
private struct EntryFieldModePayload: Codable, Equatable, Sendable { let entryID: UUID; let field: VaultAgentSecretField; let mode: VaultAgentInjectionMode }
private struct TokenModePayload: Codable, Equatable, Sendable { let token: String; let mode: VaultAgentInjectionMode }
private struct ReceiptPayload: Codable, Equatable, Sendable { let receiptID: UUID }
private struct HostPayload: Codable, Equatable, Sendable { let host: VaultAgentHostKind }
private struct VaultAgentResponseEnvelopeStorage: Codable {
    let protocolVersion: Int
    let connectionID: UUID
    let sequence: UInt64
    let requestID: UUID
    let body: VaultAgentResponseBody
}

private func validateMetadataField(_ value: String) throws { try validateUTF8(value, maximum: VaultAgentLimits.maximumMetadataFieldBytes) }
private func validateOptionalUTF8(_ value: String?, maximum: Int) throws { if let value { try validateUTF8(value, maximum: maximum) } }
private func validateUTF8(_ value: String, maximum: Int) throws { guard value.lengthOfBytes(using: .utf8) <= maximum else { throw VaultAgentProtocolError.limitExceeded } }
private func validate(limit: Int, in range: ClosedRange<Int>) throws { guard range.contains(limit) else { throw VaultAgentProtocolError.limitExceeded } }
private func decodeRawEnum<T: RawRepresentable>(_ type: T.Type, from decoder: Decoder) throws -> T where T.RawValue == String {
    guard let value = T(rawValue: try decoder.singleValueContainer().decode(String.self)) else {
        throw VaultAgentProtocolError.invalidValue
    }
    return value
}
private func encodeRawEnum<T: RawRepresentable>(_ value: T, to encoder: Encoder) throws where T.RawValue == String {
    var container = encoder.singleValueContainer()
    try container.encode(value.rawValue)
}
