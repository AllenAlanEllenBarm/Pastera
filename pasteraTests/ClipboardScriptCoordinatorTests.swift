import Foundation
import Testing
@testable import Pastera

struct ClipboardScriptCoordinatorTests {
    @Test
    func defaultEnvironmentExposesSharedScriptCoordinator() {
        let environment = Environment()

        #expect(environment.clipboardScriptCoordinator is ClipboardScriptCoordinator)
    }

    @Test
    func reportsWhetherTriggerHasEnabledScripts() {
        let coordinator = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [makeScript(runOnCopy: true)]),
            executor: RecordingScriptExecutor(result: .success("unused")),
            pasteboard: TestScriptPasteboard(text: "hello")
        )

        #expect(coordinator.hasEnabledScripts(for: .copy))
        #expect(!coordinator.hasEnabledScripts(for: .paste))
    }

    @Test
    func transformUsesMatchingScriptsAndMapsSuccess() async {
        let script = makeScript(runOnCopy: true)
        let executor = RecordingScriptExecutor(result: .success("HELLO"))
        let coordinator = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [script]),
            executor: executor,
            pasteboard: TestScriptPasteboard(text: "hello")
        )

        let outcome = await coordinator.transform(
            text: "hello",
            sourceAppBundleIdentifier: "com.example.app",
            trigger: .copy
        )

        #expect(outcome == .transformed("HELLO"))
        #expect(executor.receivedScripts == [script])
        #expect(executor.receivedInput == .init(text: "hello", sourceAppBundleIdentifier: "com.example.app"))
    }

    @Test
    func transformReturnsUnchangedWithoutMatchingScripts() async {
        let coordinator = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [makeScript(runOnPaste: true)]),
            executor: RecordingScriptExecutor(result: .success("unused")),
            pasteboard: TestScriptPasteboard(text: "hello")
        )

        let outcome = await coordinator.transform(text: "hello", sourceAppBundleIdentifier: nil, trigger: .copy)

        #expect(outcome == .unchanged)
    }

    @Test
    func repositoryAndExecutionFailuresPreserveOriginalValue() async {
        let script = makeScript(runOnCopy: true)
        let repositoryFailure = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [], error: TestRepositoryError.failed),
            executor: RecordingScriptExecutor(result: .success("unused")),
            pasteboard: TestScriptPasteboard(text: "original")
        )
        let executionFailure = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [script]),
            executor: RecordingScriptExecutor(result: .failure(.invalidResult(scriptID: script.id))),
            pasteboard: TestScriptPasteboard(text: "original")
        )

        #expect(await repositoryFailure.transform(text: "original", sourceAppBundleIdentifier: nil, trigger: .copy) == .unchanged)
        #expect(
            await executionFailure.transform(text: "original", sourceAppBundleIdentifier: nil, trigger: .copy)
                == .failed(.invalidResult(scriptID: script.id))
        )
    }

    @Test
    func manualTransformWritesOnceAndSuppressionIsConsumedOnce() async {
        let script = makeScript(runManually: true)
        let pasteboard = TestScriptPasteboard(text: "hello")
        let coordinator = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [script]),
            executor: RecordingScriptExecutor(result: .success("HELLO")),
            pasteboard: pasteboard
        )

        await coordinator.runManualTransform()

        #expect(pasteboard.text == "HELLO")
        #expect(pasteboard.writeCount == 1)
        #expect(coordinator.consumeSuppression(changeCount: pasteboard.changeCount))
        #expect(!coordinator.consumeSuppression(changeCount: pasteboard.changeCount))
    }

    @Test
    func manualTransformSkipsMissingTextAndFailure() async {
        let script = makeScript(runManually: true)
        let emptyPasteboard = TestScriptPasteboard(text: nil)
        let failedPasteboard = TestScriptPasteboard(text: "hello")
        let emptyCoordinator = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [script]),
            executor: RecordingScriptExecutor(result: .success("unused")),
            pasteboard: emptyPasteboard
        )
        let failedCoordinator = ClipboardScriptCoordinator(
            repository: StaticScriptRepository(scripts: [script]),
            executor: RecordingScriptExecutor(result: .failure(.timeout(scriptID: script.id))),
            pasteboard: failedPasteboard
        )

        await emptyCoordinator.runManualTransform()
        await failedCoordinator.runManualTransform()

        #expect(emptyPasteboard.writeCount == 0)
        #expect(failedPasteboard.writeCount == 0)
        #expect(failedPasteboard.text == "hello")
    }

    private func makeScript(
        runOnCopy: Bool = false,
        runOnPaste: Bool = false,
        runManually: Bool = false
    ) -> ScriptTransform {
        ScriptTransform(
            id: UUID(),
            name: "Test",
            code: "function transform(clip) { return clip.text; }",
            isEnabled: true,
            runOnCopy: runOnCopy,
            runOnPaste: runOnPaste,
            runManually: runManually,
            sortIndex: 0,
            createdAt: 0,
            updatedAt: 0
        )
    }
}

private enum TestRepositoryError: Error {
    case failed
}

private struct StaticScriptRepository: ScriptRepositoryProtocol {
    let scripts: [ScriptTransform]
    var error: Error?

    func fetchAll() throws -> [ScriptTransform] { scripts }
    func fetchEnabled(for trigger: ScriptTrigger) throws -> [ScriptTransform] {
        if let error { throw error }
        return scripts.filter { $0.runs(on: trigger) }
    }
    func insert(_ script: ScriptTransform) throws {}
    func update(_ script: ScriptTransform) throws {}
    func delete(id: UUID) throws {}
    func replaceOrder(ids: [UUID]) throws {}
}

private final class RecordingScriptExecutor: ScriptExecuting {
    let result: Result<String, ScriptExecutionError>
    private(set) var receivedScripts = [ScriptTransform]()
    private(set) var receivedInput: ScriptExecutionInput?

    init(result: Result<String, ScriptExecutionError>) {
        self.result = result
    }

    func execute(
        scripts: [ScriptTransform],
        input: ScriptExecutionInput
    ) async -> Result<String, ScriptExecutionError> {
        receivedScripts = scripts
        receivedInput = input
        return result
    }
}

private final class TestScriptPasteboard: ScriptPasteboard {
    var text: String?
    private(set) var changeCount = 0
    private(set) var writeCount = 0

    init(text: String?) {
        self.text = text
    }

    func readString() -> String? { text }

    @discardableResult
    func writeString(_ string: String) -> Int {
        text = string
        writeCount += 1
        changeCount += 1
        return changeCount
    }
}
