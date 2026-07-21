import Darwin
import Foundation
import PasteraAgentProtocol
import Security

struct VaultAgentSocketPeerCredentials: Equatable {
    let uid: uid_t
    let pid: pid_t
}

protocol VaultAgentSocketPeerCredentialReading {
    func credentials(fileDescriptor: Int32) throws -> VaultAgentSocketPeerCredentials
}

struct VaultAgentProcessSnapshot: Equatable {
    let pid: pid_t
    let parentPID: pid_t
    let uid: uid_t
    var startSeconds: UInt64
    let startMicroseconds: UInt64
    let executableURL: URL
    let device: UInt64
    let inode: UInt64
}

protocol VaultAgentProcessInspecting {
    func snapshot(pid: pid_t) throws -> VaultAgentProcessSnapshot
}

struct VaultAgentCodeSignature: Equatable {
    let identifier: String
    let designatedRequirement: String
    let cdHash: Data?
    let isAdHoc: Bool
}

protocol VaultAgentCodeSigningInspecting {
    func inspect(executableURL: URL) throws -> VaultAgentCodeSignature
}

struct VaultAgentInstalledHostIdentity: Equatable {
    let client: VaultAgentClientKind
    let canonicalPath: String
    let designatedRequirement: String
    let cdHash: Data?
    let isAdHoc: Bool
}

protocol VaultAgentHostIdentityProviding {
    func installedHostIdentity(for client: VaultAgentClientKind) -> VaultAgentInstalledHostIdentity?
}

enum VaultAgentPeerVerificationError: Error, Equatable {
    case peerCredentialMismatch
    case peerUnavailable
    case invalidHelperPath
    case invalidHelperFile
    case invalidHelperSignature
    case unexpectedHostIdentity
    case hostChainMismatch
    case unstableProcess
}

protocol VaultAgentPeerVerifying {
    func verify(fileDescriptor: Int32) throws -> VaultAgentPeerIdentity
}

struct VaultAgentSystemPeerCredentialReader: VaultAgentSocketPeerCredentialReading {
    func credentials(fileDescriptor: Int32) throws -> VaultAgentSocketPeerCredentials {
        var peerUID = uid_t.max
        var peerGID = gid_t.max
        guard getpeereid(fileDescriptor, &peerUID, &peerGID) == 0 else {
            throw VaultAgentPeerVerificationError.peerUnavailable
        }
        var peerPID = pid_t.zero
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fileDescriptor, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &length) == 0,
              length == MemoryLayout<pid_t>.size,
              peerPID > 0 else {
            throw VaultAgentPeerVerificationError.peerUnavailable
        }
        return .init(uid: peerUID, pid: peerPID)
    }
}

struct VaultAgentSystemProcessInspector: VaultAgentProcessInspecting {
    func snapshot(pid: pid_t) throws -> VaultAgentProcessSnapshot {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize else {
            throw VaultAgentPeerVerificationError.peerUnavailable
        }

        var pathBytes = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(pid, &pathBytes, UInt32(pathBytes.count)) > 0 else {
            throw VaultAgentPeerVerificationError.peerUnavailable
        }
        let rawPath = String(cString: pathBytes)
        var fileInfo = stat()
        guard lstat(rawPath, &fileInfo) == 0,
              (fileInfo.st_mode & S_IFMT) == S_IFREG,
              let canonical = realpath(rawPath, nil) else {
            throw VaultAgentPeerVerificationError.invalidHelperFile
        }
        defer { free(canonical) }
        return .init(
            pid: pid,
            parentPID: pid_t(info.pbi_ppid),
            uid: uid_t(info.pbi_uid),
            startSeconds: UInt64(info.pbi_start_tvsec),
            startMicroseconds: UInt64(info.pbi_start_tvusec),
            executableURL: URL(fileURLWithPath: String(cString: canonical)),
            device: UInt64(fileInfo.st_dev),
            inode: UInt64(fileInfo.st_ino)
        )
    }
}

