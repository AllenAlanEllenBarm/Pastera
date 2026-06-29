//
//  PasteraConfirmationController.swift
//
//  Clipy
//

import Cocoa

struct PasteraConfirmationOptions: Equatable {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let isDestructive: Bool
    let suppressionTitle: String?

    init(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String,
        isDestructive: Bool = false,
        suppressionTitle: String? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.suppressionTitle = suppressionTitle
    }
}

struct PasteraConfirmationResult: Equatable {
    let confirmed: Bool
    let suppressionChecked: Bool

    static let cancelled = PasteraConfirmationResult(confirmed: false, suppressionChecked: false)
}

private final class PasteraConfirmationPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class PasteraConfirmationActionButton: NSButton {
    enum Role {
        case cancel
        case confirm(isDestructive: Bool)
    }

    private let role: Role

    init(title: String, role: Role, target: AnyObject?, action: Selector?) {
        self.role = role
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    private func setup() {
        setButtonType(.momentaryPushIn)
        bezelStyle = .regularSquare
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        let weight: NSFont.Weight
        switch role {
        case .cancel:
            weight = .medium
        case .confirm:
            weight = .semibold
        }
        font = .systemFont(ofSize: 13.5, weight: weight)
        updateAppearance()
    }

    private func updateAppearance() {
        let tokens = PasteraDesignTokens.colors(for: effectiveAppearance)
        let backgroundColor: NSColor
        let foregroundColor: NSColor

        switch role {
        case .cancel:
            backgroundColor = tokens.elevatedSurface.withAlphaComponent(isHighlighted ? 0.74 : 0.92)
            foregroundColor = .labelColor
        case let .confirm(isDestructive):
            let baseColor = isDestructive ? tokens.destructive : tokens.accent
            backgroundColor = baseColor.withAlphaComponent(isHighlighted ? 0.78 : 1.0)
            foregroundColor = .white
        }

        layer?.backgroundColor = backgroundColor.cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font as Any,
                .foregroundColor: foregroundColor
            ]
        )
    }
}

final class PasteraConfirmationController: NSWindowController {
    private enum Metrics {
        static let panelWidth: CGFloat = 376
        static let panelHeight: CGFloat = 176
        static let panelHeightWithSuppression: CGFloat = 204
        static let horizontalInset: CGFloat = 24
        static let topInset: CGFloat = 24
        static let bottomInset: CGFloat = 22
        static let iconSize: CGFloat = 38
        static let titleLeadingSpacing: CGFloat = 14
        static let buttonWidth: CGFloat = 104
        static let buttonHeight: CGFloat = 34
        static let buttonSpacing: CGFloat = 8
    }

    private let options: PasteraConfirmationOptions
    private weak var sourceWindow: NSWindow?
    private let suppressionButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var modalResult = PasteraConfirmationResult.cancelled

    private let iconContainerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton: PasteraConfirmationActionButton
    private let confirmButton: PasteraConfirmationActionButton

    init(options: PasteraConfirmationOptions, sourceWindow: NSWindow? = nil) {
        self.options = options
        self.sourceWindow = sourceWindow
        self.cancelButton = PasteraConfirmationActionButton(
            title: options.cancelTitle,
            role: .cancel,
            target: nil,
            action: nil
        )
        self.confirmButton = PasteraConfirmationActionButton(
            title: options.confirmTitle,
            role: .confirm(isDestructive: options.isDestructive),
            target: nil,
            action: nil
        )
        let panel = PasteraConfirmationPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Metrics.panelWidth,
                height: options.suppressionTitle == nil ? Metrics.panelHeight : Metrics.panelHeightWithSuppression
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        panel.onCancel = { [weak self] in self?.cancel() }
        setup(panel: panel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    static func runModal(
        options: PasteraConfirmationOptions,
        sourceWindow: NSWindow? = nil
    ) -> PasteraConfirmationResult {
        let controller = PasteraConfirmationController(options: options, sourceWindow: sourceWindow)
        return controller.runModal()
    }

    private func runModal() -> PasteraConfirmationResult {
        guard let window else { return .cancelled }
        NSApp.activate(ignoringOtherApps: true)
        position(window, relativeTo: sourceWindow ?? NSApp.keyWindow ?? NSApp.mainWindow)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return modalResult
    }

    private func setup(panel: PasteraConfirmationPanel) {
        panel.isFloatingPanel = true
        panel.animationBehavior = .utilityWindow
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        let tokens = PasteraDesignTokens.colors()
        let rootView = NSView(frame: panel.contentView?.bounds ?? .zero)
        rootView.autoresizingMask = [.width, .height]
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        rootView.layer?.cornerRadius = PasteraDesignTokens.Metrics.panelCornerRadius
        rootView.layer?.borderColor = tokens.separator.cgColor
        rootView.layer?.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth
        rootView.layer?.masksToBounds = true
        panel.contentView = rootView

        setupIcon()
        setupLabels()
        setupSuppression()
        setupButtons()

        [
            iconContainerView,
            titleLabel,
            messageLabel,
            cancelButton,
            confirmButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview($0)
        }
        if options.suppressionTitle != nil {
            suppressionButton.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview(suppressionButton)
        }

        let textLeadingAnchor = titleLabel.leadingAnchor
        let actionTopAnchor = options.suppressionTitle == nil
            ? messageLabel.bottomAnchor
            : suppressionButton.bottomAnchor
        let actionTopSpacing: CGFloat = options.suppressionTitle == nil ? 22 : 18

        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Metrics.horizontalInset),
            iconContainerView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Metrics.topInset),
            iconContainerView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconContainerView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.titleLeadingSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Metrics.topInset + 1),

