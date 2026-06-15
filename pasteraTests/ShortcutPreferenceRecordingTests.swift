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
            nextToAnyLabel: ["Previous Page:", "上一页："]
        ))
        let nextRecordView = try #require(preferenceRecordView(
            in: contentView,
            nextToAnyLabel: ["Next Page:", "下一页："]
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

    private func preferenceRecordView(in view: NSView, nextToAnyLabel labels: Set<String>) -> RecordView? {
        if let textField = view as? NSTextField,
           labels.contains(textField.stringValue),
           let container = textField.superview {
            return recordViews(in: container).first
        }
        for subview in view.subviews {
            if let recordView = preferenceRecordView(in: subview, nextToAnyLabel: labels) {
                return recordView
            }
        }
        return nil
    }

    private func recordViews(in view: NSView) -> [RecordView] {
        var values = view.subviews.compactMap { $0 as? RecordView }
        view.subviews.forEach { values.append(contentsOf: recordViews(in: $0)) }
        return values
    }
}
