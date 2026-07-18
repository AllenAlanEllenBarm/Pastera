//
//  PasteraPreferenceComponents.swift
//
//  Pastera
//

import AppKit
import QuartzCore

typealias PasteraPreferencePageController = NSViewController & PasteraPreferencePage
typealias PasteraPreferencePageControllerProvider = (PasteraPreferencePaneID) -> PasteraPreferencePageController

func pasteraPreferenceString(_ key: String, defaultValue: String? = nil) -> String {
    Bundle.main.localizedString(forKey: key, value: defaultValue ?? key, table: nil)
}

private final class PasteraPreferenceHighlightView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let color = NSColor.controlAccentColor
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.rowCornerRadius
        layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        layer?.borderColor = color.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 1.5
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class PasteraPreferenceAnchorRevealer {
    static let highlightDuration: TimeInterval = 1.0

    private(set) var highlightedAnchorID: String?
    private(set) var lastRevealAnimated = false

    private weak var highlightedView: NSView?
    private var highlightView: PasteraPreferenceHighlightView?
    private var restoreWorkItem: DispatchWorkItem?

    deinit {
        restoreWorkItem?.cancel()
    }

    func reveal(anchorID: String, view anchorView: NSView, animated: Bool) -> Bool {
        restoreHighlight(animated: false)
        anchorView.scrollToVisible(anchorView.bounds.insetBy(dx: 0, dy: -12))

        let highlightView = PasteraPreferenceHighlightView(frame: anchorView.bounds)
        highlightView.alphaValue = 1
        anchorView.addSubview(highlightView, positioned: .above, relativeTo: nil)

        highlightedAnchorID = anchorID
        highlightedView = anchorView
        self.highlightView = highlightView
        lastRevealAnimated = animated

        if animated {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = 0.12
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            highlightView.layer?.add(animation, forKey: "PasteraPreferenceHighlightIn")
        }

        let workItem = DispatchWorkItem { [weak self, weak highlightView] in
            guard let self, self.highlightView === highlightView else { return }
            self.restoreHighlight(animated: animated)
        }
        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.highlightDuration,
            execute: workItem
        )
        return true
    }

    func isHighlighting(_ view: NSView) -> Bool {
        highlightedView === view && highlightView?.superview === view
    }

    func completeHighlight() {
        restoreHighlight(animated: false)
    }

    private func restoreHighlight(animated: Bool) {
        restoreWorkItem?.cancel()
        restoreWorkItem = nil

        guard let highlightView else {
            highlightedAnchorID = nil
            highlightedView = nil
            return
        }
        self.highlightView = nil
        highlightedAnchorID = nil
        highlightedView = nil

        guard animated else {
            highlightView.layer?.removeAllAnimations()
            highlightView.removeFromSuperview()
            return
        }
        highlightView.alphaValue = 0
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        highlightView.layer?.add(animation, forKey: "PasteraPreferenceHighlightOut")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak highlightView] in
            highlightView?.removeFromSuperview()
        }
    }
}

final class PasteraPreferenceAdaptiveGridView: NSView {
    static let breakpoint: CGFloat = 760
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 12

    private let stack = NSStackView()
    private var items = [NSView]()
    private(set) var columnCount = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func addItem(_ item: NSView) {
        items.append(item)
        rebuild(columns: preferredColumnCount(for: bounds.width))
    }

    func removeAllItems() {
        items.removeAll()
        rebuild(columns: 1)
    }

    override func layout() {
        let preferredColumns = preferredColumnCount(for: bounds.width)
        if preferredColumns != columnCount {
            rebuild(columns: preferredColumns)
        }
        super.layout()
    }

    var rowCount: Int {
        stack.arrangedSubviews.count
    }

    private func preferredColumnCount(for width: CGFloat) -> Int {
        width >= Self.breakpoint ? 2 : 1
    }

