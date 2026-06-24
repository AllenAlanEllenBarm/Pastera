//
//  HistoryMenuSearchField.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/03.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

final class HistoryMenuSearchField: NSSearchField {
    private static let basePlaceholder = "Keyword"
    private var trackingArea: NSTrackingArea?
    var onMouseEntered: (() -> Void)?
    var onPanelShortcutKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateHistoryShortcutPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateHistoryShortcutPlaceholder()
    }

    func updateHistoryShortcutPlaceholder() {
        let shortcutText = PasteraShortcutFormatter.string(
            for: AppEnvironment.current.hotKeyService.historyPanelKeyCombo(for: .search)
        )
        let placeholder = shortcutText.map { "\(Self.basePlaceholder) (\($0))" } ?? Self.basePlaceholder
        placeholderString = placeholder
        toolTip = placeholder
        setAccessibilityLabel(placeholder)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?(); super.mouseEntered(with: event) }

    override func mouseMoved(with event: NSEvent) { onMouseEntered?(); super.mouseMoved(with: event) }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: event) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onPanelShortcutKeyDown?(event) == true { return true }
        if moveHistoryMenuFocus(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        let selector: Selector?
        switch key {
        case "a":
            selector = #selector(NSText.selectAll(_:))
        case "c":
            selector = #selector(NSText.copy(_:))
        case "v":
            selector = #selector(NSText.paste(_:))
        case "x":
            selector = #selector(NSText.cut(_:))
        default:
            selector = nil
        }

        guard let selector else {
            return super.performKeyEquivalent(with: event)
        }
        return NSApp.sendAction(selector, to: nil, from: self) || super.performKeyEquivalent(with: event)
    }
}
