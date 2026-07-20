import CryptoKit
import Darwin
import Foundation
import PasteraAgentProtocol
import Testing

@testable import PasteraAgentAdapter

// Socket and crypto fixtures remain local so Agent tests never link the App target.
// swiftlint:disable file_length type_body_length

@Suite("Vault agent client", .serialized)
struct VaultAgentClientTests {
    @Test("default socket path is derived from Application Support")
    func defaultSocketPath() throws {
        let root = URL(fileURLWithPath: "/tmp/PasteraAgentClientTests/Application Support", isDirectory: true)
        let fileManager = VaultAgentApplicationSupportFileManager(applicationSupportURL: root)

        let socketURL = try VaultAgentClient.defaultSocketURL(fileManager: fileManager)

        #expect(socketURL == root.appendingPathComponent("Pastera/Agent/v1/broker.sock"))
    }

    @Test("client crypto reproduces the Task 5 fixed transcript byte for byte")
    func fixedTranscriptVector() throws {
        let clientKey = Data((0..<32).map(UInt8.init))
        let serverKey = Data((32..<64).map(UInt8.init))
        let serverPublicKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: serverKey
        ).publicKey.rawRepresentation
        let connectionID = UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!
        let channel = try VaultAgentClientSecureChannel.makeForTesting(
            privateKey: clientKey,
            peerPublicKey: serverPublicKey,
            clientNonce: Data(repeating: 0x11, count: 32),
            serverNonce: Data(repeating: 0x22, count: 32),
            connectionID: connectionID
        )

        let frame = try channel.seal(Data("request".utf8))

