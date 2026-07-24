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
    private struct Item {
        let view: NSView
        let weight: CGFloat
        let fillsHeight: Bool
    }

    static let breakpoint: CGFloat = 760
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 12

    private let stack = NSStackView()
    private var items = [Item]()
    private var itemWidthConstraints = [NSLayoutConstraint]()
    private var itemHeightConstraints = [NSLayoutConstraint]()
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

    func addItem(_ item: NSView, weight: CGFloat = 1, fillsHeight: Bool = false) {
        items.append(Item(view: item, weight: max(0.01, weight), fillsHeight: fillsHeight))
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
        NSLayoutConstraint.deactivate(itemWidthConstraints)
        NSLayoutConstraint.deactivate(itemHeightConstraints)
        itemWidthConstraints.removeAll()
        itemHeightConstraints.removeAll()
        stack.arrangedSubviews.forEach { row in
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        for startIndex in stride(from: 0, to: items.count, by: columns) {
            let endIndex = min(startIndex + columns, items.count)
            let rowItems = Array(items[startIndex..<endIndex])
            let row = NSStackView(views: rowItems.map(\.view))
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fill
            row.spacing = Self.columnSpacing
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            for item in rowItems where item.fillsHeight {
                let constraint = item.view.heightAnchor.constraint(equalTo: row.heightAnchor)
                constraint.isActive = true
                itemHeightConstraints.append(constraint)
            }
            if rowItems.count == 1 {
                let constraint = rowItems[0].view.widthAnchor.constraint(equalTo: row.widthAnchor)
                constraint.isActive = true
                itemWidthConstraints.append(constraint)
            } else if rowItems.count == 2 {
                let first = rowItems[0]
                let second = rowItems[1]
                let constraint = first.view.widthAnchor.constraint(
                    equalTo: second.view.widthAnchor,
                    multiplier: first.weight / second.weight
                )
                constraint.isActive = true
                itemWidthConstraints.append(constraint)
            }
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
    var fillsAvailableHeight: Bool { false }

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

    func addGroup(
        _ group: PasteraPreferenceGroupView,
        anchorID: String? = nil,
        weight: CGFloat = 1
    ) {
        _ = view
        addAdaptiveContent(group, weight: weight)
        if let anchorID {
            registerAnchor(anchorID, view: group)
        }
        invalidateContentSize()
    }

    func addAdaptiveContent(_ content: NSView, weight: CGFloat = 1, fillsHeight: Bool = false) {
        _ = view
        adaptiveGrid.addItem(content, weight: weight, fillsHeight: fillsHeight)
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
extension PasteraPreferenceAdaptiveGridView {
    var itemWidthsForTesting: [CGFloat] {
        items.map { $0.view.frame.width }
    }
}

extension PasteraPreferencePageViewController {
    var adaptiveColumnCountForTesting: Int { adaptiveGrid.columnCount }
    var adaptiveRowCountForTesting: Int { adaptiveGrid.rowCount }
    var adaptiveItemWidthsForTesting: [CGFloat] { adaptiveGrid.itemWidthsForTesting }
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

final class PasteraPreferenceEmptyStateView: NSView {
    init(
        symbolName: String,
        title: String,
        message: String,
        minimumHeight: CGFloat = 108
    ) {
        super.init(frame: .zero)

        let imageView = NSImageView(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage()
        )
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 11.5)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [imageView, titleLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class PasteraPreferenceActionBarView: NSStackView {
    init(primaryAction: NSButton, secondaryActions: [NSButton]) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        primaryAction.bezelStyle = .rounded
        primaryAction.bezelColor = .controlAccentColor
        primaryAction.contentTintColor = .white
        addArrangedSubview(primaryAction)

        secondaryActions.forEach {
            $0.bezelStyle = .rounded
            addArrangedSubview($0)
        }
        addArrangedSubview(NSView())
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class PasteraPreferenceSheetScaffold: NSView {
    static let bodyHorizontalInset: CGFloat = 22

    let contentStack = NSStackView()
    let documentView = PasteraPreferenceFlippedView()

    private let scrollView = NSScrollView()
    private let footerLeadingStack = NSStackView()
    private let footerTrailingStack = NSStackView()

    init(
        title: String,
        subtitle: String,
        minimumSize: NSSize,
        idealSize: NSSize
    ) {
        super.init(frame: NSRect(origin: .zero, size: idealSize))
        identifier = NSUserInterfaceItemIdentifier("preference.sheet.scaffold")
        setAccessibilityIdentifier("preference.sheet.scaffold")
        translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader(title: title, subtitle: subtitle)
        header.identifier = NSUserInterfaceItemIdentifier("preference.sheet.header")
        header.setAccessibilityIdentifier("preference.sheet.header")
        let footer = makeFooter()
        footer.identifier = NSUserInterfaceItemIdentifier("preference.sheet.footer")
        footer.setAccessibilityIdentifier("preference.sheet.footer")

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier("preference.sheet.body")
        scrollView.setAccessibilityIdentifier("preference.sheet.body")
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.frame = NSRect(
            x: Self.bodyHorizontalInset,
            y: 18,
            width: max(1, idealSize.width - Self.bodyHorizontalInset * 2),
            height: 1_200
        )
        contentStack.translatesAutoresizingMaskIntoConstraints = true
        contentStack.autoresizingMask = [.width]
        documentView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: idealSize.width, height: 1_236)
        )
        documentView.autoresizingMask = [.width]
        documentView.addSubview(contentStack)
        scrollView.documentView = documentView

        addSubview(header)
        addSubview(scrollView)
        addSubview(footer)

        let idealWidth = widthAnchor.constraint(equalToConstant: idealSize.width)
        idealWidth.priority = .defaultHigh
        let idealHeight = heightAnchor.constraint(equalToConstant: idealSize.height)
        idealHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: minimumSize.width),
            heightAnchor.constraint(greaterThanOrEqualToConstant: minimumSize.height),
            idealWidth,
            idealHeight,
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 74),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func addBodyView(_ bodyView: NSView) {
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(bodyView)
        bodyView.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        needsLayout = true
    }

    func setFooterActions(leading: [NSView] = [], trailing: [NSView]) {
        replaceArrangedSubviews(in: footerLeadingStack, with: leading)
        replaceArrangedSubviews(in: footerTrailingStack, with: trailing)
    }

    override func layout() {
        super.layout()
        let availableWidth = max(
            1,
            scrollView.contentSize.width - Self.bodyHorizontalInset * 2
        )
        contentStack.frame = NSRect(
            x: Self.bodyHorizontalInset,
            y: 18,
            width: availableWidth,
            height: max(1, contentStack.frame.height)
        )
        contentStack.layoutSubtreeIfNeeded()
        let contentHeight = max(1, contentStack.fittingSize.height)
        contentStack.frame.size = NSSize(width: availableWidth, height: contentHeight)
        documentView.frame.size = NSSize(
            width: scrollView.contentSize.width,
            height: max(scrollView.contentSize.height, contentHeight + 36)
        )
    }

    private func makeHeader(title: String, subtitle: String) -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11.5)
        subtitleLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false

        let separator = makeSeparator()
        header.addSubview(labels)
        header.addSubview(separator)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Self.bodyHorizontalInset),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -Self.bodyHorizontalInset),
            labels.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: PasteraDesignTokens.Metrics.hairlineWidth)
        ])
        return header
    }

    private func makeFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        footerLeadingStack.orientation = .horizontal
        footerLeadingStack.alignment = .centerY
        footerLeadingStack.spacing = 8
        footerLeadingStack.translatesAutoresizingMaskIntoConstraints = false
        footerTrailingStack.orientation = .horizontal
        footerTrailingStack.alignment = .centerY
        footerTrailingStack.spacing = 8
        footerTrailingStack.translatesAutoresizingMaskIntoConstraints = false

        let separator = makeSeparator()
        footer.addSubview(separator)
        footer.addSubview(footerLeadingStack)
        footer.addSubview(footerTrailingStack)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: PasteraDesignTokens.Metrics.hairlineWidth),
            footerLeadingStack.leadingAnchor.constraint(
                equalTo: footer.leadingAnchor,
                constant: Self.bodyHorizontalInset
            ),
            footerLeadingStack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            footerTrailingStack.trailingAnchor.constraint(
                equalTo: footer.trailingAnchor,
                constant: -Self.bodyHorizontalInset
            ),
            footerTrailingStack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            footerLeadingStack.trailingAnchor.constraint(
                lessThanOrEqualTo: footerTrailingStack.leadingAnchor,
                constant: -12
            )
        ])
        return footer
    }

    private func makeSeparator() -> NSView {
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func replaceArrangedSubviews(in stack: NSStackView, with views: [NSView]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        views.forEach(stack.addArrangedSubview)
    }
}

final class PasteraPreferenceFlippedView: NSView {
    override var isFlipped: Bool { true }
}
