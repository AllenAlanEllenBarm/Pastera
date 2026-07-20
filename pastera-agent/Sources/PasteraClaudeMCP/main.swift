import Darwin
import Dispatch
import Foundation
import PasteraAgentAdapter
import PasteraAgentProtocol

Darwin.signal(SIGPIPE, SIG_IGN)
Darwin.signal(SIGTERM, SIG_IGN)

let arguments = Array(CommandLine.arguments.dropFirst())
let client = VaultAgentClient(client: .claude)

if arguments.isEmpty {
    let server = PasteraMCPServer(client: client)
    let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
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
} else {
    guard let command = try? VaultCLICommand.parse(arguments), case .exec = command else {
        VaultCLIOutputWriter.write(.init(exitCode: 2, stdout: "", stderr: "INVALID_REQUEST\n"))
        exit(2)
    }

    let application = VaultCLIApplication(client: client)
    let executionTask = Task {
        await application.run(arguments: arguments)
    }
    let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    terminationSource.setEventHandler {
        executionTask.cancel()
    }
    terminationSource.resume()
    defer { terminationSource.cancel() }

    let result = await executionTask.value
    VaultCLIOutputWriter.write(result)
    exit(Int32(result.exitCode))
}
