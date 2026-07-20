import Foundation
import Darwin
import ApplicationServices
import PasteraAgentProtocol
import Testing
@testable import Pastera

// Task 5 keeps end-to-end Unix socket fixtures beside the broker regression suite for auditability.
// swiftlint:disable file_length

@Suite("Vault agent broker", .serialized)
struct VaultAgentBrokerTests {
    private let clientKey = Data((0..<32).map(UInt8.init))
    private let serverKey = Data((32..<64).map(UInt8.init))
    private let clientNonce = Data(repeating: 0x11, count: 32)
    private let serverNonce = Data(repeating: 0x22, count: 32)
    private let connectionID = UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!

    @Test("fixed X25519 HKDF and AAD transcript produces a stable frame")
    func fixedTranscriptVector() throws {
        let pair = try makePair()
        let frame = try pair.client.seal(Data("request".utf8))
        #expect(frame.connectionID == connectionID)
        #expect(frame.sequence == 1)
        #expect(frame.ciphertext.hex == "01000000000000000000000155b45c6f684d95a990118e4a17d1c1cb306ba474090092")
        #expect(try pair.server.open(frame) == Data("request".utf8))
    }

    @Test("directions are independent and reflected frames fail authentication")
    func directionIsAuthenticated() throws {
        let pair = try makePair()
        let request = try pair.client.seal(Data("request".utf8))
        #expect(throws: VaultAgentProtocolError.authenticationFailed) {
            try pair.client.open(request)
        }
        #expect(try pair.server.open(request) == Data("request".utf8))
        let response = try pair.server.seal(Data("response".utf8))
        #expect(try pair.client.open(response) == Data("response".utf8))
    }

    @Test("connection sequence replay and ordering are rejected before authentication")
    func sequenceAndConnectionAreBound() throws {
        let pair = try makePair()
        let first = try pair.client.seal(Data("one".utf8))
        var wrongConnection = first
        wrongConnection = .init(connectionID: UUID(), sequence: first.sequence, ciphertext: first.ciphertext)
        #expect(throws: VaultAgentProtocolError.connectionMismatch) { try pair.server.open(wrongConnection) }
        let high = VaultAgentEncryptedFrame(connectionID: connectionID, sequence: 2, ciphertext: first.ciphertext)
        #expect(throws: VaultAgentProtocolError.outOfOrderFrame) { try pair.server.open(high) }
        #expect(try pair.server.open(first) == Data("one".utf8))
        #expect(throws: VaultAgentProtocolError.replayedFrame) { try pair.server.open(first) }
    }

    @Test("failed authentication does not advance the receive sequence")
    func authenticationFailureDoesNotAdvance() throws {
        let pair = try makePair()
        let frame = try pair.client.seal(Data("secret".utf8))
        var bytes = frame.ciphertext
        bytes[bytes.startIndex] ^= 0x01
        let tampered = VaultAgentEncryptedFrame(connectionID: connectionID, sequence: 1, ciphertext: bytes)
        #expect(throws: VaultAgentProtocolError.authenticationFailed) { try pair.server.open(tampered) }
        #expect(try pair.server.open(frame) == Data("secret".utf8))
    }

    @Test("handshake version and exact key material lengths are mandatory")
    func handshakeValidation() throws {
        let client = try VaultAgentClientHandshakeContext(privateKey: clientKey, nonce: clientNonce)
        var hello = client.hello
        hello = .init(protocolVersion: 2, publicKey: hello.publicKey, nonce: hello.nonce)
        let server = try VaultAgentServerHandshakeContext(privateKey: serverKey, nonce: serverNonce, connectionID: connectionID)
        #expect(throws: VaultAgentProtocolError.protocolMismatch) { try server.accept(hello) }
    }

    @Test("UInt64 maximum is an exhausted terminal sequence")
    func sequenceExhaustion() throws {
        let pair = try VaultAgentSecureChannel.makeTestPair(
            clientPrivateKey: clientKey,
            serverPrivateKey: serverKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID,
            initialSequence: UInt64.max
        )
        #expect(throws: VaultAgentProtocolError.sequenceExhausted) { try pair.client.seal(Data()) }
    }

    @Test("write readiness is rebuilt only after a draining source finishes cancellation")
    func writeSourceLifecycleRebuildsAfterCancellation() {
        var lifecycle = VaultAgentWriteSourceLifecycle()

        let shouldInstallInitially = lifecycle.noteWouldBlock()
        #expect(shouldInstallInitially)
        lifecycle.didInstallSource()
        let didBeginFirstCancellation = lifecycle.beginDrainCancellation()
        let installedDuringCancellation = lifecycle.noteWouldBlock()
        let shouldRebuild = lifecycle.cancellationCompleted(hasPendingOutput: true)
        #expect(didBeginFirstCancellation)
        #expect(!installedDuringCancellation)
        #expect(shouldRebuild)
        lifecycle.didInstallSource()
        let didBeginSecondCancellation = lifecycle.beginDrainCancellation()
        let rebuiltWithoutPendingOutput = lifecycle.cancellationCompleted(hasPendingOutput: false)
        #expect(didBeginSecondCancellation)
        #expect(!rebuiltWithoutPendingOutput)
    }

    private func makePair() throws -> VaultAgentSecureChannel.Pair {
        try VaultAgentSecureChannel.makeTestPair(
            clientPrivateKey: clientKey,
            serverPrivateKey: serverKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID
        )
    }
}

