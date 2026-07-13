//
//  MainMenuHeaderItemView.swift
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

final class MainMenuHeaderItemView: NSControl {
    enum Metrics {
        static let width: CGFloat = MainMenuPanelLayout.width
        static let height: CGFloat = MainMenuPanelLayout.headerHeight
        static let horizontalInset: CGFloat = 9
        static let iconSize: CGFloat = 16
        static let hoverOpenDelay: TimeInterval = 0.55
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false
    private var didTriggerHoverOpen = false
    private var pendingHoverOpen: DispatchWorkItem?
    private var didDragWindow = false
    private var isKeyboardSelected = false

    var allowsWindowDrag = false
    var onOpen: (() -> Void)?
    var onHoverOpen: (() -> Void)?
    var onHoverFocus: (() -> Void)?

    init(title: String, image: NSImage?, shortcutText: String? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height))
        setup(title: title, image: image, shortcutText: shortcutText)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        pendingHoverOpen?.cancel()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelPendingHoverOpen()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        onHoverFocus?()
        scheduleHoverOpenIfNeeded()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        cancelPendingHoverOpen()
        didTriggerHoverOpen = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        cancelPendingHoverOpen()
        guard !didDragWindow else {
            didDragWindow = false
            return
        }
        onOpen?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard allowsWindowDrag else {
            super.mouseDragged(with: event)
            return
        }
        didDragWindow = true
        window?.performDrag(with: event)
    }

    func setKeyboardSelected(_ selected: Bool) {
        guard isKeyboardSelected != selected else { return }
        isKeyboardSelected = selected
        updateAppearance()
    }

    private func setup(title: String, image: NSImage?, shortcutText: String?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = image == nil
        imageView.contentTintColor = .secondaryLabelColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        shortcutBadge.shortcutText = shortcutText

        [imageView, titleLabel, shortcutBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutBadge.leadingAnchor, constant: -5),
            shortcutBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        let isEmphasized = isMouseInside || isKeyboardSelected
        layer?.backgroundColor = isEmphasized
            ? PasteraDesignTokens.colors().hoveredRow.cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = .labelColor
        imageView.contentTintColor = isEmphasized ? .labelColor : .secondaryLabelColor
        shortcutBadge.setState(isEmphasized: isEmphasized)
    }

    private func scheduleHoverOpenIfNeeded() {
        guard onHoverOpen != nil, !didTriggerHoverOpen, pendingHoverOpen == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isMouseInside, !self.didTriggerHoverOpen else { return }
            self.pendingHoverOpen = nil
            self.didTriggerHoverOpen = true
            self.onHoverOpen?()
        }
        pendingHoverOpen = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.hoverOpenDelay, execute: workItem)
    }

    private func cancelPendingHoverOpen() {
        pendingHoverOpen?.cancel()
        pendingHoverOpen = nil
    }
}