    private func rebuild(columns: Int) {
        columnCount = columns
        stack.arrangedSubviews.forEach { row in
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        for startIndex in stride(from: 0, to: items.count, by: columns) {
            let endIndex = min(startIndex + columns, items.count)
            let row = NSStackView(views: Array(items[startIndex..<endIndex]))
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = Self.columnSpacing
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        invalidateIntrinsicContentSize()
    }
}

class PasteraPreferencePageViewController: NSViewController, PasteraPreferencePage {
    static let pageTopInset: CGFloat = 14
    static let pageHorizontalInset: CGFloat = 24

    let paneID: PasteraPreferencePaneID
    let contentStack = NSStackView()
    var onContentSizeChange: ((NSSize) -> Void)?

    private let pageTitle: String
    private let documentView = PasteraPreferencePageDocumentView()
    private let adaptiveGrid = PasteraPreferenceAdaptiveGridView()
    private let anchorRevealer = PasteraPreferenceAnchorRevealer()
    private var anchors = [String: NSView]()

    init(paneID: PasteraPreferencePaneID, title: String) {
        self.paneID = paneID
        self.pageTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        adaptiveGrid.removeAllItems()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: pageTitle)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .labelColor
        contentStack.addArrangedSubview(titleLabel)
        contentStack.setCustomSpacing(14, after: titleLabel)
        contentStack.addArrangedSubview(adaptiveGrid)
        adaptiveGrid.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        documentView.addSubview(contentStack)
        documentView.measuredContentView = contentStack
        view = documentView

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: documentView.leadingAnchor,
                constant: Self.pageHorizontalInset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: documentView.trailingAnchor,
                constant: -Self.pageHorizontalInset
            ),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: Self.pageTopInset),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -22)
        ])
        invalidateContentSize()
    }

    func addGroup(_ group: PasteraPreferenceGroupView, anchorID: String? = nil) {
        _ = view
        addAdaptiveContent(group)
        if let anchorID {
            registerAnchor(anchorID, view: group)
        }
        invalidateContentSize()
    }

    func addAdaptiveContent(_ content: NSView) {
        _ = view
        adaptiveGrid.addItem(content)
        invalidateContentSize()
    }

    func registerAnchor(_ anchorID: String, view: NSView) {
        anchors[anchorID] = view
        view.setAccessibilityIdentifier(anchorID)
    }

    func revealSetting(anchorID: String, animated: Bool) -> Bool {
        _ = view
        guard let anchorView = anchors[anchorID] else { return false }
        return anchorRevealer.reveal(anchorID: anchorID, view: anchorView, animated: animated)
    }

    func invalidateContentSize() {
        documentView.invalidateIntrinsicContentSize()
        documentView.layoutSubtreeIfNeeded()
        let size = documentView.fittingSize
        documentView.frame.size = size
        onContentSizeChange?(size)
    }
}

private final class PasteraPreferencePageDocumentView: NSView {
    weak var measuredContentView: NSView?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        measuredSize
    }

    override var fittingSize: NSSize {
        measuredSize
    }

    private var measuredSize: NSSize {
        guard let measuredContentView else {
            return NSSize(width: 480, height: 1)
        }
        let contentSize = measuredContentView.fittingSize
        return NSSize(
            width: max(480, contentSize.width + PasteraPreferencePageViewController.pageHorizontalInset * 2),
            height: max(1, contentSize.height + 44)
        )
    }
}

#if DEBUG
extension PasteraPreferencePageViewController {
    var adaptiveColumnCountForTesting: Int { adaptiveGrid.columnCount }
    var adaptiveRowCountForTesting: Int { adaptiveGrid.rowCount }
    var preferencePageHorizontalInsetForTesting: CGFloat { Self.pageHorizontalInset }
    var preferencePageColumnSpacingForTesting: CGFloat { PasteraPreferenceAdaptiveGridView.columnSpacing }

    var highlightedAnchorIDForTesting: String? {
        anchorRevealer.highlightedAnchorID
    }

    var lastRevealAnimatedForTesting: Bool {
        anchorRevealer.lastRevealAnimated
    }

    var highlightDurationForTesting: TimeInterval {
        PasteraPreferenceAnchorRevealer.highlightDuration
    }

    func isAnchorHighlightedForTesting(_ anchorID: String) -> Bool {
        guard let anchorView = anchors[anchorID] else { return false }
        return anchorRevealer.isHighlighting(anchorView)
    }