private extension VaultAgentBrokerTests {
    @Test("decoded broker operations preserve envelope fields and renew only successful sensitive use")
    func dispatcherAndRenewalMatrix() async throws {
        let fixture = try RuntimeFixture(client: .codex)
        let original = try #require(fixture.grantStore.grants[.codex])

        let status = try await fixture.call(.status)
        #expect(status.connectionID == fixture.connectionID)
        #expect(status.sequence == 1)
        #expect(status.requestID == fixture.requestID)
        #expect(status.body == .success(.status(.init(
            client: .codex,
            installed: true,
            authorized: true,
            vaultReady: true,
            idleExpiresAt: original.idleExpiresAt,
            hardExpiresAt: original.hardExpiresAt,
            protocolVersion: 1
        ))))
        #expect(fixture.vault.ensureReadyCount == 0)

        fixture.advanceNow(by: 60)
        _ = try await fixture.call(.search(.init(query: "mail", folderID: nil, limit: 20, cursor: nil)))
        _ = try await fixture.call(.get(entryID: fixture.entryID))
        let ticketResponse = try await fixture.call(.prepareExec(
            entryID: fixture.entryID,
            field: .password,
            mode: .stdin
        ))
        #expect(fixture.grantStore.grants[.codex]?.idleExpiresAt == original.idleExpiresAt)

        _ = try await fixture.call(.paste(entryID: fixture.entryID, field: .password))
        let afterPaste = try #require(fixture.grantStore.grants[.codex])
        #expect(afterPaste.idleExpiresAt > original.idleExpiresAt)

        let token: String
        if case let .success(.ticket(ticket)) = ticketResponse.body {
            token = ticket.token
        } else {
            Issue.record("prepare_exec must return a ticket")
            return
        }
        fixture.advanceNow(by: 1)
        let deliveryResponse = try await fixture.call(.redeemTicket(token: token, mode: .stdin))
        #expect(fixture.grantStore.grants[.codex]?.idleExpiresAt == afterPaste.idleExpiresAt)
        let receiptID: UUID
        if case let .success(.secretDelivery(delivery)) = deliveryResponse.body {
            receiptID = delivery.receiptID
            #expect(delivery.bytes == Data("secret".utf8))
        } else {
            Issue.record("redeem_ticket must return one local secret")
            return
        }
        _ = try await fixture.call(.completeTicket(receiptID: receiptID))
        #expect(try #require(fixture.grantStore.grants[.codex]).idleExpiresAt > afterPaste.idleExpiresAt)
        #expect(fixture.audit.records.count == 7)
        #expect(fixture.audit.records.allSatisfy { $0.client == .codex })
    }

    @Test("authorization is checked before rate limiting and vault readiness")
    func authorizationPrecedesVaultWork() async throws {
        let fixture = try RuntimeFixture(client: .claude, authorized: false)
        let response = try await fixture.call(.search(.init(query: nil, folderID: nil, limit: 20, cursor: nil)))

        #expect(response.body.failureCode == .authorizationRequired)
        #expect(fixture.vault.ensureReadyCount == 0)
        #expect(fixture.vault.metadataCount == 0)
        #expect(fixture.audit.records.count == 1)
    }

    @Test("a decoded operation audits and completes exactly once")
    func decodedOperationFinishesOnce() throws {
        let fixture = try RuntimeFixture(client: .codex)
        fixture.vault.metadataCallbackCount = 2
        let request = try fixture.encodedRequest(.search(.init(
            query: nil,
            folderID: nil,
            limit: 20,
            cursor: nil
        )))
        let completionCount = RuntimeLockedInt()
        let completed = DispatchSemaphore(value: 0)

        fixture.runtime.handle(identity: fixture.identity, request: request) { _ in
            completionCount.increment()
            completed.signal()
        }

        #expect(completed.wait(timeout: .now() + 1) == .success)
        Thread.sleep(forTimeInterval: 0.05)
        #expect(completionCount.value == 1)
        #expect(fixture.audit.records.count == 1)
    }

    @Test("an already expired grant clears Agent secret state before authorization fails")
    func expiredGrantTriggersInitialCleanup() async throws {
        let fixture = try RuntimeFixture(client: .codex)
        let ticket = try fixture.issueTicket()
        fixture.advanceNow(by: VaultAgentAuthorizationPolicy.idleLifetime)

        let response = try await fixture.call(.search(.init(
            query: nil,
            folderID: nil,
            limit: 20,
            cursor: nil
        )))

        #expect(response.body.failureCode == .grantExpired)
        #expect(fixture.vault.automationCleanupCount == 1)
        #expect(throws: VaultAgentTicketError.used) {
            try fixture.ticketStore.redeem(
                token: ticket.token,
                client: .codex,
                mode: .stdin,
                now: fixture.currentDate
            )
        }
    }

    @Test("protocol mismatch and malformed requests use stable broker errors")
    func envelopeErrorsAreStable() async throws {
        let fixture = try RuntimeFixture(client: .cli)
        let mismatch = try await fixture.call(.status, protocolVersion: 2)
        #expect(mismatch.body.failureCode == .protocolMismatch)

        let malformed = await fixture.handle(Data("{not-json".utf8))
        let decoded = try JSONDecoder().decode(VaultAgentResponseEnvelope.self, from: malformed)
        #expect(decoded.body.failureCode == .invalidRequest)
        #expect(String(data: malformed, encoding: .utf8)?.contains("not-json") == false)
    }

    @Test("cursor binds query folder snapshot key and stable metadata ordering")
    func cursorAuthenticationAndPagination() async throws {
        let fixture = try RuntimeFixture(client: .codex)
        let older = fixture.vault.entries[0]
        fixture.vault.entries = [
            fixture.makeEntry(idSuffix: 9, title: "Mail C", updatedAt: 30),
            fixture.makeEntry(idSuffix: 2, title: "Mail B", updatedAt: 20),
            fixture.makeEntry(idSuffix: 1, title: "Mail A", updatedAt: 20),
            older
        ]
        let first = try await fixture.search(query: "mail", folderID: fixture.folderID, limit: 2)
        #expect(first.entries.map(\.title) == ["Mail C", "Mail A"])
        let cursor = try #require(first.nextCursor)
        let second = try await fixture.search(
            query: "mail",
            folderID: fixture.folderID,
            limit: 2,
            cursor: cursor
        )
        #expect(second.entries.map(\.title) == ["Mail B", "Mail"])

        var tampered = cursor
        let replacement = tampered.last == "A" ? "B" : "A"
        tampered.replaceSubrange(tampered.index(before: tampered.endIndex)..., with: replacement)
        #expect(try await fixture.call(.search(.init(
            query: "mail", folderID: fixture.folderID, limit: 2, cursor: tampered
        ))).body.failureCode == .invalidRequest)
        #expect(try await fixture.call(.search(.init(
            query: "other", folderID: fixture.folderID, limit: 2, cursor: cursor
        ))).body.failureCode == .invalidRequest)
        #expect(try await fixture.call(.search(.init(
            query: "mail", folderID: nil, limit: 2, cursor: cursor
        ))).body.failureCode == .invalidRequest)

        fixture.vault.entries[0].title = "Mail changed"
        #expect(try await fixture.call(.search(.init(
            query: "mail", folderID: fixture.folderID, limit: 2, cursor: cursor
        ))).body.failureCode == .invalidRequest)

        let restarted = try RuntimeFixture(client: .codex, cursorKey: Data(repeating: 0x56, count: 32))
        restarted.vault.entries = fixture.vault.entries
        #expect(try await restarted.call(.search(.init(
            query: "mail", folderID: restarted.folderID, limit: 2, cursor: cursor
        ))).body.failureCode == .invalidRequest)
    }

    @Test("search dynamically shrinks a page without truncating the 32 KiB response")
    func searchResponseShrinksToWireLimit() async throws {
        let fixture = try RuntimeFixture(client: .codex)
        fixture.vault.entries = (0..<50).map { index in
            fixture.makeEntry(
                idSuffix: index + 10,
                title: String(repeating: "t", count: 2_000),
                website: String(repeating: "w", count: 2_000),
                username: String(repeating: "u", count: 2_000),
                updatedAt: TimeInterval(100 - index)
            )
        }

        let response = try await fixture.call(.search(.init(query: nil, folderID: nil, limit: 50, cursor: nil)))
        let page = try #require(response.body.searchPage)
        #expect(!page.entries.isEmpty)
        #expect(page.entries.count < 50)
        #expect(page.nextCursor != nil)
        #expect(try JSONEncoder().encode(response).count <= VaultAgentLimits.maximumResponseBytes)
    }

    @Test("one oversized metadata item fails closed without losing request identifiers")
    func singleOversizedSearchResultFailsClosed() async throws {
        let fixture = try RuntimeFixture(client: .codex)
        fixture.vault.entries = [fixture.makeEntry(
            idSuffix: 99,
            title: String(repeating: "t", count: VaultAgentLimits.maximumResponseBytes),
            website: "",
            username: "",
            updatedAt: 1
        )]

        let response = try await fixture.call(.search(.init(
            query: nil,
            folderID: nil,
            limit: 20,
            cursor: nil
        )))

        #expect(response.connectionID == fixture.connectionID)
        #expect(response.sequence == 1)
        #expect(response.requestID == fixture.requestID)
        #expect(response.body.failureCode == .invalidRequest)
        #expect(try JSONEncoder().encode(response).count <= VaultAgentLimits.maximumResponseBytes)
    }

    @Test("grant transition to zero atomically clears automation unlock and every ticket")
    func zeroGrantLifecycleCleanup() async throws {
        let fixture = try RuntimeFixture(client: .codex)
        let firstTicket = try fixture.issueTicket()

        _ = try await fixture.call(.status)
        fixture.vault.agentVaultReady = false
        _ = try await fixture.call(.status)
        #expect(fixture.vault.automationCleanupCount == 0)
        #expect(try fixture.ticketStore.redeem(
            token: firstTicket.token,
            client: .codex,
            mode: .stdin,
            now: fixture.currentDate
        ).binding.entryID == fixture.entryID)

        let secondTicket = try fixture.issueTicket()
        try fixture.authorizationPolicy.revoke(.codex, at: fixture.currentDate)
        try fixture.runtime.authorizationStateDidChange()

        #expect(fixture.vault.automationCleanupCount == 1)
        #expect(fixture.vault.cleanupRanOnExecutor)
        #expect(throws: VaultAgentTicketError.used) {
            try fixture.ticketStore.redeem(
                token: secondTicket.token,
                client: .codex,
                mode: .stdin,
                now: fixture.currentDate
            )
        }

        try fixture.runtime.authorizationStateDidChange()
        _ = try await fixture.call(.status)
        #expect(fixture.vault.automationCleanupCount == 1)
    }

    @Test("concurrent Codex and Claude searches stay on the shared vault executor")
    func concurrentClientsShareVaultExecutor() async throws {
        let fixture = try RuntimeFixture(client: .codex)
        let claude = try fixture.authorizeAdditionalClient(.claude)
        fixture.vault.observeConcurrentMetadata = true

        async let codexResponse = fixture.call(
            .search(.init(query: nil, folderID: nil, limit: 20, cursor: nil))
        )
        async let claudeResponse = fixture.call(
            .search(.init(query: nil, folderID: nil, limit: 20, cursor: nil)),
            identity: claude
        )
        let responses = try await [codexResponse, claudeResponse]

        #expect(responses.allSatisfy { $0.body.failureCode == nil })
        #expect(fixture.vault.maximumConcurrentMetadata == 1)
        #expect(fixture.vault.metadataRanOnExecutor)
    }

    @Test("production ticket commands and cursor entropy use fixed local helpers")
    func productionRuntimeMaterial() throws {
        let applicationURL = URL(fileURLWithPath: "/Applications/Pastera.app")
        let token = "ticket-token"

        #expect(VaultAgentRuntime.helperCommand(
            applicationURL: applicationURL,
            client: .codex,
            mode: .stdin,
            token: token
        ) == [
            "/Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP",
            "exec", "--ticket", token, "--stdin", "--"
        ])
        #expect(VaultAgentRuntime.helperCommand(
            applicationURL: applicationURL,
            client: .claude,
            mode: .fileDescriptor,
            token: token
        ) == [
            "/Applications/Pastera.app/Contents/Helpers/PasteraClaudeMCP",
            "exec", "--ticket", token, "--fd", "3", "--"
        ])
        #expect(VaultAgentRuntime.helperCommand(
            applicationURL: applicationURL,
            client: .cli,
            mode: .stdin,
            token: token
        ).first == "/Applications/Pastera.app/Contents/Helpers/pastera")
        let firstKey = try VaultAgentRuntime.secureRandomCursorKey()
        let secondKey = try VaultAgentRuntime.secureRandomCursorKey()
        #expect(firstKey.count == 32)
        #expect(secondKey.count == 32)
        #expect(firstKey != secondKey)
    }

    @Test("paste tracker excludes agent paths and revalidates process signature bundle and focus")
    func pasteTargetRevalidation() throws {
        let harness = PasteTargetHarness()
        let tracker = harness.makeTracker()
        tracker.start()
        defer { tracker.stop() }

        harness.activate(pid: 41, bundleID: "com.pastera.helper", path: harness.helperURL)
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }
        harness.activate(pid: 40, bundleID: "com.openai.codex", path: harness.hostURL)
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }

        harness.activate(pid: 42, bundleID: "com.example.editor", path: harness.targetURL)
        let refreshedFocus = AXUIElementCreateApplication(142)
        harness.focusedElements[42] = refreshedFocus
        let target = try tracker.resolve()
        #expect(target.processIdentifier == 42)
        #expect(target.bundleIdentifier == "com.example.editor")
        #expect(target.focusedElement.map { CFEqual($0, refreshedFocus) } == true)

        harness.applications[42]?.bundleIdentifier = "com.example.changed"
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }
        harness.activate(pid: 42, bundleID: "com.example.editor", path: harness.targetURL)
        harness.snapshots[42]?.startSeconds += 1
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }
        harness.activate(pid: 42, bundleID: "com.example.editor", path: harness.targetURL)
        harness.signatures[harness.targetURL.path] = .init(
            identifier: "changed",
            designatedRequirement: "identifier changed",
            cdHash: Data([9]),
            isAdHoc: true
        )
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }
        harness.signatures[harness.targetURL.path] = harness.signature
        harness.activate(pid: 42, bundleID: "com.example.editor", path: harness.targetURL)
        harness.focusedElements[42] = nil
        #expect(try tracker.resolve().focusedElement != nil)
        harness.activate(pid: 43, bundleID: "com.example.no-focus", path: harness.targetURL, focus: nil)
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }
        harness.applications[43]?.isTerminated = true
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }
    }

    @Test("paste tracker start stop owns exactly one notification observer")
    func pasteTargetObserverLifecycle() throws {
        let harness = PasteTargetHarness()
        let tracker = harness.makeTracker()
        tracker.start()
        tracker.start()
        harness.activate(pid: 42, bundleID: "com.example.first", path: harness.targetURL)
        #expect(try tracker.resolve().processIdentifier == 42)

        tracker.stop()
        harness.activate(pid: 44, bundleID: "com.example.second", path: harness.secondTargetURL)
        #expect(throws: VaultAgentPasteTargetError.self) { try tracker.resolve() }
    }

    @Test("server creates private directory and socket and echoes fragmented encrypted frames")
    func privateSocketAndFragmentedRoundTrip() throws {
        let shortRoot = FileManager.default.temporaryDirectory.appendingPathComponent("pva-\(getpid())")
        let fixture = try SocketFixture(root: shortRoot, nestedAgentDirectory: true)
        let server = fixture.makeServer(handler: EchoSocketHandler())
        try server.start()
        defer { server.stop() }

        #expect(fixture.mode(fixture.v1URL) == 0o700)
        #expect(fixture.mode(fixture.v1URL.deletingLastPathComponent()) == 0o700)
        #expect(fixture.mode(fixture.socketURL) == 0o600)
        let client = try fixture.connectAndHandshake(fragmentSize: 1)
        defer { Darwin.close(client.fileDescriptor) }
        let plaintext = Data("bounded echo".utf8)
        let encrypted = try client.channel.seal(plaintext)
        try fixture.writeFrame(try JSONEncoder().encode(encrypted), fileDescriptor: client.fileDescriptor, fragmentSize: 2)
        let response = try fixture.readFrame(fileDescriptor: client.fileDescriptor)
        #expect(try client.channel.open(JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: response)) == plaintext)

        var receiveBufferBytes: Int32 = 1_024
        setsockopt(
            client.fileDescriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBufferBytes,
            socklen_t(MemoryLayout<Int32>.size)
        )
        let large = Data(repeating: 0x41, count: 16 * 1_024)
        try fixture.writeFrame(
            try JSONEncoder().encode(client.channel.seal(large)),
            fileDescriptor: client.fileDescriptor,
            fragmentSize: 113
        )
        let largeResponse = try fixture.readFrame(fileDescriptor: client.fileDescriptor)
        #expect(try client.channel.open(JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: largeResponse)) == large)

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: fixture.socketURL.path))
    }

    @Test("existing files symlinks and active sockets are never removed")
    func conflictsArePreserved() throws {
        let plain = try SocketFixture()
        FileManager.default.createFile(atPath: plain.socketURL.path, contents: Data([1]))
        #expect(throws: VaultAgentSocketServerError.socketPathConflict) { try plain.makeServer().start() }
        #expect(FileManager.default.fileExists(atPath: plain.socketURL.path))

        let linked = try SocketFixture()
        let target = linked.root.appendingPathComponent("target")
        FileManager.default.createFile(atPath: target.path, contents: Data([2]))
        try FileManager.default.createSymbolicLink(at: linked.socketURL, withDestinationURL: target)
        #expect(throws: VaultAgentSocketServerError.socketPathConflict) { try linked.makeServer().start() }
        #expect((try FileManager.default.destinationOfSymbolicLink(atPath: linked.socketURL.path)).contains("target"))

        let active = try SocketFixture()
        let listener = try active.bindRawListener()
        defer { Darwin.close(listener) }
        #expect(throws: VaultAgentSocketServerError.socketPathConflict) { try active.makeServer().start() }

        let directoryLink = try SocketFixture()
        let realDirectory = directoryLink.root.appendingPathComponent("real-v1")
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        try FileManager.default.removeItem(at: directoryLink.v1URL)
        try FileManager.default.createSymbolicLink(at: directoryLink.v1URL, withDestinationURL: realDirectory)
        #expect(throws: VaultAgentSocketServerError.directoryConflict) {
            try directoryLink.makeServer().start()
        }
    }

    @Test("a stale owned socket is replaced but an overlong path fails closed")
    func staleAndLongPaths() throws {
        let stale = try SocketFixture()
        let listener = try stale.bindRawListener()
        Darwin.close(listener)
        let server = stale.makeServer()
        try server.start()
        defer { server.stop() }
        #expect(stale.mode(stale.socketURL) == 0o600)

        let longRoot = FileManager.default.temporaryDirectory.appendingPathComponent(String(repeating: "x", count: 120))
        let long = try SocketFixture(root: longRoot)
        #expect(throws: VaultAgentSocketServerError.pathTooLong) { try long.makeServer().start() }
    }

    @Test("ninth connection and a second in-flight request are closed")
    func connectionAndInflightBounds() throws {
        let fixture = try SocketFixture()
        let delayed = DelayedSocketHandler()
        let connectionProbe = SocketConnectionProbe()
        let server = VaultAgentSocketServer(
            directoryURL: fixture.v1URL,
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: delayed,
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.bounds"),
            lifecycleProbe: .init(
                sourceCreated: connectionProbe.sourceCreated,
                descriptorClosed: connectionProbe.descriptorClosed
            )
        )
        try server.start()
        defer { server.stop() }

        var descriptors: [Int32] = []
        defer { descriptors.forEach { Darwin.close($0) } }
        for _ in 0..<8 { descriptors.append(try fixture.connectOnly()) }
        let ninth = try fixture.connectOnly()
        defer { Darwin.close(ninth) }
        #expect(fixture.waitForEOF(fileDescriptor: ninth))

        descriptors.forEach { Darwin.close($0) }
        descriptors.removeAll()
        #expect(connectionProbe.waitForNoConnections())
        let client = try fixture.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }
        let first = try client.channel.seal(Data("first".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(first), fileDescriptor: client.fileDescriptor)
        #expect(delayed.started.wait(timeout: .now() + 2) == .success)
        let second = try client.channel.seal(Data("second".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(second), fileDescriptor: client.fileDescriptor)
        #expect(fixture.waitForEOF(fileDescriptor: client.fileDescriptor))
        delayed.complete(.success(Data("late".utf8)))
    }

    @Test("idle activity invalidates an old deadline and EOF cleanup ignores late completion")
    func idleAndLateCompletion() throws {
        let fixture = try SocketFixture()
        let delayed = DelayedSocketHandler()
        let server = fixture.makeServer(handler: delayed, idleTimeout: 0.15)
        try server.start()
        defer { server.stop() }

        let client = try fixture.connectAndHandshake()
        let request = try client.channel.seal(Data("pending".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(request), fileDescriptor: client.fileDescriptor)
        #expect(delayed.started.wait(timeout: .now() + 1) == .success)
        usleep(80_000)
        var byte: UInt8 = 0
        #expect(Darwin.write(client.fileDescriptor, &byte, 1) == 1)
        usleep(90_000)
        #expect(!fixture.isEOF(fileDescriptor: client.fileDescriptor))
        Darwin.close(client.fileDescriptor)
        delayed.complete(.success(Data("late".utf8)))
        usleep(30_000)
    }

    @Test("oversized and malformed length prefixes close without reaching the handler")
    func malformedFramesClose() throws {
        let fixture = try SocketFixture()
        let handler = CountingSocketHandler()
        let server = fixture.makeServer(handler: handler)
        try server.start()
        defer { server.stop() }
        let fileDescriptor = try fixture.connectOnly()
        defer { Darwin.close(fileDescriptor) }
        var oversized = UInt32(VaultAgentLimits.maximumFrameBytes).bigEndian
        #expect(withUnsafeBytes(of: &oversized) { Darwin.write(fileDescriptor, $0.baseAddress, $0.count) } == 4)
        #expect(fixture.waitForEOF(fileDescriptor: fileDescriptor))
        #expect(!handler.wasCalled)
    }

    @Test("peer rejection happens before handshake decoding and duplicate completion is one-shot")
    func verificationOrderAndDuplicateCompletion() throws {
        let rejected = try SocketFixture()
        let count = CountingSocketHandler()
        let rejectingServer = VaultAgentSocketServer(
            directoryURL: rejected.v1URL,
            peerVerifier: RejectingPeerVerifier(),
            handler: count,
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.reject")
        )
        try rejectingServer.start()
        defer { rejectingServer.stop() }
        let rejectedFD = try rejected.connectOnly()
        defer { Darwin.close(rejectedFD) }
        let untrustedJSON = Data("{\"protocolVersion\":1}".utf8)
        do {
            try rejected.writeFrame(untrustedJSON, fileDescriptor: rejectedFD)
        } catch SocketTestError.write {
            // Peer verification may close before the untrusted client finishes writing.
        }
        #expect(rejected.waitForEOF(fileDescriptor: rejectedFD))
        #expect(!count.wasCalled)

        let duplicate = try SocketFixture()
        let duplicateServer = duplicate.makeServer(handler: DuplicateSocketHandler())
        try duplicateServer.start()
        defer { duplicateServer.stop() }
        let client = try duplicate.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }
        let request = try client.channel.seal(Data("once".utf8))
        try duplicate.writeFrame(try JSONEncoder().encode(request), fileDescriptor: client.fileDescriptor)
        let first = try duplicate.readFrame(fileDescriptor: client.fileDescriptor)
        #expect(try client.channel.open(JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: first)) == Data("once".utf8))
        usleep(20_000)
        var byte: UInt8 = 0
        #expect(Darwin.recv(client.fileDescriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT) < 0)
        #expect(errno == EAGAIN || errno == EWOULDBLOCK)
    }

    @Test("plaintext handler responses over 32 KiB close before encryption")
    func oversizedPlaintextResponseCloses() throws {
        let fixture = try SocketFixture()
        let response = Data(repeating: 0x41, count: VaultAgentLimits.maximumResponseBytes + 1)
        let server = fixture.makeServer(handler: FixedResponseSocketHandler(response: response))
        try server.start()
        defer { server.stop() }

        let client = try fixture.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }
        let request = try client.channel.seal(Data("request".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(request), fileDescriptor: client.fileDescriptor)
        #expect(fixture.waitForEOF(fileDescriptor: client.fileDescriptor))
    }

    @Test("a failed Application Support lookup never falls back to a temporary directory")
    func defaultDirectoryLookupFailsClosed() {
        let server = VaultAgentSocketServer(
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: EchoSocketHandler(),
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.default-directory"),
            applicationSupportURLProvider: { throw SocketTestError.directory }
        )

        #expect(throws: VaultAgentSocketServerError.unavailable) {
            try server.start()
        }
    }

    @Test("64 KiB of one-byte activity keeps exactly one idle timer per connection")
    func idleTimerCountIsBounded() throws {
        let fixture = try SocketFixture()
        let timerCount = LockedCounter()
        let server = fixture.makeServer(idleTimerFactory: { queue in
            timerCount.increment()
            return DispatchSource.makeTimerSource(queue: queue)
        })
        try server.start()
        defer { server.stop() }

        let fileDescriptor = try fixture.connectOnly()
        defer { Darwin.close(fileDescriptor) }
        let payload = Data(repeating: 0x7b, count: VaultAgentLimits.maximumFrameBytes - 4)
        let frame = try VaultAgentFrameCodec.frame(payload: payload)
        #expect(frame.count == 65_536)
        for value in frame {
            var byte = value
            guard Darwin.write(fileDescriptor, &byte, 1) == 1 else {
                throw SocketTestError.write
            }
        }
        #expect(timerCount.value == 1)
    }

    @Test("replacing the validated v1 directory fails before touching the replacement")
    func directoryReplacementFailsClosed() throws {
        let fixture = try SocketFixture()
        let originalDirectory = fixture.root.appendingPathComponent("held-v1")
        let sentinel = fixture.v1URL.appendingPathComponent("sentinel")
        let server = VaultAgentSocketServer(
            directoryURL: fixture.v1URL,
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: EchoSocketHandler(),
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.directory-replacement"),
            directoryIdentityValidationHook: {
                try FileManager.default.moveItem(at: fixture.v1URL, to: originalDirectory)
                try FileManager.default.createDirectory(at: fixture.v1URL, withIntermediateDirectories: false)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.v1URL.path)
                FileManager.default.createFile(atPath: sentinel.path, contents: Data([0x5a]))
            }
        )

        #expect(throws: VaultAgentSocketServerError.directoryConflict) {
            try server.start()
        }
        #expect(fixture.mode(fixture.v1URL) == 0o755)
        #expect((try Data(contentsOf: sentinel)) == Data([0x5a]))
        #expect(!FileManager.default.fileExists(atPath: fixture.socketURL.path))
        #expect(!FileManager.default.fileExists(atPath: originalDirectory.appendingPathComponent("broker.sock").path))
    }

    @Test("source cancellation completes before managed descriptors close and are reused")
    func descriptorCloseWaitsForSourceCancellation() throws {
        let fixture = try SocketFixture()
        let recorder = SocketLifecycleRecorder()
        let server = VaultAgentSocketServer(
            directoryURL: fixture.v1URL,
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: EchoSocketHandler(),
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.lifecycle"),
            lifecycleProbe: .init(
                sourceCreated: recorder.sourceCreated,
                sourceCancellationCompleted: recorder.sourceCancellationCompleted,
                descriptorClosed: recorder.descriptorClosed
            )
        )
        try server.start()
        let client = try fixture.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }

        let stopped = DispatchSemaphore(value: 0)
        server.stop { stopped.signal() }
        #expect(stopped.wait(timeout: .now() + 2) == .success)
        #expect(recorder.managedDescriptorCount == 2)
        #expect(recorder.allDescriptorsClosedAfterCancellation)
        #expect(recorder.allClosedDescriptorsImmediatelyReusable)
        #expect(!FileManager.default.fileExists(atPath: fixture.socketURL.path))
        recorder.closeReusedDescriptors()

        try server.start()
        let restarted = DispatchSemaphore(value: 0)
        server.stop { restarted.signal() }
        #expect(restarted.wait(timeout: .now() + 2) == .success)
    }

    @Test("connection capacity includes descriptors awaiting source cancellation")
    func connectionCapacityIncludesClosingResources() throws {
        let fixture = try SocketFixture()
        let recorder = SocketLifecycleRecorder()
        let handler = CancellationWindowChurnHandler(fixture: fixture)
        let serverQueue = DispatchQueue(label: "VaultAgentSocketServerTests.capacity-closing")
        let server = VaultAgentSocketServer(
            directoryURL: fixture.v1URL,
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: handler,
            queue: serverQueue,
            lifecycleProbe: .init(
                sourceCreated: recorder.sourceCreated,
                sourceCancellationCompleted: recorder.sourceCancellationCompleted,
                descriptorClosed: recorder.descriptorClosed
            )
        )
        try server.start()
        var clients: [(fileDescriptor: Int32, channel: VaultAgentSecureChannel)] = []
        defer {
            clients.forEach { Darwin.close($0.fileDescriptor) }
            handler.closeReplacements()
            let stopped = DispatchSemaphore(value: 0)
            server.stop { stopped.signal() }
            _ = stopped.wait(timeout: .now() + 2)
            recorder.closeReusedDescriptors()
        }
        for _ in 0..<VaultAgentSocketServer.maximumConnections {
            clients.append(try fixture.connectAndHandshake())
        }

        let request = try clients[0].channel.seal(Data("close-and-replace".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(request), fileDescriptor: clients[0].fileDescriptor)
        #expect(handler.replacementsReady.wait(timeout: .now() + 2) == .success)
        #expect(handler.replacementCount == 2)
        serverQueue.sync {}

        #expect(recorder.peakConnectionDescriptorCount <= VaultAgentSocketServer.maximumConnections)
    }
}

