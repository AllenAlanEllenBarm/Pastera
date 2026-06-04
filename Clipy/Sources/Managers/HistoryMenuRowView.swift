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
        static let textRowHeight: CGFloat = 30
        static let imageRowHeight: CGFloat = 42
        static let horizontalInset: CGFloat = 10
        static let imageWidth: CGFloat = 48
        static let imageHeight: CGFloat = 30
        static let textSpacing: CGFloat = 10
    }

    private static let imagePreviewController = HistoryMenuImagePreviewController()

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let onConfirm: () -> Void
    private let previewImage: NSImage?
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false
    private var isFocused = false
    var onLogicalFocusChange: (() -> Void)?
    var onKeyboardEvent: ((NSEvent) -> Bool)?

    init(title: String, image: NSImage?, onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.previewImage = image
        let height = image == nil ? Metrics.textRowHeight : Metrics.imageRowHeight
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: height))
        setup(title: title, image: image)
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

    private func setup(title: String, image: NSImage?) {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        let hasImage = image != nil

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = !hasImage
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.2).cgColor
        imageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        imageView.layer?.borderWidth = hasImage ? 0.5 : 0

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .labelColor

        [imageView, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: hasImage ? Metrics.imageWidth : 0),
            imageView.heightAnchor.constraint(equalToConstant: hasImage ? Metrics.imageHeight : 0),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: hasImage ? Metrics.textSpacing : 0),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundColor: NSColor = isFocused
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.9)
            : isMouseInside ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16) : .clear
        layer?.backgroundColor = backgroundColor.cgColor
        titleLabel.textColor = isFocused ? .selectedMenuItemTextColor : .labelColor
        updatePreviewVisibility(isFocused: isFocused)
    }

    private func updatePreviewVisibility(isFocused: Bool) {
        guard let previewImage else {
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
        Self.hideImagePreview()
        onConfirm()
    }
}