struct VaultAgentSystemCodeSigningInspector: VaultAgentCodeSigningInspecting {
    func inspect(executableURL: URL) throws -> VaultAgentCodeSignature {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }
        let noNetworkAccess = SecCSFlags(rawValue: 1 << 29)
        let validationFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | noNetworkAccess.rawValue)
        guard SecStaticCodeCheckValidity(staticCode, validationFlags, nil) == errSecSuccess else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
              let values = signingInfo as? [CFString: Any],
              let identifier = values[kSecCodeInfoIdentifier] as? String else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }
        var designatedRequirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &designatedRequirement) == errSecSuccess,
              let requirement = designatedRequirement else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }
        var requirementText: CFString?
        guard SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess,
              let requirementText else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }
        let flags = (values[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = flags & 0x0002 != 0
        let cdHash = values[kSecCodeInfoUnique] as? Data
        guard !isAdHoc || cdHash != nil else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }
        return .init(
            identifier: identifier,
            designatedRequirement: requirementText as String,
            cdHash: cdHash,
            isAdHoc: isAdHoc
        )
    }
}

final class VaultAgentPeerVerifier: VaultAgentPeerVerifying {
    private struct HelperMapping {
        let name: String
        let identifier: String
        let client: VaultAgentClientKind
    }

    private static let mappings = [
        HelperMapping(name: "PasteraCodexMCP", identifier: "com.pastera-app.PasteraCodexMCP", client: .codex),
        HelperMapping(name: "PasteraClaudeMCP", identifier: "com.pastera-app.PasteraClaudeMCP", client: .claude),
        HelperMapping(name: "pastera", identifier: "com.pastera-app.pastera", client: .cli)
    ]

    private let helpersURL: URL
    private let currentUID: uid_t
    private let credentialReader: VaultAgentSocketPeerCredentialReading
    private let processInspector: VaultAgentProcessInspecting
    private let codeSigningInspector: VaultAgentCodeSigningInspecting
    private let hostIdentityProvider: VaultAgentHostIdentityProviding

    init(
        applicationURL: URL,
        currentUID: uid_t = getuid(),
        credentialReader: VaultAgentSocketPeerCredentialReading = VaultAgentSystemPeerCredentialReader(),
        processInspector: VaultAgentProcessInspecting = VaultAgentSystemProcessInspector(),
        codeSigningInspector: VaultAgentCodeSigningInspecting = VaultAgentSystemCodeSigningInspector(),
        hostIdentityProvider: VaultAgentHostIdentityProviding
    ) {
        helpersURL = applicationURL.appendingPathComponent("Contents/Helpers").standardizedFileURL
        self.currentUID = currentUID
        self.credentialReader = credentialReader
        self.processInspector = processInspector
        self.codeSigningInspector = codeSigningInspector
        self.hostIdentityProvider = hostIdentityProvider
    }

    func verify(fileDescriptor: Int32) throws -> VaultAgentPeerIdentity {
        let credentials = try mapped { try credentialReader.credentials(fileDescriptor: fileDescriptor) }
        guard credentials.uid == currentUID, credentials.pid > 0 else {
            throw VaultAgentPeerVerificationError.peerCredentialMismatch
        }

        let helperBefore = try readSnapshot(pid: credentials.pid)
        guard helperBefore.uid == currentUID else {
            throw VaultAgentPeerVerificationError.peerCredentialMismatch
        }
        let mapping = try helperMapping(for: helperBefore.executableURL)
        let helperSignature = try inspect(helperBefore.executableURL)
        guard helperSignature.identifier == mapping.identifier,
              !helperSignature.designatedRequirement.isEmpty,
              !helperSignature.isAdHoc || helperSignature.cdHash != nil else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }
        try requireStable(helperBefore)