private final class SocketFixture {
    static let identity = VaultAgentPeerIdentity(
        client: .cli,
        helperRequirement: "helper",
        helperCDHash: Data([1]),
        helperIsAdHoc: true,
        helperPath: "/Pastera.app/Contents/Helpers/pastera",
        hostRequirement: nil,
        hostCDHash: nil,
        hostIsAdHoc: nil,
        hostPath: nil
    )

    let root: URL
    let v1URL: URL
    var socketURL: URL { v1URL.appendingPathComponent("broker.sock") }

    init(root: URL? = nil, nestedAgentDirectory: Bool = false) throws {
        self.root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        v1URL = nestedAgentDirectory
            ? self.root.appendingPathComponent("Agent/v1")
            : self.root.appendingPathComponent("v1")
        try FileManager.default.createDirectory(at: v1URL, withIntermediateDirectories: true)
        if nestedAgentDirectory {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: v1URL.deletingLastPathComponent().path
            )
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func makeServer(
        handler: VaultAgentSocketRequestHandling = EchoSocketHandler(),
        idleTimeout: TimeInterval = 30,
        idleTimerFactory: @escaping (DispatchQueue) -> DispatchSourceTimer = {
            DispatchSource.makeTimerSource(queue: $0)
        }
    ) -> VaultAgentSocketServer {
        VaultAgentSocketServer(
            directoryURL: v1URL,
            peerVerifier: FixedPeerVerifier(identity: Self.identity),
            handler: handler,
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.\(UUID())"),
            idleTimeout: idleTimeout,
            idleTimerFactory: idleTimerFactory
        )
    }

    func mode(_ url: URL) -> mode_t {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        return info.st_mode & 0o777
    }

    func bindRawListener() throws -> Int32 {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw SocketTestError.socket }
        do {
            var address = try unixAddress(socketURL)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0, listen(fileDescriptor, 1) == 0 else { throw SocketTestError.bind }
            return fileDescriptor
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    func connectOnly() throws -> Int32 {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw SocketTestError.socket }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        do {
            var address = try unixAddress(socketURL)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw SocketTestError.connect }
            return fileDescriptor
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    func connectAndHandshake(fragmentSize: Int = 7) throws -> (fileDescriptor: Int32, channel: VaultAgentSecureChannel) {
        let fileDescriptor = try connectOnly()
        do {
            let context = try VaultAgentClientHandshakeContext(
                privateKey: Data((0..<32).map(UInt8.init)),
                nonce: Data(repeating: 0x33, count: 32)
            )
            try writeFrame(
                try JSONEncoder().encode(context.hello),
                fileDescriptor: fileDescriptor,
                fragmentSize: fragmentSize
            )
            let response = try readFrame(fileDescriptor: fileDescriptor)
            let hello = try JSONDecoder().decode(VaultAgentServerHello.self, from: response)
            return (fileDescriptor, try context.complete(hello))
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    func writeFrame(_ payload: Data, fileDescriptor: Int32, fragmentSize: Int = 17) throws {
        let frame = try VaultAgentFrameCodec.frame(payload: payload)
        var offset = 0
        while offset < frame.count {
            let count = min(fragmentSize, frame.count - offset)
            let written = frame.withUnsafeBytes { buffer in
                Darwin.write(fileDescriptor, buffer.baseAddress!.advanced(by: offset), count)
            }
            guard written > 0 else { throw SocketTestError.write }
            offset += written
        }
    }

    func readFrame(fileDescriptor: Int32) throws -> Data {
        let prefix = try readExactly(4, fileDescriptor: fileDescriptor)
        let length = prefix.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        guard length <= UInt32(VaultAgentLimits.maximumFrameBytes - 4) else { throw SocketTestError.frame }
        return try readExactly(Int(length), fileDescriptor: fileDescriptor)
    }

    func waitForEOF(fileDescriptor: Int32) -> Bool {
        for _ in 0..<100 {
            if isEOF(fileDescriptor: fileDescriptor) { return true }
            usleep(5_000)
        }
        return false
    }

    func isEOF(fileDescriptor: Int32) -> Bool {
        var byte: UInt8 = 0
        let result = Darwin.recv(fileDescriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return result == 0 || (result < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
    }

    private func readExactly(_ count: Int, fileDescriptor: Int32) throws -> Data {
        var result = Data()
        while result.count < count {
            var bytes = [UInt8](repeating: 0, count: count - result.count)
            let readCount = Darwin.read(fileDescriptor, &bytes, bytes.count)
            guard readCount > 0 else { throw SocketTestError.read(result.count, errno) }
            result.append(contentsOf: bytes.prefix(readCount))
        }
        return result
    }

    private func unixAddress(_ url: URL) throws -> sockaddr_un {
        let path = Array(url.path.utf8) + [0]
        var address = sockaddr_un()
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw SocketTestError.frame }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: path) }
        return address
    }
}

private enum SocketTestError: Error { case socket, bind, connect, write, read(Int, Int32), frame, rejected, directory }
private struct FixedPeerVerifier: VaultAgentPeerVerifying {
    let identity: VaultAgentPeerIdentity

    func verify(fileDescriptor _: Int32) throws -> VaultAgentPeerIdentity { identity }
}
private struct RejectingPeerVerifier: VaultAgentPeerVerifying {
    func verify(fileDescriptor _: Int32) throws -> VaultAgentPeerIdentity { throw SocketTestError.rejected }
}
private final class EchoSocketHandler: VaultAgentSocketRequestHandling {
    func handle(identity _: VaultAgentPeerIdentity, request: Data, completion: @escaping (Result<Data, Error>) -> Void) { completion(.success(request)) }
}
private final class CountingSocketHandler: VaultAgentSocketRequestHandling {
    private let lock = NSLock()
    private var called = false

    var wasCalled: Bool { lock.lock(); defer { lock.unlock() }; return called }

    func handle(identity _: VaultAgentPeerIdentity, request _: Data, completion _: @escaping (Result<Data, Error>) -> Void) {
        lock.lock(); called = true; lock.unlock()
    }
}
private final class DelayedSocketHandler: VaultAgentSocketRequestHandling {
    let started = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var completion: ((Result<Data, Error>) -> Void)?

    func handle(identity _: VaultAgentPeerIdentity, request _: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        lock.lock(); self.completion = completion; lock.unlock(); started.signal()
    }

    func complete(_ result: Result<Data, Error>) {
        lock.lock(); let callback = completion; completion = nil; lock.unlock(); callback?(result)
    }
}
private final class DuplicateSocketHandler: VaultAgentSocketRequestHandling {
    func handle(identity _: VaultAgentPeerIdentity, request: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.success(request))
        completion(.success(Data("duplicate".utf8)))
    }
}
private final class FixedResponseSocketHandler: VaultAgentSocketRequestHandling {
    let response: Data

    init(response: Data) { self.response = response }

    func handle(identity _: VaultAgentPeerIdentity, request _: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.success(response))
    }
}
private final class CancellationWindowChurnHandler: VaultAgentSocketRequestHandling {
    let replacementsReady = DispatchSemaphore(value: 0)
    private let fixture: SocketFixture
    private let lock = NSLock()
    private var replacements: [Int32] = []

