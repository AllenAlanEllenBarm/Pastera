//
//  PasteraDesignSystem.swift
//
//  Clipy
//

import Cocoa

enum PasteraDesignTokens {
    struct ColorSet: Equatable {
        let panelBackground: NSColor
        let surface: NSColor
        let elevatedSurface: NSColor
        let hoveredRow: NSColor
        let selectedRow: NSColor
        let separator: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        let accent: NSColor
        let destructive: NSColor

        static func == (lhs: ColorSet, rhs: ColorSet) -> Bool {
            lhs.panelBackground == rhs.panelBackground
                && lhs.surface == rhs.surface
                && lhs.elevatedSurface == rhs.elevatedSurface
                && lhs.hoveredRow == rhs.hoveredRow
                && lhs.selectedRow == rhs.selectedRow
                && lhs.separator == rhs.separator
                && lhs.primaryText == rhs.primaryText
                && lhs.secondaryText == rhs.secondaryText
                && lhs.accent == rhs.accent
                && lhs.destructive == rhs.destructive
        }
    }

    enum Metrics {
        static let panelCornerRadius: CGFloat = 16
        static let rowCornerRadius: CGFloat = 8
        static let compactRowCornerRadius: CGFloat = 7
        static let controlCornerRadius: CGFloat = 8
        static let panelShadowRadius: CGFloat = 18
        static let panelShadowOpacity: Float = 0.18
        static let hairlineWidth: CGFloat = 1
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
    }

    enum Motion {
        static let quickDuration: TimeInterval = 0.10
        static let standardDuration: TimeInterval = 0.14

        static var shouldReduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        static func duration(_ value: TimeInterval) -> TimeInterval {
            shouldReduceMotion ? 0 : value
        }
    }