    func completeHighlightForTesting() {
        anchorRevealer.completeHighlight()
    }
}

#endif

final class PasteraPreferenceGroupView: NSView {
    let contentStack = NSStackView()
    private var rowCount = 0
    private weak var headerStack: NSStackView?

    init(
        title: String,
        symbolName: String = "slider.horizontal.3",
        accentColor: NSColor = .controlAccentColor
    ) {
        super.init(frame: .zero)
        setup(title: title, symbolName: symbolName, accentColor: accentColor)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(title: "", symbolName: "slider.horizontal.3", accentColor: .controlAccentColor)
    }

    func addRow(_ row: PasteraPreferenceSettingRowView) {
        addSeparator()
        contentStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        rowCount += 1
    }

    func addContent(_ view: NSView) {
        addSeparator()
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    func setHeaderAccessory(_ view: NSView) {
        headerStack?.addArrangedSubview(view)
    }

    private func setup(title: String, symbolName: String, accentColor: NSColor) {
        let colors = PasteraDesignTokens.colors(for: effectiveAppearance, opacity: 1)
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.rowCornerRadius
        layer?.backgroundColor = colors.surface.withAlphaComponent(0.58).cgColor
        layer?.borderColor = colors.separator.cgColor
        layer?.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth
        layer?.masksToBounds = true

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        if !title.isEmpty {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage()
            let imageView = NSImageView(image: image)
            imageView.contentTintColor = accentColor
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            imageView.setAccessibilityIdentifier("preference.group.icon")
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .labelColor

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let headerStack = NSStackView(views: [imageView, label, spacer])
            headerStack.orientation = .horizontal
            headerStack.alignment = .centerY
            headerStack.spacing = 8
            headerStack.edgeInsets = NSEdgeInsets(top: 5, left: 14, bottom: 5, right: 12)
            contentStack.addArrangedSubview(headerStack)
            self.headerStack = headerStack

            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
                headerStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 38)
            ])
        }

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func addSeparator() {
        guard rowCount > 0 || !contentStack.arrangedSubviews.isEmpty else { return }
        let separator = NSView()
        separator.wantsLayer = true
        let separatorAlpha: CGFloat = PasteraDesignTokens.isDarkAppearance(effectiveAppearance) ? 0.10 : 0.08
        separator.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(separatorAlpha).cgColor
        separator.setAccessibilityIdentifier("preference.group.separator")
        contentStack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            separator.heightAnchor.constraint(equalToConstant: PasteraDesignTokens.Metrics.hairlineWidth)
        ])
    }
}

final class PasteraPreferenceSettingRowView: NSView {
    init(title: String, subtitle: String? = nil, control: NSView, minimumHeight: CGFloat = 48) {
        super.init(frame: .zero)
        setup(title: title, subtitle: subtitle, control: control, minimumHeight: minimumHeight)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup(title: String, subtitle: String?, control: NSView, minimumHeight: CGFloat) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.addArrangedSubview(titleLabel)
        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 11.5)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.maximumNumberOfLines = 3
            labels.addArrangedSubview(subtitleLabel)
        }

        labels.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)
        addSubview(control)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            control.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
            heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight)
        ])
    }
}

final class PasteraPreferenceStatusView: NSStackView {
    enum Style {
        case neutral
        case success
        case warning
        case error
    }

    init(text: String, style: Style = .neutral) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 6

        let symbolName: String
        let color: NSColor
        switch style {
        case .neutral:
            symbolName = "info.circle"
            color = .secondaryLabelColor
        case .success:
            symbolName = "checkmark.circle.fill"
            color = .systemGreen
        case .warning:
            symbolName = "exclamationmark.triangle.fill"
            color = .systemOrange
        case .error:
            symbolName = "xmark.octagon.fill"
            color = .systemRed
        }

        let imageView = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage())
        imageView.contentTintColor = color
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = color
        addArrangedSubview(imageView)
        addArrangedSubview(label)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class PasteraPreferenceFlippedView: NSView {
    override var isFlipped: Bool { true }
}
