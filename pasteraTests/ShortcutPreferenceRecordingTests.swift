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
    func shortcutRecordViewsRecordCommandArrowCombosWithoutWindowInterception() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let contentView = try #require(controller.window?.contentView)
        let previousRecordView = try #require(preferenceRecordView(
            in: contentView,
            identifier: "shortcuts.historyPanel.previousPage"
        ))
        let nextRecordView = try #require(preferenceRecordView(
            in: contentView,
            identifier: "shortcuts.historyPanel.nextPage"
        ))

        let previousEvent = try makeKeyEvent(
            keyCode: 123,
            characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            modifierFlags: [.command]
        )
        let nextEvent = try makeKeyEvent(
            keyCode: 124,
            characters: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            modifierFlags: [.command]
        )

        #expect(previousRecordView.beginRecording())
        #expect(!controller.handlePreferenceKeyboardEventForTesting(previousEvent))
        #expect(previousRecordView.performKeyEquivalent(with: previousEvent))
        #expect(service.historyPanelKeyCombo(for: .previousPage)?.QWERTYKeyCode == 123)

        #expect(nextRecordView.beginRecording())
        #expect(!controller.handlePreferenceKeyboardEventForTesting(nextEvent))
        #expect(nextRecordView.performKeyEquivalent(with: nextEvent))
        #expect(service.historyPanelKeyCombo(for: .nextPage)?.QWERTYKeyCode == 124)

        previousRecordView.clear()
        nextRecordView.clear()
        #expect(previousRecordView.keyCombo == nil)
        #expect(nextRecordView.keyCombo == nil)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == nil)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == nil)
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
