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
    case beta
}

enum PasteraPreferencePaneAlignmentAdapter {
    static func layout(_ view: NSView, pane: PasteraPreferencePaneAlignmentKind, availableWidth: CGFloat) {
        view.layoutSubtreeIfNeeded()
        switch pane {
        case .exclude:
            layoutExcludePane(view, availableWidth: availableWidth)
        case .shortcuts:
            layoutShortcutsPane(view, availableWidth: availableWidth)
        case .beta:
            layoutBetaPane(view, availableWidth: availableWidth)
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
        let labelWidth = min(122, max(96, availableWidth * 0.28))
        let controlX = labelWidth + 16
        let controlWidth = max(180, availableWidth - controlX)
        let recordContainers = view.subviews.filter {
            !($0 is RecordView) && recordViews(in: $0).isEmpty == false
        }
        let sortedRecordContainers = recordContainers.sorted {
            frame(of: $0, in: view).maxY > frame(of: $1, in: view).maxY
        }

        sortedRecordContainers.forEach { container in
            let currentFrame = frame(of: container, in: view)
            setFrame(of: container, in: view, to: NSRect(
                x: 0,
                y: currentFrame.minY,
                width: availableWidth,
                height: currentFrame.height
            ))
            textFields(in: container).filter { !$0.stringValue.isEmpty }.forEach { textField in
                if isShortcutSectionTitle(textField.stringValue) {
                    textField.isHidden = true
                    return
                }
                textField.font = .systemFont(ofSize: 12.5, weight: .medium)
                textField.alignment = .left
                textField.frame = NSRect(
                    x: 0,
                    y: textField.frame.minY,
                    width: labelWidth,
                    height: textField.frame.height
                )
            }
            recordViews(in: container).forEach { recordView in
                recordView.frame = NSRect(
                    x: controlX,
                    y: recordView.frame.minY,
                    width: controlWidth,
                    height: recordView.frame.height
                )
            }
        }

        let sectionTitles = view.subviews.compactMap { $0 as? NSTextField }
            .filter { !$0.stringValue.isEmpty && isShortcutSectionTitle($0.stringValue) }
        sectionTitles.forEach { textField in
            let currentFrame = frame(of: textField, in: view)
            textField.isHidden = false
            textField.font = .systemFont(ofSize: 13, weight: .semibold)
            textField.alignment = .left
            setFrame(of: textField, in: view, to: NSRect(
                x: 0,
                y: currentFrame.minY,
                width: availableWidth,
                height: currentFrame.height
            ))
        }

        compactShortcutItems(sortedRecordContainers + sectionTitles, in: view)

        textFields(in: view).filter { !$0.stringValue.isEmpty }.forEach { textField in
            let currentFrame = frame(of: textField, in: view)
            if isShortcutSectionTitle(textField.stringValue) {
                textField.isHidden = false
                textField.font = .systemFont(ofSize: 13, weight: .semibold)
                textField.alignment = .left
                setFrame(of: textField, in: view, to: NSRect(
                    x: 0,
                    y: currentFrame.minY,
                    width: availableWidth,
                    height: currentFrame.height
                ))
            } else if isShortcutRowLabel(textField.stringValue) {
                textField.isHidden = false
                textField.font = .systemFont(ofSize: 12.5, weight: .medium)
                textField.alignment = .left
                setFrame(of: textField, in: view, to: NSRect(
                    x: 0,
                    y: currentFrame.minY,
                    width: labelWidth,
                    height: currentFrame.height
                ))
            }
        }

        recordViews(in: view).forEach { recordView in
            let currentFrame = frame(of: recordView, in: view)
            setFrame(of: recordView, in: view, to: NSRect(
                x: controlX,
                y: currentFrame.minY,
                width: controlWidth,
                height: currentFrame.height
            ))
        }
    }

    private static func compactShortcutItems(_ items: [NSView], in root: NSView) {
        let rowSpacing: CGFloat = 10
        let sectionSpacing: CGFloat = 18
        let sectionTitleSpacing: CGFloat = 8
        let sortedItems = items.sorted {
            frame(of: $0, in: root).maxY > frame(of: $1, in: root).maxY
        }
        var nextMaxY = root.bounds.maxY

        sortedItems.enumerated().forEach { index, item in
            let currentFrame = frame(of: item, in: root)
            let isSectionTitle = (item as? NSTextField).map { isShortcutSectionTitle($0.stringValue) } ?? false
            if isSectionTitle, index > 0 {
                nextMaxY -= sectionSpacing
            }
            setFrame(of: item, in: root, to: NSRect(
                x: currentFrame.minX,
                y: nextMaxY - currentFrame.height,
                width: currentFrame.width,
                height: currentFrame.height
            ))
            nextMaxY -= currentFrame.height + (isSectionTitle ? sectionTitleSpacing : rowSpacing)
        }
    }

    private static func layoutBetaPane(_ view: NSView, availableWidth: CGFloat) {
        let popupWidth: CGFloat = 118
        let popupX = max(0, availableWidth - popupWidth)

        textFields(in: view).filter { !$0.stringValue.isEmpty }.forEach { textField in
            let currentFrame = frame(of: textField, in: view)
            if isBetaIntro(textField.stringValue) || currentFrame.width >= availableWidth * 0.55 {
                textField.font = .systemFont(ofSize: 12.5, weight: .medium)
                textField.alignment = .center
                setFrame(of: textField, in: view, to: NSRect(
                    x: 0,
                    y: currentFrame.minY,
                    width: availableWidth,
                    height: currentFrame.height
                ))
            } else if isBetaSectionTitle(textField.stringValue) {
                textField.font = .systemFont(ofSize: 13, weight: .semibold)
                textField.alignment = .left
                setFrame(of: textField, in: view, to: NSRect(
                    x: 0,
                    y: currentFrame.minY,
                    width: availableWidth,
                    height: currentFrame.height
                ))
            }
        }

        controls(in: view).compactMap { $0 as? NSButton }
            .filter { !$0.title.isEmpty }
            .forEach { button in
                let currentFrame = frame(of: button, in: view)
                setFrame(of: button, in: view, to: NSRect(
                    x: 0,
                    y: currentFrame.minY,
                    width: max(1, popupX - 12),
                    height: currentFrame.height
                ))
            }

        controls(in: view).compactMap { $0 as? NSPopUpButton }.forEach { popup in
            let currentFrame = frame(of: popup, in: view)
            setFrame(of: popup, in: view, to: NSRect(
                x: popupX,
                y: currentFrame.minY,
                width: popupWidth,
                height: currentFrame.height
            ))
        }
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

    private static func isBetaIntro(_ text: String) -> Bool {
        [
            "Beta settings might be moved to a different pane in future versions.",
            "Beta 测试设置将来可能会被移到其它面板。"
        ].contains(text)
    }

    private static func isBetaSectionTitle(_ text: String) -> Bool {
        ["Action", "操作", "Screenshot", "屏幕截图"].contains(text)
    }
}
