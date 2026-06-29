//
//  PasteraOneDriveStatusBadge.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/19.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

final class PasteraOneDriveStatusBadge: NSView {
    enum State: Equatable {
        case available
        case unavailable
        case notDetected

        var displayText: String {
            switch self {
            case .available:
                return "OneDrive 可用"
            case .unavailable:
                return "OneDrive 不可用"
            case .notDetected:
                return "未检测到 OneDrive"
            }
        }

        var tooltip: String {
            switch self {
            case .available:
                return "当前同步位置在 OneDrive 文件夹内，Pastera 可以写入同步检测文件。"
            case .unavailable:
                return "当前同步位置不可用，请选择 OneDrive 中可写的文件夹。"
            case .notDetected:
                return "没有检测到可用的 OneDrive 同步位置。"
            }
        }

        var indicatorColor: NSColor {
            switch self {
            case .available:
                return .systemGreen
            case .unavailable:
                return .systemRed
            case .notDetected:
                return .secondaryLabelColor
            }
        }
    }

    private enum Metrics {
        static let height: CGFloat = 22
        static let minWidth: CGFloat = 174
        static let horizontalPadding: CGFloat = 9
        static let trailingPadding: CGFloat = 6
        static let dotSize: CGFloat = 6
        static let dotTextGap: CGFloat = 6
        static let labelButtonGap: CGFloat = 8
        static let redetectButtonWidth: CGFloat = 54
        static let redetectButtonHeight: CGFloat = 18
    }

    var state: State = .notDetected {
        didSet {
            updateAppearance()
        }
    }

    var displayText: String {
        state.displayText
    }

    private let dotView = NSView()
    private let label = NSTextField(labelWithString: "")
    private let redetectButton = NSButton(title: "", target: nil, action: nil)
    private var isRedetecting = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        let labelWidth = ceil(label.intrinsicContentSize.width)
        return NSSize(
            width: max(
                Metrics.minWidth,
                Metrics.horizontalPadding * 2
                    + Metrics.dotSize
                    + Metrics.dotTextGap
                    + labelWidth
                    + Metrics.labelButtonGap
                    + Metrics.redetectButtonWidth
                    + Metrics.trailingPadding
            ),
            height: Metrics.height
        )
    }

    override func layout() {
        super.layout()
        dotView.frame = NSRect(
            x: Metrics.horizontalPadding,
            y: floor((bounds.height - Metrics.dotSize) / 2),
            width: Metrics.dotSize,
            height: Metrics.dotSize
        )
        dotView.layer?.cornerRadius = Metrics.dotSize / 2
        let labelX = dotView.frame.maxX + Metrics.dotTextGap
        let buttonX = bounds.width - Metrics.trailingPadding - Metrics.redetectButtonWidth
        redetectButton.frame = NSRect(
            x: buttonX,
            y: floor((bounds.height - Metrics.redetectButtonHeight) / 2),
            width: Metrics.redetectButtonWidth,
            height: Metrics.redetectButtonHeight
        )
        let labelHeight: CGFloat = 16
        label.frame = NSRect(
            x: labelX,
            y: floor((bounds.height - labelHeight) / 2),
            width: max(1, buttonX - Metrics.labelButtonGap - labelX),
            height: labelHeight
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setRedetectTarget(_ target: AnyObject?, action: Selector?) {
        redetectButton.target = target
        redetectButton.action = action
    }

    func setRedetecting(_ isRedetecting: Bool) {
        self.isRedetecting = isRedetecting
        updateAppearance()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = Metrics.height / 2
        layer?.masksToBounds = true
        identifier = NSUserInterfaceItemIdentifier("oneDriveStatusBadge")
        setAccessibilityElement(true)

        dotView.wantsLayer = true
        addSubview(dotView)

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        redetectButton.title = "检测"
        redetectButton.isBordered = false
        redetectButton.bezelStyle = .regularSquare
        redetectButton.font = .systemFont(ofSize: 10, weight: .semibold)
        redetectButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "重新检测 OneDrive"
        )
        redetectButton.imagePosition = .imageLeading
        redetectButton.setAccessibilityLabel("重新检测 OneDrive")
        redetectButton.toolTip = "重新检测本地 OneDrive 文件夹和写入权限。"
        addSubview(redetectButton)
        updateAppearance()
    }

    private func updateAppearance() {
        label.stringValue = state.displayText
        label.textColor = .labelColor
        redetectButton.title = isRedetecting ? "检测中" : "检测"
        redetectButton.isEnabled = !isRedetecting
        redetectButton.contentTintColor = .labelColor
        toolTip = state.tooltip
        setAccessibilityLabel(state.displayText)
        setAccessibilityValue(state.displayText)

        let indicatorColor = state.indicatorColor
        let backgroundAlpha: CGFloat = isDarkAppearance ? 0.18 : 0.12
        let borderAlpha: CGFloat = isDarkAppearance ? 0.46 : 0.32
        layer?.backgroundColor = indicatorColor.withAlphaComponent(backgroundAlpha).cgColor
        layer?.borderColor = indicatorColor.withAlphaComponent(borderAlpha).cgColor
        layer?.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth
        dotView.layer?.backgroundColor = indicatorColor.cgColor
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
