//
//  HistoryMenuFocusableControls.swift
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

final class HistoryMenuFocusableButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        moveHistoryMenuFocus(with: event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleHistoryMenuKeyboardEventFromHeader(event) {
            return
        }
        if moveHistoryMenuFocus(with: event) {
            return
        }
        switch event.keyCode {
        case 36, 49, 76:
            performClick(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

extension NSButton {
    func updateHistoryShortcutToolTip(_ label: String, shortcut: HistoryPanelShortcut) {
        let shortcutText = PasteraShortcutFormatter.string(
            for: AppEnvironment.current.hotKeyService.historyPanelKeyCombo(for: shortcut)
        )
        let toolTip = shortcutText.map { "\(label) (\($0))" } ?? label
        self.toolTip = toolTip
        setAccessibilityLabel(toolTip)
    }
}

final class HistoryMenuFocusableSegmentedControl: NSSegmentedControl {
    private var focusedSegmentIndex: Int?

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        moveHistoryMenuFocus(with: event) || super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        if focusedSegmentIndex == nil { prepareForKeyboardFocus(backward: false) }
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        focusedSegmentIndex = nil
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        focusSegment(at: selectedSegment)
    }

    override func keyDown(with event: NSEvent) {
        if handleHistoryMenuKeyboardEventFromHeader(event) {
            return
        }
        if moveHistoryMenuFocus(with: event) {
            return
        }
        switch event.keyCode {
        case 36, 49, 76:
            activateFocusedSegment()
        default:
            super.keyDown(with: event)
        }
    }

    func prepareForKeyboardFocus(backward: Bool) {
        focusSegment(at: backward ? segmentCount - 1 : 0)
    }

    @discardableResult
    func moveFocusedSegment(backward: Bool) -> Bool {
        guard segmentCount > 1 else { return false }
        let currentIndex = focusedSegmentIndex ?? (backward ? segmentCount - 1 : 0)
        let nextIndex = backward ? currentIndex - 1 : currentIndex + 1
        guard (0..<segmentCount).contains(nextIndex) else { return false }
        focusSegment(at: nextIndex)
        return true
    }

    func focusSegment(at index: Int) {
        guard (0..<segmentCount).contains(index) else {
            focusedSegmentIndex = nil
            needsDisplay = true
            return
        }
        focusedSegmentIndex = index
        needsDisplay = true
    }

    private func activateFocusedSegment() {
        guard let focusedSegmentIndex,
              (0..<segmentCount).contains(focusedSegmentIndex) else { return }
        if segmentCount == 1 {
            setSelected(!isSelected(forSegment: focusedSegmentIndex), forSegment: focusedSegmentIndex)
        } else {
            selectedSegment = focusedSegmentIndex
        }
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder === self,
              let focusedSegmentIndex,
              (0..<segmentCount).contains(focusedSegmentIndex) else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSFocusRingPlacement.only.set()
        NSBezierPath(roundedRect: segmentRect(at: focusedSegmentIndex).insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
    }

    private func segmentRect(at targetSegment: Int) -> NSRect {
        let originX = (0..<targetSegment).reduce(bounds.minX) { $0 + width(forSegment: $1) }
        return NSRect(x: originX, y: bounds.minY, width: width(forSegment: targetSegment), height: bounds.height)
    }
}

private extension NSView {
    func handleHistoryMenuKeyboardEventFromHeader(_ event: NSEvent) -> Bool {
        (superview as? HistoryMenuHeaderView)?.handleHistoryKeyboardEvent(event) == true
    }
}