        #expect(frame.connectionID == connectionID)
        #expect(frame.sequence == 1)
        #expect(frame.ciphertext.hex == "01000000000000000000000155b45c6f684d95a990118e4a17d1c1cb306ba474090092")
    }

    @Test("client receive direction rejects wrong connection, ordering, and replay")
    func receiveSequenceAndConnectionAreStrict() throws {
        let fixture = try VaultAgentClientCryptoFixture()
        let channel = try fixture.makeClientChannel()
        let first = try fixture.serverFrame(Data("first".utf8), sequence: 1)
        let second = try fixture.serverFrame(Data("second".utf8), sequence: 2)
        let wrongConnection = VaultAgentEncryptedFrame(
            connectionID: UUID(),
            sequence: 1,
            ciphertext: first.ciphertext
        )

        #expect(throws: VaultAgentProtocolError.connectionMismatch) {
            try channel.open(wrongConnection)
        }
        #expect(throws: VaultAgentProtocolError.outOfOrderFrame) {
            try channel.open(second)
        }
        #expect(try channel.open(first) == Data("first".utf8))
        #expect(throws: VaultAgentProtocolError.replayedFrame) {
            try channel.open(first)
        }
        #expect(try channel.open(second) == Data("second".utf8))
    }

    @Test("authentication failure does not advance the receive sequence")
    func failedAuthenticationDoesNotAdvanceSequence() throws {
        let fixture = try VaultAgentClientCryptoFixture()
        let channel = try fixture.makeClientChannel()
        let valid = try fixture.serverFrame(Data("response".utf8), sequence: 1)
        var ciphertext = valid.ciphertext
        ciphertext[ciphertext.startIndex] ^= 0x01
        let tampered = VaultAgentEncryptedFrame(
            connectionID: valid.connectionID,
            sequence: valid.sequence,
            ciphertext: ciphertext
        )

        #expect(throws: VaultAgentProtocolError.authenticationFailed) {
            try channel.open(tampered)
        }
        #expect(try channel.open(valid) == Data("response".utf8))
    }

    @Test("one failed initial connection launches once and uses the fixed retry schedule")
    func boundedLaunchRetry() async throws {
        let probe = VaultAgentRetryProbe(failuresBeforeSuccess: 3)

        let value: Int = try await VaultAgentConnectionRetrier.connect(
            connect: { try probe.connect() },
            launch: { probe.launch() },
            sleep: { probe.sleep(milliseconds: $0) }
        )

        #expect(value == 42)
        #expect(probe.launchCount == 1)
        #expect(probe.connectCount == 4)
        #expect(probe.delays == [50, 100, 200])
    }

    @Test("exhausted retries never relaunch the App")
    func exhaustedRetryDoesNotRelaunch() async {
        let probe = VaultAgentRetryProbe(failuresBeforeSuccess: .max)

        await #expect(throws: VaultAgentClientError.unavailable) {
            let _: Int = try await VaultAgentConnectionRetrier.connect(
                connect: { try probe.connect() },
                launch: { probe.launch() },
                sleep: { probe.sleep(milliseconds: $0) }
            )
        }

        #expect(probe.launchCount == 1)
        #expect(probe.connectCount == 6)
        #expect(probe.delays == [50, 100, 200, 400, 800])
    }

    @Test("initial connect cancellation and timeout never launch or retry")
    func initialTerminalConnectErrorsDoNotRetry() async {
        for terminalError in [VaultAgentClientError.cancelled, .timedOut] {
            let probe = VaultAgentRetrierOutcomeProbe(outcomes: [.failure(terminalError)])

            do {
                let _: Int = try await VaultAgentConnectionRetrier.connect(
                    connect: { try probe.connect() },
                    launch: { probe.launch() },
                    sleep: { probe.sleep(milliseconds: $0) }
                )
                Issue.record("Expected terminal connect error")
            } catch let error as VaultAgentClientError {
                #expect(error == terminalError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            let snapshot = probe.snapshot()
            #expect(snapshot.connectCount == 1)
            #expect(snapshot.launchCount == 0)
            #expect(snapshot.delays.isEmpty)
        }
    }

    @Test("retry connect cancellation and timeout stop the existing retry cycle")
    func retryTerminalConnectErrorsStopImmediately() async {
        for terminalError in [VaultAgentClientError.cancelled, .timedOut] {
            let probe = VaultAgentRetrierOutcomeProbe(outcomes: [
                .failure(.unavailable),
                .failure(terminalError)
            ])

            do {
                let _: Int = try await VaultAgentConnectionRetrier.connect(
                    connect: { try probe.connect() },
                    launch: { probe.launch() },
                    sleep: { probe.sleep(milliseconds: $0) }
                )
                Issue.record("Expected terminal retry error")
            } catch let error as VaultAgentClientError {
                #expect(error == terminalError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            let snapshot = probe.snapshot()
            #expect(snapshot.connectCount == 2)
            #expect(snapshot.launchCount == 1)
            #expect(snapshot.delays == [50])
        }
    }

    @Test("CancellationError is terminal before and after launch")
    func cancellationErrorStopsRetryImmediately() async {
        for cancellationConnectCount in [1, 2] {
            let probe = VaultAgentCancellationProbe(
                cancellationConnectCount: cancellationConnectCount
            )

            await #expect(throws: VaultAgentClientError.cancelled) {
                let _: Int = try await VaultAgentConnectionRetrier.connect(
                    connect: { try probe.connect() },
                    launch: { probe.launch() },
                    sleep: { probe.sleep(milliseconds: $0) }
                )
            }

            let snapshot = probe.snapshot()
            #expect(snapshot.connectCount == cancellationConnectCount)
            #expect(snapshot.launchCount == cancellationConnectCount - 1)
            #expect(snapshot.delays == (cancellationConnectCount == 1 ? [] : [50]))
        }
    }

    @Test("retry deadline prevents launch or sleep after the request budget expires")
    func retryDeadlineIsPreserved() async {
        let probe = VaultAgentRetryProbe(failuresBeforeSuccess: .max)
        let clock = VaultAgentScriptedClock(values: [100])

        await #expect(throws: VaultAgentClientError.timedOut) {
            let _: Int = try await VaultAgentConnectionRetrier.connect(
                deadline: 100,
                now: { clock.now() },
                connect: { try probe.connect() },
                launch: { probe.launch() },
                sleep: { probe.sleep(milliseconds: $0) }
            )
        }

        #expect(probe.connectCount == 1)
        #expect(probe.launchCount == 0)
        #expect(probe.delays.isEmpty)
    }

    @Test("cancelling a blocked connect prevents launch and every retry side effect")
    func cancelledBlockedConnectHasNoSideEffects() async throws {
        let probe = try VaultAgentBlockingUnavailableProbe()
        let task = Task {
            try await VaultAgentConnectionRetrier.connect(
                connect: { try probe.connect() },
                launch: { probe.launch() },
                sleep: { probe.sleepIgnoringCancellation(milliseconds: $0) }
            ) as Int
        }
        await probe.waitUntilConnectEntered()

        task.cancel()
        probe.releaseConnect()

        await #expect(throws: VaultAgentClientError.cancelled) {
            try await task.value
        }
        let snapshot = probe.snapshot()
        #expect(snapshot.connectCount == 1)
        #expect(snapshot.launchCount == 0)
        #expect(snapshot.delays.isEmpty)
        #expect(fcntl(snapshot.descriptor, F_GETFD) == -1)
        #expect(errno == EBADF)
    }

    @Test("client launches only its containing Pastera app and keeps retries bounded")
    func clientLaunchesContainingApplicationOnce() async {
        let probe = VaultAgentLaunchProbe()
        let client = VaultAgentClient(
            client: .codex,
            dependencies: .init(
                socketURL: { URL(fileURLWithPath: "/tmp/unused.sock") },
                executableURL: {
                    URL(fileURLWithPath: "/Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP")
                },
                launch: { probe.didLaunch($0) },
                sleep: { probe.didSleep($0) },
                connect: { _, _ in try probe.connect() },
                nonce: { Data(repeating: 0, count: VaultAgentLimits.nonceBytes) },
                privateKey: { Curve25519.KeyAgreement.PrivateKey() },
                now: { 0 }
            )
        )

        await #expect(throws: VaultAgentClientError.unavailable) {
            try await client.request(.status)
        }
        let snapshot = probe.snapshot()

        #expect(snapshot.connectCount == 6)
        #expect(snapshot.launches == [URL(fileURLWithPath: "/Applications/Pastera.app")])
        #expect(snapshot.delays == [50, 100, 200, 400, 800])
    }

    @Test("a malformed handshake is a terminal protocol failure and never launches the app")
    func malformedHandshakeDoesNotLaunch() async throws {
        let socket = try VaultAgentSocketPair()
        let descriptor = socket.takeClientDescriptor()
        try socket.writeServer(VaultAgentFrameCodec.frame(payload: Data("{}".utf8)))
        let probe = VaultAgentSocketConnectProbe(descriptor: descriptor)
        let client = makeSocketClient(probe: probe)

        await #expect(throws: VaultAgentClientError.protocolFailure) {
            try await client.request(.status)
        }
        let snapshot = probe.snapshot()
        #expect(snapshot.connectCount == 1)
        #expect(snapshot.launchCount == 0)
        #expect(snapshot.delays.isEmpty)
    }

    @Test("an oversized handshake frame is rejected before allocating its payload")
    func oversizedHandshakeFrameIsRejected() async throws {
        let socket = try VaultAgentSocketPair()
        let descriptor = socket.takeClientDescriptor()
        var oversized = UInt32(VaultAgentLimits.maximumFrameBytes).bigEndian
        try withUnsafeBytes(of: &oversized) { try socket.writeServer(Data($0)) }
        let probe = VaultAgentSocketConnectProbe(descriptor: descriptor)
        let client = makeSocketClient(probe: probe)

        await #expect(throws: VaultAgentClientError.protocolFailure) {
            try await client.request(.status)
        }
        #expect(probe.snapshot().launchCount == 0)
    }

    @Test("handshake timeout closes the connection without launching or retrying")
    func handshakeTimeoutIsBounded() async throws {
        let socket = try VaultAgentSocketPair()
        let descriptor = socket.takeClientDescriptor()
        let probe = VaultAgentSocketConnectProbe(descriptor: descriptor)
        let clock = VaultAgentAdvancingClock()
        let client = makeSocketClient(probe: probe, now: { clock.now() })

        await #expect(throws: VaultAgentClientError.timedOut) {
            try await client.request(.status)
        }
        let snapshot = probe.snapshot()
        #expect(snapshot.connectCount == 1)
        #expect(snapshot.launchCount == 0)
    }

    @Test("cancelling an in-flight handshake closes the connection without relaunch")
    func handshakeCancellationIsBounded() async throws {
        let socket = try VaultAgentSocketPair()
        let descriptor = socket.takeClientDescriptor()
        let probe = VaultAgentSocketConnectProbe(descriptor: descriptor)
        let client = makeSocketClient(
            probe: probe,
            now: { DispatchTime.now().uptimeNanoseconds }
        )
        let request = Task { try await client.request(.status) }

        try await Task.sleep(for: .milliseconds(100))
        request.cancel()
        await #expect(throws: VaultAgentClientError.cancelled) {
            try await request.value
        }
        #expect(probe.snapshot().launchCount == 0)
    }

    @Test("EOF during handshake closes the connection without launching the app")
    func handshakeEOFClosesConnection() async throws {
        let socket = try VaultAgentSocketPair()
        let descriptor = socket.takeClientDescriptor()
        socket.closeServerDescriptor()
        let probe = VaultAgentSocketConnectProbe(descriptor: descriptor)
        let client = makeSocketClient(
            probe: probe,
            now: { DispatchTime.now().uptimeNanoseconds }
        )

        await #expect(throws: VaultAgentClientError.unavailable) {
            try await client.request(.status)
        }
        let snapshot = probe.snapshot()
        #expect(snapshot.connectCount == 1)
        #expect(snapshot.launchCount == 0)
    }

    @Test("real socket handshake and encrypted request response round trip")
    func encryptedSocketRoundTrip() async throws {
        let socket = try VaultAgentSocketPair()
        let clientDescriptor = socket.takeClientDescriptor()
        let serverDescriptor = socket.takeServerDescriptor()
        let fixture = try VaultAgentClientCryptoFixture()
        let expectedStatus = VaultAgentStatus(
            client: .codex,
            installed: true,
            authorized: true,
            vaultReady: true,
            idleExpiresAt: nil,
            hardExpiresAt: nil,
            protocolVersion: VaultAgentLimits.protocolVersion
        )
        let serverTask = Task.detached { () throws -> VaultAgentRequestEnvelope in
            defer { Darwin.close(serverDescriptor) }
            let helloData = try readTask7Frame(fileDescriptor: serverDescriptor)
            let hello = try JSONDecoder().decode(VaultAgentClientHello.self, from: helloData)
            guard hello.protocolVersion == VaultAgentLimits.protocolVersion,
                  hello.publicKey == fixture.clientPublicKey,
                  hello.nonce == fixture.clientNonce else {
                throw VaultAgentClientError.protocolFailure
            }
            try writeTask7Frame(
                JSONEncoder().encode(fixture.serverHello),
                fileDescriptor: serverDescriptor
            )
            let requestFrameData = try readTask7Frame(fileDescriptor: serverDescriptor)
            let requestFrame = try JSONDecoder().decode(
                VaultAgentEncryptedFrame.self,
                from: requestFrameData
            )
            let requestData = try fixture.openClientFrame(requestFrame)
            let request = try JSONDecoder().decode(VaultAgentRequestEnvelope.self, from: requestData)
            let response = VaultAgentResponseEnvelope(
                protocolVersion: request.protocolVersion,
                connectionID: request.connectionID,
                sequence: request.sequence,
                requestID: request.requestID,
                body: .success(.status(expectedStatus))
            )
            let responseFrame = try fixture.serverFrame(
                JSONEncoder().encode(response),
                sequence: request.sequence
            )
            try writeTask7Frame(
                JSONEncoder().encode(responseFrame),
                fileDescriptor: serverDescriptor
            )
            return request
        }
        let probe = VaultAgentSocketConnectProbe(descriptor: clientDescriptor)
        let client = makeSocketClient(
            probe: probe,
            now: { DispatchTime.now().uptimeNanoseconds }
        )

        let body = try await client.request(.status)
        await client.close()
        let request = try await serverTask.value

        #expect(body == .success(.status(expectedStatus)))
        #expect(request.protocolVersion == VaultAgentLimits.protocolVersion)
        #expect(request.connectionID == fixture.connectionID)
        #expect(request.sequence == 1)
        #expect(request.operation == .status)
        #expect(probe.snapshot().launchCount == 0)
    }

    @Test("concurrent cold requests share one launch, connection, and handshake")
    func concurrentColdRequestsShareConnectionAttempt() async throws {
        let socket = try VaultAgentSocketPair()
        let clientDescriptor = socket.takeClientDescriptor()
        let serverDescriptor = socket.takeServerDescriptor()
        let fixture = try VaultAgentClientCryptoFixture()
        let retryGate = VaultAgentAsyncGate()
        let probe = VaultAgentSharedConnectProbe(descriptor: clientDescriptor)
        let client = makeSharedSocketClient(probe: probe, retryGate: retryGate)
        let requestCount = 3
        let serverTask = Task.detached { () throws -> Int in
            defer { Darwin.close(serverDescriptor) }
            let helloData = try readTask7Frame(fileDescriptor: serverDescriptor)
            let hello = try JSONDecoder().decode(VaultAgentClientHello.self, from: helloData)
            guard hello.publicKey == fixture.clientPublicKey,
                  hello.nonce == fixture.clientNonce else {
                throw VaultAgentClientError.protocolFailure
            }
            try writeTask7Frame(
                JSONEncoder().encode(fixture.serverHello),
                fileDescriptor: serverDescriptor
            )
            for sequence in 1...requestCount {
                let frameData = try readTask7Frame(fileDescriptor: serverDescriptor)
                let frame = try JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: frameData)
                let plaintext = try fixture.openClientFrame(frame)
                let request = try JSONDecoder().decode(
                    VaultAgentRequestEnvelope.self,
                    from: plaintext
                )
                let response = VaultAgentResponseEnvelope(
                    protocolVersion: request.protocolVersion,
                    connectionID: request.connectionID,
                    sequence: request.sequence,
                    requestID: request.requestID,
                    body: .success(.status(Self.readyStatus))
                )
                let responseFrame = try fixture.serverFrame(
                    JSONEncoder().encode(response),
                    sequence: UInt64(sequence)
                )
                try writeTask7Frame(
                    JSONEncoder().encode(responseFrame),
                    fileDescriptor: serverDescriptor
                )
            }
            return requestCount
        }

        let requests = (0..<requestCount).map { _ in
            Task { try await client.request(.status) }
        }
        await retryGate.waitUntilEntered()
        await retryGate.release()
        for request in requests {
            #expect(try await request.value == .success(.status(Self.readyStatus)))
        }
        await client.close()
        #expect(try await serverTask.value == requestCount)
        let snapshot = probe.snapshot()
        #expect(snapshot.connectCount == 2)
        #expect(snapshot.launchCount == 1)
        #expect(snapshot.delays == [50])

        #expect(fcntl(clientDescriptor, F_GETFD) == -1)
        #expect(errno == EBADF)
    }

    @Test("cancelling one connection waiter does not destroy the shared attempt")
    func cancellingOneWaiterKeepsSharedConnection() async throws {
        let socket = try VaultAgentSocketPair()
        let clientDescriptor = socket.takeClientDescriptor()
        let serverDescriptor = socket.takeServerDescriptor()
        let fixture = try VaultAgentClientCryptoFixture()
        let helloGate = VaultAgentAsyncGate()
        let probe = VaultAgentSharedConnectProbe(
            descriptor: clientDescriptor,
            initialFailure: false
        )
        let client = makeSharedSocketClient(probe: probe)
        let serverTask = Task.detached { () throws in
            defer { Darwin.close(serverDescriptor) }
            _ = try readTask7Frame(fileDescriptor: serverDescriptor)
            await helloGate.enterAndWait()
            try writeTask7Frame(
                JSONEncoder().encode(fixture.serverHello),
                fileDescriptor: serverDescriptor
            )
            let frameData = try readTask7Frame(fileDescriptor: serverDescriptor)
            let frame = try JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: frameData)
            let plaintext = try fixture.openClientFrame(frame)
            let request = try JSONDecoder().decode(
                VaultAgentRequestEnvelope.self,
                from: plaintext
            )
            let response = VaultAgentResponseEnvelope(
                protocolVersion: request.protocolVersion,
                connectionID: request.connectionID,
                sequence: request.sequence,
                requestID: request.requestID,
                body: .success(.status(Self.readyStatus))
            )
            try writeTask7Frame(
                JSONEncoder().encode(try fixture.serverFrame(
                    JSONEncoder().encode(response),
                    sequence: request.sequence
                )),
                fileDescriptor: serverDescriptor
            )
        }

        let cancelled = Task { try await client.request(.status) }
        let surviving = Task { try await client.request(.status) }
        await helloGate.waitUntilEntered()
        let immediatelyCancelled = Task { try await client.request(.status) }
        immediatelyCancelled.cancel()
        cancelled.cancel()
        await helloGate.release()

        await #expect(throws: VaultAgentClientError.cancelled) {
            try await immediatelyCancelled.value
        }
        await #expect(throws: VaultAgentClientError.cancelled) {
            try await cancelled.value
        }
        #expect(try await surviving.value == .success(.status(Self.readyStatus)))
        try await serverTask.value
        #expect(probe.snapshot().connectCount == 1)
        await client.close()
        #expect(fcntl(clientDescriptor, F_GETFD) == -1)
    }

    @Test("connection waiter capacity is 32 and every continuation is released", .timeLimit(.minutes(1)))
    func connectionWaiterCapacityIsBoundedAndReusable() async throws {
        let probe = VaultAgentCapacityConnectProbe()
        let client = VaultAgentClient(
            client: .codex,
            dependencies: socketDependencies(
                sleep: { probe.didSleep($0) },
                connect: { try probe.connect() },
                launch: { probe.didLaunch() }
            )
        )
        let outcomes = VaultAgentWaiterOutcomeQueue()
        let requests = (0..<33).map { _ in
            Task {
                let outcome: VaultAgentWaiterOutcome
                do {
                    _ = try await client.request(.status)
                    outcome = .success
                } catch let error as VaultAgentClientError {
                    outcome = .failure(error)
                } catch {
                    outcome = .failure(.protocolFailure)
                }
                await outcomes.record(outcome)
                return outcome
            }
        }
        await probe.waitUntilFirstConnectEntered()

        #expect(await outcomes.next() == .failure(.unavailable))
        for request in requests { request.cancel() }
        var cancelledOutcomes: [VaultAgentWaiterOutcome] = []
        for request in requests { cancelledOutcomes.append(await request.value) }

        #expect(cancelledOutcomes.filter { $0 == .failure(.cancelled) }.count == 32)
        #expect(cancelledOutcomes.filter { $0 == .failure(.unavailable) }.count == 1)
        probe.releaseFirstConnect()
        await probe.waitUntilFirstConnectFinished()

        let socket = try VaultAgentSocketPair()
        let clientDescriptor = socket.takeClientDescriptor()
        let serverDescriptor = socket.takeServerDescriptor()
        let fixture = try VaultAgentClientCryptoFixture()
        probe.enableSuccess(descriptor: clientDescriptor)
        let serverTask = Task.detached { () throws in
            defer { Darwin.close(serverDescriptor) }
            _ = try readTask7Frame(fileDescriptor: serverDescriptor)
            try writeTask7Frame(
                JSONEncoder().encode(fixture.serverHello),
                fileDescriptor: serverDescriptor
            )
            let frameData = try readTask7Frame(fileDescriptor: serverDescriptor)
            let frame = try JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: frameData)
            let request = try JSONDecoder().decode(
                VaultAgentRequestEnvelope.self,
                from: fixture.openClientFrame(frame)
            )
            let response = VaultAgentResponseEnvelope(
                protocolVersion: request.protocolVersion,
                connectionID: request.connectionID,
                sequence: request.sequence,
                requestID: request.requestID,
                body: .success(.status(Self.readyStatus))
            )
            try writeTask7Frame(
                JSONEncoder().encode(try fixture.serverFrame(
                    JSONEncoder().encode(response),
                    sequence: request.sequence
                )),
                fileDescriptor: serverDescriptor
            )
        }

        #expect(try await client.request(.status) == .success(.status(Self.readyStatus)))
        try await serverTask.value
        let snapshot = probe.snapshot()
        #expect(snapshot.connectCount == 2)
        #expect(snapshot.launchCount == 0)
        #expect(snapshot.delays.isEmpty)
        await client.close()
        #expect(fcntl(clientDescriptor, F_GETFD) == -1)
        #expect(errno == EBADF)
    }

    @Test("a failed shared attempt is released so a later request can reconnect")
    func failedSharedAttemptCanReconnect() async throws {
        let socket = try VaultAgentSocketPair()
        let clientDescriptor = socket.takeClientDescriptor()
        let serverDescriptor = socket.takeServerDescriptor()
        let fixture = try VaultAgentClientCryptoFixture()
        let probe = VaultAgentRecoveryConnectProbe(descriptor: clientDescriptor)
        let client = VaultAgentClient(
            client: .codex,
            dependencies: socketDependencies(connect: { try probe.connect() })
        )
        let serverTask = Task.detached { () throws in
            defer { Darwin.close(serverDescriptor) }
            _ = try readTask7Frame(fileDescriptor: serverDescriptor)
            try writeTask7Frame(
                JSONEncoder().encode(fixture.serverHello),
                fileDescriptor: serverDescriptor
            )
            let frameData = try readTask7Frame(fileDescriptor: serverDescriptor)
            let frame = try JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: frameData)
            let request = try JSONDecoder().decode(
                VaultAgentRequestEnvelope.self,
                from: fixture.openClientFrame(frame)
            )
            let response = VaultAgentResponseEnvelope(
                protocolVersion: request.protocolVersion,
                connectionID: request.connectionID,
                sequence: request.sequence,
                requestID: request.requestID,
                body: .success(.status(Self.readyStatus))
            )
            try writeTask7Frame(
                JSONEncoder().encode(try fixture.serverFrame(
                    JSONEncoder().encode(response),
                    sequence: request.sequence
                )),
                fileDescriptor: serverDescriptor
            )
        }

        await #expect(throws: VaultAgentClientError.timedOut) {
            try await client.request(.status)
        }
        #expect(try await client.request(.status) == .success(.status(Self.readyStatus)))
        try await serverTask.value
        #expect(probe.snapshot() == 2)
        await client.close()
    }

    @Test("application launcher uses open without inheriting any standard stream")
    func applicationLauncherRoutesStandardStreamsToNull() throws {
        let applicationURL = URL(fileURLWithPath: "/Applications/Pastera.app")
        let process = VaultAgentClient.makeApplicationLaunchProcess(applicationURL)

        #expect(process.executableURL == URL(fileURLWithPath: "/usr/bin/open"))
        #expect(process.arguments == ["-gj", applicationURL.path])
        #expect(try isNullDevice(process.standardInput))
        #expect(try isNullDevice(process.standardOutput))
        #expect(try isNullDevice(process.standardError))
    }

    @Test("a failing child cannot emit its output through a null-routed process")
    func nullRoutedFailingChildDoesNotLeakOutput() throws {
        let process = VaultAgentClient.makeNullRoutedProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "printf PASTERA_CHILD_SENTINEL; printf PASTERA_CHILD_SENTINEL >&2; exit 7"
            ]
        )

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 7)
        #expect(try isNullDevice(process.standardOutput))
        #expect(try isNullDevice(process.standardError))
    }
    private func makeSocketClient(
        probe: VaultAgentSocketConnectProbe,
        now: @escaping @Sendable () -> UInt64 = { 0 }
    ) -> VaultAgentClient {
        VaultAgentClient(
            client: .codex,
            dependencies: .init(
                socketURL: { URL(fileURLWithPath: "/tmp/test-broker.sock") },
                executableURL: {
                    URL(fileURLWithPath: "/Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP")
                },
                launch: { _ in probe.didLaunch() },
                sleep: { probe.didSleep($0) },
                connect: { _, _ in try probe.connect() },
                nonce: { Data(repeating: 0x11, count: VaultAgentLimits.nonceBytes) },
                privateKey: {
                    try Curve25519.KeyAgreement.PrivateKey(
                        rawRepresentation: Data((0..<32).map(UInt8.init))
                    )
                },
                now: now
            )
        )
    }

    private func makeSharedSocketClient(
        probe: VaultAgentSharedConnectProbe,
        retryGate: VaultAgentAsyncGate? = nil
    ) -> VaultAgentClient {
        VaultAgentClient(
            client: .codex,
            dependencies: socketDependencies(
                sleep: { milliseconds in
                    probe.didSleep(milliseconds)
                    if let retryGate { await retryGate.enterAndWait() }
                },
                connect: { try probe.connect() },
                launch: { probe.didLaunch() }
            )
        )
    }

    private func socketDependencies(
        sleep: @escaping @Sendable (Int) async throws -> Void = { _ in },
        connect: @escaping @Sendable () throws -> Int32,
        launch: @escaping @Sendable () -> Void = {}
    ) -> VaultAgentClient.Dependencies {
        .init(
            socketURL: { URL(fileURLWithPath: "/tmp/test-broker.sock") },
            executableURL: {
                URL(fileURLWithPath: "/Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP")
            },
            launch: { _ in launch() },
            sleep: sleep,
            connect: { _, _ in try connect() },
            nonce: { Data(repeating: 0x11, count: VaultAgentLimits.nonceBytes) },
            privateKey: {
                try Curve25519.KeyAgreement.PrivateKey(
                    rawRepresentation: Data((0..<32).map(UInt8.init))
                )
            },
            now: { DispatchTime.now().uptimeNanoseconds }
        )
    }

    private static let readyStatus = VaultAgentStatus(
        client: .codex,
        installed: true,
        authorized: true,
        vaultReady: true,
        idleExpiresAt: nil,
        hardExpiresAt: nil,
        protocolVersion: VaultAgentLimits.protocolVersion
    )
}
// swiftlint:enable type_body_length

