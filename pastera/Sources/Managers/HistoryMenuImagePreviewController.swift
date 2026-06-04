//
//  HistoryMenuImagePreviewController.swift
//  Clipy
//
//  Created by Codex on 2026/06/03.
//

import Cocoa

final class HistoryMenuImagePreviewController {
    private enum Metrics {
        static let size = NSSize(width: 260, height: 180)
        static let contentInset: CGFloat = 8
        static let horizontalOffset: CGFloat = 12
    }

    private(set) var panel: NSPanel?
    private let imageView = NSImageView()

    func show(image: NSImage, relativeTo rect: NSRect, in sourceView: NSView?) {
        let panel = panel ?? makePanel()
        let contentView = panel.contentView ?? makeContentView()
        if panel.contentView == nil {
            panel.contentView = contentView
        }

        imageView.image = image
        contentView.frame = NSRect(origin: .zero, size: Metrics.size)
        panel.setContentSize(Metrics.size)
        contentView.layoutSubtreeIfNeeded()
        panel.setFrameOrigin(previewOrigin(relativeTo: rect, in: sourceView))
        panel.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    deinit {
        panel?.close()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = makeContentView()
        self.panel = panel
        return panel
    }

    private func makeContentView() -> NSView {
        let contentView = NSView(frame: NSRect(origin: .zero, size: Metrics.size))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 9
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        contentView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        contentView.layer?.borderWidth = 1

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.contentInset),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.contentInset),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.contentInset),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.contentInset)
        ])

        return contentView
    }

    private func previewOrigin(relativeTo rect: NSRect, in sourceView: NSView?) -> NSPoint {
        let sourceRect: NSRect
        if let sourceView,
           let window = sourceView.window {
            let windowRect = sourceView.convert(rect, to: nil)
            sourceRect = window.convertToScreen(windowRect)
        } else {
            sourceRect = rect
        }

        let screenFrame = sourceView?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        var origin = NSPoint(
            x: sourceRect.maxX + Metrics.horizontalOffset,
            y: sourceRect.midY - Metrics.size.height / 2
        )

        guard let screenFrame else {
            return origin
        }

        if origin.x + Metrics.size.width > screenFrame.maxX {
            origin.x = sourceRect.minX - Metrics.horizontalOffset - Metrics.size.width
        }
        origin.x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - Metrics.size.width)
        origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - Metrics.size.height)
        return origin
    }
}
