import CryptoKit
import Darwin
import Dispatch
import Foundation
import PasteraAgentProtocol
import Security

enum VaultAgentInstallerError: Error, Equatable {
    case userModifiedSkill
    case installationConflict
    case invalidHost
    case invalidSignature
    case commandFailed(Int32)
    case commandLaunchFailed
    case commandTimedOut
    case manifestCorrupt
    case hostManagedUnsupported
    case rollbackFailed
    case managedPolicyRestricted
}

struct VaultAgentInstallerCodeSignature: Codable, Equatable {
    let identifier: String
    let designatedRequirement: String
    let teamID: String?
    let cdHash: Data?
    let isAdHoc: Bool
}

struct VaultAgentInstallerAuthorizationStatus: Equatable {
    let authorized: Bool
    let idleExpiresAt: Date?
    let hardExpiresAt: Date?

    static let unauthorized = VaultAgentInstallerAuthorizationStatus(
        authorized: false,
        idleExpiresAt: nil,
        hardExpiresAt: nil
    )
}

protocol VaultAgentInstallerCodeSigningInspecting: AnyObject {
    func inspect(executableURL: URL) throws -> VaultAgentInstallerCodeSignature
}

protocol VaultAgentHostCommandRunning: AnyObject {
    func run(executableURL: URL, arguments: [String]) throws -> Int32
    func registration(
        executableURL: URL,
        host: VaultAgentHostKind
    ) throws -> VaultAgentHostRegistration?
}

struct VaultAgentHostRegistration: Codable, Equatable {
    let command: String
    let arguments: [String]
    let userScoped: Bool
    let hasAdditionalConfiguration: Bool

    init(
        command: String,
        arguments: [String],
        userScoped: Bool,
        hasAdditionalConfiguration: Bool = false
    ) {
        self.command = command
        self.arguments = arguments
        self.userScoped = userScoped
        self.hasAdditionalConfiguration = hasAdditionalConfiguration
    }
}

enum VaultAgentAtomicWritePhase: Equatable {
    case beforeSwap
    case beforeConflictRollback
    case afterSwapBeforeSync
    case afterRollbackTargetQuarantined
}

// swiftlint:disable:next type_name
final class VaultAgentSystemInstallerCodeSigningInspector:
    VaultAgentInstallerCodeSigningInspecting {
    private static let adHocSignatureFlag: UInt32 = 0x0002

    func inspect(executableURL: URL) throws -> VaultAgentInstallerCodeSignature {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw VaultAgentInstallerError.invalidSignature
        }
        let noNetworkAccess = SecCSFlags(rawValue: 1 << 29)
        let validationFlags = SecCSFlags(
            rawValue: kSecCSStrictValidate
                | kSecCSCheckAllArchitectures
                | noNetworkAccess.rawValue
        )
        guard SecStaticCodeCheckValidity(staticCode, validationFlags, nil) == errSecSuccess else {
            throw VaultAgentInstallerError.invalidSignature
        }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        ) == errSecSuccess,
            let values = signingInfo as? [CFString: Any],
            let identifier = values[kSecCodeInfoIdentifier] as? String else {
            throw VaultAgentInstallerError.invalidSignature
        }
        var designatedRequirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(
            staticCode,
            [],
            &designatedRequirement
        ) == errSecSuccess,
            let requirement = designatedRequirement else {
            throw VaultAgentInstallerError.invalidSignature
        }
        var requirementText: CFString?
        guard SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess,
              let requirementText else {
            throw VaultAgentInstallerError.invalidSignature
        }

        let flags = (values[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = flags & Self.adHocSignatureFlag != 0
        let teamID = values[kSecCodeInfoTeamIdentifier] as? String
        let cdHash = values[kSecCodeInfoUnique] as? Data
        let signature = VaultAgentInstallerCodeSignature(
            identifier: identifier,
            designatedRequirement: requirementText as String,
            teamID: teamID,
            cdHash: cdHash,
            isAdHoc: isAdHoc
        )
        guard !signature.identifier.isEmpty,
              !signature.designatedRequirement.isEmpty,
              !signature.isAdHoc || signature.cdHash != nil,
              signature.isAdHoc || !(signature.teamID?.isEmpty ?? true) else {
            throw VaultAgentInstallerError.invalidSignature
        }
        return signature
    }
}

// swiftlint:disable:next type_body_length
final class VaultAgentSystemHostCommandRunner: VaultAgentHostCommandRunning {
    private final class BoundedOutput: @unchecked Sendable {
        private let maximumBytes: Int
        private let lock = NSLock()
        private var data = Data()
        private var overflowed = false
        private var readFailed = false

        init(maximumBytes: Int) {
            self.maximumBytes = maximumBytes
        }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            let remaining = max(0, maximumBytes - data.count)
            data.append(chunk.prefix(remaining))
            if chunk.count > remaining { overflowed = true }
        }

        func markReadFailed() {
            lock.lock()
            readFailed = true
            lock.unlock()
        }

