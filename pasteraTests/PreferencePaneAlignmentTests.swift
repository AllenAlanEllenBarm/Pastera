//
//  PreferencePaneAlignmentTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct PreferencePaneAlignmentTests {
    @Test
    func excludePaneTitleAndTableUseSameContentColumn() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Exclude")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let titleFrame = try #require(preferenceTextFieldFrames(in: contentView)
            .first { ["Exclude these applications:", "排除这些程序："].contains($0.text) }?.frame)
        let tableFrame = try #require(preferenceTableScrollFrame(in: contentView))

        #expect(abs(titleFrame.minX - tableFrame.minX) <= 1)
        #expect(tableFrame.width >= controller.selectedPaneDocumentWidthForTesting - 4)
        #expect(
            paneFrame.maxY - titleFrame.maxY <= 24,
            "Exclude pane title should be top-aligned, but top gap is \(paneFrame.maxY - titleFrame.maxY)"
        )
    }

    @Test
    func shortcutsPaneDisplaysHistoryPanelRowsAndAlignsLabelAndRecordColumns() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let textFrames = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let sectionTitles = textFrames.filter {
            [
                "Menu Shortcuts",
                "菜单快捷键",
                "History Panel Shortcuts",
                "历史面板快捷键"
            ].contains($0.text)
        }
        let rowLabels = textFrames.filter {
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
        let recordFrames = preferenceRecordViewFrames(in: contentView)
            .filter { $0.minX >= paneMinX }
        let menuTitle = try #require(textFrames.first {
            ["Menu Shortcuts", "菜单快捷键"].contains($0.text)
        })
        let historyPanelTitle = try #require(textFrames.first {
            ["History Panel Shortcuts", "历史面板快捷键"].contains($0.text)
        })
        let snippetsLabel = try #require(rowLabels.first {
            ["Snippets:", "片段："].contains($0.text)
        })
        let searchLabel = try #require(rowLabels.first {
            ["Search:", "搜索："].contains($0.text)
        })
        let previousPageLabel = try #require(rowLabels.first {
            ["Previous Page:", "上一页："].contains($0.text)
        })
        let nextPageLabel = try #require(rowLabels.first {
            ["Next Page:", "下一页："].contains($0.text)
        })
        let nextPageFrameInPane = try #require(controller.selectedPaneTextFrameForTesting(
            matching: ["Next Page:", "下一页："]
        ))

        #expect(sectionTitles.count == 2)
        #expect(rowLabels.count == 6)
        #expect(recordFrames.count == 6)
        #expect(!textFrames.contains {
            ["Clear History:", "清空历史：", "清除历史："].contains($0.text)
        })
        #expect(menuTitle.frame.maxY > snippetsLabel.frame.maxY)
        #expect(snippetsLabel.frame.maxY > historyPanelTitle.frame.maxY)
        #expect(historyPanelTitle.frame.maxY > searchLabel.frame.maxY)
        #expect(searchLabel.frame.maxY > previousPageLabel.frame.maxY)
        #expect(previousPageLabel.frame.maxY > nextPageLabel.frame.maxY)
        #expect(nextPageFrameInPane.minY >= -0.5)
        #expect(nextPageFrameInPane.maxY <= controller.selectedPaneDocumentHeightForTesting + 0.5)

        let labelMinX = try #require(rowLabels.map(\.frame.minX).min())
        for label in rowLabels {
            #expect(abs(label.frame.minX - labelMinX) <= 1)
        }

        let recordMinX = try #require(recordFrames.map(\.minX).min())
        let paneMaxX = paneFrame.maxX
        for frame in recordFrames {
            #expect(abs(frame.minX - recordMinX) <= 1)
            #expect(frame.maxX >= paneMaxX - 4)
        }
    }

    @Test
    func betaPaneIntroIsCenteredAndFormColumnsAlign() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Beta")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let textFrames = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let introFrame = try #require(textFrames.first {
            [
                "Beta settings might be moved to a different pane in future versions.",
                "Beta 测试设置将来可能会被移到其它面板。"
            ].contains($0.text)
        }?.frame)
        let actionFrame = try #require(textFrames.first { ["Action", "操作"].contains($0.text) }?.frame)
        let screenshotFrame = try #require(textFrames.first { ["Screenshot", "屏幕截图"].contains($0.text) }?.frame)
        let checkboxFrames = preferenceButtons(in: contentView)
            .filter {
                [
                    "Paste as PlainText",
                    "Delete history",
                    "Paste and delete history",
                    "Save screenshots in history",
                    "以纯文本格式粘贴",
                    "删除历史",
                    "粘贴并删除历史",
                    "在历史中保存屏幕截图"
                ].contains($0.title)
            }
            .map { contentView.convert($0.frame, from: $0.superview) }
            .filter { $0.minX >= paneMinX }
        let popupFrames = preferencePopUpFrames(in: contentView)
            .filter { $0.minX >= paneMinX }

        #expect(abs(introFrame.midX - paneFrame.midX) <= 1)
        #expect(checkboxFrames.count == 4)
        #expect(popupFrames.count == 3)
        for frame in [actionFrame, screenshotFrame] + checkboxFrames {
            #expect(abs(frame.minX - actionFrame.minX) <= 1)
        }
        let paneMaxX = paneFrame.maxX
        for frame in popupFrames {
            #expect(frame.maxX >= paneMaxX - 4)
        }
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard view.isHidden == false, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, textField.stringValue.isEmpty == false {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceTableScrollFrame(in view: NSView, root: NSView? = nil) -> NSRect? {
        let rootView = root ?? view
        if let scrollView = view as? NSScrollView,
           scrollView.documentView is NSTableView {
            return rootView.convert(scrollView.frame, from: scrollView.superview)
        }
        for subview in view.subviews {
            if let frame = preferenceTableScrollFrame(in: subview, root: rootView) {
                return frame
            }
        }
        return nil
    }

    private func preferenceRecordViewFrames(in view: NSView, root: NSView? = nil) -> [NSRect] {
        let rootView = root ?? view
        var values = [NSRect]()
        if String(describing: type(of: view)).contains("RecordView") {
            values.append(rootView.convert(view.frame, from: view.superview))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceRecordViewFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferencePopUpFrames(in view: NSView, root: NSView? = nil) -> [NSRect] {
        let rootView = root ?? view
        var values = [NSRect]()
        if view is NSPopUpButton {
            values.append(rootView.convert(view.frame, from: view.superview))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferencePopUpFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }
}
