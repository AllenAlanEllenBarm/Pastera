import Foundation
import Testing
@testable import Pastera

@MainActor
struct ScriptPreferenceTests {
    @Test
    func editorRequiresSuccessfulValidationBeforeSave() async {
        let editor = ScriptEditorViewController(
            script: nil,
            executor: ScriptEditorExecutor(result: .success("Hello")),
            onSave: { _ in }
        )
        _ = editor.view
        editor.setNameForTesting("Identity")
        editor.setTriggerForTesting(.manual, enabled: true)

        #expect(!editor.canSaveForTesting)
        await editor.validateForTesting(input: "Hello")
        #expect(editor.canSaveForTesting)
    }

    @Test
    func editorShowsEmptyStringAsSuccessfulOutput() async {
        let editor = ScriptEditorViewController(
            script: nil,
            executor: ScriptEditorExecutor(result: .success("")),
            onSave: { _ in }
        )
        _ = editor.view
        editor.setNameForTesting("Empty")
        editor.setTriggerForTesting(.manual, enabled: true)

        await editor.validateForTesting(input: "Hello")

        #expect(editor.testOutputForTesting == "")
        #expect(editor.testErrorForTesting == nil)
        #expect(editor.canSaveForTesting)
    }

    @Test
    func marketFiltersAndSelectsTemplate() {
        var selectedID: String?
        let controller = ScriptTemplateMarketViewController { template in
            selectedID = template.id
        }
        _ = controller.view

        controller.searchForTesting("URL")
        #expect(controller.visibleTemplateIDsForTesting == ["extract-url"])
        controller.selectTemplateForTesting(id: "extract-url")
        #expect(selectedID == "extract-url")
    }

    @Test
    func editorRunsRealJavaScriptAndInvalidatesResultAfterCodeChanges() async {
        let editor = ScriptEditorViewController(
            script: nil,
            executor: ScriptExecutionService(),
            onSave: { _ in }
        )
        _ = editor.view
        editor.setNameForTesting("Uppercase")
        editor.setTriggerForTesting(.manual, enabled: true)
        editor.setCodeForTesting("function transform(clip) { return clip.text.toUpperCase(); }")

        await editor.validateForTesting(input: "Hello World")

        #expect(editor.testOutputForTesting == "HELLO WORLD")
        #expect(editor.testErrorForTesting == nil)
        #expect(editor.canSaveForTesting)

        editor.setCodeForTesting("function transform(clip) { return clip.text; }")
        #expect(!editor.canSaveForTesting)
    }

    @Test
    func editorShowsJavaScriptFailureAndPreventsSave() async {
        let editor = ScriptEditorViewController(
            script: nil,
            executor: ScriptExecutionService(),
            onSave: { _ in }
        )
        _ = editor.view
        editor.setNameForTesting("Broken")
        editor.setTriggerForTesting(.manual, enabled: true)
        editor.setCodeForTesting("function transform(clip) { throw new Error('broken'); }")

        await editor.validateForTesting(input: "Hello")

        #expect(editor.testOutputForTesting == nil)
        #expect(editor.testErrorForTesting != nil)
        #expect(!editor.canSaveForTesting)
    }

    @Test
    func scriptsPreferencePageRunsSelectedScriptTest() async {
        let script = ScriptTransform(
            id: UUID(),
            name: "Uppercase",
            code: "function transform(clip) { return clip.text.toUpperCase(); }",
            isEnabled: true,
            runOnCopy: false,
            runOnPaste: false,
            runManually: true,
            sortIndex: 0,
            createdAt: 1,
            updatedAt: 1
        )
        let page = CPYScriptsPreferenceViewController(
            repository: ScriptPreferenceRepository(scripts: [script]),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService()
        )
        _ = page.view

        #expect(page.hasTestCardForTesting)
        await page.runSelectedScriptTestForTesting(input: "Hello World")
        #expect(page.testOutputForTesting == "HELLO WORLD")
        #expect(page.testErrorForTesting == nil)
    }
}

private struct ScriptEditorExecutor: ScriptExecuting {
    let result: Result<String, ScriptExecutionError>

    func execute(scripts: [ScriptTransform], input: ScriptExecutionInput) async -> Result<String, ScriptExecutionError> {
        result
    }
}

private final class ScriptPreferenceRepository: ScriptRepositoryProtocol {
    private var scripts: [ScriptTransform]

    init(scripts: [ScriptTransform]) {
        self.scripts = scripts
    }

    func fetchAll() throws -> [ScriptTransform] { scripts }
    func fetchEnabled(for trigger: ScriptTrigger) throws -> [ScriptTransform] { scripts.filter { $0.runs(on: trigger) } }
    func insert(_ script: ScriptTransform) throws { scripts.append(script) }
    func update(_ script: ScriptTransform) throws {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        scripts[index] = script
    }
    func delete(id: UUID) throws { scripts.removeAll { $0.id == id } }
    func replaceOrder(ids: [UUID]) throws {}
}