        func value() throws -> Data {
            lock.lock()
            defer { lock.unlock() }
            guard !overflowed, !readFailed else {
                throw VaultAgentInstallerError.installationConflict
            }
            return data
        }
    }

    private struct CapturedResult {
        let exitCode: Int32
        let standardOutput: Data
        let standardError: Data
    }

    private let timeout: TimeInterval
    private let terminationGracePeriod: TimeInterval
    private let maximumCapturedBytes = 65_536

    init(timeout: TimeInterval = 30, terminationGracePeriod: TimeInterval = 1) {
        precondition(timeout > 0)
        precondition(terminationGracePeriod > 0)
        self.timeout = timeout
        self.terminationGracePeriod = terminationGracePeriod
    }

    func run(executableURL: URL, arguments: [String]) throws -> Int32 {
        guard let nullDevice = FileHandle(forUpdatingAtPath: "/dev/null") else {
            throw VaultAgentInstallerError.installationConflict
        }
        defer { try? nullDevice.close() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = nullDevice
        process.standardOutput = nullDevice
        process.standardError = nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw VaultAgentInstallerError.commandLaunchFailed
        }

        if waitForExit(process, semaphore: exited, timeout: timeout) {
            return process.terminationStatus
        }
        if process.isRunning {
            process.terminate()
        }
        if !waitForExit(process, semaphore: exited, timeout: terminationGracePeriod),
           process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        throw VaultAgentInstallerError.commandTimedOut
    }

    func registration(
        executableURL: URL,
        host: VaultAgentHostKind
    ) throws -> VaultAgentHostRegistration? {
        let arguments: [String]
        switch host {
        case .codex:
            arguments = ["mcp", "get", "pastera-vault", "--json"]
        case .claude:
            arguments = ["mcp", "get", "pastera-vault"]
        }
        let result = try runCaptured(executableURL: executableURL, arguments: arguments)
        if result.exitCode != 0 {
            guard let diagnostic = String(
                data: result.standardOutput + result.standardError,
                encoding: .utf8
            )?.lowercased() else {
                throw VaultAgentInstallerError.installationConflict
            }
            guard diagnostic.contains("no mcp server"),
                  diagnostic.contains("pastera-vault"),
                  diagnostic.contains("found") else {
                throw VaultAgentInstallerError.commandFailed(result.exitCode)
            }
            return nil
        }
        switch host {
        case .codex:
            return try parseCodexRegistration(result.standardOutput)
        case .claude:
            return try parseClaudeRegistration(result.standardOutput)
        }
    }

    private func waitForExit(
        _ process: Process,
        semaphore: DispatchSemaphore,
        timeout: TimeInterval
    ) -> Bool {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return false }
        process.waitUntilExit()
        return true
    }

    private func runCaptured(
        executableURL: URL,
        arguments: [String]
    ) throws -> CapturedResult {
        guard let nullDevice = FileHandle(forReadingAtPath: "/dev/null") else {
            throw VaultAgentInstallerError.installationConflict
        }
        defer { try? nullDevice.close() }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let output = BoundedOutput(maximumBytes: maximumCapturedBytes)
        let error = BoundedOutput(maximumBytes: maximumCapturedBytes)
        let readers = DispatchGroup()
        drain(outputPipe.fileHandleForReading, into: output, group: readers)
        drain(errorPipe.fileHandleForReading, into: error, group: readers)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            try? finishReaders(outputPipe, errorPipe, group: readers)
            throw VaultAgentInstallerError.commandLaunchFailed
        }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()

        guard waitForExit(process, semaphore: exited, timeout: timeout) else {
            if process.isRunning { process.terminate() }
            if !waitForExit(process, semaphore: exited, timeout: terminationGracePeriod),
               process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            try? finishReaders(outputPipe, errorPipe, group: readers)
            throw VaultAgentInstallerError.commandTimedOut
        }
        try finishReaders(outputPipe, errorPipe, group: readers)
        return .init(
            exitCode: process.terminationStatus,
            standardOutput: try output.value(),
            standardError: try error.value()
        )
    }

    private func drain(
        _ handle: FileHandle,
        into output: BoundedOutput,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                while let chunk = try handle.read(upToCount: 8_192), !chunk.isEmpty {
                    output.append(chunk)
                }
            } catch {
                output.markReadFailed()
            }
        }
    }

    private func finishReaders(
        _ outputPipe: Pipe,
        _ errorPipe: Pipe,
        group: DispatchGroup
    ) throws {
        if group.wait(timeout: .now() + terminationGracePeriod) == .success { return }
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
        guard group.wait(timeout: .now() + terminationGracePeriod) == .success else {
            throw VaultAgentInstallerError.commandTimedOut
        }
    }

    private func parseCodexRegistration(_ data: Data) throws -> VaultAgentHostRegistration {
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw VaultAgentInstallerError.installationConflict
            }
            object = decoded
        } catch {
            throw VaultAgentInstallerError.installationConflict
        }
        guard
              let transport = object["transport"] as? [String: Any],
              transport["type"] as? String == "stdio",
              let command = transport["command"] as? String else {
            throw VaultAgentInstallerError.installationConflict
        }
        let rawArguments = transport["args"] ?? []
        guard let arguments = rawArguments as? [Any],
              arguments.allSatisfy({ $0 is String }) else {
            throw VaultAgentInstallerError.installationConflict
        }
        let environmentConfigured = nonEmptyDictionaryOrUnexpectedValue(
            transport["env"]
        )
        let inheritedEnvironmentConfigured = nonEmptyArrayOrUnexpectedValue(
            transport["env_vars"]
        )
        let additionalConfiguration = environmentConfigured
            || inheritedEnvironmentConfigured
            || nonNullValue(transport["cwd"])
            || (object["name"] as? String).map { $0 != "pastera-vault" } == true
            || (object["enabled"] as? Bool == false)
            || nonNullValue(object["disabled_reason"])
            || nonNullValue(object["enabled_tools"])
            || nonNullValue(object["disabled_tools"])
            || nonNullValue(object["startup_timeout_sec"])
            || nonNullValue(object["tool_timeout_sec"])
            || hasUnknownKeys(
                object,
                allowed: [
                    "name", "enabled", "disabled_reason", "transport",
                    "enabled_tools", "disabled_tools", "startup_timeout_sec",
                    "tool_timeout_sec"
                ]
            )
            || hasUnknownKeys(
                transport,
                allowed: ["type", "command", "args", "env", "env_vars", "cwd"]
            )
        return .init(
            command: command,
            arguments: arguments.compactMap { $0 as? String },
            userScoped: true,
            hasAdditionalConfiguration: additionalConfiguration
        )
    }

    private func parseClaudeRegistration(_ data: Data) throws -> VaultAgentHostRegistration {
        guard let output = String(data: data, encoding: .utf8) else {
            throw VaultAgentInstallerError.installationConflict
        }
        let rawLines = output.split(whereSeparator: \.isNewline).map(String.init)
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let commandLine = lines.first(where: { $0.hasPrefix("Command:") }),
              let scopeLine = lines.first(where: { $0.hasPrefix("Scope:") }),
              let typeLine = lines.first(where: { $0.hasPrefix("Type:") }),
              let argumentsLine = lines.first(where: { $0.hasPrefix("Args:") }),
              let environmentLine = lines.first(where: { $0.hasPrefix("Environment:") }) else {
            throw VaultAgentInstallerError.installationConflict
        }
        let command = commandLine.dropFirst("Command:".count)
            .trimmingCharacters(in: .whitespaces)
        let rawArguments = argumentsLine.dropFirst("Args:".count)
            .trimmingCharacters(in: .whitespaces)
        let rawEnvironment = environmentLine.dropFirst("Environment:".count)
            .trimmingCharacters(in: .whitespaces)
        let hasNestedArguments = sectionHasNestedValues(
            named: "Args:",
            rawLines: rawLines
        )
        let hasNestedEnvironment = sectionHasNestedValues(
            named: "Environment:",
            rawLines: rawLines
        )
        let hasUnknownConfigurationField = claudeHasUnknownConfigurationField(
            rawLines,
            scopeLine: scopeLine
        )
        guard !command.isEmpty, typeLine.lowercased() == "type: stdio" else {
            throw VaultAgentInstallerError.installationConflict
        }
        return .init(
            command: command,
            arguments: rawArguments.isEmpty && !hasNestedArguments ? [] : ["<configured>"],
            userScoped: scopeLine.lowercased().contains("user"),
            hasAdditionalConfiguration: !rawEnvironment.isEmpty
                || hasNestedEnvironment
                || hasUnknownConfigurationField
        )
    }

    private func hasUnknownKeys(
        _ object: [String: Any],
        allowed: Set<String>
    ) -> Bool {
        !Set(object.keys).isSubset(of: allowed)
    }

    private func claudeHasUnknownConfigurationField(
        _ rawLines: [String],
        scopeLine: String
    ) -> Bool {
        guard let scopeIndex = rawLines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == scopeLine
        }) else { return true }
        let fieldIndent = leadingWhitespaceCount(rawLines[scopeIndex])
        let knownPrefixes = [
            "Scope:", "Status:", "Type:", "Command:", "Args:", "Environment:"
        ]
        return rawLines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return leadingWhitespaceCount(line) == fieldIndent
                && trimmed.contains(":")
                && !knownPrefixes.contains(where: { trimmed.hasPrefix($0) })
        }
    }

    private func sectionHasNestedValues(named name: String, rawLines: [String]) -> Bool {
        guard let index = rawLines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(name)
        }) else { return false }
        let sectionIndent = leadingWhitespaceCount(rawLines[index])
        return rawLines.dropFirst(index + 1).prefix { line in
            line.trimmingCharacters(in: .whitespaces).isEmpty
                || leadingWhitespaceCount(line) > sectionIndent
        }.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func leadingWhitespaceCount(_ value: String) -> Int {
        value.prefix { $0 == " " || $0 == "\t" }.count
    }

    private func nonNullValue(_ value: Any?) -> Bool {
        value != nil && !(value is NSNull)
    }

    private func nonEmptyDictionaryOrUnexpectedValue(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        return (value as? [String: Any])?.isEmpty != true
    }

    private func nonEmptyArrayOrUnexpectedValue(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        return (value as? [Any])?.isEmpty != true
    }
}

struct VaultAgentManagedPolicyDetector {
    func disposition() -> VaultAgentManagedPermissionDisposition {
        if let managedValue = CFPreferencesCopyAppValue(
            "allowManagedPermissionRulesOnly" as CFString,
            "com.anthropic.claudecode" as CFString
        ) as? Bool,
           managedValue {
            return .managedRulesOnly
        }

        let root = URL(fileURLWithPath: "/Library/Application Support/ClaudeCode")
        var candidates = [root.appendingPathComponent("managed-settings.json")]
        let directory = root.appendingPathComponent("managed-settings.d")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            candidates.append(contentsOf: names
                .filter { !$0.hasPrefix(".") && $0.hasSuffix(".json") }
                .sorted()
                .map { directory.appendingPathComponent($0) })
        }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let data = try? Data(contentsOf: candidate),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unknown
            }
            if object["allowManagedPermissionRulesOnly"] as? Bool == true {
                return .managedRulesOnly
            }
        }
        // Remote managed settings are not synchronously observable from this process.
        return .unknown
    }
}

struct VaultAgentHostCandidate {
    let host: VaultAgentHostKind
    let urls: [URL]
}

enum VaultAgentHostPermissionScope: String, Codable, CaseIterable {
    case metadataOnly
    case allCurrentPasteraTools
}

struct VaultAgentPermissionSnippet: Equatable {
    let allowedTools: [String]
    let serialized: String

    static func canonicalAllowedTools(for scope: VaultAgentHostPermissionScope) -> [String] {
        let names: [String]
        switch scope {
        case .metadataOnly:
            names = ["vault_get", "vault_search", "vault_status"]
        case .allCurrentPasteraTools:
            names = [
                "vault_get",
                "vault_paste",
                "vault_prepare_exec",
                "vault_search",
                "vault_status"
            ]
        }
        return names.map { "mcp__pastera-vault__\($0)" }
    }

    static func canonical(for scope: VaultAgentHostPermissionScope) throws -> Self {
        let allowedTools = canonicalAllowedTools(for: scope)
        let data = try JSONSerialization.data(
            withJSONObject: ["permissions": ["allow": allowedTools]],
            options: [.sortedKeys]
        )
        guard let serialized = String(data: data, encoding: .utf8) else {
            throw VaultAgentInstallerError.installationConflict
        }
        return .init(allowedTools: allowedTools, serialized: serialized)
    }

    func exactlyMatches(scope: VaultAgentHostPermissionScope) -> Bool {
        let canonical = Self.canonicalAllowedTools(for: scope)
        guard allowedTools == canonical,
              let data = serialized.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["permissions"],
              let permissions = root["permissions"] as? [String: Any],
              Set(permissions.keys) == ["allow"],
              let serializedTools = permissions["allow"] as? [String] else {
            return false
        }
        return serializedTools == canonical
    }
}

struct VaultAgentHostConfigurationMutation: Equatable {
    let serialized: String
}

enum VaultAgentManagedPermissionDisposition: String, Equatable {
    case userRulesAllowed
    case managedRulesOnly
    case unknown
}

struct VaultAgentClaudePermissionStatus: Equatable {
    let policyDisposition: VaultAgentManagedPermissionDisposition
    let ownedRules: [String]
}

struct VaultAgentPermissionChange: Equatable {
    let addedRules: [String]
    let removedRules: [String]
    let unchanged: Bool
}

protocol VaultAgentHostPermissionManaging {
    func claudePermissionStatus() throws -> VaultAgentClaudePermissionStatus
    func applyClaudePermissionScope(
        _ scope: VaultAgentHostPermissionScope
    ) throws -> VaultAgentPermissionChange
    func removeOwnedClaudePermissionRules() throws -> VaultAgentPermissionChange
}

struct VaultAgentCLIInstallationStatus: Equatable {
    let installed: Bool
    let executablePath: String
    let pathHint: String?
}

