import AppKit
import Foundation
import Testing
@testable import Pastera

@MainActor
struct ScriptPreferenceTests {
    @Test
    func scriptsPreferencePageKeepsManagementShortcutAndTestingInOneWorkspace() {
        let page = CPYScriptsPreferenceViewController(
            repository: ScriptPreferenceRepository(scripts: []),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService()
        )
        _ = page.view

        #expect(page.emptyStateMinimumHeightForTesting >= 96)
        #expect(page.emptyStateMinimumHeightForTesting <= 120)
        #expect(!page.hasEmbeddedTestControlsForTesting)
        #expect(allSubviews(in: page.view).compactMap { $0 as? PasteraPreferenceGroupView }.count == 1)
        #expect(!page.isTestActionEnabledForTesting)
        #expect(page.view.fittingSize.height > 200)
        #expect(page.orderedSectionIDsForTesting == [
            "scripts.list", "scripts.shortcut"
        ])
        #expect(!page.orderedSectionIDsForTesting.contains("scripts.promptOptimization"))
    }

    @Test
    func scriptsHomeUsesSingleFullHeightWorkspaceAndOnePrimaryAction() {
        let scripts = [
            makeScript(name: "First", sortIndex: 0),
            makeScript(name: "Second", sortIndex: 1)
        ]
        let page = CPYScriptsPreferenceViewController(
            repository: ScriptPreferenceRepository(scripts: scripts),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService()
        )
        _ = page.view

        #expect(allSubviews(in: page.view).compactMap { $0 as? PasteraPreferenceGroupView }.count == 1)
        #expect(views(in: page.view, identifierPrefix: "scripts.workspace").count == 1)
        let scriptRows = views(in: page.view, identifierPrefix: "scripts.row.").filter {
            $0 is NSStackView && $0.identifier?.rawValue.split(separator: ".").count == 3
        }
        #expect(scriptRows.count == 2)
        #expect(scriptRows.allSatisfy {
            $0.layer?.backgroundColor == nil
        })

        let actionButtons = allSubviews(in: page.view).compactMap { $0 as? NSButton }
        #expect(actionButtons.filter { $0.identifier?.rawValue == "scripts.action.primary" }.count == 1)
        #expect(actionButtons.filter {
            $0.identifier?.rawValue.hasPrefix("scripts.action.secondary.") == true
        }.count == 2)
        #expect(actionButtons.contains {
            $0.identifier?.rawValue.hasPrefix("scripts.row.move-up.") == true
        })
        #expect(actionButtons.contains {
            $0.identifier?.rawValue.hasPrefix("scripts.row.move-down.") == true
        })
    }

    @Test
    func scriptsHomeFillsAvailablePreferenceHeight() throws {
        let scriptsPage = CPYScriptsPreferenceViewController(
            repository: ScriptPreferenceRepository(scripts: [
                makeScript(name: "Identity", sortIndex: 0)
            ]),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService()
        )
        let controller = CPYPreferencesWindowController(
            catalog: .default,
            pageControllerProvider: { paneID in
                if paneID == .scripts {
                    return scriptsPage
                }
                return PasteraPreferencePageViewController(paneID: paneID, title: paneID.rawValue)
            },
            reduceMotion: { true },
            frameAutosaveName: "ScriptPreferenceTests.FullHeight.\(UUID().uuidString)",
            deactivateApplication: {}
        )
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePane(.scripts)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let viewportHeight = controller.preferencePaneViewportHeightForTesting
        let expectedPageHeight = viewportHeight - 32
        #expect(abs(controller.selectedPaneDocumentHeightForTesting - expectedPageHeight) <= 1)
        let workspaceFrame = try #require(controller.selectedPaneDescendantFrameForTesting(
            accessibilityIdentifier: "scripts.workspace"
        ))
        #expect(workspaceFrame.height >= expectedPageHeight * 0.75)
        #expect(workspaceFrame.maxY >= expectedPageHeight - 23)
    }

    @Test
    func scriptsHomeReordersFromInlineRowActions() {
        let first = makeScript(name: "First", sortIndex: 0)
        let second = makeScript(name: "Second", sortIndex: 1)
        let repository = ScriptPreferenceRepository(scripts: [first, second])
        let page = CPYScriptsPreferenceViewController(
            repository: repository,
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService()
        )
        _ = page.view

        let moveDown = allSubviews(in: page.view)
            .compactMap { $0 as? NSButton }
            .first {
                $0.identifier?.rawValue == "scripts.row.move-down.\(first.id.uuidString)"
            }
        moveDown?.performClick(nil)

        #expect(repository.orderedIDs == [second.id, first.id])
    }

    @Test
    func scriptSheetsShareResponsiveDesktopSizing() {
        let editor = ScriptEditorViewController(script: nil, onSave: { _ in })
        let market = ScriptTemplateMarketViewController { _ in }
        let test = ScriptTestViewController(scripts: [], executor: ScriptExecutionService())
        _ = editor.view
        _ = market.view
        _ = test.view

        #expect(editor.minimumSheetWidthForTesting == 560)
        #expect(market.minimumSheetWidthForTesting == 560)
        #expect(test.minimumSheetWidthForTesting == 560)
        #expect(editor.usesFlexibleDocumentWidthForTesting)
        #expect(market.usesFlexibleTemplateRowsForTesting)
        for controller in [editor, market, test] {
            #expect(views(in: controller.view, identifierPrefix: "preference.sheet.scaffold").count == 1)
            #expect(views(in: controller.view, identifierPrefix: "preference.sheet.header").count == 1)
            #expect(views(in: controller.view, identifierPrefix: "preference.sheet.body").count == 1)
            #expect(views(in: controller.view, identifierPrefix: "preference.sheet.footer").count == 1)
        }
    }

    @Test
    func scriptEditorUsesWeakSectionsAndStableTestFeedback() {
        let editor = ScriptEditorViewController(script: nil, onSave: { _ in })
        _ = editor.view

        let sections = views(in: editor.view, identifierPrefix: "script.editor.section.")
        #expect(sections.count == 4)
        #expect(sections.allSatisfy { ($0.layer?.borderWidth ?? 0) == 0 })
        #expect(views(in: editor.view, identifierPrefix: "script.editor.code-scroll").count == 1)
        let result = views(in: editor.view, identifierPrefix: "script.editor.test-result").first
        #expect(result?.isHidden == false)
        #expect((result?.frame.height ?? 0) >= 36)
    }

    @Test
    func templateMarketUsesReadableListRowsAndLabeledAddActions() {
        let market = ScriptTemplateMarketViewController { _ in }
        _ = market.view

        let rows = views(in: market.view, identifierPrefix: "script.template.row.")
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { ($0.layer?.borderWidth ?? 0) == 0 })
        let addButtons = allSubviews(in: market.view)
            .compactMap { $0 as? NSButton }
            .filter { $0.identifier?.rawValue.hasPrefix("script.template.add.") == true }
        #expect(addButtons.count == rows.count)
        #expect(addButtons.allSatisfy {
            $0.title == pasteraScriptString("Add", "添加")
        })
    }

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
    func scriptTestSheetRunsSelectedScriptWithoutChangingClipboard() async {
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
        let originalPasteboard = NSPasteboard.general.string(forType: .string)
        let sheet = ScriptTestViewController(
            scripts: [script],
            executor: ScriptExecutionService()
        )
        _ = sheet.view

        #expect(sheet.usesSingleColumnLayoutForTesting)
        await sheet.runSelectedScriptForTesting(input: "Hello World")
        #expect(sheet.testOutputForTesting == "HELLO WORLD")
        #expect(sheet.testErrorForTesting == nil)
        #expect(NSPasteboard.general.string(forType: .string) == originalPasteboard)
    }

    @Test
    func scriptsPreferenceEnablesTestActionWhenScriptExists() {
        let script = makeScript(name: "Identity", sortIndex: 0)
        let page = CPYScriptsPreferenceViewController(
            repository: ScriptPreferenceRepository(scripts: [script]),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService()
        )
        _ = page.view

        #expect(page.isTestActionEnabledForTesting)
    }

    private func makeScript(name: String, sortIndex: Int) -> ScriptTransform {
        ScriptTransform(
            id: UUID(),
            name: name,
            code: "function transform(clip) { return clip.text; }",
            isEnabled: true,
            runOnCopy: false,
            runOnPaste: false,
            runManually: true,
            sortIndex: sortIndex,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func views(in root: NSView, identifierPrefix: String) -> [NSView] {
        allSubviews(in: root).filter {
            $0.identifier?.rawValue.hasPrefix(identifierPrefix) == true
        }
    }

    private func allSubviews(in root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { allSubviews(in: $0) }
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
    var orderedIDs: [UUID] { scripts.map(\.id) }

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
    func replaceOrder(ids: [UUID]) throws {
        let scriptsByID = Dictionary(uniqueKeysWithValues: scripts.map { ($0.id, $0) })
        scripts = ids.compactMap { scriptsByID[$0] }
    }
}
