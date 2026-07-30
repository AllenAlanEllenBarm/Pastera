//
//  ShortcutPreferenceRecordingTests.swift
//
//  Pastera
//

import AppKit
import KeyHolder
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct ShortcutPreferenceRecordingTests {
    @Test
    func searchShortcutRecordViewRecordsWithoutWindowInterception() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let contentView = try #require(controller.window?.contentView)
        let searchRecordView = try #require(preferenceRecordView(
            in: contentView,
            identifier: "shortcuts.historyPanel.search"
        ))
        let searchEvent = try makeKeyEvent(
            keyCode: 17,
            characters: "t",
            modifierFlags: [.command, .option]
        )

        #expect(preferenceRecordView(
            in: contentView,
            identifier: "shortcuts.historyPanel.previousPage"
        ) == nil)
        #expect(preferenceRecordView(
            in: contentView,
            identifier: "shortcuts.historyPanel.nextPage"
        ) == nil)
        #expect(searchRecordView.beginRecording())
        #expect(!controller.handlePreferenceKeyboardEventForTesting(searchEvent))
        #expect(searchRecordView.performKeyEquivalent(with: searchEvent))
        #expect(service.historyPanelKeyCombo(for: .search)?.QWERTYKeyCode == 17)

        searchRecordView.clear()
        #expect(searchRecordView.keyCombo == nil)
        #expect(service.historyPanelKeyCombo(for: .search) == nil)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func preferenceRecordView(in view: NSView, identifier: String) -> RecordView? {
        if let recordView = view as? RecordView,
           recordView.accessibilityIdentifier() == identifier {
            return recordView
        }
        for subview in view.subviews {
            if let recordView = preferenceRecordView(in: subview, identifier: identifier) {
                return recordView
            }
        }
        return nil
    }
}