// swiftlint:disable:next type_body_length
final class VaultAgentIntegrationInstaller:
    VaultAgentIntegrationServicing,
    VaultAgentHostIdentityProviding,
    VaultAgentHostPermissionManaging {
    private struct Manifest: Codable {
        let schemaVersion: Int
        let installationVersion: String
        var hosts: [String: HostRecord]
        var cli: CLIRecord?
        var claudePermissions: ClaudePermissionRecord?
    }

    private struct ManifestState {
        var manifest: Manifest
        let snapshot: FileSnapshot?
    }

    private struct HostRecord: Codable, Equatable {
        let host: String
        let identity: HostIdentity
        let registration: VaultAgentHostRegistration
        let helperRelativePath: String
        let helperSHA256: String
        let skillDestinationRelativePath: String
        let files: [FileRecord]
    }

    private struct HostIdentity: Codable, Equatable {
        let canonicalPath: String
        let signature: VaultAgentInstallerCodeSignature
    }

    private struct FileRecord: Codable, Equatable {
        let sourceRelativePath: String
        let destinationRelativePath: String
        let sha256: String
    }

    private struct CLIRecord: Codable, Equatable {
        let helperRelativePath: String
        let helperSHA256: String
        let destinationRelativePath: String
    }

    private struct ClaudePermissionRecord: Codable, Equatable {
        let ownedRules: [String]
    }

    private struct ClaudeSettingsState {
        var object: [String: Any]
        let originalData: Data
        let snapshot: FileSnapshot?
    }

    private struct ClaudePermissionDelta {
        let addedRules: [String]
        let removedRules: [String]
    }

    private struct FileSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let sha256: String
    }

    private struct LinkSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let destination: String
    }

    private struct PreparedInstall {
        let canonicalHostURL: URL
        let hostIdentity: HostIdentity
        let helperURL: URL
        let helperRelativePath: String
        let helperSHA256: String
        let skillDestinationRelativePath: String
        let targetSkillURL: URL
        let stagedSkillURL: URL
        let files: [FileRecord]
    }

    private struct ValidatedHelper {
        let url: URL
        let relativePath: String
        let sha256: String
    }

    private struct InstallContext {
        let host: VaultAgentHostKind
        let hostURL: URL
        let identity: HostIdentity
        let helper: ValidatedHelper
        let destination: String
    }

    private static let manifestRelativePath =
        "Library/Application Support/Pastera/Agent/v1/install-manifest.json"
    private static let manifestDirectoryRelativePath =
        "Library/Application Support/Pastera/Agent/v1"
    private static let cliDestinationRelativePath = ".local/bin/pastera"
    private static let claudeSettingsRelativePath = ".claude/settings.json"
    private static let backupDirectoryRelativePath =
        "Library/Application Support/Pastera/Agent/v1/backups"
    private static let skillFiles = [
        "SKILL.md",
        "references/tool-contract.md",
        "references/security-boundary.md",
        "agents/openai.yaml"
    ]
    private let sourceSkillURL: URL
    private let applicationURL: URL
    private let userRootURL: URL
    private let hostCandidates: [VaultAgentHostCandidate]
    private let currentUID: uid_t
    private let signingInspector: VaultAgentInstallerCodeSigningInspecting
    private let commandRunner: VaultAgentHostCommandRunning
    private let installationVersion: String
    private let environmentPathProvider: () -> String
    private let atomicWriteInterposer: (URL, VaultAgentAtomicWritePhase) throws -> Void
    private let managedPermissionDispositionProvider:
        () -> VaultAgentManagedPermissionDisposition
    private let authorizationStatusProvider:
        (VaultAgentClientKind) -> VaultAgentInstallerAuthorizationStatus
    private let fileManager: FileManager
    private let transactionLock = NSLock()

    init(
        sourceSkillURL: URL,
        applicationURL: URL,
        userRootURL: URL,
        hostCandidates: [VaultAgentHostCandidate],
        currentUID: uid_t,
        signingInspector: VaultAgentInstallerCodeSigningInspecting =
            VaultAgentSystemInstallerCodeSigningInspector(),
        commandRunner: VaultAgentHostCommandRunning = VaultAgentSystemHostCommandRunner(),
        installationVersion: String,
        environmentPathProvider: @escaping () -> String = {
            ProcessInfo.processInfo.environment["PATH"] ?? ""
        },
        atomicWriteInterposer: @escaping (
            URL,
            VaultAgentAtomicWritePhase
        ) throws -> Void = { _, _ in },
        managedPermissionDispositionProvider: @escaping (
        ) -> VaultAgentManagedPermissionDisposition = {
            VaultAgentManagedPolicyDetector().disposition()
        },
        authorizationStatusProvider: @escaping (
            VaultAgentClientKind
        ) -> VaultAgentInstallerAuthorizationStatus = { _ in .unauthorized },
        fileManager: FileManager = .default
    ) {
        self.sourceSkillURL = sourceSkillURL.standardizedFileURL
        self.applicationURL = applicationURL.standardizedFileURL
        self.userRootURL = userRootURL.standardizedFileURL
        self.hostCandidates = hostCandidates
        self.currentUID = currentUID
        self.signingInspector = signingInspector
        self.commandRunner = commandRunner
        self.installationVersion = installationVersion
        self.environmentPathProvider = environmentPathProvider
        self.atomicWriteInterposer = atomicWriteInterposer
        self.managedPermissionDispositionProvider = managedPermissionDispositionProvider
        self.authorizationStatusProvider = authorizationStatusProvider
        self.fileManager = fileManager
    }

    func status(host: VaultAgentHostKind?) throws -> VaultAgentIntegrationStatus {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let manifest = try loadManifestState().manifest
        let requestedHosts = host.map { [$0] } ?? [.codex, .claude]
        return .init(hosts: try requestedHosts.map {
            try makeStatus(host: $0, manifest: manifest)
        })
    }

    func installedHostIdentity(
        for client: VaultAgentClientKind
    ) -> VaultAgentInstalledHostIdentity? {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let host: VaultAgentHostKind
        switch client {
        case .codex: host = .codex
        case .claude: host = .claude
        case .cli: return nil
        }
        guard let manifest = try? loadManifestState().manifest,
              let record = manifest.hosts[host.rawValue] else {
            return nil
        }
        return .init(
            client: client,
            canonicalPath: record.identity.canonicalPath,
            designatedRequirement: record.identity.signature.designatedRequirement,
            cdHash: record.identity.signature.cdHash,
            isAdHoc: record.identity.signature.isAdHoc
        )
    }

    func install(host: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let hostURL = try locateHost(host)
        let hostSignature = try inspect(hostURL, expectedIdentifier: nil)
        let identity = HostIdentity(canonicalPath: hostURL.path, signature: hostSignature)
        let helper = try validateHelper(for: host)
        let expectedRegistration = makeRegistration(helperURL: helper.url)
        let state = try loadManifestState()
        let manifest = state.manifest
        let destination = skillDestination(for: host)
        let context = InstallContext(
            host: host,
            hostURL: hostURL,
            identity: identity,
            helper: helper,
            destination: destination
        )

        if let record = manifest.hosts[host.rawValue] {
            return try updateOwnedInstallIfNeeded(
                record,
                state: state,
                context: context
            )
        }

        guard try commandRunner.registration(executableURL: hostURL, host: host) == nil else {
            throw VaultAgentInstallerError.installationConflict
        }

        let target = userRootURL.appendingPathComponent(destination)
        guard try pathKind(target) == nil else {
            throw VaultAgentInstallerError.installationConflict
        }
        let prepared = try prepareInstall(context)
        defer { try? fileManager.removeItem(at: prepared.stagedSkillURL) }
        let exitCode = try commandRunner.run(
            executableURL: prepared.canonicalHostURL,
            arguments: addArguments(for: host, helperURL: prepared.helperURL)
        )
        if exitCode != 0 {
            let registration = try commandRunner.registration(
                executableURL: prepared.canonicalHostURL,
                host: host
            )
            if registration == expectedRegistration {
                try removeRegistrationIfOwned(
                    host: host,
                    hostURL: prepared.canonicalHostURL,
                    expected: expectedRegistration
                )
            } else if registration != nil {
                throw VaultAgentInstallerError.rollbackFailed
            }
            throw VaultAgentInstallerError.commandFailed(exitCode)
        }
        let installedRecord = HostRecord(
            host: host.rawValue,
            identity: prepared.hostIdentity,
            registration: expectedRegistration,
            helperRelativePath: prepared.helperRelativePath,
            helperSHA256: prepared.helperSHA256,
            skillDestinationRelativePath: prepared.skillDestinationRelativePath,
            files: prepared.files
        )
        var movedSkill = false
        do {
            try fileManager.moveItem(at: prepared.stagedSkillURL, to: prepared.targetSkillURL)
            movedSkill = true
            try validateOwnedSkillSnapshot(installedRecord, at: prepared.targetSkillURL)

            var updatedManifest = manifest
            updatedManifest.hosts[host.rawValue] = installedRecord
            try writeManifest(updatedManifest, replacing: state.snapshot)
        } catch {
            let originalError = error
            try removeRegistrationIfOwned(
                host: host,
                hostURL: prepared.canonicalHostURL,
                expected: expectedRegistration
            )
            if movedSkill {
                guard (try? validateOwnedSkillSnapshot(
                    installedRecord,
                    at: prepared.targetSkillURL
                )) != nil else {
                    throw VaultAgentInstallerError.rollbackFailed
                }
                try fileManager.removeItem(at: prepared.targetSkillURL)
                try fsyncDirectory(prepared.targetSkillURL.deletingLastPathComponent())
            }
            throw originalError
        }
        return installedStatus(host: host, hostPath: hostURL.path)
    }

    func uninstall(host: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let hostURL = try locateHost(host)
        let hostSignature = try inspect(hostURL, expectedIdentifier: nil)
        let identity = HostIdentity(canonicalPath: hostURL.path, signature: hostSignature)
        let helper = try validateHelper(for: host)
        let state = try loadManifestState()
        var manifest = state.manifest
        guard let record = manifest.hosts[host.rawValue] else {
            return uninstalledStatus(host: host, hostPath: hostURL.path)
        }
        let context = InstallContext(
            host: host,
            hostURL: hostURL,
            identity: identity,
            helper: helper,
            destination: skillDestination(for: host)
        )
        try validateOwnedFilesForUpdate(record, context: context)
        guard try commandRunner.registration(executableURL: hostURL, host: host)
                == record.registration else {
            throw VaultAgentInstallerError.installationConflict
        }
        let target = userRootURL.appendingPathComponent(record.skillDestinationRelativePath)
        let quarantine = target.deletingLastPathComponent()
            .appendingPathComponent(".pastera-vault-uninstall-\(UUID().uuidString).tmp")
        try fileManager.moveItem(at: target, to: quarantine)
        do {
            try validateOwnedSkillSnapshot(record, at: quarantine)
        } catch {
            try restoreQuarantinedItem(quarantine, to: target)
            throw error
        }
        do {
            let exitCode = try commandRunner.run(
                executableURL: hostURL,
                arguments: removeArguments(for: host)
            )
            guard exitCode == 0 else {
                throw VaultAgentInstallerError.commandFailed(exitCode)
            }
        } catch {
            let originalError = error
            try restoreQuarantinedItem(quarantine, to: target)
            let currentRegistration = try commandRunner.registration(
                executableURL: hostURL,
                host: host
            )
            if currentRegistration == nil {
                try restoreOwnedRegistration(
                    host: host,
                    hostURL: hostURL,
                    registration: record.registration
                )
            } else if currentRegistration != record.registration {
                throw VaultAgentInstallerError.rollbackFailed
            }
            throw originalError
        }
        manifest.hosts.removeValue(forKey: host.rawValue)
        do {
            try writeManifest(manifest, replacing: state.snapshot)
        } catch {
            let originalError = error
            do {
                try restoreQuarantinedItem(quarantine, to: target)
            } catch {
                throw VaultAgentInstallerError.rollbackFailed
            }
            try restoreOwnedRegistration(
                host: host,
                hostURL: hostURL,
                registration: record.registration
            )
            throw originalError
        }
        do {
            try fileManager.removeItem(at: quarantine)
            try fsyncDirectory(quarantine.deletingLastPathComponent())
        } catch {
            throw VaultAgentInstallerError.rollbackFailed
        }
        return uninstalledStatus(host: host, hostPath: hostURL.path)
    }

    func cliStatus() throws -> VaultAgentCLIInstallationStatus {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let state = try loadManifestState()
        let helper = try validateCLIHelper()
        let installed = state.manifest.cli.map { cliRecordMatches($0, helper: helper) } ?? false
        return makeCLIStatus(installed: installed)
    }

    func installCLI() throws -> VaultAgentCLIInstallationStatus {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let helper = try validateCLIHelper()
        let state = try loadManifestState()
        if let record = state.manifest.cli {
            guard cliRecordMatches(record, helper: helper) else {
                throw VaultAgentInstallerError.installationConflict
            }
            return makeCLIStatus(installed: true)
        }

        let target = userRootURL.appendingPathComponent(Self.cliDestinationRelativePath)
        guard try pathKind(target) == nil else {
            throw VaultAgentInstallerError.installationConflict
        }
        try ensureUserDirectory(
            ".local/bin",
            createdPermissions: 0o755,
            enforceFinalPermissions: false
        )
        var createdSnapshot: LinkSnapshot?
        do {
            guard symlink(helper.url.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            createdSnapshot = try linkSnapshot(target)
            try fsyncDirectory(target.deletingLastPathComponent())
            var manifest = state.manifest
            manifest.cli = .init(
                helperRelativePath: helper.relativePath,
                helperSHA256: helper.sha256,
                destinationRelativePath: Self.cliDestinationRelativePath
            )
            try writeManifest(manifest, replacing: state.snapshot)
        } catch {
            if let createdSnapshot,
               (try? linkSnapshot(target)) == createdSnapshot {
                _ = unlink(target.path)
                try? fsyncDirectory(target.deletingLastPathComponent())
            }
            throw error
        }
        return makeCLIStatus(installed: true)
    }

    func uninstallCLI() throws -> VaultAgentCLIInstallationStatus {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let state = try loadManifestState()
        guard let record = state.manifest.cli else {
            return makeCLIStatus(installed: false)
        }
        let helper = try validateCLIHelper()
        guard cliRecordMatches(record, helper: helper) else {
            throw VaultAgentInstallerError.installationConflict
        }
        let target = userRootURL.appendingPathComponent(record.destinationRelativePath)
        let expectedLink = try linkSnapshot(target)
        let quarantine = target.deletingLastPathComponent()
            .appendingPathComponent(".pastera-cli-uninstall-\(UUID().uuidString).tmp")
        try fileManager.moveItem(at: target, to: quarantine)
        guard try linkSnapshot(quarantine) == expectedLink else {
            try restoreQuarantinedItem(quarantine, to: target)
            throw VaultAgentInstallerError.installationConflict
        }
        var manifest = state.manifest
        manifest.cli = nil
        do {
            try writeManifest(manifest, replacing: state.snapshot)
        } catch {
            try restoreQuarantinedItem(quarantine, to: target)
            throw error
        }
        guard unlink(quarantine.path) == 0 else {
            throw VaultAgentInstallerError.rollbackFailed
        }
        try fsyncDirectory(target.deletingLastPathComponent())
        return makeCLIStatus(installed: false)
    }

    func supportedPermissionScopes(
        for host: VaultAgentHostKind
    ) -> [VaultAgentHostPermissionScope] {
        switch host {
        case .codex: []
        case .claude: VaultAgentHostPermissionScope.allCases
        }
    }

    func configurationMutations(
        for host: VaultAgentHostKind
    ) -> [VaultAgentHostConfigurationMutation] {
        guard host == .claude else { return [] }
        return supportedPermissionScopes(for: host).compactMap { scope in
            try? permissionSnippet(for: host, scope: scope)
        }.map { .init(serialized: $0.serialized) }
    }

    func permissionSnippet(
        for host: VaultAgentHostKind,
        scope: VaultAgentHostPermissionScope
    ) throws -> VaultAgentPermissionSnippet {
        guard host == .claude else {
            throw VaultAgentInstallerError.hostManagedUnsupported
        }
        return try VaultAgentPermissionSnippet.canonical(for: scope)
    }

    func claudePermissionStatus() throws -> VaultAgentClaudePermissionStatus {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let manifest = try loadManifestState().manifest
        return .init(
            policyDisposition: managedPermissionDispositionProvider(),
            ownedRules: manifest.claudePermissions?.ownedRules.sorted() ?? []
        )
    }

    func applyClaudePermissionScope(
        _ scope: VaultAgentHostPermissionScope
    ) throws -> VaultAgentPermissionChange {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        guard managedPermissionDispositionProvider() == .userRulesAllowed else {
            throw VaultAgentInstallerError.managedPolicyRestricted
        }
        let state = try loadManifestState()
        try validateInstalledClaude(manifest: state.manifest)
        let settings = try readClaudeSettings()
        let requestedRules = try permissionSnippet(for: .claude, scope: scope).allowedTools
        let currentRules = try claudeAllowRules(in: settings.object)
        let currentRuleSet = Set(currentRules)
        let addedRules = requestedRules.filter { !currentRuleSet.contains($0) }
        guard !addedRules.isEmpty else {
            return .init(addedRules: [], removedRules: [], unchanged: true)
        }

        var updatedObject = settings.object
        try setClaudeAllowRules(stableUnique(currentRules + addedRules), in: &updatedObject)
        var updatedManifest = state.manifest
        updatedManifest.claudePermissions = .init(
            ownedRules: stableUnique(
                (state.manifest.claudePermissions?.ownedRules ?? []) + addedRules
            ).sorted()
        )
        try commitClaudePermissionChange(
            settings: settings,
            updatedObject: updatedObject,
            delta: .init(addedRules: addedRules, removedRules: []),
            manifest: updatedManifest,
            replacingManifest: state.snapshot
        )
        return .init(addedRules: addedRules, removedRules: [], unchanged: false)
    }

    func removeOwnedClaudePermissionRules() throws -> VaultAgentPermissionChange {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let state = try loadManifestState()
        let ownedRules = state.manifest.claudePermissions?.ownedRules ?? []
        guard !ownedRules.isEmpty else {
            return .init(addedRules: [], removedRules: [], unchanged: true)
        }
        let settings = try readClaudeSettings()
        let currentRules = try claudeAllowRules(in: settings.object)
        let ownedSet = Set(ownedRules)
        let removedRules = stableUnique(currentRules.filter { ownedSet.contains($0) }).sorted()
        var updatedManifest = state.manifest
        updatedManifest.claudePermissions = nil
        guard !removedRules.isEmpty else {
            try writeManifest(updatedManifest, replacing: state.snapshot)
            return .init(addedRules: [], removedRules: [], unchanged: true)
        }

        var updatedObject = settings.object
        try setClaudeAllowRules(
            currentRules.filter { !ownedSet.contains($0) },
            in: &updatedObject
        )
        try commitClaudePermissionChange(
            settings: settings,
            updatedObject: updatedObject,
            delta: .init(addedRules: [], removedRules: removedRules),
            manifest: updatedManifest,
            replacingManifest: state.snapshot
        )
        return .init(addedRules: [], removedRules: removedRules, unchanged: false)
    }
}

