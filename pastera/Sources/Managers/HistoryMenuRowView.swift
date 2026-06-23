//
//  HistoryMenuRowView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/04.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

final class HistoryMenuRowView: NSControl {
    private enum Metrics {
        static let width: CGFloat = HistoryBrowserLayout.width
        static let textRowHeight: CGFloat = 28
        static let imageRowHeight: CGFloat = 42
        static let horizontalInset: CGFloat = 10
        static let imageWidth: CGFloat = 52
        static let imageHeight: CGFloat = 32
        static let textSpacing: CGFloat = 10
        static let shortcutSpacing: CGFloat = 8
        static let deleteButtonSize: CGFloat = 24
    }

    private static let imagePreviewController = HistoryMenuImagePreviewController()

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let deleteButton = NSButton()
    private let onConfirm: () -> Void
    private let onDelete: (() -> Void)?
    private let previewImage: NSImage?
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false
    private var isFocused = false
    var onLogicalFocusChange: (() -> Void)?
    var onKeyboardEvent: ((NSEvent) -> Bool)?

    init(
        title: String,
        image: NSImage?,
        shortcutText: String? = nil,
        onDelete: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onDelete = onDelete
        self.previewImage = image
        let height = image == nil ? Metrics.textRowHeight : Metrics.imageRowHeight
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: height))
        setup(title: title, image: image, shortcutText: shortcutText)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        moveHistoryMenuFocus(with: event) || super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        onLogicalFocusChange?()
        isFocused = true
        updateAppearance()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        updateAppearance()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onLogicalFocusChange?()
        isMouseInside = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onLogicalFocusChange?()
        window?.makeFirstResponder(self)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        guard deleteButton.isHidden || !deleteButton.frame.contains(location) else { return }
        confirm()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isFocused = false
            isMouseInside = false
            updateAppearance()
            Self.hideImagePreview()
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKeyboardEvent?(event) == true {
            return
        }
        switch event.keyCode {
        case 36, 76:
            confirm()
        case 48:
            if moveHistoryMenuFocus(with: event) {
                return
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    func confirmFromKeyboard() {
        confirm()
    }

    static func hideImagePreview() {
        imagePreviewController.hide()
    }

    private func setup(title: String, image: NSImage?, shortcutText: String?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        let hasImage = image != nil

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = !hasImage
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 5
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = PasteraDesignTokens.colors().surface.cgColor
        imageView.layer?.borderColor = PasteraDesignTokens.colors().separator.cgColor
        imageView.layer?.borderWidth = hasImage ? 0.5 : 0

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .labelColor

        shortcutBadge.style = .itemNumber
        shortcutBadge.shortcutText = shortcutText

        deleteButton.identifier = NSUserInterfaceItemIdentifier("historyRowDeleteButton")
        deleteButton.setButtonType(.momentaryPushIn)
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .tertiaryLabelColor
        deleteButton.toolTip = String(localized: "Delete History")
        deleteButton.setAccessibilityLabel(String(localized: "Delete History"))
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked(_:))
        deleteButton.isHidden = onDelete == nil

        [shortcutBadge, imageView, titleLabel, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let hasShortcut = shortcutText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let shortcutSpacing: CGFloat = hasShortcut ? Metrics.shortcutSpacing : 0
        let deleteButtonWidth: CGFloat = onDelete == nil ? 0 : Metrics.deleteButtonSize
        let deleteButtonSpacing: CGFloat = onDelete == nil ? 0 : -6

        NSLayoutConstraint.activate([
            shortcutBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.leadingAnchor.constraint(equalTo: shortcutBadge.trailingAnchor, constant: shortcutSpacing),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: hasImage ? Metrics.imageWidth : 0),
            imageView.heightAnchor.constraint(equalToConstant: hasImage ? Metrics.imageHeight : 0),

            titleLabel.leadingAnchor.constraint(
                equalTo: hasImage ? imageView.trailingAnchor : shortcutBadge.trailingAnchor,
                constant: hasImage ? Metrics.textSpacing : shortcutSpacing
            ),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: deleteButtonSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: deleteButtonWidth),
            deleteButton.heightAnchor.constraint(equalToConstant: Metrics.deleteButtonSize)
        ])
        updateAppearance()
    }

    private func updateAppearance() {
        let tokens = PasteraDesignTokens.colors()
        let backgroundColor: NSColor = isFocused
            ? tokens.selectedRow
            : isMouseInside ? tokens.hoveredRow : .clear
        layer?.backgroundColor = backgroundColor.cgColor
        titleLabel.textColor = isFocused ? .selectedMenuItemTextColor : .labelColor
        shortcutBadge.setState(isEmphasized: isFocused || isMouseInside)
        deleteButton.contentTintColor = isFocused || isMouseInside ? .secondaryLabelColor : .tertiaryLabelColor
        updatePreviewVisibility(isFocused: isFocused)
    }

    private func updatePreviewVisibility(isFocused: Bool) {
        guard let previewImage else {
            Self.hideImagePreview()
            return
        }

        guard window?.isVisible == true else {
            Self.hideImagePreview()
            return
        }

        if isFocused || isMouseInside {
            Self.imagePreviewController.show(image: previewImage, relativeTo: bounds, in: self)
        } else {
            Self.hideImagePreview()
        }
    }

    private func confirm() {
        isFocused = false
        isMouseInside = false
        Self.hideImagePreview()
        onConfirm()
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        Self.hideImagePreview()
        onDelete?()
    }
}

#if DEBUG
extension HistoryMenuRowView {
    static var isImagePreviewVisibleForTesting: Bool {
        imagePreviewController.isVisibleForTesting
    }

    var textValuesForTesting: [String] {
        collectTextValues(in: self)
    }

    func confirmForTesting() {
        confirm()
    }

    private func collectTextValues(in view: NSView) -> [String] {
        var values = [String]()
        for subview in view.subviews {
            if let label = subview as? NSTextField {
                values.append(label.stringValue)
            } else if let badge = subview as? PasteraShortcutBadgeView {
                values.append(badge.shortcutTextForTesting)
            }
            values.append(contentsOf: collectTextValues(in: subview))
        }
        return values
    }
}
#endif
