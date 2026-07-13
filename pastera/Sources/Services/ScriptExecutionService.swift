import Foundation
import JavaScriptCore

struct ScriptExecutionInput: Equatable, Sendable {
    let text: String
    let sourceAppBundleIdentifier: String?
}

enum ScriptExecutionError: Error, Equatable, Sendable {
    case inputTooLarge
    case sourceTooLarge(scriptID: UUID)
    case missingTransform(scriptID: UUID)
    case javaScriptException(scriptID: UUID)
    case invalidResult(scriptID: UUID)
    case timeout(scriptID: UUID)
    case capacityExhausted

    var scriptID: UUID? {
        switch self {
        case .inputTooLarge, .capacityExhausted:
            return nil
        case let .sourceTooLarge(scriptID),
             let .missingTransform(scriptID),
             let .javaScriptException(scriptID),
             let .invalidResult(scriptID),
             let .timeout(scriptID):
            return scriptID
        }
    }
}

protocol ScriptExecuting {
    func execute(
        scripts: [ScriptTransform],
        input: ScriptExecutionInput
    ) async -> Result<String, ScriptExecutionError>
}

final class ScriptExecutionService: ScriptExecuting {
    private let timeout: TimeInterval
    private let maximumSourceUTF8Bytes: Int
    private let maximumInputUTF8Bytes: Int
    private let maximumConcurrentExecutions: Int
    private let workerQueue = DispatchQueue(
        label: "com.pastera.script-execution",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let capacityLock = NSLock()
    private var activeExecutions = 0

    init(
        timeout: TimeInterval = 0.25,
        maximumSourceUTF8Bytes: Int = 256 * 1_024,
        maximumInputUTF8Bytes: Int = 2 * 1_024 * 1_024,
        maximumConcurrentExecutions: Int = 2
    ) {
        self.timeout = timeout
        self.maximumSourceUTF8Bytes = maximumSourceUTF8Bytes
        self.maximumInputUTF8Bytes = maximumInputUTF8Bytes
        self.maximumConcurrentExecutions = maximumConcurrentExecutions
    }

    func execute(
        scripts: [ScriptTransform],
        input: ScriptExecutionInput
    ) async -> Result<String, ScriptExecutionError> {
        guard input.text.utf8.count <= maximumInputUTF8Bytes else {
            return .failure(.inputTooLarge)
        }
        if let oversized = scripts.first(where: { $0.code.utf8.count > maximumSourceUTF8Bytes }) {
            return .failure(.sourceTooLarge(scriptID: oversized.id))
        }
        guard !scripts.isEmpty else { return .success(input.text) }
        guard reserveCapacity() else { return .failure(.capacityExhausted) }

        return await withCheckedContinuation { continuation in
            let state = ScriptExecutionState(initialScriptID: scripts[0].id, continuation: continuation)
            workerQueue.async { [weak self] in
                guard let self else { return }
                let result = self.evaluatePipeline(scripts: scripts, input: input, state: state)
                self.releaseCapacity()
                state.resumeIfPending(with: result)
            }
            workerQueue.asyncAfter(deadline: .now() + timeout) {
                state.resumeIfPending(with: .failure(.timeout(scriptID: state.currentScriptID)))
            }
        }
    }

    private func evaluatePipeline(
        scripts: [ScriptTransform],
        input: ScriptExecutionInput,
        state: ScriptExecutionState
    ) -> Result<String, ScriptExecutionError> {
        var text = input.text
        for script in scripts {
            state.currentScriptID = script.id
            switch evaluate(script: script, text: text, sourceAppBundleIdentifier: input.sourceAppBundleIdentifier) {
            case let .success(output):
                text = output
            case let .failure(error):
                return .failure(error)
            }
        }
        return .success(text)
    }

    private func evaluate(
        script: ScriptTransform,
        text: String,
        sourceAppBundleIdentifier: String?
    ) -> Result<String, ScriptExecutionError> {
        guard let context = JSContext() else {
            return .failure(.javaScriptException(scriptID: script.id))
        }
        var didRaiseException = false
        context.exceptionHandler = { _, _ in
            didRaiseException = true
        }
        context.evaluateScript(script.code)
        guard !didRaiseException else {
            return .failure(.javaScriptException(scriptID: script.id))
        }
        guard let function = context.objectForKeyedSubscript("transform"),
              !function.isUndefined else {
            return .failure(.missingTransform(scriptID: script.id))
        }

        let clip = JSValue(newObjectIn: context)
        clip?.setValue(text, forProperty: "text")
        clip?.setValue(sourceAppBundleIdentifier, forProperty: "sourceAppBundleIdentifier")
        let value = function.call(withArguments: [clip as Any])
        guard !didRaiseException else {
            return .failure(.javaScriptException(scriptID: script.id))
        }
        guard let value, value.isString else {
            return .failure(.invalidResult(scriptID: script.id))
        }
        return .success(value.toString())
    }

    private func reserveCapacity() -> Bool {
        capacityLock.lock()
        defer { capacityLock.unlock() }
        guard activeExecutions < maximumConcurrentExecutions else { return false }
        activeExecutions += 1
        return true
    }

    private func releaseCapacity() {
        capacityLock.lock()
        activeExecutions -= 1
        capacityLock.unlock()
    }
}

private final class ScriptExecutionState {
    private let lock = NSLock()
    private var scriptID: UUID
    private var continuation: CheckedContinuation<Result<String, ScriptExecutionError>, Never>?

    init(
        initialScriptID: UUID,
        continuation: CheckedContinuation<Result<String, ScriptExecutionError>, Never>
    ) {
        self.scriptID = initialScriptID
        self.continuation = continuation
    }

    var currentScriptID: UUID {
        get {
            lock.lock()
            defer { lock.unlock() }
            return scriptID
        }
        set {
            lock.lock()
            scriptID = newValue
            lock.unlock()
        }
    }

    func resumeIfPending(with result: Result<String, ScriptExecutionError>) {
        lock.lock()
        let pendingContinuation = continuation
        continuation = nil
        lock.unlock()
        pendingContinuation?.resume(returning: result)
    }
}