private extension VaultAgentIntegrationInstaller {
    private func makeStatus(
        host: VaultAgentHostKind,
        manifest: Manifest
    ) throws -> VaultAgentHostIntegrationStatus {
        let detectedHostURL: URL?
        if let hostURL = try? locateHost(host),
           (try? inspect(hostURL, expectedIdentifier: nil)) != nil {
            detectedHostURL = hostURL
        } else {
            detectedHostURL = nil
        }
        let record = manifest.hosts[host.rawValue]
        let registrationMatches: Bool
        if let record, let detectedHostURL {
            registrationMatches = try commandRunner.registration(
                executableURL: detectedHostURL,
                host: host
            ) == record.registration
        } else {
            registrationMatches = false
        }
        let authorization = authorizationStatusProvider(client(for: host))
        return .init(
            host: host,
            hostDetected: detectedHostURL != nil,
            hostExecutablePath: detectedHostURL?.path,
            mcpInstalled: registrationMatches,
            skillInstalled: record.map(installedSkillMatches) ?? false,
            installedVersion: record == nil ? nil : manifest.installationVersion,
            authorized: authorization.authorized,
            idleExpiresAt: authorization.idleExpiresAt,
            hardExpiresAt: authorization.hardExpiresAt
        )
    }

    private func installedSkillMatches(_ record: HostRecord) -> Bool {
        let root = userRootURL.appendingPathComponent(record.skillDestinationRelativePath)
        return (try? validateOwnedSkillSnapshot(record, at: root)) != nil
    }

