//
//  HistoryMenuImagePreviewController.swift
//  Clipy
//
//  Created by Codex on 2026/06/03.
//

import Cocoa
import QuartzCore

private enum HistoryMenuPreviewSide {
    case leftOfSource
    case rightOfSource
}

private struct HistoryMenuPreviewPlacement {
    let targetFrame: NSRect
    let entryFrame: NSRect
    let side: HistoryMenuPreviewSide
    let anchorY: CGFloat
}

private enum HistoryMenuPreviewMotion {
    static let appearDuration: TimeInterval = 0.14
    static let repositionDuration: TimeInterval = 0.10
    static let hideDuration: TimeInterval = 0.08
    static let entryOffset: CGFloat = 12
    static let notchDepth: CGFloat = 10
    static let notchMinimumVerticalInset: CGFloat = 18

    #if DEBUG
    static var disableAnimationsForTesting = false
    #endif

    static func show(panel: NSPanel, placement: HistoryMenuPreviewPlacement) {
        let wasVisible = panel.isVisible
        if !wasVisible {
            panel.alphaValue = 0
            panel.setFrame(placement.entryFrame, display: false)
            panel.orderFront(nil)
        }

        guard !shouldPlaceImmediately else {
            panel.setFrame(placement.targetFrame, display: true)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = wasVisible ? repositionDuration : appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(placement.targetFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    static func hide(panel: NSPanel, canComplete: @escaping () -> Bool, completion: @escaping () -> Void) {
        guard panel.isVisible, !shouldPlaceImmediately else {
            guard canComplete() else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            guard canComplete() else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            completion()
        }
    }

    static func placement(
        cardSize: NSSize,
        horizontalOffset: CGFloat,
        relativeTo rect: NSRect,
        in sourceView: NSView?
    ) -> HistoryMenuPreviewPlacement {
        let size = NSSize(width: cardSize.width + notchDepth, height: cardSize.height)
        let sourceRect = sourceScreenRect(relativeTo: rect, in: sourceView)
        let screenFrame = sourceView?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        var origin = NSPoint(
            x: sourceRect.maxX + horizontalOffset,
            y: sourceRect.midY - size.height / 2
        )
        var side = HistoryMenuPreviewSide.rightOfSource

        if let screenFrame {
            let rightOriginX = sourceRect.maxX + horizontalOffset
            let leftOriginX = sourceRect.minX - horizontalOffset - size.width
            let rightSpace = screenFrame.maxX - rightOriginX
            let leftSpace = leftOriginX + size.width - screenFrame.minX
            let rightFits = rightSpace >= size.width
            let leftFits = leftOriginX >= screenFrame.minX

            if rightFits || (!leftFits && rightSpace >= leftSpace) {
                origin.x = rightOriginX
                side = .rightOfSource
            } else {
                origin.x = leftOriginX
                side = .leftOfSource
            }
            origin.x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - size.width)
            origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height)
        }

        let targetFrame = NSRect(origin: origin, size: size)
        let entryDirection: CGFloat = side == .leftOfSource ? 1 : -1
        let entryFrame = targetFrame.offsetBy(dx: entryDirection * entryOffset, dy: 0)
        let anchorY = min(
            max(sourceRect.midY - targetFrame.minY, notchMinimumVerticalInset),
            max(notchMinimumVerticalInset, size.height - notchMinimumVerticalInset)
        )
        return HistoryMenuPreviewPlacement(
            targetFrame: targetFrame,
            entryFrame: entryFrame,
            side: side,
            anchorY: anchorY
        )
    }

    private static var shouldPlaceImmediately: Bool {
        #if DEBUG
        if disableAnimationsForTesting {
            return true
        }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func sourceScreenRect(relativeTo rect: NSRect, in sourceView: NSView?) -> NSRect {
        guard let sourceView,
              let window = sourceView.window else {
            return rect
        }
        let windowRect = sourceView.convert(rect, to: nil)
        return window.convertToScreen(windowRect)
    }
}

private final class HistoryMenuPreviewContainerView: NSView {
    let cardView = NSView()
    private let notchView = HistoryMenuPreviewNotchView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(cardView)
        addSubview(notchView)

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 9
        cardView.layer?.masksToBounds = true
        cardView.layer?.backgroundColor = previewBackgroundColor.cgColor
        cardView.layer?.borderColor = previewBorderColor.cgColor
        cardView.layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { nil }

    func configure(cardSize: NSSize, side: HistoryMenuPreviewSide, anchorY: CGFloat) {
        frame = NSRect(
            origin: .zero,
            size: NSSize(width: cardSize.width + HistoryMenuPreviewMotion.notchDepth, height: cardSize.height)
        )
        notchView.side = side
        notchView.anchorY = anchorY

        switch side {
        case .leftOfSource:
            cardView.frame = NSRect(origin: .zero, size: cardSize)
            notchView.frame = NSRect(
                x: cardSize.width - 0.5,
                y: 0,
                width: HistoryMenuPreviewMotion.notchDepth + 0.5,
                height: cardSize.height
            )
        case .rightOfSource:
            notchView.frame = NSRect(
                x: 0,
                y: 0,
                width: HistoryMenuPreviewMotion.notchDepth + 0.5,
                height: cardSize.height
            )
            cardView.frame = NSRect(
                x: HistoryMenuPreviewMotion.notchDepth,
                y: 0,
                width: cardSize.width,
                height: cardSize.height
            )
        }
        notchView.needsDisplay = true
    }
}

private final class HistoryMenuPreviewNotchView: NSView {
    var side = HistoryMenuPreviewSide.rightOfSource {
        didSet { needsDisplay = true }
    }

    var anchorY: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("historyPreviewNotchView")
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let halfHeight: CGFloat = 22
        let anchorPositionY = min(
            max(anchorY, halfHeight + 1),
            max(halfHeight + 1, bounds.height - halfHeight - 1)
        )
        let path = NSBezierPath()
        switch side {
        case .leftOfSource:
            path.move(to: NSPoint(x: bounds.minX, y: anchorPositionY - halfHeight))
            path.curve(
                to: NSPoint(x: bounds.maxX, y: anchorPositionY),
                controlPoint1: NSPoint(x: bounds.minX, y: anchorPositionY - 10),
                controlPoint2: NSPoint(x: bounds.maxX, y: anchorPositionY - 12)
            )
            path.curve(
                to: NSPoint(x: bounds.minX, y: anchorPositionY + halfHeight),
                controlPoint1: NSPoint(x: bounds.maxX, y: anchorPositionY + 12),
                controlPoint2: NSPoint(x: bounds.minX, y: anchorPositionY + 10)
            )
        case .rightOfSource:
            path.move(to: NSPoint(x: bounds.maxX, y: anchorPositionY - halfHeight))
            path.curve(
                to: NSPoint(x: bounds.minX, y: anchorPositionY),
                controlPoint1: NSPoint(x: bounds.maxX, y: anchorPositionY - 10),
                controlPoint2: NSPoint(x: bounds.minX, y: anchorPositionY - 12)
            )
            path.curve(
                to: NSPoint(x: bounds.maxX, y: anchorPositionY + halfHeight),
                controlPoint1: NSPoint(x: bounds.minX, y: anchorPositionY + 12),
                controlPoint2: NSPoint(x: bounds.maxX, y: anchorPositionY + 10)
            )
        }
        path.close()

        previewBackgroundColor.setFill()
        previewBorderColor.setStroke()
        path.fill()
        path.lineWidth = 1
        path.stroke()
    }
}

private let previewBackgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97)
private let previewBorderColor = NSColor.separatorColor.withAlphaComponent(0.5)