    var replacementCount: Int { lock.lock(); defer { lock.unlock() }; return replacements.count }

    init(fixture: SocketFixture) { self.fixture = fixture }

    func handle(
        identity _: VaultAgentPeerIdentity,
        request _: Data,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        completion(.failure(SocketTestError.rejected))
        let descriptors = (0..<2).compactMap { _ in try? fixture.connectOnly() }
        lock.lock(); replacements.append(contentsOf: descriptors); lock.unlock()
        replacementsReady.signal()
    }

    func closeReplacements() {
        lock.lock()
        let descriptors = replacements
        replacements.removeAll()
        lock.unlock()
        descriptors.forEach { Darwin.close($0) }
    }
}
private final class LockedCounter {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.lock(); defer { lock.unlock() }; return count }

    func increment() { lock.lock(); count += 1; lock.unlock() }
}
private final class SocketLifecycleRecorder {
    private let lock = NSLock()
    private var created: [Int32: Set<VaultAgentSocketSourceKind>] = [:]
    private var cancelled: [Int32: Set<VaultAgentSocketSourceKind>] = [:]
    private var closedAfterCancellation: [Int32: Bool] = [:]
    private var reused: [Int32: Bool] = [:]
    private var replacementDescriptors: [Int32] = []
    private var liveConnectionDescriptors: Set<Int32> = []
    private var connectionDescriptorPeak = 0

