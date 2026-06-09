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

final class PasteraConfirmationController: NSWindowController {
    private let options: PasteraConfirmationOptions
    private let suppressionButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var modalResult = PasteraConfirmationResult.cancelled

    init(options: PasteraConfirmationOptions) {
        self.options = options
        let panel = PasteraConfirmationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 328, height: options.suppressionTitle == nil ? 160 : 188),
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

    static func runModal(options: PasteraConfirmationOptions) -> PasteraConfirmationResult {
        let controller = PasteraConfirmationController(options: options)
        return controller.runModal()
    }

    private func runModal() -> PasteraConfirmationResult {
        guard let window else { return .cancelled }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return modalResult
    }

    private func setup(panel: PasteraConfirmationPanel) {
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let tokens = PasteraDesignTokens.colors()
        let rootView = NSView(frame: panel.contentView?.bounds ?? .zero)
        rootView.autoresizingMask = [.width, .height]
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        rootView.layer?.cornerRadius = PasteraDesignTokens.Metrics.panelCornerRadius
        rootView.layer?.masksToBounds = true
        panel.contentView = rootView

        let titleLabel = NSTextField(labelWithString: options.title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let messageLabel = NSTextField(wrappingLabelWithString: options.message)
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 3

        let cancelButton = NSButton(title: options.cancelTitle, target: self, action: #selector(cancelButtonTapped(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.font = .systemFont(ofSize: 13, weight: .medium)
        cancelButton.keyEquivalent = "\u{1b}"

        let confirmButton = NSButton(title: options.confirmTitle, target: self, action: #selector(confirmButtonTapped(_:)))
        confirmButton.bezelStyle = .rounded
        confirmButton.controlSize = .large
        confirmButton.font = .systemFont(ofSize: 13, weight: .semibold)
        confirmButton.keyEquivalent = "\r"
        confirmButton.contentTintColor = options.isDestructive ? tokens.destructive : tokens.accent
        confirmButton.setAccessibilityLabel(options.confirmTitle)

        let buttonStack = NSStackView(views: [cancelButton, confirmButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually

        [cancelButton, confirmButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)

        if let suppressionTitle = options.suppressionTitle {
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
            stack.addArrangedSubview(suppressionButton)
        }

        stack.addArrangedSubview(buttonStack)
        buttonStack.alignment = .trailing

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 22),

            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            messageLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: 32)
        ])
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
