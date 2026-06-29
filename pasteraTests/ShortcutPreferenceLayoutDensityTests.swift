//
//  ShortcutPreferenceLayoutDensityTests.swift
//
//  Pastera
//

import AppKit
import KeyHolder
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct ShortcutPreferenceLayoutDensityTests {
    @Test
    func shortcutsPaneUsesDenseTwoColumnLayoutWithoutInitialClipping() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let textFrames = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let recordFrames = preferenceRecordViewFrames(in: contentView)
            .filter { $0.minX >= paneMinX }
        let menuTitle = try #require(textFrames.first {
            ["Menu Shortcuts", "菜单快捷键"].contains($0.text)
        })
        let historyPanelTitle = try #require(textFrames.first {
            ["History Panel Shortcuts", "历史面板快捷键"].contains($0.text)
        })
        let nextPageFrame = try #require(textFrames.first {
            ["Next Page:", "下一页："].contains($0.text)
        }?.frame)
        let recordMaxY = try #require(recordFrames.map(\.maxY).max())
        let recordMinY = try #require(recordFrames.map(\.minY).min())
        let labelColumns = Set(rowLabelFrames(from: textFrames).map {
            Int(($0.frame.minX / 2).rounded())
        })
        let recordColumns = Set(recordFrames.map {
            Int(($0.minX / 2).rounded())
        })

        #expect(recordFrames.count == 6)
        #expect(labelColumns.count == 2)
        #expect(recordColumns.count == 2)
        #expect(historyPanelTitle.frame.minX > menuTitle.frame.minX)
        #expect(abs(historyPanelTitle.frame.midY - menuTitle.frame.midY) <= 1)
        #expect(recordMaxY - recordMinY <= 136)
        #expect(controller.selectedPaneDocumentHeightForTesting <= 180)
        #expect(controller.selectedPaneDocumentHeightForTesting <= controller.preferencePaneViewportHeightForTesting - 32)
        #expect(nextPageFrame.minY >= paneFrame.minY)
        #expect(nextPageFrame.maxY <= paneFrame.maxY)
        for frame in recordFrames {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
            #expect(frame.width >= 132)
        }
    }

    private func rowLabelFrames(
        from textFrames: [(text: String, frame: NSRect)]
    ) -> [(text: String, frame: NSRect)] {
        textFrames.filter {
            [
                "Main:",
                "History:",
                "Search:",
                "Previous Page:",
                "Next Page:",
                "Snippets:",
                "主体：",
                "历史：",
                "搜索：",
                "上一页：",
                "下一页：",
                "片段："
            ].contains($0.text)
        }
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard !view.isHidden, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, !textField.stringValue.isEmpty {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceRecordViewFrames(in view: NSView, root: NSView? = nil) -> [NSRect] {
        let rootView = root ?? view
        var values = [NSRect]()
        if view is RecordView {
            values.append(rootView.convert(view.frame, from: view.superview))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceRecordViewFrames(in: $0, root: rootView))
        }
        return values
    }
}
