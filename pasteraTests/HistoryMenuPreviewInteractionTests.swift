//
//  HistoryMenuPreviewInteractionTests.swift
//  Pastera
//
//  Created by Codex on 2026/07/09.
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct HistoryMenuPreviewInteractionTests {
    @Test
    func imagePreviewPanelIncludesPointerTowardSourceRow() throws {
        let controller = HistoryMenuImagePreviewController()
        let image = NSImage(size: NSSize(width: 640, height: 360))

        controller.show(image: image, relativeTo: NSRect(x: 40, y: 40, width: 48, height: 30), in: nil)

        let contentView = try #require(controller.panel?.contentView)
        let notch = try #require(contentView.subviews.first {
            $0.identifier?.rawValue == "historyPreviewNotchView"
        })
        #expect(notch.frame.minX == contentView.bounds.minX)
        #expect(notch.frame.height == contentView.bounds.height)
        controller.hide()
    }

    @Test
    func imagePreviewPanelFlipsToLeftSideWhenRightEdgeHasNoRoom() throws {
        HistoryMenuImagePreviewController.disableAnimationsForTesting = true
        defer { HistoryMenuImagePreviewController.disableAnimationsForTesting = false }

        let controller = HistoryMenuImagePreviewController()
        let image = NSImage(size: NSSize(width: 640, height: 360))
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = makePreviewTestWindow(width: 128, height: 80)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 128, height: 80))
        let sourceView = NSView(frame: NSRect(x: 92, y: 25, width: 24, height: 30))
        container.addSubview(sourceView)
        window.contentView = container
        window.setFrameOrigin(NSPoint(
            x: screenFrame.maxX - window.frame.width - 2,
            y: screenFrame.midY - window.frame.height / 2
        ))
        window.orderFront(nil)
        defer {
            controller.hide()
            closePreviewTestWindow(window)
        }

        controller.show(image: image, relativeTo: sourceView.bounds, in: sourceView)

        let panel = try #require(controller.panel)
        let contentView = try #require(panel.contentView)
        let notch = try #require(contentView.subviews.first {
            $0.identifier?.rawValue == "historyPreviewNotchView"
        })
        let sourceScreenFrame = window.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
        #expect(panel.frame.maxX <= sourceScreenFrame.minX)
        #expect(notch.frame.maxX == contentView.bounds.maxX)
    }

    @Test
    func staleHideAnimationDoesNotOrderOutNewImagePreview() async throws {
        let controller = HistoryMenuImagePreviewController()
        let image = NSImage(size: NSSize(width: 640, height: 360))
        defer { controller.hide() }

        controller.show(image: image, relativeTo: NSRect(x: 40, y: 40, width: 48, height: 30), in: nil)
        controller.hide()
        controller.show(image: image, relativeTo: NSRect(x: 80, y: 40, width: 48, height: 30), in: nil)

        try await Task.sleep(nanoseconds: 180_000_000)

        #expect(controller.isVisibleForTesting)
    }

    @Test
    func historyRowProvidesTextPreviewWhenTitleIsVisuallyTruncated() throws {
        let fullTitle = "CGQ_HET_9C6377 2026-07-08 timetable item with extra route metadata"
        let row = HistoryMenuRowView(
            title: fullTitle,
            image: nil,
            previewText: nil
        ) {}
        row.frame = NSRect(x: 0, y: 0, width: 180, height: row.frame.height)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: row.frame.height))
        container.addSubview(row)
        let window = makePreviewTestWindow(width: 180, height: row.frame.height)
        window.contentView = container
        window.setContentSize(NSSize(width: 180, height: row.frame.height))
        window.orderFront(nil)
        row.frame = NSRect(x: 0, y: 0, width: 180, height: row.frame.height)
        container.layoutSubtreeIfNeeded()
        defer { closePreviewTestWindow(window) }

        #expect(row.textPreviewCandidateForTesting == fullTitle)
    }

    @Test
    func focusedTruncatedHistoryRowRequestsTextPreview() throws {
        let fullTitle = "CGQ_HET_9C6377 2026-07-08 timetable item with extra route metadata"
        let row = HistoryMenuRowView(
            title: fullTitle,
            image: nil,
            previewText: nil
        ) {}
        row.frame = NSRect(x: 0, y: 0, width: 180, height: row.frame.height)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: row.frame.height))
        container.addSubview(row)
        let window = makePreviewTestWindow(width: 180, height: row.frame.height)
        window.contentView = container
        window.setContentSize(NSSize(width: 180, height: row.frame.height))
        window.orderFront(nil)
        row.frame = NSRect(x: 0, y: 0, width: 180, height: row.frame.height)
        container.layoutSubtreeIfNeeded()

        var scheduledWorkItem: DispatchWorkItem?
        var requestedText: String?
        HistoryMenuRowView.scheduleTextPreviewWorkItemsForTesting { scheduledWorkItem = $0 }
        HistoryMenuRowView.observeTextPreviewRequestsForTesting { requestedText = $0 }
        defer {
            HistoryMenuRowView.scheduleTextPreviewWorkItemsForTesting(nil)
            HistoryMenuRowView.observeTextPreviewRequestsForTesting(nil)
            HistoryMenuRowView.hidePreviews()
            closePreviewTestWindow(window)
        }

        #expect(window.makeFirstResponder(row))
        try #require(scheduledWorkItem).perform()

        #expect(requestedText == fullTitle)
        #expect(HistoryMenuRowView.isTextPreviewVisibleForTesting)
    }

    private func makePreviewTestWindow(width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        return window
    }

    private func closePreviewTestWindow(_ window: NSWindow) {
        window.makeFirstResponder(nil)
        let retainedContentView = window.contentView
        window.contentView = nil
        window.orderOut(nil)
        PreviewTestWindowRetainer.retain(window: window, contentView: retainedContentView)
    }
}

private enum PreviewTestWindowRetainer {
    private static var windows = [NSWindow]()
    private static var contentViews = [NSView]()

    static func retain(window: NSWindow, contentView: NSView?) {
        windows.append(window)
        if let contentView {
            contentViews.append(contentView)
        }
    }
}
