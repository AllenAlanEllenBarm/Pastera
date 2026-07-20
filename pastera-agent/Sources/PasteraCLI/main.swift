import Darwin
import Dispatch
import Foundation
import PasteraAgentAdapter
import PasteraAgentProtocol

Darwin.signal(SIGPIPE, SIG_IGN)
Darwin.signal(SIGTERM, SIG_IGN)

let arguments = Array(CommandLine.arguments.dropFirst())
let application = VaultCLIApplication(client: VaultAgentClient(client: .cli))
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
