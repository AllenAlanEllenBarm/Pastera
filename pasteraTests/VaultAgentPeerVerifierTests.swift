import Darwin
import Foundation
import PasteraAgentProtocol
import Testing
@testable import Pastera

@Suite("Vault agent peer verifier", .serialized)
struct VaultAgentPeerVerifierTests {
    @Test("valid Codex helper must have its recorded host in the first four parents")
    func codexRequiresRecordedHostChain() throws {
        let fixture = try PeerFixture(helper: "PasteraCodexMCP", client: .codex)
        fixture.addProcess(pid: 90, parent: 80, url: fixture.helperURL)
        fixture.addProcess(pid: 80, parent: 1, url: fixture.makeExecutable("launcher"))

        #expect(throws: VaultAgentPeerVerificationError.hostChainMismatch) {
            try fixture.verifier().verify(fileDescriptor: 9)
        }

        let host = fixture.makeExecutable("Codex")
        fixture.addProcess(pid: 80, parent: 1, url: host)
        fixture.hosts[.codex] = fixture.hostRecord(client: .codex, url: host)
        let identity = try fixture.verifier().verify(fileDescriptor: 9)
        #expect(identity.client == .codex)
        #expect(identity.helperPath == fixture.helperURL.path)
        #expect(identity.hostPath == host.path)
    }

    @Test("a matching host at the fifth parent is rejected")
    func parentWalkIsBounded() throws {
        let fixture = try PeerFixture(helper: "PasteraClaudeMCP", client: .claude)
        fixture.addProcess(pid: 90, parent: 80, url: fixture.helperURL)
        for (pid, parent): (pid_t, pid_t) in [(80, 70), (70, 60), (60, 50), (50, 40)] {
            fixture.addProcess(pid: pid, parent: parent, url: fixture.makeExecutable("p\(pid)"))
        }
        let host = fixture.makeExecutable("Claude")
        fixture.addProcess(pid: 40, parent: 1, url: host)
        fixture.hosts[.claude] = fixture.hostRecord(client: .claude, url: host)

        #expect(throws: VaultAgentPeerVerificationError.hostChainMismatch) {
            try fixture.verifier().verify(fileDescriptor: 9)
        }
    }

    @Test("helper identity path and stable process snapshots are mandatory")
    func helperIdentityAndSnapshotAreChecked() throws {
        let wrongName = try PeerFixture(helper: "PasteraCodexMCP", client: .codex)
        wrongName.signatures[wrongName.helperURL.path] = .init(
            identifier: "com.attacker.Helper",
            designatedRequirement: "helper-req",
            cdHash: nil,
            isAdHoc: false
        )
        wrongName.addProcess(pid: 90, parent: 1, url: wrongName.helperURL)
        #expect(throws: VaultAgentPeerVerificationError.invalidHelperSignature) {
            try wrongName.verifier().verify(fileDescriptor: 9)
        }

        let changed = try PeerFixture(helper: "pastera", client: .cli)
        changed.addProcess(pid: 90, parent: 1, url: changed.helperURL)
        changed.mutateOnSecondRead.insert(90)
        #expect(throws: VaultAgentPeerVerificationError.unstableProcess) {
            try changed.verifier().verify(fileDescriptor: 9)
        }

        let outside = try PeerFixture(helper: "PasteraCodexMCP", client: .codex)
        let borrowed = outside.makeExecutable("PasteraCodexMCP")
        outside.signatures[borrowed.path] = outside.signatures[outside.helperURL.path]
        outside.addProcess(pid: 90, parent: 1, url: borrowed)
        #expect(throws: VaultAgentPeerVerificationError.invalidHelperPath) {
            try outside.verifier().verify(fileDescriptor: 9)
        }

        let linked = try PeerFixture(helper: "pastera", client: .cli)
        linked.addProcess(pid: 90, parent: 1, url: linked.helperURL)
        let target = linked.makeExecutable("target")
        try FileManager.default.removeItem(at: linked.helperURL)
        try FileManager.default.createSymbolicLink(at: linked.helperURL, withDestinationURL: target)
        #expect(throws: VaultAgentPeerVerificationError.invalidHelperFile) {
            try linked.verifier().verify(fileDescriptor: 9)
        }
    }

    @Test("Claude Host snapshot and ad-hoc cdhash must remain stable")
    func hostIdentityIsStableAndExact() throws {
        let changed = try PeerFixture(helper: "PasteraClaudeMCP", client: .claude)
        let changedHost = changed.makeExecutable("Claude")
        changed.addProcess(pid: 90, parent: 80, url: changed.helperURL)
        changed.addProcess(pid: 80, parent: 1, url: changedHost)
        changed.hosts[.claude] = changed.hostRecord(client: .claude, url: changedHost)
        changed.mutateOnSecondRead.insert(80)
        #expect(throws: VaultAgentPeerVerificationError.unstableProcess) {
            try changed.verifier().verify(fileDescriptor: 9)
        }

        let adHoc = try PeerFixture(helper: "PasteraClaudeMCP", client: .claude)
        let adHocHost = adHoc.makeExecutable("ClaudeAdHoc")
        adHoc.signatures[adHocHost.path] = .init(
            identifier: "host.ClaudeAdHoc",
            designatedRequirement: "host-req",
            cdHash: Data([9]),
            isAdHoc: true
        )
        adHoc.addProcess(pid: 90, parent: 80, url: adHoc.helperURL)
        adHoc.addProcess(pid: 80, parent: 1, url: adHocHost)
        let terminal = adHoc.makeExecutable("launchd")
        adHoc.addProcess(pid: 1, parent: 0, url: terminal)
        adHoc.hosts[.claude] = adHoc.hostRecord(client: .claude, url: adHocHost)
        adHoc.signatures[adHocHost.path] = .init(
            identifier: "host.ClaudeAdHoc",
            designatedRequirement: "host-req",
            cdHash: Data([8]),
            isAdHoc: true
        )
        #expect(throws: VaultAgentPeerVerificationError.hostChainMismatch) {
            try adHoc.verifier().verify(fileDescriptor: 9)
        }
    }

    @Test("CLI never accepts a stored Host tuple")
    func cliRejectsUnexpectedHostRecord() throws {
        let fixture = try PeerFixture(helper: "pastera", client: .cli)
        fixture.addProcess(pid: 90, parent: 1, url: fixture.helperURL)
        fixture.hosts[.cli] = fixture.hostRecord(client: .cli, url: fixture.makeExecutable("host"))

        #expect(throws: VaultAgentPeerVerificationError.unexpectedHostIdentity) {
            try fixture.verifier().verify(fileDescriptor: 9)
        }
    }

    @Test("peer credentials come from the socket and must match the current UID")
    func socketPeerCredentialsAreAuthoritative() throws {
        let fixture = try PeerFixture(helper: "pastera", client: .cli)
        fixture.addProcess(pid: 90, parent: 1, url: fixture.helperURL)
        fixture.credentials = .init(uid: fixture.uid + 1, pid: 90)
        #expect(throws: VaultAgentPeerVerificationError.peerCredentialMismatch) {
            try fixture.verifier().verify(fileDescriptor: 9)
        }
        fixture.credentials = .init(uid: fixture.uid, pid: -1)
        #expect(throws: VaultAgentPeerVerificationError.peerCredentialMismatch) {
            try fixture.verifier().verify(fileDescriptor: 9)
        }

        var descriptors = [Int32](repeating: -1, count: 2)
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { descriptors.forEach { if $0 >= 0 { Darwin.close($0) } } }
        let real = VaultAgentSystemPeerCredentialReader()
        let peer = try real.credentials(fileDescriptor: descriptors[0])
        #expect(peer.uid == getuid())
        #expect(peer.pid == getpid())
    }
}