final class HistoryMenuImagePreviewController {
    private enum Metrics {
        static let cardSize = NSSize(width: 360, height: 248)
        static let contentInset: CGFloat = 7
        static let horizontalOffset: CGFloat = 10
    }

    private(set) var panel: NSPanel?
    private let imageView = NSImageView()
    private var isHiding = false
    private var previewGeneration = 0

    func show(image: NSImage, relativeTo rect: NSRect, in sourceView: NSView?) {
        let panel = panel ?? makePanel()
        let contentView = (panel.contentView as? HistoryMenuPreviewContainerView) ?? makeContentView()
        if panel.contentView !== contentView {
            panel.contentView = contentView
        }
        isHiding = false
        previewGeneration += 1

        imageView.image = image
        let placement = HistoryMenuPreviewMotion.placement(
            cardSize: Metrics.cardSize,
            horizontalOffset: Metrics.horizontalOffset,
            relativeTo: rect,
            in: sourceView
        )
        contentView.configure(cardSize: Metrics.cardSize, side: placement.side, anchorY: placement.anchorY)
        panel.setContentSize(placement.targetFrame.size)
        contentView.layoutSubtreeIfNeeded()
        HistoryMenuPreviewMotion.show(panel: panel, placement: placement)
    }

    func hide() {
        guard let panel else {
            imageView.image = nil
            return
        }
        isHiding = true
        let hideGeneration = previewGeneration
        HistoryMenuPreviewMotion.hide(panel: panel) { [weak self] in
            guard let self else { return false }
            return self.isHiding && self.previewGeneration == hideGeneration
        } completion: { [weak self] in
            guard let self, self.isHiding, self.previewGeneration == hideGeneration else { return }
            self.imageView.image = nil
            self.isHiding = false
        }
    }