private final class VaultAgentRetryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let failuresBeforeSuccess: Int
    private(set) var connectCount = 0
    private(set) var launchCount = 0
    private(set) var delays: [Int] = []

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func connect() throws -> Int {
        try lock.withLock {
            connectCount += 1
            if connectCount <= failuresBeforeSuccess { throw VaultAgentClientError.unavailable }
            return 42
        }
    }

    func launch() {
        lock.withLock { launchCount += 1 }
    }

    func sleep(milliseconds: Int) {
        lock.withLock { delays.append(milliseconds) }
    }
}

private final class VaultAgentRetrierOutcomeProbe: @unchecked Sendable {
    enum Outcome {
        case success(Int)
        case failure(VaultAgentClientError)
    }

    struct Snapshot {
        let connectCount: Int
        let launchCount: Int
        let delays: [Int]
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var connectCount = 0
    private var launchCount = 0
    private var delays: [Int] = []

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    func connect() throws -> Int {
        try lock.withLock {
            connectCount += 1
            guard !outcomes.isEmpty else { throw VaultAgentClientError.unavailable }
            switch outcomes.removeFirst() {
            case let .success(value): return value
            case let .failure(error): throw error
            }
        }
    }

    func launch() { lock.withLock { launchCount += 1 } }
    func sleep(milliseconds: Int) { lock.withLock { delays.append(milliseconds) } }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(connectCount: connectCount, launchCount: launchCount, delays: delays)
        }
    }
}