private final class PeerFixture {
    let uid = getuid()
    let root: URL
    let appURL: URL
    let helperURL: URL
    var credentials: VaultAgentSocketPeerCredentials
    var processes: [pid_t: VaultAgentProcessSnapshot] = [:]
    var signatures: [String: VaultAgentCodeSignature] = [:]
    var hosts: [VaultAgentClientKind: VaultAgentInstalledHostIdentity] = [:]
    var mutateOnSecondRead: Set<pid_t> = []
    private var reads: [pid_t: Int] = [:]

    init(helper: String, client: VaultAgentClientKind) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        appURL = root.appendingPathComponent("Pastera.app")
        let helpers = appURL.appendingPathComponent("Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        helperURL = helpers.appendingPathComponent(helper)
        FileManager.default.createFile(atPath: helperURL.path, contents: Data([0x01]))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        credentials = .init(uid: uid, pid: 90)
        signatures[helperURL.path] = .init(
            identifier: Self.identifier(client),
            designatedRequirement: "helper-req",
            cdHash: client == .cli ? Data([1, 2]) : nil,
            isAdHoc: client == .cli
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func makeExecutable(_ name: String) -> URL {
        let url = root.appendingPathComponent(name + "-" + UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: Data([0x02]))
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        signatures[url.path] = .init(identifier: "host.\(name)", designatedRequirement: "host-req", cdHash: nil, isAdHoc: false)
        return url
    }

    func addProcess(pid: pid_t, parent: pid_t, url: URL) {
        var info = stat()
        lstat(url.path, &info)
        processes[pid] = .init(
            pid: pid,
            parentPID: parent,
            uid: uid,
            startSeconds: 100,
            startMicroseconds: 2,
            executableURL: url,
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino)
        )
    }

    func hostRecord(client: VaultAgentClientKind, url: URL) -> VaultAgentInstalledHostIdentity {
        let signature = signatures[url.path]!
        return .init(client: client, canonicalPath: url.path, designatedRequirement: signature.designatedRequirement, cdHash: signature.cdHash, isAdHoc: signature.isAdHoc)
    }

    func verifier() -> VaultAgentPeerVerifier {
        VaultAgentPeerVerifier(
            applicationURL: appURL,
            currentUID: uid,
            credentialReader: CredentialProbe { [unowned self] in credentials },
            processInspector: ProcessProbe { [unowned self] pid in
                reads[pid, default: 0] += 1
                guard var snapshot = processes[pid] else { throw ProbeFailure.missing }
                if mutateOnSecondRead.contains(pid), reads[pid, default: 0] > 1 { snapshot.startSeconds += 1 }
                return snapshot
            },
            codeSigningInspector: SigningProbe { [unowned self] url in
                guard let signature = signatures[url.path] else { throw ProbeFailure.missing }
                return signature
            },
            hostIdentityProvider: HostProbe { [unowned self] client in hosts[client] }
        )
    }

    private static func identifier(_ client: VaultAgentClientKind) -> String {
        switch client {
        case .codex: "com.pastera-app.PasteraCodexMCP"
        case .claude: "com.pastera-app.PasteraClaudeMCP"
        case .cli: "com.pastera-app.pastera"
        }
    }
}

private enum ProbeFailure: Error { case missing }
private struct CredentialProbe: VaultAgentSocketPeerCredentialReading {
    let read: () throws -> VaultAgentSocketPeerCredentials

