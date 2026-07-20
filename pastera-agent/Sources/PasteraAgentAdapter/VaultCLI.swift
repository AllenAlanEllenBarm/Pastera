import Darwin
import Foundation
import PasteraAgentProtocol

public enum VaultCLIError: Error, Equatable, Sendable {
    case invalidArguments
    case unsafeResponse
    case outputTooLarge
    case brokerFailure
    case executionFailure
}

public enum VaultAgentCommandInput: Equatable, Sendable {
    case standardInput
    case fileDescriptor(Int32)

    var injectionMode: VaultAgentInjectionMode {
        switch self {
        case .standardInput: .stdin
        case .fileDescriptor: .fileDescriptor
        }
    }
}

public enum VaultCLICommand: Equatable, Sendable {
    case integrationStatus(host: VaultAgentHostKind?, json: Bool)
    case integrationInstall(host: VaultAgentHostKind)
    case integrationUninstall(host: VaultAgentHostKind)
    case status(json: Bool)
    case search(query: String?, folderID: UUID?, limit: Int, cursor: String?, json: Bool)
    case get(entryID: UUID, json: Bool)
    case paste(entryID: UUID, field: VaultAgentSecretField)
    case copy(entryID: UUID, field: VaultAgentSecretField)
    case exec(ticket: String, input: VaultAgentCommandInput, command: [String])

    public static func parse(_ arguments: [String]) throws -> Self {
        guard let root = arguments.first else { throw VaultCLIError.invalidArguments }
        let remaining = Array(arguments.dropFirst())
        switch root {
        case "integration": return try parseIntegration(remaining)
        case "vault": return try parseVault(remaining)
        case "exec": return try parseExec(remaining)
        default: throw VaultCLIError.invalidArguments
        }
    }

    private static func parseIntegration(_ arguments: [String]) throws -> Self {
        guard let action = arguments.first else { throw VaultCLIError.invalidArguments }
        let remaining = Array(arguments.dropFirst())
        switch action {
        case "status":
            var host: VaultAgentHostKind?
            var json = false
            for argument in remaining {
                if argument == "--json" {
                    guard !json else { throw VaultCLIError.invalidArguments }
                    json = true
                } else {
                    guard host == nil, let parsedHost = VaultAgentHostKind(rawValue: argument) else {
                        throw VaultCLIError.invalidArguments
                    }
                    host = parsedHost
                }
            }
            return .integrationStatus(host: host, json: json)
        case "install", "uninstall":
            guard remaining.count == 1,
                  let host = VaultAgentHostKind(rawValue: remaining[0]) else {
                throw VaultCLIError.invalidArguments
            }
            return action == "install" ? .integrationInstall(host: host) : .integrationUninstall(host: host)
        default: throw VaultCLIError.invalidArguments
        }
    }

    private static func parseVault(_ arguments: [String]) throws -> Self {
        guard let action = arguments.first else { throw VaultCLIError.invalidArguments }
        let remaining = Array(arguments.dropFirst())
        switch action {
        case "status":
            return .status(json: try parseOnlyJSON(remaining))
        case "search":
            return try parseSearch(remaining)
        case "get":
            guard let first = remaining.first, let entryID = UUID(uuidString: first) else {
                throw VaultCLIError.invalidArguments
            }
            return .get(entryID: entryID, json: try parseOnlyJSON(Array(remaining.dropFirst())))
        case "paste", "copy":
            guard remaining.count == 3,
                  let entryID = UUID(uuidString: remaining[0]),
                  remaining[1] == "--field",
                  let field = VaultAgentSecretField(rawValue: remaining[2]) else {
                throw VaultCLIError.invalidArguments
            }
            return action == "paste" ? .paste(entryID: entryID, field: field) : .copy(entryID: entryID, field: field)
        default: throw VaultCLIError.invalidArguments
        }
    }