    func locateHost(_ host: VaultAgentHostKind) throws -> URL {
        guard let candidates = hostCandidates.first(where: { $0.host == host })?.urls else {
            throw VaultAgentInstallerError.invalidHost
        }
        for candidate in candidates {
            if let validated = try? validateExecutable(candidate, requiresCurrentOwner: true) {
                return validated
            }
        }
        throw VaultAgentInstallerError.invalidHost
    }

    private func validateHelper(
        for host: VaultAgentHostKind
    ) throws -> ValidatedHelper {
        let helperName: String
        let identifier: String
        switch host {
        case .codex:
            helperName = "PasteraCodexMCP"
            identifier = "com.pastera-app.PasteraCodexMCP"
        case .claude:
            helperName = "PasteraClaudeMCP"
            identifier = "com.pastera-app.PasteraClaudeMCP"
        }
        let relativePath = "Contents/Helpers/\(helperName)"
        let helperURL = try validateExecutable(
            applicationURL.appendingPathComponent(relativePath),
            requiresCurrentOwner: false
        )
        _ = try inspect(helperURL, expectedIdentifier: identifier)
        return .init(url: helperURL, relativePath: relativePath, sha256: try digest(helperURL))
    }

    func validateExecutable(_ url: URL, requiresCurrentOwner: Bool) throws -> URL {
        var linkInfo = stat()
        guard lstat(url.path, &linkInfo) == 0 else {
            throw VaultAgentInstallerError.invalidHost
        }
        let linkType = linkInfo.st_mode & S_IFMT
        guard linkType == S_IFREG || linkType == S_IFLNK else {
            throw VaultAgentInstallerError.invalidHost
        }
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        var fileInfo = stat()
        guard stat(canonicalURL.path, &fileInfo) == 0,
              fileInfo.st_mode & S_IFMT == S_IFREG,
              fileInfo.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH) != 0,
              !requiresCurrentOwner || fileInfo.st_uid == currentUID else {
            throw VaultAgentInstallerError.invalidHost
        }
        return canonicalURL
    }

    func inspect(
        _ executableURL: URL,
        expectedIdentifier: String?
    ) throws -> VaultAgentInstallerCodeSignature {
        let signature: VaultAgentInstallerCodeSignature
        do {
            signature = try signingInspector.inspect(executableURL: executableURL)
        } catch {
            throw VaultAgentInstallerError.invalidSignature
        }
        guard !signature.identifier.isEmpty,
              !signature.designatedRequirement.isEmpty,
              expectedIdentifier == nil || signature.identifier == expectedIdentifier,
              !signature.isAdHoc || signature.cdHash != nil,
              signature.isAdHoc || !(signature.teamID?.isEmpty ?? true) else {
            throw VaultAgentInstallerError.invalidSignature
        }
        return signature
    }

    private func prepareInstall(_ context: InstallContext) throws -> PreparedInstall {
        let target = userRootURL.appendingPathComponent(context.destination)
        let parent = target.deletingLastPathComponent()
        let parentRelativePath = (context.destination as NSString).deletingLastPathComponent
        try ensureUserDirectory(
            parentRelativePath,
            createdPermissions: 0o700,
            enforceFinalPermissions: false
        )
        let staged = parent.appendingPathComponent(".pastera-vault-\(UUID().uuidString).tmp")
        try fileManager.createDirectory(at: staged, withIntermediateDirectories: false)
        do {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
            let files = try Self.skillFiles.map { relativePath in
                try copySkillFile(
                    relativePath,
                    into: staged,
                    destinationRoot: context.destination
                )
            }
            return .init(
                canonicalHostURL: context.hostURL,
                hostIdentity: context.identity,
                helperURL: context.helper.url,
                helperRelativePath: context.helper.relativePath,
                helperSHA256: context.helper.sha256,
                skillDestinationRelativePath: context.destination,
                targetSkillURL: target,
                stagedSkillURL: staged,
                files: files
            )
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    private func updateOwnedInstallIfNeeded(
        _ record: HostRecord,
        state: ManifestState,
        context: InstallContext
    ) throws -> VaultAgentIntegrationStatus {
        try validateOwnedFilesForUpdate(record, context: context)
        guard try commandRunner.registration(
            executableURL: context.hostURL,
            host: context.host
        ) == record.registration else {
            throw VaultAgentInstallerError.installationConflict
        }
        let prepared = try prepareInstall(context)
        var stagedNeedsCleanup = true
        defer {
            if stagedNeedsCleanup { try? fileManager.removeItem(at: prepared.stagedSkillURL) }
        }
        let updatedRegistration = makeRegistration(helperURL: prepared.helperURL)
        let updatedRecord = HostRecord(
            host: context.host.rawValue,
            identity: prepared.hostIdentity,
            registration: updatedRegistration,
            helperRelativePath: prepared.helperRelativePath,
            helperSHA256: prepared.helperSHA256,
            skillDestinationRelativePath: prepared.skillDestinationRelativePath,
            files: prepared.files
        )
        guard updatedRecord != record else {
            return installedStatus(host: context.host, hostPath: context.hostURL.path)
        }

        let registrationChanged = updatedRegistration != record.registration
        if registrationChanged {
            try replaceOwnedRegistration(
                host: context.host,
                hostURL: context.hostURL,
                current: record.registration,
                replacement: updatedRegistration
            )
        }
        var skillSwapped = false
        do {
            guard renamex_np(
                prepared.stagedSkillURL.path,
                prepared.targetSkillURL.path,
                UInt32(RENAME_SWAP)
            ) == 0 else {
                throw VaultAgentInstallerError.installationConflict
            }
            skillSwapped = true
            try validateOwnedSkillSnapshot(record, at: prepared.stagedSkillURL)
            try validateOwnedSkillSnapshot(updatedRecord, at: prepared.targetSkillURL)
            var manifest = state.manifest
            manifest.hosts[context.host.rawValue] = updatedRecord
            try writeManifest(manifest, replacing: state.snapshot)
        } catch {
            let originalError = error
            if skillSwapped {
                try rollbackSkillSwap(
                    oldRecord: record,
                    newRecord: updatedRecord,
                    stagedURL: prepared.stagedSkillURL,
                    targetURL: prepared.targetSkillURL
                )
            }
            if registrationChanged {
                try replaceOwnedRegistration(
                    host: context.host,
                    hostURL: context.hostURL,
                    current: updatedRegistration,
                    replacement: record.registration
                )
            }
            throw originalError
        }
        do {
            try fileManager.removeItem(at: prepared.stagedSkillURL)
            stagedNeedsCleanup = false
            try fsyncDirectory(prepared.stagedSkillURL.deletingLastPathComponent())
        } catch {
            throw VaultAgentInstallerError.rollbackFailed
        }
        return installedStatus(host: context.host, hostPath: context.hostURL.path)
    }

    private func copySkillFile(
        _ relativePath: String,
        into staged: URL,
        destinationRoot: String
    ) throws -> FileRecord {
        let source = sourceSkillURL.appendingPathComponent(relativePath)
        let sourceData = try readRegularFile(source, maximumBytes: 1_048_576).data
        let destination = staged.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sourceData.write(to: destination, options: .withoutOverwriting)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let sourceDigest = sha256(sourceData)
        guard try digest(destination) == sourceDigest else {
            throw VaultAgentInstallerError.installationConflict
        }
        return .init(
            sourceRelativePath: relativePath,
            destinationRelativePath: "\(destinationRoot)/\(relativePath)",
            sha256: sourceDigest
        )
    }

    private func validateOwnedInstall(
        _ record: HostRecord,
        context: InstallContext
    ) throws {
        try validateOwnedFiles(record, context: context)
        for file in record.files {
            let sourceURL = sourceSkillURL.appendingPathComponent(file.sourceRelativePath)
            guard (try? digest(sourceURL)) == file.sha256 else {
                throw VaultAgentInstallerError.installationConflict
            }
        }
    }

    private func validateOwnedFilesForUpdate(
        _ record: HostRecord,
        context: InstallContext
    ) throws {
        guard record.host == context.host.rawValue,
              hostIdentityAllowsUpdate(from: record.identity, to: context.identity),
              record.helperRelativePath == context.helper.relativePath,
              record.skillDestinationRelativePath == context.destination,
              record.files.count == Self.skillFiles.count else {
            throw VaultAgentInstallerError.installationConflict
        }
        let expectedHelperPath = applicationURL
            .appendingPathComponent(record.helperRelativePath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard expectedHelperPath == context.helper.url.path else {
            throw VaultAgentInstallerError.installationConflict
        }
        let root = userRootURL.appendingPathComponent(record.skillDestinationRelativePath)
        try validateOwnedSkillSnapshot(record, at: root)
    }

    private func hostIdentityAllowsUpdate(from old: HostIdentity, to current: HostIdentity) -> Bool {
        guard old.canonicalPath == current.canonicalPath,
              old.signature.identifier == current.signature.identifier,
              old.signature.designatedRequirement == current.signature.designatedRequirement,
              old.signature.isAdHoc == current.signature.isAdHoc else {
            return false
        }
        if old.signature.isAdHoc {
            return old.signature.cdHash == current.signature.cdHash
        }
        return old.signature.teamID == current.signature.teamID
    }

    private func validateOwnedFiles(
        _ record: HostRecord,
        context: InstallContext
    ) throws {
        guard record.host == context.host.rawValue,
              record.identity == context.identity,
              record.helperSHA256 == context.helper.sha256,
              record.skillDestinationRelativePath == context.destination,
              record.files.count == Self.skillFiles.count else {
            throw VaultAgentInstallerError.installationConflict
        }
        let expectedHelperPath = applicationURL
            .appendingPathComponent(record.helperRelativePath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard expectedHelperPath == context.helper.url.path else {
            throw VaultAgentInstallerError.installationConflict
        }
        let root = userRootURL.appendingPathComponent(record.skillDestinationRelativePath)
        try validateOwnedSkillSnapshot(record, at: root)
    }

    private func validateOwnedSkillSnapshot(_ record: HostRecord, at rootURL: URL) throws {
        let rootRelativePath = record.skillDestinationRelativePath
        var expectedFiles = Set<String>()
        var expectedDirectories: Set<String> = [""]
        for file in record.files {
            let prefix = "\(rootRelativePath)/"
            guard file.destinationRelativePath.hasPrefix(prefix) else {
                throw VaultAgentInstallerError.installationConflict
            }
            let relativePath = String(file.destinationRelativePath.dropFirst(prefix.count))
            guard !relativePath.isEmpty, expectedFiles.insert(relativePath).inserted else {
                throw VaultAgentInstallerError.installationConflict
            }
            let installedURL = rootURL.appendingPathComponent(relativePath)
            guard (try? digest(installedURL)) == file.sha256 else {
                throw VaultAgentInstallerError.userModifiedSkill
            }
            var parent = (relativePath as NSString).deletingLastPathComponent
            while parent != ".", !parent.isEmpty {
                expectedDirectories.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }

        var pending: [(url: URL, relativePath: String)] = [(rootURL, "")]
        var actualFiles = Set<String>()
        while let directory = pending.popLast() {
            var directoryInfo = stat()
            guard lstat(directory.url.path, &directoryInfo) == 0,
                  directoryInfo.st_mode & S_IFMT == S_IFDIR else {
                throw VaultAgentInstallerError.userModifiedSkill
            }
            for child in try fileManager.contentsOfDirectory(
                at: directory.url,
                includingPropertiesForKeys: nil,
                options: []
            ) {
                let relativePath = directory.relativePath.isEmpty
                    ? child.lastPathComponent
                    : "\(directory.relativePath)/\(child.lastPathComponent)"
                var childInfo = stat()
                guard lstat(child.path, &childInfo) == 0 else {
                    throw VaultAgentInstallerError.userModifiedSkill
                }
                switch childInfo.st_mode & S_IFMT {
                case S_IFDIR where expectedDirectories.contains(relativePath):
                    pending.append((child, relativePath))
                case S_IFREG where expectedFiles.contains(relativePath):
                    actualFiles.insert(relativePath)
                default:
                    throw VaultAgentInstallerError.userModifiedSkill
                }
            }
        }
        guard actualFiles == expectedFiles else {
            throw VaultAgentInstallerError.userModifiedSkill
        }
    }

    private func validateInstalledClaude(manifest: Manifest) throws {
        let hostURL = try locateHost(.claude)
        let hostSignature = try inspect(hostURL, expectedIdentifier: nil)
        let helper = try validateHelper(for: .claude)
        guard let record = manifest.hosts[VaultAgentHostKind.claude.rawValue] else {
            throw VaultAgentInstallerError.installationConflict
        }
        try validateOwnedInstall(
            record,
            context: .init(
                host: .claude,
                hostURL: hostURL,
                identity: .init(canonicalPath: hostURL.path, signature: hostSignature),
                helper: helper,
                destination: skillDestination(for: .claude)
            )
        )
    }

    private func readClaudeSettings() throws -> ClaudeSettingsState {
        let url = userRootURL.appendingPathComponent(Self.claudeSettingsRelativePath)
        let read: (data: Data, info: stat)
        do {
            read = try readRegularFile(url, maximumBytes: 4_194_304)
        } catch let error as POSIXError where error.code == .ENOENT {
            return .init(object: [:], originalData: Data("{}".utf8), snapshot: nil)
        } catch {
            throw VaultAgentInstallerError.installationConflict
        }
        guard read.info.st_uid == currentUID,
              read.info.st_mode & (S_IWGRP | S_IWOTH) == 0,
              read.info.st_mode & S_IRUSR != 0,
              read.info.st_mode & S_IWUSR != 0 else {
            throw VaultAgentInstallerError.installationConflict
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: read.data) as? [String: Any] else {
                throw VaultAgentInstallerError.installationConflict
            }
            _ = try claudeAllowRules(in: object)
            return .init(
                object: object,
                originalData: read.data,
                snapshot: makeSnapshot(read)
            )
        } catch let error as VaultAgentInstallerError {
            throw error
        } catch {
            throw VaultAgentInstallerError.installationConflict
        }
    }

    private func claudeAllowRules(in object: [String: Any]) throws -> [String] {
        guard let rawPermissions = object["permissions"] else { return [] }
        guard let permissions = rawPermissions as? [String: Any] else {
            throw VaultAgentInstallerError.installationConflict
        }
        guard let rawAllow = permissions["allow"] else { return [] }
        guard let values = rawAllow as? [Any],
              values.allSatisfy({ $0 is String }) else {
            throw VaultAgentInstallerError.installationConflict
        }
        return values.compactMap { $0 as? String }
    }

    private func setClaudeAllowRules(
        _ rules: [String],
        in object: inout [String: Any]
    ) throws {
        var permissions: [String: Any]
        if let rawPermissions = object["permissions"] {
            guard let existing = rawPermissions as? [String: Any] else {
                throw VaultAgentInstallerError.installationConflict
            }
            permissions = existing
        } else {
            permissions = [:]
        }
        permissions["allow"] = rules
        object["permissions"] = permissions
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func serializeJSONObject(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw VaultAgentInstallerError.installationConflict
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func commitClaudePermissionChange(
        settings: ClaudeSettingsState,
        updatedObject: [String: Any],
        delta: ClaudePermissionDelta,
        manifest: Manifest,
        replacingManifest manifestSnapshot: FileSnapshot?
    ) throws {
        try ensureUserDirectory(
            ".claude",
            createdPermissions: 0o700,
            enforceFinalPermissions: false
        )
        let settingsURL = userRootURL.appendingPathComponent(Self.claudeSettingsRelativePath)
        let backupURL = try createClaudeSettingsBackup(settings.originalData)
        let updatedData = try serializeJSONObject(updatedObject)
        do {
            try writeAtomicFile(
                updatedData,
                to: settingsURL,
                permissions: 0o600,
                replacing: settings.snapshot
            )
            try runClaudeDoctorIfAvailable()
            let verified = try readClaudeSettings()
            guard try serializeJSONObject(verified.object) == updatedData else {
                throw VaultAgentInstallerError.installationConflict
            }
            try writeManifest(manifest, replacing: manifestSnapshot)
        } catch {
            let originalError = error
            do {
                try compensateClaudePermissionChange(
                    original: settings,
                    writtenData: updatedData,
                    delta: delta,
                    settingsURL: settingsURL
                )
                try removeBackup(backupURL)
            } catch {
                throw VaultAgentInstallerError.rollbackFailed
            }
            throw originalError
        }
        try removeBackup(backupURL)
    }

    private func compensateClaudePermissionChange(
        original: ClaudeSettingsState,
        writtenData: Data,
        delta: ClaudePermissionDelta,
        settingsURL: URL
    ) throws {
        let currentSnapshot = try fileSnapshot(settingsURL, maximumBytes: 4_194_304)
        if currentSnapshot?.sha256 == sha256(writtenData) {
            try restoreClaudeSettings(
                original,
                replacing: currentSnapshot,
                at: settingsURL
            )
            return
        }

        let current = try readClaudeSettings()
        let currentRules = try claudeAllowRules(in: current.object)
        let addedSet = Set(delta.addedRules)
        var compensatedRules = currentRules.filter { !addedSet.contains($0) }
        let compensatedSet = Set(compensatedRules)
        compensatedRules.append(contentsOf: delta.removedRules.filter {
            !compensatedSet.contains($0)
        })
        guard compensatedRules != currentRules else { return }
        var compensatedObject = current.object
        try setClaudeAllowRules(stableUnique(compensatedRules), in: &compensatedObject)
        let compensatedData = try serializeJSONObject(compensatedObject)
        try writeAtomicFile(
            compensatedData,
            to: settingsURL,
            permissions: 0o600,
            replacing: current.snapshot
        )
    }

    private func createClaudeSettingsBackup(_ data: Data) throws -> URL {
        try ensureUserDirectory(
            Self.backupDirectoryRelativePath,
            createdPermissions: 0o700,
            enforceFinalPermissions: true
        )
        let backup = userRootURL.appendingPathComponent(Self.backupDirectoryRelativePath)
            .appendingPathComponent("claude-settings-\(UUID().uuidString).json")
        try writeAtomicFile(data, to: backup, permissions: 0o600, replacing: nil)
        return backup
    }

    private func removeBackup(_ backupURL: URL) throws {
        guard unlink(backupURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try fsyncDirectory(backupURL.deletingLastPathComponent())
    }

    private func restoreClaudeSettings(
        _ original: ClaudeSettingsState,
        replacing currentSnapshot: FileSnapshot?,
        at settingsURL: URL
    ) throws {
        if original.snapshot != nil {
            try writeAtomicFile(
                original.originalData,
                to: settingsURL,
                permissions: 0o600,
                replacing: currentSnapshot
            )
            return
        }
        guard let currentSnapshot else { return }
        let tombstone = settingsURL.deletingLastPathComponent()
            .appendingPathComponent(".pastera-settings-rollback-\(UUID().uuidString).tmp")
        guard renamex_np(settingsURL.path, tombstone.path, UInt32(RENAME_EXCL)) == 0 else {
            throw VaultAgentInstallerError.rollbackFailed
        }
        guard try fileSnapshot(tombstone, maximumBytes: 4_194_304) == currentSnapshot else {
            guard renamex_np(tombstone.path, settingsURL.path, UInt32(RENAME_EXCL)) == 0 else {
                throw VaultAgentInstallerError.rollbackFailed
            }
            throw VaultAgentInstallerError.rollbackFailed
        }
        guard unlink(tombstone.path) == 0 else {
            throw VaultAgentInstallerError.rollbackFailed
        }
        try fsyncDirectory(settingsURL.deletingLastPathComponent())
    }

    private func runClaudeDoctorIfAvailable() throws {
        guard let hostURL = try? locateHost(.claude) else { return }
        let exitCode = try commandRunner.run(executableURL: hostURL, arguments: ["doctor"])
        guard exitCode == 0 else {
            throw VaultAgentInstallerError.commandFailed(exitCode)
        }
    }

    private func loadManifestState() throws -> ManifestState {
        let url = userRootURL.appendingPathComponent(Self.manifestRelativePath)
        let read: (data: Data, info: stat)
        do {
            read = try readRegularFile(url, maximumBytes: 1_048_576)
        } catch let error as POSIXError where error.code == .ENOENT {
            return .init(
                manifest: .init(
                    schemaVersion: 1,
                    installationVersion: installationVersion,
                    hosts: [:],
                    cli: nil,
                    claudePermissions: nil
                ),
                snapshot: nil
            )
        } catch {
            throw VaultAgentInstallerError.manifestCorrupt
        }
        do {
            let manifest = try JSONDecoder().decode(Manifest.self, from: read.data)
            guard manifest.schemaVersion == 1,
                  manifest.installationVersion == installationVersion else {
                throw VaultAgentInstallerError.manifestCorrupt
            }
            return .init(manifest: manifest, snapshot: makeSnapshot(read))
        } catch let error as VaultAgentInstallerError {
            throw error
        } catch {
            throw VaultAgentInstallerError.manifestCorrupt
        }
    }

    private func writeManifest(
        _ manifest: Manifest,
        replacing expectedSnapshot: FileSnapshot?
    ) throws {
        let url = userRootURL.appendingPathComponent(Self.manifestRelativePath)
        try ensureUserDirectory(
            Self.manifestDirectoryRelativePath,
            createdPermissions: 0o700,
            enforceFinalPermissions: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeAtomicFile(
            encoder.encode(manifest),
            to: url,
            permissions: 0o600,
            replacing: expectedSnapshot
        )
    }

    func digest(_ url: URL) throws -> String {
        do {
            return sha256(try readRegularFile(url, maximumBytes: 134_217_728).data)
        } catch {
            throw VaultAgentInstallerError.installationConflict
        }
    }

    private func readRegularFile(
        _ url: URL,
        maximumBytes: Int
    ) throws -> (data: Data, info: stat) {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        var initialInfo = stat()
        guard fstat(descriptor, &initialInfo) == 0,
              initialInfo.st_mode & S_IFMT == S_IFREG,
              initialInfo.st_size >= 0,
              initialInfo.st_size <= maximumBytes else {
            throw VaultAgentInstallerError.installationConflict
        }

        var data = Data()
        data.reserveCapacity(Int(initialInfo.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard data.count + count <= maximumBytes else {
                throw VaultAgentInstallerError.installationConflict
            }
            data.append(buffer, count: count)
        }
        var finalInfo = stat()
        guard fstat(descriptor, &finalInfo) == 0,
              initialInfo.st_dev == finalInfo.st_dev,
              initialInfo.st_ino == finalInfo.st_ino,
              initialInfo.st_size == finalInfo.st_size,
              initialInfo.st_mtimespec.tv_sec == finalInfo.st_mtimespec.tv_sec,
              initialInfo.st_mtimespec.tv_nsec == finalInfo.st_mtimespec.tv_nsec,
              data.count == Int(finalInfo.st_size) else {
            throw VaultAgentInstallerError.installationConflict
        }
        return (data, finalInfo)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeSnapshot(_ read: (data: Data, info: stat)) -> FileSnapshot {
        .init(
            device: UInt64(read.info.st_dev),
            inode: UInt64(read.info.st_ino),
            size: Int64(read.info.st_size),
            modifiedSeconds: Int(read.info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int(read.info.st_mtimespec.tv_nsec),
            sha256: sha256(read.data)
        )
    }

    private func fileSnapshot(_ url: URL, maximumBytes: Int) throws -> FileSnapshot? {
        do {
            return makeSnapshot(try readRegularFile(url, maximumBytes: maximumBytes))
        } catch let error as POSIXError where error.code == .ENOENT {
            return nil
        }
    }

    private func writeAtomicFile(
        _ data: Data,
        to url: URL,
        permissions: mode_t,
        replacing expectedSnapshot: FileSnapshot?
    ) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".pastera-write-\(UUID().uuidString).tmp")
        let descriptor = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            permissions
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var descriptorOpen = true
        var shouldRemoveTemporary = true
        defer {
            if descriptorOpen { close(descriptor) }
            if shouldRemoveTemporary { unlink(temporary.path) }
        }
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += count
            }
        }
        guard fchmod(descriptor, permissions) == 0,
              fsync(descriptor) == 0,
              close(descriptor) == 0 else {
            descriptorOpen = false
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        descriptorOpen = false
        guard let newSnapshot = try fileSnapshot(
            temporary,
            maximumBytes: max(data.count, 1)
        ) else {
            throw VaultAgentInstallerError.installationConflict
        }

        try atomicWriteInterposer(url, .beforeSwap)
        if expectedSnapshot == nil {
            guard renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL)) == 0 else {
                throw VaultAgentInstallerError.installationConflict
            }
        } else {
            guard renamex_np(temporary.path, url.path, UInt32(RENAME_SWAP)) == 0 else {
                throw VaultAgentInstallerError.installationConflict
            }
            let displacedSnapshot = try? fileSnapshot(
                temporary,
                maximumBytes: 4_194_304
            )
            guard displacedSnapshot == expectedSnapshot else {
                try atomicWriteInterposer(url, .beforeConflictRollback)
                try rollbackCommittedAtomicWrite(
                    at: url,
                    temporary: temporary,
                    newSnapshot: newSnapshot,
                    restoreDisplacedFile: true,
                    shouldRemoveTemporary: &shouldRemoveTemporary
                )
                throw VaultAgentInstallerError.installationConflict
            }
        }
        do {
            try atomicWriteInterposer(url, .afterSwapBeforeSync)
            guard try fileSnapshot(url, maximumBytes: max(data.count, 1)) == newSnapshot else {
                throw VaultAgentInstallerError.installationConflict
            }
            try fsyncDirectory(url.deletingLastPathComponent())
        } catch {
            let originalError = error
            do {
                try rollbackCommittedAtomicWrite(
                    at: url,
                    temporary: temporary,
                    newSnapshot: newSnapshot,
                    restoreDisplacedFile: expectedSnapshot != nil,
                    shouldRemoveTemporary: &shouldRemoveTemporary
                )
            } catch {
                throw VaultAgentInstallerError.rollbackFailed
            }
            throw originalError
        }
    }

    private func rollbackCommittedAtomicWrite(
        at url: URL,
        temporary: URL,
        newSnapshot: FileSnapshot,
        restoreDisplacedFile: Bool,
        shouldRemoveTemporary: inout Bool
    ) throws {
        let rollbackCandidate = url.deletingLastPathComponent()
            .appendingPathComponent(".pastera-rollback-\(UUID().uuidString).tmp")
        guard renamex_np(url.path, rollbackCandidate.path, UInt32(RENAME_EXCL)) == 0 else {
            shouldRemoveTemporary = false
            throw VaultAgentInstallerError.rollbackFailed
        }
        try atomicWriteInterposer(url, .afterRollbackTargetQuarantined)
        let candidateIsPasteraWrite = (try? fileSnapshot(
            rollbackCandidate,
            maximumBytes: max(Int(newSnapshot.size), 1)
        )) == newSnapshot
        guard candidateIsPasteraWrite else {
            guard renamex_np(rollbackCandidate.path, url.path, UInt32(RENAME_EXCL)) == 0 else {
                shouldRemoveTemporary = false
                throw VaultAgentInstallerError.rollbackFailed
            }
            try fsyncDirectory(url.deletingLastPathComponent())
            return
        }

        if restoreDisplacedFile {
            guard renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL)) == 0 else {
                shouldRemoveTemporary = false
                throw VaultAgentInstallerError.rollbackFailed
            }
            shouldRemoveTemporary = false
        }
        guard unlink(rollbackCandidate.path) == 0 else {
            throw VaultAgentInstallerError.rollbackFailed
        }
        try fsyncDirectory(url.deletingLastPathComponent())
    }

    private func fsyncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func ensureUserDirectory(
        _ relativePath: String,
        createdPermissions: mode_t,
        enforceFinalPermissions: Bool
    ) throws {
        let components = NSString(string: relativePath).pathComponents
            .filter { $0 != "/" && $0 != "." && !$0.isEmpty }
        var current = userRootURL
        for (index, component) in components.enumerated() {
            guard component != ".." else {
                throw VaultAgentInstallerError.installationConflict
            }
            current.appendPathComponent(component)
            var info = stat()
            if lstat(current.path, &info) != 0 {
                guard errno == ENOENT,
                      mkdir(current.path, createdPermissions) == 0 else {
                    throw VaultAgentInstallerError.installationConflict
                }
                guard chmod(current.path, createdPermissions) == 0 else {
                    throw VaultAgentInstallerError.installationConflict
                }
                continue
            }
            guard info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == currentUID else {
                throw VaultAgentInstallerError.installationConflict
            }
            if enforceFinalPermissions, index == components.count - 1 {
                guard chmod(current.path, createdPermissions) == 0 else {
                    throw VaultAgentInstallerError.installationConflict
                }
            }
        }
    }

    private func pathKind(_ url: URL) throws -> mode_t? {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            return info.st_mode & S_IFMT
        }
        guard errno == ENOENT else {
            throw VaultAgentInstallerError.installationConflict
        }
        return nil
    }

    private func validateCLIHelper() throws -> ValidatedHelper {
        let relativePath = "Contents/Helpers/pastera"
        let helperURL = try validateExecutable(
            applicationURL.appendingPathComponent(relativePath),
            requiresCurrentOwner: false
        )
        _ = try inspect(helperURL, expectedIdentifier: "com.pastera-app.pastera")
        return .init(url: helperURL, relativePath: relativePath, sha256: try digest(helperURL))
    }

    private func cliRecordMatches(_ record: CLIRecord, helper: ValidatedHelper) -> Bool {
        guard record.helperRelativePath == helper.relativePath,
              record.helperSHA256 == helper.sha256,
              record.destinationRelativePath == Self.cliDestinationRelativePath else {
            return false
        }
        let link = userRootURL.appendingPathComponent(record.destinationRelativePath)
        return cliLinkPointsTo(link, helperURL: helper.url)
    }

    private func cliLinkPointsTo(_ link: URL, helperURL: URL) -> Bool {
        guard let snapshot = try? linkSnapshot(link),
              snapshot.destination == helperURL.path else {
            return false
        }
        return link.resolvingSymlinksInPath().standardizedFileURL.path == helperURL.path
    }

    private func linkSnapshot(_ url: URL) throws -> LinkSnapshot {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFLNK else {
            throw VaultAgentInstallerError.installationConflict
        }
        return .init(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            destination: try fileManager.destinationOfSymbolicLink(atPath: url.path)
        )
    }

    private func makeCLIStatus(installed: Bool) -> VaultAgentCLIInstallationStatus {
        let executable = userRootURL.appendingPathComponent(Self.cliDestinationRelativePath)
        let localBin = executable.deletingLastPathComponent().standardizedFileURL.path
        let pathDirectories = environmentPathProvider().split(separator: ":", omittingEmptySubsequences: false)
            .map { URL(fileURLWithPath: String($0)).standardizedFileURL.path }
        return .init(
            installed: installed,
            executablePath: executable.path,
            pathHint: pathDirectories.contains(localBin)
                ? nil
                : "Add ~/.local/bin to PATH to run pastera from a shell."
        )
    }

    private func restoreQuarantinedItem(_ quarantine: URL, to target: URL) throws {
        guard try pathKind(target) == nil else {
            throw VaultAgentInstallerError.rollbackFailed
        }
        do {
            try fileManager.moveItem(at: quarantine, to: target)
        } catch {
            throw VaultAgentInstallerError.rollbackFailed
        }
    }

    func skillDestination(for host: VaultAgentHostKind) -> String {
        switch host {
        case .codex: ".agents/skills/pastera-vault"
        case .claude: ".claude/skills/pastera-vault"
        }
    }

    func client(for host: VaultAgentHostKind) -> VaultAgentClientKind {
        switch host {
        case .codex: .codex
        case .claude: .claude
        }
    }

    func addArguments(for host: VaultAgentHostKind, helperURL: URL) -> [String] {
        switch host {
        case .codex:
            ["mcp", "add", "pastera-vault", "--", helperURL.path]
        case .claude:
            [
                "mcp", "add", "--transport", "stdio", "--scope", "user",
                "pastera-vault", "--", helperURL.path
            ]
        }
    }

    func makeRegistration(helperURL: URL) -> VaultAgentHostRegistration {
        .init(command: helperURL.path, arguments: [], userScoped: true)
    }

    private func addArguments(
        for host: VaultAgentHostKind,
        registration: VaultAgentHostRegistration
    ) -> [String] {
        let helperURL = URL(fileURLWithPath: registration.command)
        return addArguments(for: host, helperURL: helperURL) + registration.arguments
    }

    private func removeRegistrationIfOwned(
        host: VaultAgentHostKind,
        hostURL: URL,
        expected: VaultAgentHostRegistration
    ) throws {
        guard try commandRunner.registration(executableURL: hostURL, host: host) == expected else {
            throw VaultAgentInstallerError.rollbackFailed
        }
        let exitCode = try commandRunner.run(
            executableURL: hostURL,
            arguments: removeArguments(for: host)
        )
        guard exitCode == 0 else {
            throw VaultAgentInstallerError.rollbackFailed
        }
    }

    private func restoreOwnedRegistration(
        host: VaultAgentHostKind,
        hostURL: URL,
        registration: VaultAgentHostRegistration
    ) throws {
        guard try commandRunner.registration(executableURL: hostURL, host: host) == nil else {
            throw VaultAgentInstallerError.rollbackFailed
        }
        let exitCode = try commandRunner.run(
            executableURL: hostURL,
            arguments: addArguments(for: host, registration: registration)
        )
        guard exitCode == 0 else {
            throw VaultAgentInstallerError.rollbackFailed
        }
    }

    private func replaceOwnedRegistration(
        host: VaultAgentHostKind,
        hostURL: URL,
        current: VaultAgentHostRegistration,
        replacement: VaultAgentHostRegistration
    ) throws {
        guard try commandRunner.registration(executableURL: hostURL, host: host) == current else {
            throw VaultAgentInstallerError.installationConflict
        }
        let exitCode = try commandRunner.run(
            executableURL: hostURL,
            arguments: addArguments(for: host, registration: replacement)
        )
        guard exitCode == 0 else {
            let observed = try commandRunner.registration(executableURL: hostURL, host: host)
            if observed == replacement {
                let rollbackCode = try commandRunner.run(
                    executableURL: hostURL,
                    arguments: addArguments(for: host, registration: current)
                )
                guard rollbackCode == 0,
                      try commandRunner.registration(executableURL: hostURL, host: host)
                        == current else {
                    throw VaultAgentInstallerError.rollbackFailed
                }
            } else if observed != current {
                throw VaultAgentInstallerError.rollbackFailed
            }
            throw VaultAgentInstallerError.commandFailed(exitCode)
        }
    }

    private func rollbackSkillSwap(
        oldRecord: HostRecord,
        newRecord: HostRecord,
        stagedURL: URL,
        targetURL: URL
    ) throws {
        guard (try? validateOwnedSkillSnapshot(oldRecord, at: stagedURL)) != nil,
              (try? validateOwnedSkillSnapshot(newRecord, at: targetURL)) != nil,
              renamex_np(stagedURL.path, targetURL.path, UInt32(RENAME_SWAP)) == 0 else {
            throw VaultAgentInstallerError.rollbackFailed
        }
    }

    func removeArguments(for host: VaultAgentHostKind) -> [String] {
        switch host {
        case .codex, .claude:
            ["mcp", "remove", "pastera-vault"]
        }
    }

    func installedStatus(host: VaultAgentHostKind, hostPath: String) -> VaultAgentIntegrationStatus {
        let authorization = authorizationStatusProvider(client(for: host))
        return .init(hosts: [
            .init(
                host: host,
                hostDetected: true,
                hostExecutablePath: hostPath,
                mcpInstalled: true,
                skillInstalled: true,
                installedVersion: installationVersion,
                authorized: authorization.authorized,
                idleExpiresAt: authorization.idleExpiresAt,
                hardExpiresAt: authorization.hardExpiresAt
            )
        ])
    }

    func uninstalledStatus(host: VaultAgentHostKind, hostPath: String) -> VaultAgentIntegrationStatus {
        let authorization = authorizationStatusProvider(client(for: host))
        return .init(hosts: [
            .init(
                host: host,
                hostDetected: true,
                hostExecutablePath: hostPath,
                mcpInstalled: false,
                skillInstalled: false,
                installedVersion: nil,
                authorized: authorization.authorized,
                idleExpiresAt: authorization.idleExpiresAt,
                hardExpiresAt: authorization.hardExpiresAt
            )
        ])
    }
}
// swiftlint:disable:this file_length
