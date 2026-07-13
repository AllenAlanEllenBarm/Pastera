import Foundation
import Testing
@testable import Pastera

struct ScriptExecutionServiceTests {
    @Test
    func executesOrderedAtomicPipeline() async throws {
        let service = ScriptExecutionService(timeout: 0.5)
        let scripts = [
            makeScript(code: "function transform(clip) { return clip.text.trim(); }", sortIndex: 0),
            makeScript(code: "function transform(clip) { return clip.text.toUpperCase(); }", sortIndex: 1)
        ]

        let result = await service.execute(
            scripts: scripts,
            input: ScriptExecutionInput(text: " hello ", sourceAppBundleIdentifier: "com.example.editor")
        )

        #expect(try result.get() == "HELLO")
    }

    @Test
    func acceptsEmptyStringOutput() async throws {
        let service = ScriptExecutionService(timeout: 0.5)
        let script = makeScript(code: "function transform(clip) { return ''; }")

        let result = await service.execute(scripts: [script], input: .init(text: "hello", sourceAppBundleIdentifier: nil))

        #expect(try result.get() == "")
    }

    @Test(arguments: [
        "let value = 1;",
        "function transform(clip) { throw new Error('secret clipboard text'); }",
        "function transform(clip) { return 42; }"
    ])
    func reportsContractFailuresWithoutReturningInput(_ code: String) async {
        let service = ScriptExecutionService(timeout: 0.5)
        let script = makeScript(code: code)

        let result = await service.execute(scripts: [script], input: .init(text: "private input", sourceAppBundleIdentifier: nil))

        switch result {
        case .success:
            Issue.record("Expected the script contract to fail")
        case let .failure(error):
            #expect(error.scriptID == script.id)
        }
    }

    @Test
    func failureDoesNotExposePartialPipelineOutput() async {
        let service = ScriptExecutionService(timeout: 0.5)
        let first = makeScript(code: "function transform(clip) { return 'partial'; }", sortIndex: 0)
        let second = makeScript(code: "function transform(clip) { throw new Error('failed'); }", sortIndex: 1)

        let result = await service.execute(
            scripts: [first, second],
            input: .init(text: "original", sourceAppBundleIdentifier: nil)
        )

        #expect(result == .failure(.javaScriptException(scriptID: second.id)))
    }

    @Test
    func enforcesSourceAndInputLimitsBeforeExecution() async {
        let service = ScriptExecutionService(timeout: 0.5, maximumSourceUTF8Bytes: 32, maximumInputUTF8Bytes: 8)
        let oversizedSource = makeScript(code: String(repeating: "x", count: 33))
        let normal = makeScript(code: "function transform(clip) { return clip.text; }")

        #expect(
            await service.execute(scripts: [oversizedSource], input: .init(text: "ok", sourceAppBundleIdentifier: nil))
                == .failure(.sourceTooLarge(scriptID: oversizedSource.id))
        )
        #expect(
            await service.execute(scripts: [normal], input: .init(text: "123456789", sourceAppBundleIdentifier: nil))
                == .failure(.inputTooLarge)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func infiniteLoopTimesOutAndOccupiesBoundedCapacity() async {
        let service = ScriptExecutionService(timeout: 0.05, maximumConcurrentExecutions: 1)
        let infinite = makeScript(code: "function transform(clip) { while (true) {} }")
        let normal = makeScript(code: "function transform(clip) { return clip.text; }")

        let timeout = await service.execute(scripts: [infinite], input: .init(text: "hello", sourceAppBundleIdentifier: nil))
        let capacity = await service.execute(scripts: [normal], input: .init(text: "hello", sourceAppBundleIdentifier: nil))

        #expect(timeout == .failure(.timeout(scriptID: infinite.id)))
        #expect(capacity == .failure(.capacityExhausted))
    }

    private func makeScript(
        code: String,
        sortIndex: Int = 0
    ) -> ScriptTransform {
        ScriptTransform(
            id: UUID(),
            name: "Test",
            code: code,
            isEnabled: true,
            runOnCopy: false,
            runOnPaste: false,
            runManually: true,
            sortIndex: sortIndex,
            createdAt: sortIndex,
            updatedAt: sortIndex
        )
    }
}