    private static func parseSearch(_ arguments: [String]) throws -> Self {
        var query: String?
        var folderID: UUID?
        var limit = VaultAgentLimits.defaultPageSize
        var cursor: String?
        var json = false
        var seenFolder = false
        var seenLimit = false
        var seenCursor = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--folder":
                guard !seenFolder, index + 1 < arguments.count,
                      let value = UUID(uuidString: arguments[index + 1]) else {
                    throw VaultCLIError.invalidArguments
                }
                seenFolder = true
                folderID = value
                index += 2
            case "--limit":
                guard !seenLimit, index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]), (1...VaultAgentLimits.maximumPageSize).contains(value) else {
                    throw VaultCLIError.invalidArguments
                }
                seenLimit = true
                limit = value
                index += 2
            case "--cursor":
                guard !seenCursor, index + 1 < arguments.count,
                      isBounded(arguments[index + 1], maximum: VaultAgentLimits.maximumCursorBytes) else {
                    throw VaultCLIError.invalidArguments
                }
                seenCursor = true
                cursor = arguments[index + 1]
                index += 2
            case "--json":
                guard !json else { throw VaultCLIError.invalidArguments }
                json = true
                index += 1
            default:
                guard !argument.hasPrefix("--"), query == nil,
                      isBounded(argument, maximum: VaultAgentLimits.maximumQueryBytes) else {
                    throw VaultCLIError.invalidArguments
                }
                query = argument
                index += 1
            }
        }
        return .search(query: query, folderID: folderID, limit: limit, cursor: cursor, json: json)
    }

    private static func parseExec(_ arguments: [String]) throws -> Self {
        let separators = arguments.indices.filter { arguments[$0] == "--" }
        guard separators.count == 1, let separator = separators.first,
              separator > 0, separator + 1 < arguments.count else {
            throw VaultCLIError.invalidArguments
        }
        let options = Array(arguments[..<separator])
        let command = Array(arguments[(separator + 1)...])
        guard command.count <= VaultAgentLimits.maximumCommandArguments,
              command.first?.isEmpty == false,
              command.allSatisfy({ isBounded($0, maximum: VaultAgentLimits.maximumCommandArgumentBytes, allowEmpty: true) }) else {
            throw VaultCLIError.invalidArguments
        }

        var ticket: String?
        var input: VaultAgentCommandInput?
        var index = 0
        while index < options.count {
            switch options[index] {
            case "--ticket":
                guard ticket == nil, index + 1 < options.count,
                      isBounded(options[index + 1], maximum: VaultAgentLimits.maximumTokenBytes) else {
                    throw VaultCLIError.invalidArguments
                }
                ticket = options[index + 1]
                index += 2
            case "--stdin":
                guard input == nil else { throw VaultCLIError.invalidArguments }
                input = .standardInput
                index += 1
            case "--fd":
                guard input == nil, index + 1 < options.count,
                      let value = Int32(options[index + 1]), (3...255).contains(value) else {
                    throw VaultCLIError.invalidArguments
                }
                input = .fileDescriptor(value)
                index += 2
            default: throw VaultCLIError.invalidArguments
            }
        }
        guard let ticket, let input else { throw VaultCLIError.invalidArguments }
        return .exec(ticket: ticket, input: input, command: command)
    }

    private static func parseOnlyJSON(_ arguments: [String]) throws -> Bool {
        switch arguments {
        case []: false
        case ["--json"]: true
        default: throw VaultCLIError.invalidArguments
        }
    }

    private static func isBounded(_ value: String, maximum: Int, allowEmpty: Bool = false) -> Bool {
        let count = value.utf8.count
        return (allowEmpty || count > 0) && count <= maximum
    }
}

public enum VaultCLIJSONRenderer {
    private static let maximumBytes = VaultAgentLimits.maximumResponseBytes

