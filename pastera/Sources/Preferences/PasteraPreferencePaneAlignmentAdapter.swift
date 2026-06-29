//
//  PasteraPreferencePaneAlignmentAdapter.swift
//
//  Pastera
//

import Cocoa
import KeyHolder

enum PasteraPreferencePaneAlignmentKind {
    case exclude
    case shortcuts
}

enum PasteraPreferencePaneAlignmentAdapter {
    static func layout(_ view: NSView, pane: PasteraPreferencePaneAlignmentKind, availableWidth: CGFloat) {
        view.layoutSubtreeIfNeeded()
        switch pane {
        case .exclude:
            layoutExcludePane(view, availableWidth: availableWidth)
        case .shortcuts:
            layoutShortcutsPane(view, availableWidth: availableWidth)
        }
        view.layoutSubtreeIfNeeded()
    }

    private static func layoutExcludePane(_ view: NSView, availableWidth: CGFloat) {
        guard let tableScroll = scrollViews(in: view).first(where: { $0.documentView is NSTableView }) else { return }
        let labels = textFields(in: view).filter { !$0.isEditable && !$0.stringValue.isEmpty }
        let title = labels.first(where: { isExcludeTitle($0.stringValue) })
            ?? nearestLabel(above: tableScroll, labels: labels, root: view)
        let titleFrame = title.map { frame(of: $0, in: view) }
        let titleHeight = titleFrame?.height ?? 18
        let titleY = max(0, view.bounds.height - titleHeight)

        if let title, let originalTitleFrame = titleFrame {
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            title.alignment = .left
            setFrame(of: title, in: view, to: NSRect(
                x: 0,
                y: titleY,
                width: availableWidth,
                height: originalTitleFrame.height
            ))
        }

        let buttons = controls(in: view).compactMap { $0 as? NSButton }
            .filter { !$0.title.isEmpty || $0.image != nil }
            .filter { frame(of: $0, in: view).maxY <= frame(of: tableScroll, in: view).minY + 1 }
            .sorted { frame(of: $0, in: view).minX < frame(of: $1, in: view).minX }

        let buttonHeight = buttons.map { frame(of: $0, in: view).height }.max() ?? 24
        let buttonY: CGFloat = 0
        let tableY = buttonY + buttonHeight + 8
        let tableTopY = max(tableY + 80, titleY - 10)
        setFrame(of: tableScroll, in: view, to: NSRect(
            x: 0,
            y: tableY,
            width: availableWidth,
            height: max(80, tableTopY - tableY)
        ))
        if let tableView = tableScroll.documentView as? NSTableView {
            tableView.tableColumns.forEach {
                $0.width = max(0, tableScroll.contentView.bounds.width)
            }
        }

        buttons.enumerated().forEach { index, button in
            let buttonFrame = frame(of: button, in: view)
            setFrame(of: button, in: view, to: NSRect(
                x: CGFloat(index) * (buttonFrame.width + 4),
                y: buttonY,
                width: buttonFrame.width,
                height: buttonFrame.height
            ))
        }
    }

    private static func layoutShortcutsPane(_ view: NSView, availableWidth: CGFloat) {
        PasteraShortcutPreferencePaneLayout.apply(to: view, availableWidth: availableWidth)
    }

    private static func nearestLabel(above target: NSView, labels: [NSTextField], root: NSView) -> NSTextField? {
        let targetFrame = frame(of: target, in: root)
        return labels
            .filter { frame(of: $0, in: root).minY >= targetFrame.maxY - 2 }
            .min { lhs, rhs in
                frame(of: lhs, in: root).minY < frame(of: rhs, in: root).minY
            }
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        var values = view.subviews.compactMap { $0 as? NSTextField }
        view.subviews.forEach { values.append(contentsOf: textFields(in: $0)) }
        return values
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        var values = view.subviews.compactMap { $0 as? NSScrollView }
        view.subviews.forEach { values.append(contentsOf: scrollViews(in: $0)) }
        return values
    }

    private static func controls(in view: NSView) -> [NSControl] {
        var values = view.subviews.compactMap { $0 as? NSControl }
        view.subviews.forEach { values.append(contentsOf: controls(in: $0)) }
        return values
    }