        switch mapping.client {
        case .cli:
            guard hostIdentityProvider.installedHostIdentity(for: .cli) == nil else {
                throw VaultAgentPeerVerificationError.unexpectedHostIdentity
            }
            try requireFinalIdentity(snapshot: helperBefore, signature: helperSignature)
            return makeIdentity(mapping.client, helperSignature, helperBefore, host: nil, hostSnapshot: nil)
        case .codex, .claude:
            guard let installedHost = hostIdentityProvider.installedHostIdentity(for: mapping.client),
                  installedHost.client == mapping.client else {
                throw VaultAgentPeerVerificationError.hostChainMismatch
            }
            let match = try findHost(startingAt: helperBefore.parentPID, installed: installedHost)
            try requireFinalIdentity(snapshot: helperBefore, signature: helperSignature)
            return makeIdentity(mapping.client, helperSignature, helperBefore, host: match.signature, hostSnapshot: match.snapshot)
        }
    }

    private func findHost(
        startingAt firstPID: pid_t,
        installed: VaultAgentInstalledHostIdentity
    ) throws -> (snapshot: VaultAgentProcessSnapshot, signature: VaultAgentCodeSignature) {
        var pid = firstPID
        for _ in 0..<4 {
            guard pid > 0 else { break }
            let snapshot = try readSnapshot(pid: pid)
            guard snapshot.uid == currentUID else {
                throw VaultAgentPeerVerificationError.hostChainMismatch
            }
            let signature = try inspect(snapshot.executableURL)
            try requireStable(snapshot)
            if signature.designatedRequirement == installed.designatedRequirement,
               snapshot.executableURL.path == installed.canonicalPath,
               signature.isAdHoc == installed.isAdHoc,
               !signature.isAdHoc || signature.cdHash == installed.cdHash {
                try requireFinalIdentity(snapshot: snapshot, signature: signature)
                return (snapshot, signature)
            }
            pid = snapshot.parentPID
        }
        throw VaultAgentPeerVerificationError.hostChainMismatch
    }

    private func helperMapping(for executableURL: URL) throws -> HelperMapping {
        try validateExecutable(executableURL)
        guard let mapping = Self.mappings.first(where: { candidate in
            let expected = helpersURL.appendingPathComponent(candidate.name).standardizedFileURL
            return expected.path == executableURL.standardizedFileURL.path
        }) else {
            throw VaultAgentPeerVerificationError.invalidHelperPath
        }
        return mapping
    }

    private func readSnapshot(pid: pid_t) throws -> VaultAgentProcessSnapshot {
        let snapshot = try mapped { try processInspector.snapshot(pid: pid) }
        try validateExecutable(snapshot.executableURL)
        return snapshot
    }

    private func requireStable(_ before: VaultAgentProcessSnapshot) throws {
        let after = try readSnapshot(pid: before.pid)
        guard before == after else {
            throw VaultAgentPeerVerificationError.unstableProcess
        }
    }

    private func requireFinalIdentity(
        snapshot: VaultAgentProcessSnapshot,
        signature: VaultAgentCodeSignature
    ) throws {
        let finalSnapshot = try readSnapshot(pid: snapshot.pid)
        guard snapshot == finalSnapshot else {
            throw VaultAgentPeerVerificationError.unstableProcess
        }
        let finalSignature = try inspect(snapshot.executableURL)
        guard signature == finalSignature else {
            throw VaultAgentPeerVerificationError.invalidHelperSignature
        }
    }

    private func validateExecutable(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == currentUID else {
            throw VaultAgentPeerVerificationError.invalidHelperFile
        }
    }

    private func inspect(_ url: URL) throws -> VaultAgentCodeSignature {
        try mapped { try codeSigningInspector.inspect(executableURL: url) }
    }

    private func makeIdentity(
        _ client: VaultAgentClientKind,
        _ helper: VaultAgentCodeSignature,
        _ helperSnapshot: VaultAgentProcessSnapshot,
        host: VaultAgentCodeSignature?,
        hostSnapshot: VaultAgentProcessSnapshot?
    ) -> VaultAgentPeerIdentity {
        .init(
            client: client,
            helperRequirement: helper.designatedRequirement,
            helperCDHash: helper.cdHash,
            helperIsAdHoc: helper.isAdHoc,
            helperPath: helperSnapshot.executableURL.path,
            hostRequirement: host?.designatedRequirement,
            hostCDHash: host?.cdHash,
            hostIsAdHoc: host?.isAdHoc,
            hostPath: hostSnapshot?.executableURL.path
        )
    }

    private func mapped<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch let error as VaultAgentPeerVerificationError { throw error } catch { throw VaultAgentPeerVerificationError.peerUnavailable }
    }
}
