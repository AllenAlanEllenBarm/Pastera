//
//  PreferenceWindowInteractionRegressionTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct PreferenceWindowInteractionRegressionTests {
    @Test
    func productionRouteSelectsAboutPane() {
        let controller = CPYPreferencesWindowController(
            frameAutosaveName: "PreferenceWindowInteractionRegressionTests.About.\(UUID().uuidString)",
            reduceMotion: { true },
            deactivateApplication: {}
        )
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePane(.about)

        #expect(controller.selectedPreferencePaneIDForTesting == .about)
    }

    @Test
    func escapeRestoresNumericDraftBeforeClosingWindow() throws {
        let defaults = AppEnvironment.current.defaults
        let previousValue = defaults.object(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: Constants.UserDefaults.maxMenuItemTitleLength)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
            }
        }
        defaults.set(20, forKey: Constants.UserDefaults.maxMenuItemTitleLength)

        let controller = CPYPreferencesWindowController(
            frameAutosaveName: "PreferenceWindowInteractionRegressionTests.\(UUID().uuidString)",
            reduceMotion: { true },
            deactivateApplication: {}
        )
        defer { controller.close() }
        controller.showWindow(nil)
        let contentView = try #require(controller.window?.contentView)
        let field = try #require(textFields(in: contentView).first {
            $0.accessibilityLabel() == pasteraPreferenceString("Menu Title Length")
        })
        #expect(controller.window?.makeFirstResponder(field) == true)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = "invalid"

        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
        controller.window?.keyDown(with: escape)

        #expect(controller.window?.isVisible == true)
        #expect(field.stringValue == "20")
    }

    @Test
    func scriptTemplateEditorCancelDismissesSheetFromProductionPreferenceWindow() throws {
        let scriptsPage = CPYScriptsPreferenceViewController(
            repository: PreferenceWindowScriptRepository(),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService()
        )
        let controller = CPYPreferencesWindowController(
            catalog: .default,
            pageControllerProvider: { paneID in
                switch paneID {
                case .general:
                    return CPYGeneralPreferenceViewController()
                case .scripts:
                    return scriptsPage
                default:
                    preconditionFailure("Unexpected preference pane in script sheet regression test")
                }
            },
            reduceMotion: { true },
            frameAutosaveName: "PreferenceWindowInteractionRegressionTests.Scripts.\(UUID().uuidString)",
            deactivateApplication: {}
        )
        defer {
            if let window = controller.window, let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            controller.close()
        }

        controller.showWindow(nil)
        controller.showPreferencePane(.scripts)
        let contentView = try #require(controller.window?.contentView)
        let createFromTemplate = try #require(buttons(in: contentView).first {
            $0.title == pasteraScriptString("Create from Template", "从模板创建")
        })

        createFromTemplate.performClick(nil)

        let market = try #require(controller.window?.attachedSheet)
        let marketContentView = try #require(market.contentView)
        let removeBlankLines = try #require(buttons(in: marketContentView).first {
            $0.identifier?.rawValue == "script.template.add.remove-blank-lines"
        })
        removeBlankLines.performClick(nil)

        let editorAppeared = waitUntil {
            guard let editorContentView = controller.window?.attachedSheet?.contentView else { return false }
            return buttons(in: editorContentView).contains {
                $0.title == pasteraScriptString("Cancel", "取消")
            }
        }
        #expect(editorAppeared)
        let editorContentView = try #require(controller.window?.attachedSheet?.contentView)
        let cancel = try #require(buttons(in: editorContentView).first {
            $0.title == pasteraScriptString("Cancel", "取消")
        })
        cancel.performClick(nil)

        #expect(waitUntil { controller.window?.attachedSheet == nil })
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var fields = view.subviews.compactMap { $0 as? NSTextField }
        view.subviews.forEach { fields.append(contentsOf: textFields(in: $0)) }
        return fields
    }

    private func buttons(in view: NSView) -> [NSButton] {
        var result = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { result.append(contentsOf: buttons(in: $0)) }
        return result
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        } while Date() < deadline
        return condition()
    }
}

private final class PreferenceWindowScriptRepository: ScriptRepositoryProtocol {
    func fetchAll() throws -> [ScriptTransform] { [] }
    func fetchEnabled(for trigger: ScriptTrigger) throws -> [ScriptTransform] { [] }
    func insert(_ script: ScriptTransform) throws {}
    func update(_ script: ScriptTransform) throws {}
    func delete(id: UUID) throws {}
    func replaceOrder(ids: [UUID]) throws {}
}