    private static func recordViews(in view: NSView) -> [RecordView] {
        var values = view.subviews.compactMap { $0 as? RecordView }
        view.subviews.forEach { values.append(contentsOf: recordViews(in: $0)) }
        return values
    }

    private static func frame(of view: NSView, in root: NSView) -> NSRect {
        view.superview?.convert(view.frame, to: root) ?? view.frame
    }

    private static func setFrame(of view: NSView, in root: NSView, to frame: NSRect) {
        guard let superview = view.superview else {
            view.frame = frame
            return
        }
        view.frame = superview.convert(frame, from: root)
    }

    private static func isExcludeTitle(_ text: String) -> Bool {
        ["Exclude these applications:", "排除这些程序："].contains(text)
    }

}

private enum PasteraShortcutPreferencePaneLayout {
    static func apply(to view: NSView, availableWidth: CGFloat) {
        let metrics = Metrics(availableWidth: availableWidth, topY: view.bounds.maxY)
        let recordContainers = sortedRecordContainers(in: view)
        let sectionTitles = shortcutSectionTitles(in: view)

        layoutSectionTitles(sectionTitles, in: view, metrics: metrics)
        layoutRows(recordContainers, in: view, metrics: metrics)
        normalizeFrames(in: view, metrics: metrics)
    }

    private struct Metrics {
        let columnWidth: CGFloat
        let labelWidth: CGFloat
        let controlX: CGFloat
        let controlWidth: CGFloat
        let rowHeight: CGFloat = 28
        let rowSpacing: CGFloat = 8
        let sectionHeight: CGFloat = 18
        let recordHeight: CGFloat = 26
        let columnXs: [CGFloat]
        let sectionTitleY: CGFloat
        let rowStartY: CGFloat

        init(availableWidth: CGFloat, topY: CGFloat) {
            let columnGap: CGFloat = 14
            columnWidth = floor(max(1, (availableWidth - columnGap) / 2))
            labelWidth = min(66, max(52, columnWidth * 0.34))
            controlX = labelWidth + 8
            controlWidth = max(132, columnWidth - controlX)
            columnXs = [0, columnWidth + columnGap]
            sectionTitleY = topY - sectionHeight
            rowStartY = sectionTitleY - 8 - rowHeight
        }
    }

    private static func sortedRecordContainers(in view: NSView) -> [NSView] {
        view.subviews.filter {
            !($0 is RecordView) && recordViews(in: $0).isEmpty == false
        }.sorted {
            let lhsOrder = shortcutRowOrder(in: $0)
            let rhsOrder = shortcutRowOrder(in: $1)
            if let lhsOrder, let rhsOrder, lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            if lhsOrder != nil {
                return true
            }
            if rhsOrder != nil {
                return false
            }
            return frame(of: $0, in: view).maxY > frame(of: $1, in: view).maxY
        }
    }

    private static func shortcutSectionTitles(in view: NSView) -> [NSTextField] {
        view.subviews.compactMap { $0 as? NSTextField }
            .filter { !$0.stringValue.isEmpty && isShortcutSectionTitle($0.stringValue) }
            .sorted { frame(of: $0, in: view).maxY > frame(of: $1, in: view).maxY }
    }

    private static func layoutSectionTitles(
        _ sectionTitles: [NSTextField],
        in view: NSView,
        metrics: Metrics
    ) {
        sectionTitles.enumerated().forEach { index, textField in
            let columnX = metrics.columnXs[min(index, metrics.columnXs.count - 1)]
            textField.isHidden = false
            textField.font = .systemFont(ofSize: 13, weight: .semibold)
            textField.alignment = .left
            setFrame(of: textField, in: view, to: NSRect(
                x: columnX,
                y: metrics.sectionTitleY,
                width: metrics.columnWidth,
                height: metrics.sectionHeight
            ))
        }
    }

    private static func layoutRows(
        _ recordContainers: [NSView],
        in view: NSView,
        metrics: Metrics
    ) {
        recordContainers.enumerated().forEach { index, container in
            let columnIndex = min(index / 3, metrics.columnXs.count - 1)
            let rowIndex = index % 3
            let rowY = metrics.rowStartY - CGFloat(rowIndex) * (metrics.rowHeight + metrics.rowSpacing)
            setFrame(of: container, in: view, to: NSRect(
                x: metrics.columnXs[columnIndex],
                y: rowY,
                width: metrics.columnWidth,
                height: metrics.rowHeight
            ))
            layoutRowChildren(in: container, metrics: metrics)
        }
    }

