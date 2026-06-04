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
        static let height: CGFloat = 38
        static let horizontalInset: CGFloat = 10
        static let iconSize: CGFloat = 18
        static let pinSize: CGFloat = 22
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pinButton = HistoryMenuPinButton()
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false
    private var didDragWindow = false
    private var isPinned: Bool

    var allowsWindowDrag = false
    var onOpen: (() -> Void)?
    var onPinnedChange: ((Bool, NSRect?) -> Void)?

    init(title: String, image: NSImage?, isPinned: Bool) {
        self.isPinned = isPinned
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height))
        setup(title: title, image: image)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragWindow else {
            didDragWindow = false
            return
        }
        guard !pinButtonContains(event) else { return }
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

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        updatePinAppearance()
    }

    private func setup(title: String, image: NSImage?) {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = image == nil

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        pinButton.identifier = NSUserInterfaceItemIdentifier("mainMenuPinButton")
        pinButton.setButtonType(.momentaryPushIn)
        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.target = self
        pinButton.action = #selector(togglePinned(_:))

        [imageView, titleLabel, pinButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinButton.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            pinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: Metrics.pinSize),
            pinButton.heightAnchor.constraint(equalToConstant: Metrics.pinSize)
        ])

        updateAppearance()
        updatePinAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isMouseInside
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isMouseInside ? .selectedMenuItemTextColor : .labelColor
    }

    private func updatePinAppearance() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = isPinned ? "Unpin Menu" : "Pin Menu"
        pinButton.setAccessibilityLabel(pinButton.toolTip)
    }

    private func pinButtonContains(_ event: NSEvent) -> Bool {
        let location = pinButton.convert(event.locationInWindow, from: nil)
        return pinButton.bounds.contains(location)
    }

    @objc private func togglePinned(_ sender: NSButton) {
        onPinnedChange?(!isPinned, window?.frame)
    }
}