    init(_ read: @escaping () throws -> VaultAgentSocketPeerCredentials) { self.read = read }

    func credentials(fileDescriptor _: Int32) throws -> VaultAgentSocketPeerCredentials { try read() }
}
private struct ProcessProbe: VaultAgentProcessInspecting {
    let read: (pid_t) throws -> VaultAgentProcessSnapshot

    init(_ read: @escaping (pid_t) throws -> VaultAgentProcessSnapshot) { self.read = read }

    func snapshot(pid: pid_t) throws -> VaultAgentProcessSnapshot { try read(pid) }
}
private struct SigningProbe: VaultAgentCodeSigningInspecting {
    let inspect: (URL) throws -> VaultAgentCodeSignature

    init(_ inspect: @escaping (URL) throws -> VaultAgentCodeSignature) { self.inspect = inspect }

    func inspect(executableURL: URL) throws -> VaultAgentCodeSignature { try inspect(executableURL) }
}
private struct HostProbe: VaultAgentHostIdentityProviding {
    let load: (VaultAgentClientKind) -> VaultAgentInstalledHostIdentity?

    init(_ load: @escaping (VaultAgentClientKind) -> VaultAgentInstalledHostIdentity?) { self.load = load }

    func installedHostIdentity(for client: VaultAgentClientKind) -> VaultAgentInstalledHostIdentity? { load(client) }
}
