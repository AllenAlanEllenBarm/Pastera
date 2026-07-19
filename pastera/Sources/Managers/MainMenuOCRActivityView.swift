import AppKit

final class MainMenuOCRActivityView: NSView {
    static let height: CGFloat = 32

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("mainMenuOCRActivity")
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5

        iconView.imageScaling = .scaleProportionallyDown
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .right
        [iconView, titleLabel, detailLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 10, y: 9, width: 14, height: 14)
        detailLabel.frame = NSRect(x: bounds.width - 104, y: 8, width: 94, height: 16)
        titleLabel.frame = NSRect(x: 31, y: 8, width: max(0, detailLabel.frame.minX - 37), height: 16)
    }

    func render(_ activity: PasteboardHistoryOCRActivity) {
        switch activity {
        case .idle:
            isHidden = true
        case let .indexing(remaining):
            isHidden = false
            iconView.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            titleLabel.stringValue = String(localized: "Recognizing image text")
            detailLabel.stringValue = String.localizedStringWithFormat(
                String(localized: "%lld items remaining"),
                remaining
            )
        case let .completed(processed, skipped):
            isHidden = false
            if skipped == 0 {
                iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                iconView.contentTintColor = .systemGreen
                titleLabel.stringValue = String(localized: "Image text updated")
                detailLabel.stringValue = String.localizedStringWithFormat(
                    String(localized: "%lld items recognized"),
                    processed
                )
            } else {
                iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                iconView.contentTintColor = .systemOrange
                titleLabel.stringValue = String(localized: "Some images could not be recognized")
                detailLabel.stringValue = String.localizedStringWithFormat(
                    String(localized: "%lld items skipped"),
                    skipped
                )
            }
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel(titleLabel.stringValue)
        setAccessibilityValue(detailLabel.stringValue)
        needsLayout = true
    }
}
