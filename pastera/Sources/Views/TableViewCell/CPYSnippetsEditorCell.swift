//
//  CPYSnippetsEditorCell.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/07/02.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa

final class CPYSnippetsEditorCell: NSTextFieldCell {

    // MARK: - Properties
    enum Metrics {
        static let folderIconLeadingInset: CGFloat = 5
        static let folderIconWidth: CGFloat = 16
        static let folderIconHeight: CGFloat = 13
        static let folderTitleLeadingInset: CGFloat = 25
        static let shortcutHeight: CGFloat = 16
        static let shortcutHorizontalPadding: CGFloat = 4
        static let shortcutMinWidth: CGFloat = 22
        static let shortcutCornerRadius: CGFloat = 4
        static let commandShortcutHeight: CGFloat = 17
        static let commandShortcutHorizontalPadding: CGFloat = 6
        static let commandShortcutMinWidth: CGFloat = 24
        static let commandShortcutCornerRadius: CGFloat = 5
        static let shortcutSpacing: CGFloat = 6
        static let shortcutTrailingInset: CGFloat = 6
    }

    var iconType = IconType.folder
    var isItemEnabled = false
    var shortcutText: String?
    var shortcutStyle = PasteraShortcutBadgeView.Style.itemNumber

    override var cellSize: NSSize {
        var size = super.cellSize
        size.width += 3.0 + 16.0
        return size
    }

    // MARK: - Enums
    enum IconType {
        case folder, none
    }

    // MARK: - Initialize
    override init(textCell string: String) {
        super.init(textCell: string)
        font = NSFont.systemFont(ofSize: 13)
        configureInlineEditing()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        font = NSFont.systemFont(ofSize: 14)
        configureInlineEditing()
    }

    override func copy(with zone: NSZone?) -> Any {
        guard let cell = super.copy(with: zone) as? CPYSnippetsEditorCell else { return super.copy(with: zone) }
        cell.iconType = iconType
        cell.isItemEnabled = isItemEnabled
        cell.shortcutText = shortcutText
        cell.shortcutStyle = shortcutStyle
        return cell
    }

    // MARK: - Draw
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if iconType == .folder {
            drawFolderIcon(in: cellFrame)
        }

        textColor = titleTextColor(isHighlighted: isHighlighted)