    private static func layoutRowChildren(in container: NSView, metrics: Metrics) {
        textFields(in: container).filter { !$0.stringValue.isEmpty }.forEach { textField in
            if isShortcutSectionTitle(textField.stringValue) {
                textField.isHidden = true
                return
            }
            textField.font = .systemFont(ofSize: 12.5, weight: .medium)
            textField.alignment = .left
            textField.frame = NSRect(
                x: 0,
                y: (metrics.rowHeight - textField.frame.height) / 2,
                width: metrics.labelWidth,
                height: textField.frame.height
            )
        }

        recordViews(in: container).forEach { recordView in
            recordView.frame = NSRect(
                x: metrics.controlX,
                y: (metrics.rowHeight - metrics.recordHeight) / 2,
                width: metrics.controlWidth,
                height: metrics.recordHeight
            )
        }
    }

    private static func normalizeFrames(in view: NSView, metrics: Metrics) {
        textFields(in: view).filter { !$0.stringValue.isEmpty }.forEach { textField in
            let currentFrame = frame(of: textField, in: view)
            if isShortcutSectionTitle(textField.stringValue) {
                normalizeTextField(textField, in: view, frame: currentFrame, width: metrics.columnWidth)
            } else if isShortcutRowLabel(textField.stringValue) {
                normalizeTextField(textField, in: view, frame: currentFrame, width: metrics.labelWidth)
            }
        }

        recordViews(in: view).forEach { recordView in
            let currentFrame = frame(of: recordView, in: view)
            setFrame(of: recordView, in: view, to: NSRect(
                x: currentFrame.minX,
                y: currentFrame.minY,
                width: metrics.controlWidth,
                height: currentFrame.height
            ))
        }
    }

    private static func normalizeTextField(
        _ textField: NSTextField,
        in view: NSView,
        frame currentFrame: NSRect,
        width: CGFloat
    ) {
        textField.isHidden = false
        textField.font = isShortcutSectionTitle(textField.stringValue)
            ? .systemFont(ofSize: 13, weight: .semibold)
            : .systemFont(ofSize: 12.5, weight: .medium)
        textField.alignment = .left
        setFrame(of: textField, in: view, to: NSRect(
            x: currentFrame.minX,
            y: currentFrame.minY,
            width: width,
            height: currentFrame.height
        ))
    }

    private static func isShortcutSectionTitle(_ text: String) -> Bool {
        [
            "Menu",
            "菜单",
            "History",
            "历史",
            "Menu Shortcuts",
            "菜单快捷键",
            "History Panel Shortcuts",
            "历史面板快捷键"
        ].contains(text)
    }

    private static func isShortcutRowLabel(_ text: String) -> Bool {
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
        ].contains(text)
    }

    private static func shortcutRowOrder(in view: NSView) -> Int? {
        textFields(in: view)
            .compactMap { shortcutRowOrder(for: $0.stringValue) }
            .min()
    }

    private static func shortcutRowOrder(for text: String) -> Int? {
        switch text {
        case "Main:", "主体：": 0
        case "History:", "历史：": 1
        case "Snippets:", "片段：": 2
        case "Search:", "搜索：": 3
        case "Previous Page:", "上一页：": 4
        case "Next Page:", "下一页：": 5
        default: nil
        }
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        var values = view.subviews.compactMap { $0 as? NSTextField }
        view.subviews.forEach { values.append(contentsOf: textFields(in: $0)) }
        return values
    }

    private static func recordViews(in view: NSView) -> [RecordView] {
        var values = view.subviews.compactMap { $0 as? RecordView }
        view.subviews.forEach { values.append(contentsOf: recordViews(in: $0)) }
        return values
    }

    private static func frame(of view: NSView, in root: NSView) -> NSRect {
        view.superview?.convert(view.frame, to: root) ?? view.frame
    }

    private static func setFrame(of view: NSView, in root: NSView, to frame: NSRect) {
        guard let superview = view.superview else {
            view.frame = frame
            return
        }
        view.frame = superview.convert(frame, from: root)
    }
}