private final class VaultAgentCancellationProbe: @unchecked Sendable {
    struct Snapshot {
        let connectCount: Int
        let launchCount: Int
        let delays: [Int]
    }

    private let lock = NSLock()
    private let cancellationConnectCount: Int
    private var connectCount = 0
    private var launchCount = 0
    private var delays: [Int] = []

    init(cancellationConnectCount: Int) {
        self.cancellationConnectCount = cancellationConnectCount
    }

    func connect() throws -> Int {
        try lock.withLock {
            connectCount += 1
            if connectCount == cancellationConnectCount { throw CancellationError() }
            throw VaultAgentClientError.unavailable
        }
    }

    func launch() { lock.withLock { launchCount += 1 } }
    func sleep(milliseconds: Int) { lock.withLock { delays.append(milliseconds) } }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(connectCount: connectCount, launchCount: launchCount, delays: delays)
        }
    }
}

private final class VaultAgentBlockingUnavailableProbe: @unchecked Sendable {
    struct Snapshot {
        let connectCount: Int
        let launchCount: Int
        let delays: [Int]
        let descriptor: Int32
    }

    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var connectCount = 0
    private var launchCount = 0
    private var delays: [Int] = []
    private let descriptor: Int32
    private var descriptorClosed = false

    init() throws {
        descriptor = Darwin.open("/dev/null", O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(.EMFILE) }
    }

