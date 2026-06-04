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
    private var trackingArea: NSTrackingArea?
    var onMouseEntered: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?(); super.mouseEntered(with: event) }

    override func mouseMoved(with event: NSEvent) { onMouseEntered?(); super.mouseMoved(with: event) }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: event) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
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