    public static func render(_ response: VaultAgentResponseBody) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let encodedValue: Data
        let prefix: String
        switch response {
        case let .failure(failure):
            prefix = #"{"ok":false,"error":"#
            encodedValue = try encoder.encode(failure)
        case let .success(payload):
            prefix = #"{"ok":true,"data":"#
            switch payload {
            case .empty:
                encodedValue = try encoder.encode(EmptyData())
            case let .status(value):
                encodedValue = try encoder.encode(value)
            case let .search(value):
                encodedValue = try encoder.encode(value)
            case let .entry(value):
                encodedValue = try encoder.encode(value)
            case let .integrationStatus(value):
                encodedValue = try encoder.encode(value)
            case .ticket, .secretDelivery:
                throw VaultCLIError.unsafeResponse
            }
        }
        guard let value = String(data: encodedValue, encoding: .utf8) else {
            throw VaultCLIError.outputTooLarge
        }
        let output = prefix + value + "}"
        guard output.utf8.count <= maximumBytes else { throw VaultCLIError.outputTooLarge }
        return output
    }

    private struct EmptyData: Encodable {}
}

public struct VaultCLIExecutionResult: Equatable, Sendable {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum VaultCLIOutputWriter {
    public static func write(_ result: VaultCLIExecutionResult) {
        write(result.stdout, to: STDOUT_FILENO)
        write(result.stderr, to: STDERR_FILENO)
    }

    private static func write(_ value: String, to descriptor: Int32) {
        guard !value.isEmpty else { return }
        let bytes = Array(value.utf8.prefix(VaultAgentLimits.maximumResponseBytes + 1))
        bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}

public struct VaultCLIApplication: Sendable {
    public typealias CommandExecutor = @Sendable (
        String,
        VaultAgentCommandInput,
        [String]
    ) async throws -> Int

    private let client: any VaultAgentRequesting
    private let runCommand: CommandExecutor

    public init(client: any VaultAgentRequesting) {
        self.client = client
        runCommand = { ticket, input, command in
            try await VaultAgentCommandRunner(client: client).run(
                ticket: ticket,
                input: input,
                command: command
            )
        }
    }

    public init(client: any VaultAgentRequesting, runCommand: @escaping CommandExecutor) {
        self.client = client
        self.runCommand = runCommand
    }

    public func run(arguments: [String]) async -> VaultCLIExecutionResult {
        let command: VaultCLICommand
        do {
            command = try VaultCLICommand.parse(arguments)
        } catch {
            return .init(exitCode: 2, stdout: "", stderr: "INVALID_REQUEST\n")
        }

        if case let .exec(ticket, input, childCommand) = command {
            do {
                let status = try await runCommand(ticket, input, childCommand)
                return .init(exitCode: status, stdout: "", stderr: "")
            } catch let error as VaultAgentCommandRunnerError {
                if case let .broker(failure) = error {
                    return .init(exitCode: 1, stdout: "", stderr: failure.code.rawValue + "\n")
                }
                if case .cancelled = error {
                    return .init(exitCode: 128 + Int(SIGTERM), stdout: "", stderr: "")
                }
                return .init(exitCode: 1, stdout: "", stderr: "EXECUTION_FAILED\n")
            } catch {
                return .init(exitCode: 1, stdout: "", stderr: "EXECUTION_FAILED\n")
            }
        }

        do {
            let response = try await client.request(operation(for: command))
            return try render(response, json: command.usesJSON)
        } catch {
            return localFailure(json: command.usesJSON)
        }
    }

    private func operation(for command: VaultCLICommand) -> VaultAgentOperation {
        switch command {
        case let .integrationStatus(host, _): .integrationStatus(host: host)
        case let .integrationInstall(host): .integrationInstall(host: host)
        case let .integrationUninstall(host): .integrationUninstall(host: host)
        case .status: .status
        case let .search(query, folderID, limit, cursor, _):
            .search(.init(query: query, folderID: folderID, limit: limit, cursor: cursor))
        case let .get(entryID, _): .get(entryID: entryID)
        case let .paste(entryID, field): .paste(entryID: entryID, field: field)
        case let .copy(entryID, field): .copy(entryID: entryID, field: field)
        case .exec: preconditionFailure("exec is handled before Broker operation mapping")
        }
    }

