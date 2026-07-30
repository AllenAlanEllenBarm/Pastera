//
//  ShortcutPreferenceResetTests.swift
//
//  Pastera
//

import AppKit
import Carbon
import KeyHolder
import Magnet
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct ShortcutPreferenceResetTests {
    @Test
    func menuResetRestoresServiceRefreshesAllRecordViewsAndShowsStatus() throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let service = context.service
        let customMenu = try #require(KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey | controlKey))
        let customPanel = try #require(KeyCombo(QWERTYKeyCode: 1, carbonModifiers: optionKey | shiftKey))
        service.change(with: .main, keyCombo: customMenu)
        service.change(with: .history, keyCombo: customMenu)
        service.change(with: .snippet, keyCombo: customMenu)
        service.change(with: .passwordVault, keyCombo: customMenu)
        HistoryPanelShortcut.allCases.forEach {
            service.changeHistoryPanelKeyCombo($0, keyCombo: customPanel)
        }

        let controller = CPYShortcutsPreferenceViewController()
        _ = controller.view
        let resetButton = try shortcutButton(in: controller.view, identifier: "shortcuts.menu.reset")

        resetButton.performClick(nil)

        #expect(service.mainKeyCombo == KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey))
        #expect(service.historyKeyCombo == KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | optionKey))
        #expect(service.snippetKeyCombo == KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | optionKey))
        #expect(service.passwordVaultKeyCombo == KeyCombo(QWERTYKeyCode: 35, carbonModifiers: controlKey | optionKey))
        #expect(service.historyPanelKeyCombo(for: .search) == customPanel)
        try expectAllRecordViewsMatchService(in: controller.view, service: service)
        let status = try shortcutView(in: controller.view, identifier: "shortcuts.restoredStatus")
        #expect(!status.isHidden)
        #expect(status.accessibilityLabel() == pasteraPreferenceString("Restored Defaults"))
    }

    @Test
    func historyPanelResetRestoresOnlyPanelAndRefreshesAllRecordViews() throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let service = context.service
        let customMenu = try #require(KeyCombo(QWERTYKeyCode: 2, carbonModifiers: cmdKey | controlKey))
        let customPanel = try #require(KeyCombo(QWERTYKeyCode: 5, carbonModifiers: optionKey | shiftKey))
        service.change(with: .main, keyCombo: customMenu)
        service.change(with: .history, keyCombo: customMenu)
        service.change(with: .snippet, keyCombo: customMenu)
        service.change(with: .passwordVault, keyCombo: customMenu)
        HistoryPanelShortcut.allCases.forEach {
            service.changeHistoryPanelKeyCombo($0, keyCombo: customPanel)
        }

        let controller = CPYShortcutsPreferenceViewController()
        _ = controller.view
        let resetButton = try shortcutButton(in: controller.view, identifier: "shortcuts.historyPanel.reset")

        resetButton.performClick(nil)

        #expect(service.mainKeyCombo == customMenu)
        #expect(service.historyKeyCombo == customMenu)
        #expect(service.snippetKeyCombo == customMenu)
        #expect(service.passwordVaultKeyCombo == customMenu)
        for shortcut in HistoryPanelShortcut.allCases {
            #expect(service.historyPanelKeyCombo(for: shortcut) == shortcut.defaultKeyCombo)
        }
        try expectAllRecordViewsMatchService(in: controller.view, service: service)
    }

    @Test
    func repeatedResetReplacesStatusDismissalAndPendingWorkDoesNotRetainController() throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let weakController = try makeControllerWithRepeatedReset()

        #expect(weakController.value == nil)
    }

    @Test
    func repeatedLoadViewRebuildsControlsWithoutDuplicatesOrStaleStatusWork() throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let controller = CPYShortcutsPreferenceViewController()
        _ = controller.view
        let firstRecordViews = shortcutRecordViews(in: controller.view)
        let resetButton = try shortcutButton(in: controller.view, identifier: "shortcuts.menu.reset")
        #expect(NSApp.sendAction(try #require(resetButton.action), to: resetButton.target, from: resetButton))
        #expect(controller.restoreStatusDismissWorkItemForTesting != nil)

        controller.loadView()
        let secondRecordViews = shortcutRecordViews(in: controller.view)
        controller.loadView()
        let currentView = controller.view
        let currentViews = shortcutViews(in: currentView)
        let currentRecordViews = shortcutRecordViews(in: currentView)

        #expect(firstRecordViews.allSatisfy { !$0.isDescendant(of: currentView) })
        #expect(firstRecordViews.allSatisfy { $0.delegate == nil })
        #expect(secondRecordViews.allSatisfy { !$0.isDescendant(of: currentView) })
        #expect(secondRecordViews.allSatisfy { $0.delegate == nil })
        #expect(currentViews.compactMap { $0 as? PasteraPreferenceGroupView }.count == 2)
        let currentRecordIdentifiers = Set(currentRecordViews.compactMap { $0.accessibilityIdentifier() })
        #expect(currentRecordIdentifiers == [
            "shortcuts.main",
            "shortcuts.history",
            "shortcuts.snippet",
            "shortcuts.passwordVault",
            "shortcuts.historyPanel.search"
        ])
        #expect(!currentRecordIdentifiers.contains("shortcuts.historyPanel.previousPage"))
        #expect(!currentRecordIdentifiers.contains("shortcuts.historyPanel.nextPage"))
        #expect(Set(currentRecordViews.map(ObjectIdentifier.init)).isDisjoint(
            with: Set(firstRecordViews.map(ObjectIdentifier.init))
        ))
        #expect(Set(currentRecordViews.map(ObjectIdentifier.init)).isDisjoint(
            with: Set(secondRecordViews.map(ObjectIdentifier.init))
        ))
        #expect(currentViews.compactMap { $0 as? NSButton }
            .filter { $0.title == pasteraPreferenceString("Reset to Defaults") }.count == 2)
        let statuses = currentViews.filter {
            $0.accessibilityIdentifier() == "shortcuts.restoredStatus"
        }
        #expect(statuses.count == 1)
        #expect(statuses.first?.isHidden == true)
        #expect(controller.restoreStatusDismissWorkItemForTesting == nil)
    }

    private func makeContext() throws -> ShortcutPreferenceTestContext {
        let suiteName = "ShortcutPreferenceResetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let service = HotKeyService(defaults: defaults)
        AppEnvironment.push(hotKeyService: service, defaults: defaults)
        return ShortcutPreferenceTestContext(
            service: service,
            cleanup: {
                _ = AppEnvironment.popLast()
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }

    private func expectAllRecordViewsMatchService(in view: NSView, service: HotKeyService) throws {
        let expected: [String: KeyCombo?] = [
            "shortcuts.main": service.mainKeyCombo,
            "shortcuts.history": service.historyKeyCombo,
            "shortcuts.snippet": service.snippetKeyCombo,
            "shortcuts.passwordVault": service.passwordVaultKeyCombo,
            "shortcuts.historyPanel.search": service.historyPanelKeyCombo(for: .search)
        ]
        let recordViews = shortcutRecordViews(in: view)
        #expect(recordViews.count == expected.count)
        for (identifier, keyCombo) in expected {
            let recordView = try #require(recordViews.first {
                $0.accessibilityIdentifier() == identifier
            })
            #expect(recordView.keyCombo == keyCombo)
        }
    }

    private func makeControllerWithRepeatedReset() throws -> WeakShortcutController {
        let controller = CPYShortcutsPreferenceViewController()
        let weakController = WeakShortcutController(controller)
        _ = controller.view
        let resetButton = try shortcutButton(in: controller.view, identifier: "shortcuts.menu.reset")

        #expect(NSApp.sendAction(try #require(resetButton.action), to: resetButton.target, from: resetButton))
        let firstDismissal = try #require(controller.restoreStatusDismissWorkItemForTesting)
        #expect(!firstDismissal.isCancelled)

        #expect(NSApp.sendAction(try #require(resetButton.action), to: resetButton.target, from: resetButton))
        let secondDismissal = try #require(controller.restoreStatusDismissWorkItemForTesting)
        #expect(firstDismissal.isCancelled)
        #expect(secondDismissal !== firstDismissal)
        #expect(!secondDismissal.isCancelled)
        return weakController
    }

}

private struct ShortcutPreferenceTestContext {
    let service: HotKeyService
    let cleanup: () -> Void
}

private final class WeakShortcutController {
    private(set) weak var value: CPYShortcutsPreferenceViewController?

    init(_ value: CPYShortcutsPreferenceViewController) {
        self.value = value
    }
}

private func shortcutButton(in view: NSView, identifier: String) throws -> NSButton {
    try #require(shortcutViews(in: view).compactMap { $0 as? NSButton }.first {
        $0.accessibilityIdentifier() == identifier
    })
}

private func shortcutView(in view: NSView, identifier: String) throws -> NSView {
    try #require(shortcutViews(in: view).first { $0.accessibilityIdentifier() == identifier })
}

private func shortcutRecordViews(in view: NSView) -> [RecordView] {
    shortcutViews(in: view).compactMap { $0 as? RecordView }
}

private func shortcutViews(in view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + shortcutViews(in: $0) }
}
