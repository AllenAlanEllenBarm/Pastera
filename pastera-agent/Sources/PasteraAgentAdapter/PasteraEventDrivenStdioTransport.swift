import Darwin
import Dispatch
import Foundation
import Logging
import MCP
import PasteraAgentProtocol

actor PasteraEventDrivenStdioTransport: Transport {
    nonisolated let logger: Logger

    private let state: PasteraEventDrivenStdioState

    init(
        inputFileDescriptor: Int32 = STDIN_FILENO,
        outputFileDescriptor: Int32 = STDOUT_FILENO,
        readObserver: @escaping @Sendable () -> Void = {}
    ) {
        logger = Logger(
            label: "pastera.mcp.transport.stdio",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )
        state = PasteraEventDrivenStdioState(
            inputFileDescriptor: inputFileDescriptor,
            outputFileDescriptor: outputFileDescriptor,
            readObserver: readObserver
        )
    }

    func connect() async throws {
        try state.connect()
    }

    func disconnect() async {
        state.disconnect()
    }

    func send(_ data: Data) async throws {
        try await state.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        state.messageStream
    }
}

private final class PasteraEventDrivenStdioState: @unchecked Sendable {
    private static let maximumBufferedMessages = 8
    private static let maximumBufferedOutputBytes =
        maximumBufferedMessages * (VaultAgentLimits.maximumFrameBytes + 1)

    private struct PendingWrite {
        let data: Data
        var offset: Int
        let continuation: CheckedContinuation<Void, Error>
    }

    let messageStream: AsyncThrowingStream<Data, Error>

    private let inputFileDescriptor: Int32
    private let outputFileDescriptor: Int32
    private let readObserver: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.pastera-app.Pastera.mcp-stdio")
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var pendingInput = Data()
    private var pendingWrites = [PendingWrite]()
    private var pendingWriteBytes = 0
    private var connected = false
    private var finished = false

    init(
        inputFileDescriptor: Int32,
        outputFileDescriptor: Int32,
        readObserver: @escaping @Sendable () -> Void
    ) {
        self.inputFileDescriptor = inputFileDescriptor
        self.outputFileDescriptor = outputFileDescriptor
        self.readObserver = readObserver
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        messageStream = AsyncThrowingStream(
            bufferingPolicy: .bufferingOldest(Self.maximumBufferedMessages)
        ) { continuation = $0 }
        self.continuation = continuation
    }

    func connect() throws {
        try queue.sync {
            guard !connected, !finished else { return }
            try Self.setNonBlocking(inputFileDescriptor)
            try Self.setNonBlocking(outputFileDescriptor)
            guard fcntl(outputFileDescriptor, F_SETNOSIGPIPE, 1) >= 0 else {
                throw Self.currentPOSIXError()
            }
            connected = true
            let source = DispatchSource.makeReadSource(
                fileDescriptor: inputFileDescriptor,
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.readAvailableData() }
            readSource = source
            source.resume()
        }
    }

    func disconnect() {
        queue.sync { finish() }
    }

    func send(_ data: Data) async throws {
        var framed = data
        framed.append(UInt8(ascii: "\n"))
        let framedData = framed
        guard framedData.count <= VaultAgentLimits.maximumFrameBytes + 1 else {
            throw POSIXError(.EMSGSIZE)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self, connected, !finished else {
                    continuation.resume(throwing: POSIXError(.ENOTCONN))
                    return
                }
                guard pendingWrites.count < Self.maximumBufferedMessages,
                      pendingWriteBytes + framedData.count <= Self.maximumBufferedOutputBytes else {
                    continuation.resume(throwing: POSIXError(.ENOBUFS))
                    finish(error: POSIXError(.ENOBUFS))
                    return
                }
                pendingWrites.append(PendingWrite(
                    data: framedData,
                    offset: 0,
                    continuation: continuation
                ))
                pendingWriteBytes += framedData.count
                pumpWrites()
            }
        }
    }

    private func readAvailableData() {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while connected, !finished {
            readObserver()
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(inputFileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count > 0 {
                pendingInput.append(contentsOf: buffer.prefix(count))
                yieldCompleteMessages()
                guard !finished else { return }
                guard pendingInput.count <= VaultAgentLimits.maximumFrameBytes else {
                    finish(error: POSIXError(.EMSGSIZE))
                    return
                }
                continue
            }
            if count == 0 {
                finish()
                return
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            finish(error: Self.currentPOSIXError())
            return
        }
    }

    private func yieldCompleteMessages() {
        while let newline = pendingInput.firstIndex(of: UInt8(ascii: "\n")) {
            let message = Data(pendingInput[..<newline])
            pendingInput.removeSubrange(...newline)
            guard message.count <= VaultAgentLimits.maximumFrameBytes else {
                finish(error: POSIXError(.EMSGSIZE))
                return
            }
            guard !message.isEmpty else { continue }
            switch continuation.yield(message) {
            case .enqueued:
                break
            case .dropped:
                finish(error: POSIXError(.ENOBUFS))
                return
            case .terminated:
                finish()
                return
            @unknown default:
                finish(error: POSIXError(.EIO))
                return
            }
        }
    }

    private func pumpWrites() {
        while connected, !finished, !pendingWrites.isEmpty {
            let current = pendingWrites[0]
            let remaining = current.data.count - current.offset
            let written = current.data.withUnsafeBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.write(
                    outputFileDescriptor,
                    baseAddress.advanced(by: current.offset),
                    remaining
                )
            }
            if written > 0 {
                pendingWrites[0].offset += written
                if pendingWrites[0].offset == pendingWrites[0].data.count {
                    let completed = pendingWrites.removeFirst()
                    pendingWriteBytes -= completed.data.count
                    completed.continuation.resume()
                }
                continue
            }
            if written == -1, errno == EINTR { continue }
            if written == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                installWriteSourceIfNeeded()
                return
            }
            finish(error: Self.currentPOSIXError())
            return
        }
        if pendingWrites.isEmpty {
            writeSource?.cancel()
            writeSource = nil
        }
    }

    private func installWriteSourceIfNeeded() {
        guard writeSource == nil else { return }
        let source = DispatchSource.makeWriteSource(
            fileDescriptor: outputFileDescriptor,
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.pumpWrites() }
        writeSource = source
        source.resume()
    }

    private func finish(error: Error? = nil) {
        guard !finished else { return }
        connected = false
        finished = true
        readSource?.cancel()
        readSource = nil
        writeSource?.cancel()
        writeSource = nil
        let writes = pendingWrites
        pendingWrites.removeAll(keepingCapacity: false)
        pendingWriteBytes = 0
        let terminalError = error ?? POSIXError(.ECANCELED)
        writes.forEach { $0.continuation.resume(throwing: terminalError) }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    private static func setNonBlocking(_ fileDescriptor: Int32) throws {
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0 else { throw currentPOSIXError() }
        guard fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw currentPOSIXError()
        }
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
