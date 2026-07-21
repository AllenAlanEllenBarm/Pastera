import Darwin
import Foundation

private func fail() -> Never { exit(64) }

Darwin.signal(SIGTERM, SIG_DFL)

var arguments = Array(CommandLine.arguments.dropFirst())
var inputFD: Int32?
var exitCode: Int32 = 0
var exitWithCount = false
var signalNumber: Int32?
var sleepMilliseconds = 0
var ignoresTermination = false
var index = 0

while index < arguments.count {
    switch arguments[index] {
    case "--stdin":
        guard inputFD == nil else { fail() }
        inputFD = STDIN_FILENO
        index += 1
    case "--fd":
        guard inputFD == nil, index + 1 < arguments.count,
              let value = Int32(arguments[index + 1]), (3...255).contains(value) else { fail() }
        inputFD = value
        index += 2
    case "--exit":
        guard index + 1 < arguments.count,
              let value = Int32(arguments[index + 1]), (0...125).contains(value) else { fail() }
        exitCode = value
        index += 2
    case "--exit-count":
        exitWithCount = true
        index += 1
    case "--signal":
        guard index + 1 < arguments.count,
              let value = Int32(arguments[index + 1]), (1...31).contains(value) else { fail() }
        signalNumber = value
        index += 2
    case "--sleep-ms":
        guard index + 1 < arguments.count,
              let value = Int(arguments[index + 1]), (0...60_000).contains(value) else { fail() }
        sleepMilliseconds = value
        index += 2
    case "--ignore-term":
        ignoresTermination = true
        index += 1
    default:
        fail()
    }
}

guard let inputFD else { fail() }
if ignoresTermination { Darwin.signal(SIGTERM, SIG_IGN) }
if sleepMilliseconds > 0 {
    usleep(useconds_t(sleepMilliseconds * 1_000))
}

var count = 0
var buffer = [UInt8](repeating: 0, count: 1_024)

while true {
    let result = Darwin.read(inputFD, &buffer, buffer.count)
    if result > 0 {
        count += result
    } else if result == 0 {
        break
    } else if errno != EINTR {
        fail()
    }
}

let output = Data("\(count)\n".utf8)

_ = output.withUnsafeBytes { Darwin.write(STDOUT_FILENO, $0.baseAddress, output.count) }
if let signalNumber {
    Darwin.kill(Darwin.getpid(), signalNumber)
    pause()
}
exit(exitWithCount ? Int32(min(count, 125)) : exitCode)
