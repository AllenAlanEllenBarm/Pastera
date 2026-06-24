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
        static let textPreviewDelay: TimeInterval = 0.45
        static let maxPreviewTextLength = 1200
    }

    private static let imagePreviewController = HistoryMenuImagePreviewController()
    private static let textPreviewController = HistoryMenuTextPreviewController()

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let deleteButton = NSButton()
    private let onConfirm: () -> Void
    private let onDelete: (() -> Void)?
    private let previewImage: NSImage?
    private let previewText: String?
    private var trackingArea: NSTrackingArea?
    private var textPreviewWorkItem: DispatchWorkItem?
    private var isMouseInside = false
    private var isFocused = false
    var onLogicalFocusChange: (() -> Void)?
    var onKeyboardEvent: ((NSEvent) -> Bool)?

    init(
        title: String,
        image: NSImage?,
        shortcutText: String? = nil,
        previewText: String? = nil,
        onDelete: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onDelete = onDelete
        self.previewImage = image
        self.previewText = Self.boundedPreviewText(previewText)
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
        scheduleTextPreview()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        cancelTextPreview()
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
            cancelTextPreview()
            updateAppearance()
            Self.hidePreviews()
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

    static func hideTextPreview() {
        textPreviewController.hide()
    }

    static func hidePreviews() {
        hideImagePreview()
        hideTextPreview()
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

    private func scheduleTextPreview() {
        cancelTextPreview()
        guard previewImage == nil,
              let previewText,
              !previewText.isEmpty else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.showTextPreviewIfNeeded()
        }
        textPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.textPreviewDelay, execute: workItem)
    }

    private func showTextPreviewIfNeeded() {
        guard isMouseInside,
              window?.isVisible == true,
              let previewText,
              !previewText.isEmpty else {
            Self.hideTextPreview()
            return
        }
        Self.textPreviewController.show(text: previewText, relativeTo: bounds, in: self)
    }

    private func cancelTextPreview() {
        textPreviewWorkItem?.cancel()
        textPreviewWorkItem = nil
        Self.hideTextPreview()
    }

    private func confirm() {
        isFocused = false
        isMouseInside = false
        cancelTextPreview()
        Self.hideImagePreview()
        onConfirm()
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        cancelTextPreview()
        Self.hideImagePreview()
        onDelete?()
    }

    private static func boundedPreviewText(_ text: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedText, !trimmedText.isEmpty else { return nil }
        guard trimmedText.utf16.count > Metrics.maxPreviewTextLength else { return trimmedText }
        return (trimmedText as NSString).substring(to: Metrics.maxPreviewTextLength - 1) + "…"
    }
}

#if DEBUG
extension HistoryMenuRowView {
    static var isImagePreviewVisibleForTesting: Bool {
        imagePreviewController.isVisibleForTesting
    }

    static var isTextPreviewVisibleForTesting: Bool {
        textPreviewController.isVisibleForTesting
    }

    static var textPreviewValueForTesting: String {
        textPreviewController.textValueForTesting
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