            messageLabel.leadingAnchor.constraint(equalTo: textLeadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            confirmButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.horizontalInset),
            confirmButton.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Metrics.bottomInset),
            confirmButton.widthAnchor.constraint(equalToConstant: Metrics.buttonWidth),
            confirmButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),

            cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -Metrics.buttonSpacing),
            cancelButton.centerYAnchor.constraint(equalTo: confirmButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: Metrics.buttonWidth),
            cancelButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),

            cancelButton.topAnchor.constraint(greaterThanOrEqualTo: actionTopAnchor, constant: actionTopSpacing)
        ])

        if options.suppressionTitle != nil {
            NSLayoutConstraint.activate([
                suppressionButton.leadingAnchor.constraint(equalTo: textLeadingAnchor),
                suppressionButton.trailingAnchor.constraint(lessThanOrEqualTo: titleLabel.trailingAnchor),
                suppressionButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12)
            ])
        }
    }

    private func setupIcon() {
        let tokens = PasteraDesignTokens.colors()
        iconContainerView.wantsLayer = true
        iconContainerView.layer?.cornerRadius = Metrics.iconSize / 2
        iconContainerView.layer?.masksToBounds = true
        iconContainerView.layer?.backgroundColor = (options.isDestructive ? tokens.destructive : tokens.accent)
            .withAlphaComponent(0.16)
            .cgColor

        let iconView = NSImageView()
        iconView.image = NSImage(
            systemSymbolName: options.isDestructive ? "trash.fill" : "checkmark.circle.fill",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = options.isDestructive ? tokens.destructive : tokens.accent
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func setupLabels() {
        titleLabel.stringValue = options.title
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        messageLabel.stringValue = options.message
        messageLabel.font = .systemFont(ofSize: 13.5)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 3
    }

    private func setupSuppression() {
        guard let suppressionTitle = options.suppressionTitle else { return }
        suppressionButton.title = suppressionTitle
        suppressionButton.font = .systemFont(ofSize: 13)
        suppressionButton.attributedTitle = NSAttributedString(
            string: suppressionTitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        suppressionButton.setAccessibilityLabel(suppressionTitle)
    }

    private func setupButtons() {
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonTapped(_:))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityLabel(options.cancelTitle)

        confirmButton.target = self
        confirmButton.action = #selector(confirmButtonTapped(_:))
        confirmButton.keyEquivalent = "\r"
        confirmButton.setAccessibilityLabel(options.confirmTitle)
    }

    private func position(_ window: NSWindow, relativeTo sourceWindow: NSWindow?) {
        guard let visibleFrame = sourceWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            window.center()
            return
        }
        let sourceFrame = sourceWindow?.frame ?? visibleFrame
        window.setFrameOrigin(Self.panelOrigin(
            panelSize: window.frame.size,
            sourceWindowFrame: sourceFrame,
            visibleFrame: visibleFrame
        ))
    }

    private static func panelOrigin(
        panelSize: NSSize,
        sourceWindowFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSPoint {
        let centeredOrigin = NSPoint(
            x: sourceWindowFrame.midX - panelSize.width / 2,
            y: sourceWindowFrame.midY - panelSize.height / 2
        )
        return NSPoint(
            x: clamped(centeredOrigin.x, min: visibleFrame.minX, max: visibleFrame.maxX - panelSize.width),
            y: clamped(centeredOrigin.y, min: visibleFrame.minY, max: visibleFrame.maxY - panelSize.height)
        )
    }

    private static func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else {
            return minValue
        }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }

    @objc private func cancelButtonTapped(_ sender: NSButton) {
        cancel()
    }

    @objc private func confirmButtonTapped(_ sender: NSButton) {
        modalResult = PasteraConfirmationResult(
            confirmed: true,
            suppressionChecked: suppressionButton.state == .on
        )
        stopModal()
    }

    private func cancel() {
        modalResult = .cancelled
        stopModal()
    }

    private func stopModal() {
        NSApp.stopModal()
        window?.orderOut(nil)
    }
}

#if DEBUG
struct PasteraConfirmationLayoutForTesting {
    let panelFrame: NSRect
    let iconFrame: NSRect
    let titleFrame: NSRect
    let messageFrame: NSRect
    let cancelButtonFrame: NSRect
    let confirmButtonFrame: NSRect
    let confirmButtonUsesDestructiveStyle: Bool
}

extension PasteraConfirmationController {
    static func panelOriginForTesting(
        panelSize: NSSize,
        sourceWindowFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSPoint {
        panelOrigin(panelSize: panelSize, sourceWindowFrame: sourceWindowFrame, visibleFrame: visibleFrame)
    }

    var confirmationLayoutForTesting: PasteraConfirmationLayoutForTesting? {
        guard let window,
              let rootView = window.contentView else { return nil }
        rootView.layoutSubtreeIfNeeded()
        return PasteraConfirmationLayoutForTesting(
            panelFrame: window.frame,
            iconFrame: iconContainerView.frame,
            titleFrame: titleLabel.frame,
            messageFrame: messageLabel.frame,
            cancelButtonFrame: cancelButton.frame,
            confirmButtonFrame: confirmButton.frame,
            confirmButtonUsesDestructiveStyle: options.isDestructive
        )
    }
}
#endif
