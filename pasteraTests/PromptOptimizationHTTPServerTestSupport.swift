import Darwin
import Foundation

final class LoopbackHTTPServer: @unchecked Sendable {
    enum Response {
        case json(String)
        case redirect(statusCode: Int, location: URL)
        case sameOriginRedirect(statusCode: Int, path: String)

        func wireValue(serverURL: URL) -> Data {
            switch self {
            case let .json(body):
                let bodyData = Data(body.utf8)
                return Data((
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" +
                        "Content-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
                ).utf8) + bodyData
            case let .redirect(statusCode, location):
                return Data((
                    "HTTP/1.1 \(statusCode) Temporary Redirect\r\n" +
                        "Location: \(location.absoluteString)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                ).utf8)
            case let .sameOriginRedirect(statusCode, path):
                return Response.redirect(
                    statusCode: statusCode,
                    location: serverURL.appendingPathComponent(path)
                ).wireValue(serverURL: serverURL)
            }
        }
    }

    struct Request {
        let method: String
        let headers: [String: String]
        let body: Data
        var authorization: String? { headers["authorization"] }
    }

    let url: URL
    private let listener: Int32
    private let responses: [Response]
    private let queue = DispatchQueue(label: "PromptOptimizationHTTPServerTestSupport")
    private let lock = NSLock()
    private var capturedRequests: [Request] = []

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    convenience init(response: Response) throws {
        try self.init(responses: [response])
    }

    init(responses: [Response]) throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(listener, Int32(responses.count)) == 0 else {
            Darwin.close(listener)
            throw POSIXError(.EADDRINUSE)
        }
        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listener, $0, &boundAddressLength)
            }
        }
        guard nameResult == 0,
              let url = URL(string: "http://127.0.0.1:\(Int(UInt16(bigEndian: boundAddress.sin_port)))") else {
            Darwin.close(listener)
            throw POSIXError(.EIO)
        }
        self.listener = listener
        self.responses = responses
        self.url = url
        queue.async { [self] in acceptRequests() }
    }

    deinit { Darwin.close(listener) }

    private func acceptRequests() {
        for response in responses {
            let connection = Darwin.accept(listener, nil, nil)
            guard connection >= 0 else { return }
            guard let request = Self.readRequest(from: connection) else {
                Darwin.close(connection)
                return
            }
            lock.lock()
            capturedRequests.append(request)
            lock.unlock()
            Self.write(response.wireValue(serverURL: url), to: connection)
            Darwin.close(connection)
        }
    }

    private static func readRequest(from connection: Int32) -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        var data = Data()
        var expectedLength: Int?
        while expectedLength.map({ data.count < $0 }) ?? true {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(connection, &buffer, buffer.count)
            guard count > 0 else { return nil }
            data.append(contentsOf: buffer.prefix(count))
            if expectedLength == nil,
               let range = data.range(of: separator),
               let header = String(data: data[..<range.lowerBound], encoding: .utf8) {
                let length = header.components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                expectedLength = range.upperBound + length
            }
        }
        guard let range = data.range(of: separator),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return Request(
            method: lines.first?.split(separator: " ").first.map(String.init) ?? "",
            headers: headers,
            body: Data(data[range.upperBound...])
        )
    }

    private static func write(_ data: Data, to connection: Int32) {
        data.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let count = Darwin.write(connection, pointer, remaining)
                guard count > 0 else { return }
                remaining -= count
                pointer = pointer.advanced(by: count)
            }
        }
    }
}