    var managedDescriptorCount: Int { lock.lock(); defer { lock.unlock() }; return created.count }
    var allDescriptorsClosedAfterCancellation: Bool {
        lock.lock(); defer { lock.unlock() }
        return closedAfterCancellation.count == created.count && closedAfterCancellation.values.allSatisfy { $0 }
    }
    var allClosedDescriptorsImmediatelyReusable: Bool {
        lock.lock(); defer { lock.unlock() }
        return reused.count == created.count && reused.values.allSatisfy { $0 }
    }
    var peakConnectionDescriptorCount: Int {
        lock.lock(); defer { lock.unlock() }
        return connectionDescriptorPeak
    }

    func sourceCreated(_ kind: VaultAgentSocketSourceKind, _ fileDescriptor: Int32) {
        lock.lock()
        created[fileDescriptor, default: []].insert(kind)
        if kind != .listener {
            liveConnectionDescriptors.insert(fileDescriptor)
            connectionDescriptorPeak = max(connectionDescriptorPeak, liveConnectionDescriptors.count)
        }
        lock.unlock()
    }

    func sourceCancellationCompleted(_ kind: VaultAgentSocketSourceKind, _ fileDescriptor: Int32) {
        lock.lock(); cancelled[fileDescriptor, default: []].insert(kind); lock.unlock()
    }