    deinit {
        let shouldClose = lock.withLock { !descriptorClosed }
        if shouldClose { Darwin.close(descriptor) }
    }

    func connect() throws -> Int {
        let state = lock.withLock { () -> (Bool, [CheckedContinuation<Void, Never>]) in
            connectCount += 1
            guard connectCount == 1 else { return (false, []) }
            entered = true
            defer { enteredWaiters.removeAll() }
            return (true, enteredWaiters)
        }
        for waiter in state.1 { waiter.resume() }
        if state.0 {
            releaseSemaphore.wait()
            Darwin.close(descriptor)
            lock.withLock { descriptorClosed = true }
        }
        throw VaultAgentClientError.unavailable
    }

    func waitUntilConnectEntered() async {
        if lock.withLock({ entered }) { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                if entered { return true }
                enteredWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func releaseConnect() { releaseSemaphore.signal() }
    func launch() { lock.withLock { launchCount += 1 } }

    func sleepIgnoringCancellation(milliseconds: Int) {
        lock.withLock { delays.append(milliseconds) }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                connectCount: connectCount,
                launchCount: launchCount,
                delays: delays,
                descriptor: descriptor
            )
        }
    }
}

private final class VaultAgentScriptedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt64]

    init(values: [UInt64]) { self.values = values }

    func now() -> UInt64 {
        lock.withLock {
            guard values.count > 1 else { return values.first ?? 0 }
            return values.removeFirst()
        }
    }
}