    static func colors(for appearance: NSAppearance? = nil, opacity: CGFloat? = nil) -> ColorSet {
        let isDark = isDarkAppearance(appearance)
        let panelAlpha = opacity ?? CGFloat(CPYWindowAppearance.defaultOpacity)

        if isDark {
            return ColorSet(
                panelBackground: NSColor(calibratedRed: 0.105, green: 0.110, blue: 0.120, alpha: panelAlpha),
                surface: NSColor(calibratedWhite: 0.16, alpha: 0.86),
                elevatedSurface: NSColor(calibratedWhite: 0.20, alpha: 0.92),
                hoveredRow: NSColor(calibratedWhite: 1.0, alpha: 0.075),
                selectedRow: NSColor(calibratedRed: 0.19, green: 0.45, blue: 0.92, alpha: 0.90),
                separator: NSColor(calibratedWhite: 1.0, alpha: 0.14),
                primaryText: .labelColor,
                secondaryText: .secondaryLabelColor,
                accent: .controlAccentColor,
                destructive: NSColor(calibratedRed: 1.0, green: 0.28, blue: 0.24, alpha: 1.0)
            )
        }

        return ColorSet(
            panelBackground: NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.974, alpha: panelAlpha),
            surface: NSColor(calibratedWhite: 1.0, alpha: 0.78),
            elevatedSurface: NSColor(calibratedWhite: 1.0, alpha: 0.94),
            hoveredRow: NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.055),
            selectedRow: NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.88, alpha: 0.90),
            separator: NSColor(calibratedWhite: 0.0, alpha: 0.12),
            primaryText: .labelColor,
            secondaryText: .secondaryLabelColor,
            accent: .controlAccentColor,
            destructive: NSColor(calibratedRed: 0.88, green: 0.12, blue: 0.10, alpha: 1.0)
        )
    }

    static func isDarkAppearance(_ appearance: NSAppearance? = nil) -> Bool {
        let targetAppearance = appearance ?? NSApp.effectiveAppearance
        return targetAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

enum PasteraMotion {
    static let quickDuration = PasteraDesignTokens.Motion.quickDuration
    static let standardDuration = PasteraDesignTokens.Motion.standardDuration

    static var shouldReduceMotion: Bool {
        PasteraDesignTokens.Motion.shouldReduceMotion
    }
}

final class PasteraToolbarButton: NSButton {
    init(title: String, symbolName: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setup(symbolName: symbolName)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(symbolName: nil)
    }

    private func setup(symbolName: String?) {
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        controlSize = .regular
        font = .systemFont(ofSize: 12.5, weight: .medium)
        imagePosition = .imageLeading
        contentTintColor = .labelColor
        if let symbolName {
            image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        }
        setContentHuggingPriority(.required, for: .horizontal)
    }
}

final class PasteraSectionView: NSView {
    let contentView = NSStackView()

    init(title: String? = nil) {
        super.init(frame: .zero)
        setup(title: title)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(title: nil)
    }

    private func setup(title: String?) {
        let tokens = PasteraDesignTokens.colors()
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.rowCornerRadius
        layer?.backgroundColor = tokens.surface.cgColor
        layer?.borderColor = tokens.separator.cgColor
        layer?.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth

        contentView.orientation = .vertical
        contentView.spacing = PasteraDesignTokens.Spacing.medium
        contentView.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .secondaryLabelColor
            contentView.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class PasteraShortcutBadgeView: NSView {
    enum Style: Equatable {
        case command
        case itemNumber
    }

    enum Metrics {
        static let horizontalPadding: CGFloat = 3
        static let height: CGFloat = 16
        static let minWidth: CGFloat = 22
        static let cornerRadius: CGFloat = 4

        static let itemHorizontalPadding: CGFloat = 5
        static let itemHeight: CGFloat = 20
        static let itemMinWidth: CGFloat = 22
        static let itemCornerRadius: CGFloat = 5
    }

    var shortcutText: String? {
        didSet {
            updateText()
        }
    }

    var style: Style = .command {
        didSet {
            updateStyle()
        }
    }

    var isEmphasized = false {
        didSet {
            updateAppearance()
        }
    }

    var isBadgeEnabled = true {
        didSet {
            updateAppearance()
        }
    }

    private let label = NSTextField(labelWithString: "")
    private var labelLeadingConstraint: NSLayoutConstraint?
    private var labelTrailingConstraint: NSLayoutConstraint?

    init(shortcutText: String? = nil, style: Style = .command) {
        self.shortcutText = shortcutText
        self.style = style
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        guard label.stringValue.isEmpty == false else {
            return .zero
        }
        let width = max(
            minWidth,
            ceil(label.intrinsicContentSize.width + horizontalPadding * 2)
        )
        return NSSize(width: width, height: height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setState(isEmphasized: Bool, isEnabled: Bool = true) {
        self.isEmphasized = isEmphasized
        self.isBadgeEnabled = isEnabled
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        let leadingConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding)
        let trailingConstraint = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding)
        labelLeadingConstraint = leadingConstraint
        labelTrailingConstraint = trailingConstraint

        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateStyle()
        updateText()
        updateAppearance()
    }

    private func updateStyle() {
        label.font = font
        layer?.cornerRadius = cornerRadius
        labelLeadingConstraint?.constant = horizontalPadding
        labelTrailingConstraint?.constant = -horizontalPadding
        invalidateIntrinsicContentSize()
        updateAppearance()
    }

    private func updateText() {
        let text = shortcutText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        label.stringValue = text
        isHidden = text.isEmpty
        invalidateIntrinsicContentSize()
    }

    private func updateAppearance() {
        let isDark = PasteraDesignTokens.isDarkAppearance(effectiveAppearance)

        if isBadgeEnabled == false {
            label.textColor = .disabledControlTextColor
            layer?.backgroundColor = (isDark
                ? NSColor(calibratedWhite: 1, alpha: 0.06)
                : NSColor(calibratedWhite: 0, alpha: 0.045)
            ).cgColor
            return
        }

        switch style {
        case .command:
            label.textColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
            let alpha: CGFloat = isEmphasized ? 0.13 : 0.085
            layer?.backgroundColor = (isDark
                ? NSColor(calibratedWhite: 1, alpha: alpha)
                : NSColor(calibratedWhite: 0, alpha: alpha)
            ).cgColor
        case .itemNumber:
            label.textColor = isEmphasized ? .labelColor : .tertiaryLabelColor
            let alpha: CGFloat = isEmphasized ? 0.16 : 0.055
            layer?.backgroundColor = (isDark
                ? NSColor(calibratedWhite: 1, alpha: alpha)
                : NSColor(calibratedWhite: 0, alpha: alpha)
            ).cgColor
        }
    }

    private var horizontalPadding: CGFloat {
        style == .command ? Metrics.horizontalPadding : Metrics.itemHorizontalPadding
    }

    private var height: CGFloat {
        style == .command ? Metrics.height : Metrics.itemHeight
    }

    private var minWidth: CGFloat {
        style == .command ? Metrics.minWidth : Metrics.itemMinWidth
    }

    private var cornerRadius: CGFloat {
        style == .command ? Metrics.cornerRadius : Metrics.itemCornerRadius
    }

    private var font: NSFont {
        switch style {
        case .command:
            return .systemFont(ofSize: 11, weight: .medium)
        case .itemNumber:
            return .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        }
    }
}

#if DEBUG
extension PasteraShortcutBadgeView {
    var shortcutTextForTesting: String {
        label.stringValue
    }

    var labelWidthForTesting: CGFloat {
        label.intrinsicContentSize.width
    }

    var styleForTesting: Style {
        style
    }
}
#endif