    private func render(
        _ response: VaultAgentResponseBody,
        json: Bool
    ) throws -> VaultCLIExecutionResult {
        switch response {
        case let .failure(failure):
            if json {
                return .init(
                    exitCode: 1,
                    stdout: try VaultCLIJSONRenderer.render(response) + "\n",
                    stderr: ""
                )
            }
            return .init(exitCode: 1, stdout: "", stderr: failure.code.rawValue + "\n")
        case let .success(payload):
            let output: String
            if json {
                output = try VaultCLIJSONRenderer.render(response)
            } else {
                output = try VaultCLITextRenderer.render(payload)
            }
            return .init(exitCode: 0, stdout: output + "\n", stderr: "")
        }
    }

    private func localFailure(json: Bool) -> VaultCLIExecutionResult {
        guard json else {
            return .init(exitCode: 1, stdout: "", stderr: "BROKER_UNAVAILABLE\n")
        }
        let failure = VaultAgentFailure(
            code: .brokerUnavailable,
            message: "Pastera is unavailable.",
            retryable: true,
            retryAfterMilliseconds: nil
        )
        let output = (try? VaultCLIJSONRenderer.render(.failure(failure)))
            ?? #"{"ok":false,"error":{"code":"BROKER_UNAVAILABLE","message":"Pastera is unavailable.","retryable":true}}"#
        return .init(exitCode: 1, stdout: output + "\n", stderr: "")
    }
}

private extension VaultCLICommand {
    var usesJSON: Bool {
        switch self {
        case let .integrationStatus(_, json), let .status(json),
             let .search(_, _, _, _, json), let .get(_, json): json
        default: false
        }
    }
}

private enum VaultCLITextRenderer {
    static func render(_ payload: VaultAgentResponsePayload) throws -> String {
        let output: String
        switch payload {
        case .empty:
            output = "OK"
        case let .status(status):
            output = [
                "client: \(status.client.rawValue)",
                "installed: \(yesNo(status.installed))",
                "authorized: \(yesNo(status.authorized))",
                "vault_ready: \(yesNo(status.vaultReady))",
                "idle_expires_at: \(date(status.idleExpiresAt))",
                "hard_expires_at: \(date(status.hardExpiresAt))",
                "protocol_version: \(status.protocolVersion)"
            ].joined(separator: "\n")
        case let .search(page):
            var lines = page.entries.map(entryLine)
            if let cursor = page.nextCursor { lines.append("next_cursor: \(safe(cursor))") }
            output = lines.isEmpty ? "No entries." : lines.joined(separator: "\n")
        case let .entry(entry):
            output = entryLine(entry)
        case let .integrationStatus(status):
            output = status.hosts.map { host in
                [
                    "host: \(host.host.rawValue)",
                    "detected: \(yesNo(host.hostDetected))",
                    "mcp_installed: \(yesNo(host.mcpInstalled))",
                    "skill_installed: \(yesNo(host.skillInstalled))",
                    "authorized: \(yesNo(host.authorized))",
                    "idle_expires_at: \(date(host.idleExpiresAt))",
                    "hard_expires_at: \(date(host.hardExpiresAt))"
                ].joined(separator: " ")
            }.joined(separator: "\n")
        case .ticket, .secretDelivery:
            throw VaultCLIError.unsafeResponse
        }
        guard output.utf8.count <= VaultAgentLimits.maximumResponseBytes else {
            throw VaultCLIError.outputTooLarge
        }
        return output
    }

    private static func entryLine(_ entry: VaultAgentEntryMetadata) -> String {
        [
            entry.id.uuidString.lowercased(),
            safe(entry.folderName),
            safe(entry.title),
            safe(entry.website),
            safe(entry.username),
            date(entry.updatedAt)
        ].joined(separator: "\t")
    }

    private static func safe(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
        })
    }

    private static func date(_ value: Date?) -> String {
        value.map(date) ?? "-"
    }

    private static func date(_ value: Date) -> String {
        ISO8601DateFormatter().string(from: value)
    }

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