private final class VaultAgentLaunchProbe: @unchecked Sendable {
    struct Snapshot {
        let connectCount: Int
        let launches: [URL]
        let delays: [Int]
    }

    private let lock = NSLock()
    private var connectCount = 0
    private var launches: [URL] = []
    private var delays: [Int] = []

    func connect() throws -> Int32 {
        try lock.withLock {
            connectCount += 1
            throw VaultAgentClientError.unavailable
        }
    }

    func didLaunch(_ applicationURL: URL) {
        lock.withLock { launches.append(applicationURL) }
    }

    func didSleep(_ milliseconds: Int) {
        lock.withLock { delays.append(milliseconds) }
    }

    func snapshot() -> Snapshot {
        lock.withLock { Snapshot(connectCount: connectCount, launches: launches, delays: delays) }
    }
}

private final class VaultAgentSocketConnectProbe: @unchecked Sendable {
    struct Snapshot {
        let connectCount: Int
        let launchCount: Int
        let delays: [Int]
    }

    private let lock = NSLock()
    private let descriptor: Int32
    private var connectCount = 0
    private var launchCount = 0
    private var delays: [Int] = []

    init(descriptor: Int32) { self.descriptor = descriptor }

    func connect() throws -> Int32 {
        try lock.withLock {
            connectCount += 1
            guard connectCount == 1 else { throw VaultAgentClientError.unavailable }
            return descriptor
        }
    }