        super.draw(withFrame: titleRect(forBounds: cellFrame), in: controlView)
        drawShortcutBadgeIfNeeded(in: cellFrame)
    }

    // MARK: - Frame
    override func select(withFrame aRect: NSRect, in controlView: NSView, editor textObj: NSText, delegate anObject: Any?, start selStart: Int, length selLength: Int) {
        let textFrame = titleRect(forBounds: aRect)
        textColor = .textColor
        super.select(withFrame: textFrame, in: controlView, editor: textObj, delegate: anObject, start: selStart, length: selLength)
    }

    override func edit(withFrame aRect: NSRect, in controlView: NSView, editor textObj: NSText, delegate anObject: Any?, event theEvent: NSEvent?) {
        let textFrame = titleRect(forBounds: aRect)
        super.edit(withFrame: textFrame, in: controlView, editor: textObj, delegate: anObject, event: theEvent)
    }

    override func titleRect(forBounds theRect: NSRect) -> NSRect {
        centeredTitleRect(forBounds: theRect)
    }

    private func centeredTitleRect(forBounds theRect: NSRect) -> NSRect {
        var newFrame = horizontalTitleRect(forBounds: theRect)
        if let shortcutText = normalizedShortcutText {
            let reservedWidth = shortcutBadgeWidth(for: shortcutText)
                + Metrics.shortcutSpacing
                + Metrics.shortcutTrailingInset
            newFrame.size.width = max(0, newFrame.size.width - reservedWidth)
        }

        let titleHeight = min(newFrame.height, ceil(titleLineHeight))
        newFrame.origin.y = theRect.midY - titleHeight / 2
        newFrame.size.height = titleHeight

        return newFrame
    }

    private func configureInlineEditing() {
        isEditable = true
        isSelectable = true
        sendsActionOnEndEditing = true
    }

    private func titleTextColor(isHighlighted: Bool) -> NSColor {
        guard isItemEnabled else { return .disabledControlTextColor }
        return isHighlighted ? .selectedMenuItemTextColor : .labelColor
    }

    private var normalizedShortcutText: String? {
        let text = shortcutText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func horizontalTitleRect(forBounds theRect: NSRect) -> NSRect {
        switch iconType {
        case .folder:
            var newFrame = theRect
            newFrame.origin.x += Metrics.folderTitleLeadingInset
            newFrame.size.width -= Metrics.folderTitleLeadingInset
            return newFrame

        case .none:
            return theRect
        }
    }

    private var titleLineHeight: CGFloat {
        let titleFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return max(1, titleFont.ascender - titleFont.descender + titleFont.leading)
    }

    private func drawFolderIcon(in frame: NSRect) {
        let imageFrame = folderIconRect(forBounds: frame)

        let drawImage = (isHighlighted)
            ? NSImage(resource: .snippetsIconFolderWhite)
            : NSImage(resource: .snippetsIconFolderBlue)
        drawImage.size = NSSize(width: Metrics.folderIconWidth, height: Metrics.folderIconHeight)
        drawImage.draw(
            in: imageFrame,
            from: NSRect.zero,
            operation: .sourceOver,
            fraction: isItemEnabled ? 1.0 : 0.45,
            respectFlipped: true,
            hints: nil
        )
    }

    private func folderIconRect(forBounds frame: NSRect) -> NSRect {
        NSRect(
            x: frame.minX + Metrics.folderIconLeadingInset,
            y: frame.midY - Metrics.folderIconHeight / 2,
            width: Metrics.folderIconWidth,
            height: Metrics.folderIconHeight
        )
    }

    private func drawShortcutBadgeIfNeeded(in frame: NSRect) {
        guard let shortcutText = normalizedShortcutText else { return }

        let badgeRect = shortcutBadgeRect(forBounds: frame)
        guard badgeRect.width > 0 else { return }

        let path = NSBezierPath(
            roundedRect: badgeRect,
            xRadius: shortcutCornerRadius,
            yRadius: shortcutCornerRadius
        )
        shortcutBadgeBackgroundColor.setFill()
        path.fill()

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: shortcutFont,
            .foregroundColor: shortcutBadgeTextColor
        ]
        let textSize = (shortcutText as NSString).size(withAttributes: textAttributes)
        let textRect = NSRect(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2 - 0.5,
            width: textSize.width,
            height: textSize.height
        )
        (shortcutText as NSString).draw(in: textRect, withAttributes: textAttributes)
    }

    func shortcutBadgeRect(forBounds theRect: NSRect) -> NSRect {
        guard let shortcutText = normalizedShortcutText else { return .zero }
        let width = shortcutBadgeWidth(for: shortcutText)
        return NSRect(
            x: max(theRect.minX, theRect.maxX - Metrics.shortcutTrailingInset - width),
            y: theRect.midY - shortcutHeight / 2,
            width: width,
            height: shortcutHeight
        )
    }

    private func shortcutBadgeWidth(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: shortcutFont]
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        return max(
            shortcutMinWidth,
            ceil(textWidth + shortcutHorizontalPadding * 2)
        )
    }

    private var shortcutFont: NSFont {
        switch shortcutStyle {
        case .command:
            return .systemFont(ofSize: 11.5, weight: .medium)
        case .itemNumber:
            return .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        }
    }

    private var shortcutBadgeBackgroundColor: NSColor {
        if isHighlighted {
            let alpha: CGFloat = shortcutStyle == .command ? 0.18 : 0.16
            return NSColor.white.withAlphaComponent(isItemEnabled ? alpha : 0.10)
        }
        let isDark = PasteraDesignTokens.isDarkAppearance()
        let alpha: CGFloat = shortcutStyle == .command ? 0.085 : 0.055
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: isItemEnabled ? alpha : 0.05)
            : NSColor(calibratedWhite: 0, alpha: isItemEnabled ? alpha : 0.045)
    }

    private var shortcutBadgeTextColor: NSColor {
        if isItemEnabled == false {
            return .disabledControlTextColor
        }
        if isHighlighted {
            return shortcutStyle == .command ? .selectedMenuItemTextColor : .labelColor
        }
        return .tertiaryLabelColor
    }

    private var shortcutHeight: CGFloat {
        shortcutStyle == .command ? Metrics.commandShortcutHeight : Metrics.shortcutHeight
    }

    private var shortcutHorizontalPadding: CGFloat {
        shortcutStyle == .command ? Metrics.commandShortcutHorizontalPadding : Metrics.shortcutHorizontalPadding
    }

    private var shortcutMinWidth: CGFloat {
        shortcutStyle == .command ? Metrics.commandShortcutMinWidth : Metrics.shortcutMinWidth
    }

    private var shortcutCornerRadius: CGFloat {
        shortcutStyle == .command ? Metrics.commandShortcutCornerRadius : Metrics.shortcutCornerRadius
    }
}

#if DEBUG
extension CPYSnippetsEditorCell {
    var shortcutTextForTesting: String {
        shortcutText ?? ""
    }

    func shortcutBadgeRectForTesting(in bounds: NSRect) -> NSRect {
        shortcutBadgeRect(forBounds: bounds)
    }

    func folderIconRectForTesting(in bounds: NSRect) -> NSRect {
        folderIconRect(forBounds: bounds)
    }

    func titleTextColorForTesting(isHighlighted: Bool) -> NSColor {
        titleTextColor(isHighlighted: isHighlighted)
    }
}
#endif