    func descriptorClosed(_ fileDescriptor: Int32) {
        lock.lock()
        closedAfterCancellation[fileDescriptor] = created[fileDescriptor] == cancelled[fileDescriptor]
        lock.unlock()

        let replacement = socket(AF_UNIX, SOCK_STREAM, 0)
        lock.lock()
        reused[fileDescriptor] = replacement == fileDescriptor
        if replacement >= 0 { replacementDescriptors.append(replacement) }
        liveConnectionDescriptors.remove(fileDescriptor)
        lock.unlock()
    }

    func closeReusedDescriptors() {
        lock.lock()
        let descriptors = replacementDescriptors
        replacementDescriptors.removeAll()
        lock.unlock()
        descriptors.forEach { Darwin.close($0) }
    }
}

private final class SocketConnectionProbe {
    private let lock = NSLock()
    private let empty = DispatchSemaphore(value: 0)
    private var descriptors = Set<Int32>()

    func sourceCreated(_ kind: VaultAgentSocketSourceKind, _ fileDescriptor: Int32) {
        guard kind == .read else { return }
        lock.lock()
        descriptors.insert(fileDescriptor)
        lock.unlock()
    }

    func descriptorClosed(_ fileDescriptor: Int32) {
        lock.lock()
        descriptors.remove(fileDescriptor)
        let isEmpty = descriptors.isEmpty
        lock.unlock()
        if isEmpty { empty.signal() }
    }