    func didLaunch() { lock.withLock { launchCount += 1 } }
    func didSleep(_ milliseconds: Int) { lock.withLock { delays.append(milliseconds) } }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(connectCount: connectCount, launchCount: launchCount, delays: delays)
        }
    }
}

private actor VaultAgentAsyncGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private final class VaultAgentSharedConnectProbe: @unchecked Sendable {
    struct Snapshot {
        let connectCount: Int
        let launchCount: Int
        let delays: [Int]
    }

    private let lock = NSLock()
    private let descriptor: Int32
    private let initialFailure: Bool
    private var connectCount = 0
    private var launchCount = 0
    private var delays: [Int] = []

    init(descriptor: Int32, initialFailure: Bool = true) {
        self.descriptor = descriptor
        self.initialFailure = initialFailure
    }

    func connect() throws -> Int32 {
        try lock.withLock {
            connectCount += 1
            let successCount = initialFailure ? 2 : 1
            guard connectCount == successCount else {
                throw VaultAgentClientError.unavailable
            }
            return descriptor
        }
    }

    func didLaunch() { lock.withLock { launchCount += 1 } }
    func didSleep(_ milliseconds: Int) { lock.withLock { delays.append(milliseconds) } }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(connectCount: connectCount, launchCount: launchCount, delays: delays)
        }
    }
}

private final class VaultAgentRecoveryConnectProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let descriptor: Int32
    private var connectCount = 0

    init(descriptor: Int32) { self.descriptor = descriptor }

    func connect() throws -> Int32 {
        try lock.withLock {
            connectCount += 1
            if connectCount == 1 { throw VaultAgentClientError.timedOut }
            guard connectCount == 2 else { throw VaultAgentClientError.unavailable }
            return descriptor
        }
    }

    func snapshot() -> Int { lock.withLock { connectCount } }
}

private enum VaultAgentWaiterOutcome: Sendable, Equatable {
    case success
    case failure(VaultAgentClientError)
}

private actor VaultAgentWaiterOutcomeQueue {
    private var outcomes: [VaultAgentWaiterOutcome] = []
    private var waiter: CheckedContinuation<VaultAgentWaiterOutcome, Never>?

    func record(_ outcome: VaultAgentWaiterOutcome) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: outcome)
        } else {
            outcomes.append(outcome)
        }
    }

    func next() async -> VaultAgentWaiterOutcome {
        if !outcomes.isEmpty { return outcomes.removeFirst() }
        return await withCheckedContinuation { waiter = $0 }
    }
}

private final class VaultAgentCapacityConnectProbe: @unchecked Sendable {
    struct Snapshot {
        let connectCount: Int
        let launchCount: Int
        let delays: [Int]
    }

    private let lock = NSLock()
    private let firstRelease = DispatchSemaphore(value: 0)
    private var firstEntered = false
    private var firstFinished = false
    private var firstEnteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstFinishedWaiters: [CheckedContinuation<Void, Never>] = []
    private var successDescriptor: Int32?
    private var connectCount = 0
    private var launchCount = 0
    private var delays: [Int] = []

    func connect() throws -> Int32 {
        let state = lock.withLock { () -> (Int, [CheckedContinuation<Void, Never>]) in
            connectCount += 1
            guard connectCount == 1 else { return (connectCount, []) }
            firstEntered = true
            defer { firstEnteredWaiters.removeAll() }
            return (connectCount, firstEnteredWaiters)
        }
        for waiter in state.1 { waiter.resume() }
        if state.0 == 1 {
            firstRelease.wait()
            let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                firstFinished = true
                defer { firstFinishedWaiters.removeAll() }
                return firstFinishedWaiters
            }
            for waiter in waiters { waiter.resume() }
            throw VaultAgentClientError.unavailable
        }
        return try lock.withLock {
            guard let descriptor = successDescriptor else {
                throw VaultAgentClientError.unavailable
            }
            successDescriptor = nil
            return descriptor
        }
    }

    func waitUntilFirstConnectEntered() async {
        if lock.withLock({ firstEntered }) { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                if firstEntered { return true }
                firstEnteredWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func waitUntilFirstConnectFinished() async {
        if lock.withLock({ firstFinished }) { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                if firstFinished { return true }
                firstFinishedWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func releaseFirstConnect() { firstRelease.signal() }
    func enableSuccess(descriptor: Int32) { lock.withLock { successDescriptor = descriptor } }
    func didLaunch() { lock.withLock { launchCount += 1 } }
    func didSleep(_ milliseconds: Int) { lock.withLock { delays.append(milliseconds) } }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(connectCount: connectCount, launchCount: launchCount, delays: delays)
        }
    }
}

private final class VaultAgentAdvancingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func now() -> UInt64 {
        lock.withLock {
            defer { callCount += 1 }
            return callCount == 0 ? 0 : 10_000_000_001
        }
    }
}

private final class VaultAgentSocketPair {
    private var clientDescriptor: Int32
    private var serverDescriptor: Int32

