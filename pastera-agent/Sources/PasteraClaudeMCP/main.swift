import Darwin
import Dispatch
import PasteraAgentAdapter
import PasteraAgentProtocol

Darwin.signal(SIGPIPE, SIG_IGN)
Darwin.signal(SIGTERM, SIG_IGN)

let server = PasteraMCPServer(client: VaultAgentClient(client: .claude))
let terminationSource = DispatchSource.makeSignalSource(
    signal: SIGTERM,
    queue: .main
)

terminationSource.setEventHandler {
    Task { await server.stop() }
}
terminationSource.resume()
defer { terminationSource.cancel() }

do {
    try await server.run()
} catch {
    exit(EXIT_FAILURE)
}