    func waitForNoConnections() -> Bool {
        empty.wait(timeout: .now() + 2) == .success
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private extension VaultAgentResponseBody {
    var failureCode: VaultAgentErrorCode? {
        guard case let .failure(failure) = self else { return nil }
        return failure.code
    }

    var searchPage: VaultAgentSearchPage? {
        guard case let .success(.search(page)) = self else { return nil }
        return page
    }
}

private final class RuntimeFixture {
    let connectionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let requestID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let entryID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    let folderID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    let identity: VaultAgentPeerIdentity
    let grantStore = RuntimeGrantStore()
    let vault: RuntimeVaultProbe
    let audit = RuntimeAuditProbe()
    let executor: VaultAgentSerialExecutor
    let authorizationPolicy: VaultAgentAuthorizationPolicy
    let ticketStore: VaultAgentTicketStore
    let runtime: VaultAgentRuntime
    private let nowBox = RuntimeDateBox(Date(timeIntervalSince1970: 1_000_000))

    init(
        client: VaultAgentClientKind,
        authorized: Bool = true,
        cursorKey: Data = Data(repeating: 0x55, count: 32)
    ) throws {
        identity = .init(
            client: client,
            helperRequirement: "identifier com.pastera.helper",
            helperCDHash: Data([0x01]),
            helperIsAdHoc: false,
            helperPath: "/Applications/Pastera.app/Contents/Helpers/helper",
            hostRequirement: client == .cli ? nil : "identifier com.example.host",
            hostCDHash: client == .cli ? nil : Data([0x02]),
            hostIsAdHoc: client == .cli ? nil : false,
            hostPath: client == .cli ? nil : "/Applications/Host.app/Contents/MacOS/Host"
        )
        executor = VaultAgentSerialExecutor(queue: DispatchQueue(label: "RuntimeFixture.store"))
        authorizationPolicy = try VaultAgentAuthorizationPolicy(store: grantStore, executor: executor)
        if authorized {
            try authorizationPolicy.authorize(identity: identity, authenticatedAt: nowBox.value)
        }
        vault = RuntimeVaultProbe(entryID: entryID, folderID: folderID, executor: executor)
        let ticketRandom = RuntimeTicketRandom()
        ticketStore = VaultAgentTicketStore(
            randomBytes: ticketRandom.next,
            commandBuilder: { client, mode, token in
                VaultAgentRuntime.helperCommand(
                    applicationURL: URL(fileURLWithPath: "/Applications/Pastera.app"),
                    client: client,
                    mode: mode,
                    token: token
                )
            }
        )
        runtime = try VaultAgentRuntime(
            executor: executor,
            authorizationPolicy: authorizationPolicy,
            vault: vault,
            pasteTargetTracker: RuntimeTargetTracker(),
            integrationService: RuntimeIntegrationService(),
            rateLimiter: VaultAgentRateLimiter(),
            ticketStore: ticketStore,
            auditLogger: audit,
            now: { [nowBox] in nowBox.value },
            cursorKey: cursorKey
        )
    }

    func advanceNow(by interval: TimeInterval) { nowBox.value = nowBox.value.addingTimeInterval(interval) }

    var currentDate: Date { nowBox.value }

    func issueTicket() throws -> VaultAgentPreparedTicket {
        try ticketStore.issue(
            client: identity.client,
            entryID: entryID,
            field: .password,
            mode: .stdin,
            now: nowBox.value
        )
    }

    func encodedRequest(_ operation: VaultAgentOperation) throws -> Data {
        try JSONEncoder().encode(VaultAgentRequestEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: connectionID,
            sequence: 1,
            requestID: requestID,
            operation: operation
        ))
    }

    func authorizeAdditionalClient(_ client: VaultAgentClientKind) throws -> VaultAgentPeerIdentity {
        let additionalIdentity = VaultAgentPeerIdentity(
            client: client,
            helperRequirement: identity.helperRequirement,
            helperCDHash: identity.helperCDHash,
            helperIsAdHoc: identity.helperIsAdHoc,
            helperPath: identity.helperPath,
            hostRequirement: client == .cli ? nil : "identifier com.example.\(client.rawValue)",
            hostCDHash: client == .cli ? nil : Data([0x03]),
            hostIsAdHoc: client == .cli ? nil : false,
            hostPath: client == .cli ? nil : "/Applications/Host.app/Contents/MacOS/Host"
        )
        try authorizationPolicy.authorize(identity: additionalIdentity, authenticatedAt: nowBox.value)
        try runtime.authorizationStateDidChange()
        return additionalIdentity
    }

    func call(
        _ operation: VaultAgentOperation,
        protocolVersion: Int = VaultAgentLimits.protocolVersion,
        identity requestIdentity: VaultAgentPeerIdentity? = nil
    ) async throws -> VaultAgentResponseEnvelope {
        let request = VaultAgentRequestEnvelope(
            protocolVersion: protocolVersion,
            connectionID: connectionID,
            sequence: 1,
            requestID: requestID,
            operation: operation
        )
        return try JSONDecoder().decode(
            VaultAgentResponseEnvelope.self,
            from: await handle(try JSONEncoder().encode(request), identity: requestIdentity ?? identity)
        )
    }

    func handle(_ data: Data, identity requestIdentity: VaultAgentPeerIdentity? = nil) async -> Data {
        await withCheckedContinuation { continuation in
            runtime.handle(identity: requestIdentity ?? identity, request: data) { result in
                continuation.resume(returning: (try? result.get()) ?? Data())
            }
        }
    }

    func search(
        query: String?,
        folderID: UUID?,
        limit: Int,
        cursor: String? = nil
    ) async throws -> VaultAgentSearchPage {
        let response = try await call(.search(.init(
            query: query,
            folderID: folderID,
            limit: limit,
            cursor: cursor
        )))
        return try #require(response.body.searchPage)
    }

    func makeEntry(
        idSuffix: Int,
        title: String,
        website: String = "https://mail.example",
        username: String = "alice",
        updatedAt: TimeInterval
    ) -> PasswordVaultEntry {
        let suffix = String(format: "%012x", idSuffix)
        return .init(
            id: UUID(uuidString: "30000000-0000-0000-0000-\(suffix)")!,
            folderID: folderID,
            title: title,
            website: website,
            username: username,
            note: "must-not-leak",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

private final class RuntimeDateBox: @unchecked Sendable {
    var value: Date

    init(_ value: Date) { self.value = value }
}

private final class RuntimeTicketRandom {
    private var value: UInt8 = 0x40

    func next() -> Data {
        value &+= 1
        return Data(repeating: value, count: 32)
    }
}

private final class RuntimeGrantStore: VaultAgentGrantStoring {
    var grants: [VaultAgentClientKind: VaultAgentGrant] = [:]

    func load() -> [VaultAgentClientKind: VaultAgentGrant] { grants }
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) { self.grants = grants }
}

private final class RuntimeVaultProbe: PasswordVaultAgentAccess {
    let entryID: UUID
    let folderID: UUID
    var agentVaultReady = true
    var folders: [PasswordVaultFolder]
    var entries: [PasswordVaultEntry]
    private(set) var ensureReadyCount = 0
    private(set) var metadataCount = 0
    private(set) var secretCount = 0
    private(set) var automationCleanupCount = 0
    private(set) var cleanupRanOnExecutor = false
    private(set) var maximumConcurrentMetadata = 0
    private(set) var metadataRanOnExecutor = false
    var observeConcurrentMetadata = false
    var metadataCallbackCount = 1
    private let executor: VaultAgentSerialExecutor
    private var activeMetadata = 0

    init(entryID: UUID, folderID: UUID, executor: VaultAgentSerialExecutor) {
        self.entryID = entryID
        self.folderID = folderID
        self.executor = executor
        folders = [.init(id: folderID, name: "Work", createdAt: .distantPast, updatedAt: .distantPast)]
        entries = [.init(
            id: entryID,
            folderID: folderID,
            title: "Mail",
            website: "https://mail.example",
            username: "alice",
            note: "must-not-leak",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 0)
        )]
    }

    func ensureReadyForAgent(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        ensureReadyCount += 1
        completion(.success(()))
    }

    func agentMetadata(
        completion: @escaping (Result<([PasswordVaultFolder], [PasswordVaultEntry]), PasswordVaultError>) -> Void
    ) {
        executor.async {
            self.metadataRanOnExecutor = self.executor.isCurrent
            self.metadataCount += 1
            self.activeMetadata += 1
            self.maximumConcurrentMetadata = max(self.maximumConcurrentMetadata, self.activeMetadata)
            if self.observeConcurrentMetadata {
                Thread.sleep(forTimeInterval: 0.02)
            }
            let metadata = (self.folders, self.entries)
            self.activeMetadata -= 1
            for _ in 0..<self.metadataCallbackCount {
                completion(.success(metadata))
            }
        }
    }

    func agentPaste(
        entryID _: UUID,
        field _: VaultAgentSecretField,
        target _: PasteTargetContext,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) { completion(.success(())) }

    func agentCopy(
        entryID _: UUID,
        field _: VaultAgentSecretField,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) { completion(.success(())) }

    func agentSecret(
        entryID _: UUID,
        field _: VaultAgentSecretField,
        completion: @escaping (Result<Data, PasswordVaultError>) -> Void
    ) {
        secretCount += 1
        completion(.success(Data("secret".utf8)))
    }

    func disableAutomationUnlockForAgent() throws {
        automationCleanupCount += 1
        cleanupRanOnExecutor = executor.isCurrent
    }
}

private final class RuntimeTargetTracker: VaultAgentPasteTargetTracking {
    func resolve() throws -> PasteTargetContext {
        .init(processIdentifier: 42, bundleIdentifier: "com.example.target", application: nil, focusedElement: nil)
    }
}

private struct RuntimeIntegrationService: VaultAgentIntegrationServicing {
    func status(host: VaultAgentHostKind?) throws -> VaultAgentIntegrationStatus {
        .init(hosts: (host.map { [$0] } ?? [.codex, .claude]).map {
            .init(
                host: $0,
                hostDetected: true,
                hostExecutablePath: "/Applications/Host.app/Contents/MacOS/Host",
                mcpInstalled: true,
                skillInstalled: true,
                installedVersion: "1",
                authorized: true,
                idleExpiresAt: nil,
                hardExpiresAt: nil
            )
        })
    }
    func install(host _: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus { .init(hosts: []) }
    func uninstall(host _: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus { .init(hosts: []) }
}

private final class RuntimeAuditProbe: VaultAgentAuditLogging {
    struct Record { let client: VaultAgentClientKind }

    private(set) var records: [Record] = []

    // swiftlint:disable:next function_parameter_count
    func record(
        client: VaultAgentClientKind,
        action _: VaultAgentAuditAction,
        entryID _: UUID?,
        result _: VaultAgentErrorCode?,
        latencyBucket _: VaultAgentLatencyBucket,
        at _: Date
    ) { records.append(.init(client: client)) }
}

private final class PasteTargetHarness {
    let notificationCenter = NotificationCenter()
    let helperURL = URL(fileURLWithPath: "/Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP")
    let hostURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/MacOS/Codex")
    let targetURL = URL(fileURLWithPath: "/Applications/Editor.app/Contents/MacOS/Editor")
    let secondTargetURL = URL(fileURLWithPath: "/Applications/Second.app/Contents/MacOS/Second")
    let signature = VaultAgentCodeSignature(
        identifier: "com.example.editor",
        designatedRequirement: "identifier com.example.editor",
        cdHash: Data([1]),
        isAdHoc: true
    )
    var applications: [pid_t: VaultAgentPasteApplication] = [:]
    var snapshots: [pid_t: VaultAgentProcessSnapshot] = [:]
    var signatures: [String: VaultAgentCodeSignature] = [:]
    var focusedElements: [pid_t: AXUIElement] = [:]

    func makeTracker() -> VaultAgentPasteTargetTracker {
        VaultAgentPasteTargetTracker(
            notificationCenter: notificationCenter,
            notificationName: .vaultAgentPasteTargetTestActivation,
            currentProcessID: 10,
            currentBundleIdentifier: "com.pastera-app.Pastera",
            excludedExecutableURLs: { [weak self] in self.map { [$0.helperURL, $0.hostURL] } ?? [] },
            applicationFromNotification: { [weak self] notification in
                guard let pid = notification.object as? pid_t else { return nil }
                return self?.applications[pid]
            },
            runningApplication: { [weak self] pid in self?.applications[pid] },
            processInspector: PasteTargetProcessInspector { [weak self] pid in
                guard let snapshot = self?.snapshots[pid] else { throw SocketTestError.rejected }
                return snapshot
            },
            codeSigningInspector: PasteTargetSigningInspector { [weak self] url in
                guard let signature = self?.signatures[url.path] else { throw SocketTestError.rejected }
                return signature
            },
            focusedElement: { [weak self] pid in self?.focusedElements[pid] }
        )
    }

    func activate(
        pid: pid_t,
        bundleID: String,
        path: URL,
        focus: AXUIElement? = AXUIElementCreateApplication(99)
    ) {
        let app = VaultAgentPasteApplication(
            processIdentifier: pid,
            bundleIdentifier: bundleID,
            executableURL: path,
            isTerminated: false,
            application: nil
        )
        applications[pid] = app
        snapshots[pid] = .init(
            pid: pid,
            parentPID: 1,
            uid: getuid(),
            startSeconds: 1,
            startMicroseconds: 2,
            executableURL: path,
            device: 3,
            inode: UInt64(pid)
        )
        signatures[path.path] = signature
        focusedElements[pid] = focus
        notificationCenter.post(name: .vaultAgentPasteTargetTestActivation, object: pid)
    }
}

private struct PasteTargetProcessInspector: VaultAgentProcessInspecting {
    let operation: (pid_t) throws -> VaultAgentProcessSnapshot

    func snapshot(pid: pid_t) throws -> VaultAgentProcessSnapshot { try operation(pid) }
}

private struct PasteTargetSigningInspector: VaultAgentCodeSigningInspecting {
    let operation: (URL) throws -> VaultAgentCodeSignature

    func inspect(executableURL: URL) throws -> VaultAgentCodeSignature { try operation(executableURL) }
}

private final class RuntimeLockedInt {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private extension Notification.Name {
    static let vaultAgentPasteTargetTestActivation = Notification.Name("VaultAgentPasteTargetTestActivation")
}