    init() throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw POSIXError(.EMFILE)
        }
        clientDescriptor = descriptors[0]
        serverDescriptor = descriptors[1]
        let flags = fcntl(clientDescriptor, F_GETFL)
        guard flags >= 0,
              fcntl(clientDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            Darwin.close(clientDescriptor)
            Darwin.close(serverDescriptor)
            throw POSIXError(.EINVAL)
        }
        var enabled: Int32 = 1
        guard setsockopt(
            clientDescriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            Darwin.close(clientDescriptor)
            Darwin.close(serverDescriptor)
            throw POSIXError(.EINVAL)
        }
    }

    deinit {
        if clientDescriptor >= 0 { Darwin.close(clientDescriptor) }
        if serverDescriptor >= 0 { Darwin.close(serverDescriptor) }
    }

    func takeClientDescriptor() -> Int32 {
        defer { clientDescriptor = -1 }
        return clientDescriptor
    }

    func takeServerDescriptor() -> Int32 {
        defer { serverDescriptor = -1 }
        return serverDescriptor
    }

    func closeServerDescriptor() {
        guard serverDescriptor >= 0 else { return }
        Darwin.close(serverDescriptor)
        serverDescriptor = -1
    }

    func writeServer(_ data: Data) throws {
        var remaining = data
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes {
                Darwin.write(serverDescriptor, $0.baseAddress, $0.count)
            }
            guard written > 0 else { throw POSIXError(.EIO) }
            remaining = remaining.dropFirst(written)
        }
    }
}

private struct VaultAgentClientCryptoFixture {
    private let clientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    private let serverPrivateKey: Curve25519.KeyAgreement.PrivateKey
    let clientNonce = Data(repeating: 0x11, count: VaultAgentLimits.nonceBytes)
    private let serverNonce = Data(repeating: 0x22, count: VaultAgentLimits.nonceBytes)
    let connectionID = UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!
    private let key: SymmetricKey

    init() throws {
        clientPrivateKey = try .init(rawRepresentation: Data((0..<32).map(UInt8.init)))
        serverPrivateKey = try .init(rawRepresentation: Data((32..<64).map(UInt8.init)))
        let sharedSecret = try serverPrivateKey.sharedSecretFromKeyAgreement(
            with: clientPrivateKey.publicKey
        )
        var info = Data("PasteraVaultAgent/v1".utf8)
        info.append(0)
        info.append(Self.uuidBytes(connectionID))
        key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: clientNonce + serverNonce,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    var clientPublicKey: Data { clientPrivateKey.publicKey.rawRepresentation }
    var serverHello: VaultAgentServerHello {
        .init(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: connectionID,
            publicKey: serverPrivateKey.publicKey.rawRepresentation,
            nonce: serverNonce
        )
    }

    func makeClientChannel() throws -> VaultAgentClientSecureChannel {
        try .init(
            privateKey: clientPrivateKey,
            peerPublicKey: serverPrivateKey.publicKey.rawRepresentation,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID,
            deterministicNonce: true
        )
    }

    func serverFrame(_ plaintext: Data, sequence: UInt64) throws -> VaultAgentEncryptedFrame {
        var nonce = Data([2, 0, 0, 0])
        var encodedSequence = sequence.bigEndian
        withUnsafeBytes(of: &encodedSequence) { nonce.append(contentsOf: $0) }
        let box = try ChaChaPoly.seal(
            plaintext,
            using: key,
            nonce: try .init(data: nonce),
            authenticating: Self.authenticatedData(
                connectionID: connectionID,
                direction: 2,
                sequence: sequence
            )
        )
        return .init(
            connectionID: connectionID,
            sequence: sequence,
            ciphertext: box.combined
        )
    }

    func openClientFrame(_ frame: VaultAgentEncryptedFrame) throws -> Data {
        guard frame.connectionID == connectionID else {
            throw VaultAgentProtocolError.connectionMismatch
        }
        let box = try ChaChaPoly.SealedBox(combined: frame.ciphertext)
        return try ChaChaPoly.open(
            box,
            using: key,
            authenticating: Self.authenticatedData(
                connectionID: connectionID,
                direction: 1,
                sequence: frame.sequence
            )
        )
    }

    private static func authenticatedData(
        connectionID: UUID,
        direction: UInt8,
        sequence: UInt64
    ) -> Data {
        var data = Data("PVA1".utf8)
        var version = UInt32(VaultAgentLimits.protocolVersion).bigEndian
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        data.append(uuidBytes(connectionID))
        data.append(direction)
        var encodedSequence = sequence.bigEndian
        withUnsafeBytes(of: &encodedSequence) { data.append(contentsOf: $0) }
        return data
    }

    private static func uuidBytes(_ value: UUID) -> Data {
        let bytes = value.uuid
        return Data([
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15
        ])
    }
}

private func readTask7Frame(fileDescriptor: Int32) throws -> Data {
    let prefix = try readTask7Exactly(4, fileDescriptor: fileDescriptor)
    let length = prefix.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
    guard length <= UInt32(VaultAgentLimits.maximumFrameBytes - 4) else {
        throw VaultAgentProtocolError.frameTooLarge
    }
    return try readTask7Exactly(Int(length), fileDescriptor: fileDescriptor)
}

private func readTask7Exactly(_ count: Int, fileDescriptor: Int32) throws -> Data {
    var result = Data()
    while result.count < count {
        var bytes = [UInt8](repeating: 0, count: count - result.count)
        let readCount = Darwin.read(fileDescriptor, &bytes, bytes.count)
        guard readCount > 0 else { throw VaultAgentClientError.unavailable }
        result.append(contentsOf: bytes.prefix(readCount))
    }
    return result
}

private func writeTask7Frame(_ payload: Data, fileDescriptor: Int32) throws {
    var remaining = try VaultAgentFrameCodec.frame(payload: payload)
    while !remaining.isEmpty {
        let written = remaining.withUnsafeBytes {
            Darwin.write(fileDescriptor, $0.baseAddress, $0.count)
        }
        guard written > 0 else { throw VaultAgentClientError.unavailable }
        remaining = remaining.dropFirst(written)
    }
}

private func isNullDevice(_ stream: Any?) throws -> Bool {
    guard let fileHandle = stream as? FileHandle else { return false }
    return fileHandle === FileHandle.nullDevice
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