    deinit {
        panel?.close()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: Metrics.cardSize.width + HistoryMenuPreviewMotion.notchDepth,
                    height: Metrics.cardSize.height
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        panel.contentView = makeContentView()
        self.panel = panel
        return panel
    }

    private func makeContentView() -> HistoryMenuPreviewContainerView {
        let contentView = HistoryMenuPreviewContainerView()

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        contentView.cardView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.cardView.leadingAnchor, constant: Metrics.contentInset),
            imageView.trailingAnchor.constraint(equalTo: contentView.cardView.trailingAnchor, constant: -Metrics.contentInset),
            imageView.topAnchor.constraint(equalTo: contentView.cardView.topAnchor, constant: Metrics.contentInset),
            imageView.bottomAnchor.constraint(equalTo: contentView.cardView.bottomAnchor, constant: -Metrics.contentInset)
        ])

        return contentView
    }
}

final class HistoryMenuTextPreviewController {
    private enum Metrics {
        static let cardSize = NSSize(width: 288, height: 112)
        static let contentInset: CGFloat = 10
        static let horizontalOffset: CGFloat = 10
    }

    private(set) var panel: NSPanel?
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private var isHiding = false
    private var previewGeneration = 0

    func show(text: String, relativeTo rect: NSRect, in sourceView: NSView?) {
        let panel = panel ?? makePanel()
        let contentView = (panel.contentView as? HistoryMenuPreviewContainerView) ?? makeContentView()
        if panel.contentView !== contentView {
            panel.contentView = contentView
        }
        isHiding = false
        previewGeneration += 1

        textLabel.stringValue = text
        let placement = HistoryMenuPreviewMotion.placement(
            cardSize: Metrics.cardSize,
            horizontalOffset: Metrics.horizontalOffset,
            relativeTo: rect,
            in: sourceView
        )
        contentView.configure(cardSize: Metrics.cardSize, side: placement.side, anchorY: placement.anchorY)
        panel.setContentSize(placement.targetFrame.size)
        HistoryMenuPreviewMotion.show(panel: panel, placement: placement)
    }

    func hide() {
        guard let panel else {
            textLabel.stringValue = ""
            return
        }
        isHiding = true
        let hideGeneration = previewGeneration
        HistoryMenuPreviewMotion.hide(panel: panel) { [weak self] in
            guard let self else { return false }
            return self.isHiding && self.previewGeneration == hideGeneration
        } completion: { [weak self] in
            guard let self, self.isHiding, self.previewGeneration == hideGeneration else { return }
            self.textLabel.stringValue = ""
            self.isHiding = false
        }
    }

    deinit {
        panel?.close()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: Metrics.cardSize.width + HistoryMenuPreviewMotion.notchDepth,
                    height: Metrics.cardSize.height
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        panel.contentView = makeContentView()
        self.panel = panel
        return panel
    }

    private func makeContentView() -> HistoryMenuPreviewContainerView {
        let contentView = HistoryMenuPreviewContainerView()

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .systemFont(ofSize: 12)
        textLabel.textColor = .labelColor
        textLabel.maximumNumberOfLines = 5
        textLabel.lineBreakMode = .byTruncatingTail
        contentView.cardView.addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: contentView.cardView.leadingAnchor, constant: Metrics.contentInset),
            textLabel.trailingAnchor.constraint(equalTo: contentView.cardView.trailingAnchor, constant: -Metrics.contentInset),
            textLabel.topAnchor.constraint(equalTo: contentView.cardView.topAnchor, constant: Metrics.contentInset),
            textLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.cardView.bottomAnchor,
                constant: -Metrics.contentInset
            )
        ])

        return contentView
    }
}

#if DEBUG
extension HistoryMenuImagePreviewController {
    static var disableAnimationsForTesting: Bool {
        get { HistoryMenuPreviewMotion.disableAnimationsForTesting }
        set { HistoryMenuPreviewMotion.disableAnimationsForTesting = newValue }
    }

    var isVisibleForTesting: Bool {
        panel?.isVisible == true && !isHiding
    }
}

extension HistoryMenuTextPreviewController {
    var isVisibleForTesting: Bool {
        panel?.isVisible == true && !isHiding
    }

    var textValueForTesting: String {
        textLabel.stringValue
    }
}
#endif
