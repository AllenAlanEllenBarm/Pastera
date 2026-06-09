//
//  SnippetEditorCellLayoutTests.swift
//
//  Clipy
//

import AppKit
import Testing
@testable import Pastera

@MainActor
struct SnippetEditorCellLayoutTests {
    private let rowBounds = NSRect(x: 0, y: 0, width: 240, height: 28)

    @Test
    func folderTitleUsesCompactCenteredTextRect() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")
        cell.iconType = .folder

        let titleRect = cell.titleRect(forBounds: rowBounds)

        #expect(abs(titleRect.midY - rowBounds.midY) <= 0.5)
        #expect(titleRect.height == 16)
    }

    @Test
    func snippetTitleUsesCompactCenteredTextRectWithoutIcon() {
        let cell = CPYSnippetsEditorCell(textCell: "test1")
        cell.iconType = .none

        let titleRect = cell.titleRect(forBounds: rowBounds)

        #expect(abs(titleRect.midY - rowBounds.midY) <= 0.5)
        #expect(titleRect.height == 16)
    }

    @Test
    func titleRectUsesSingleLineHeightForFourteenPointFont() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")
        cell.iconType = .folder
        cell.font = .systemFont(ofSize: 14)

        let titleRect = cell.titleRect(forBounds: rowBounds)

        #expect(abs(titleRect.midY - rowBounds.midY) <= 0.5)
        #expect(titleRect.height == 17)
    }

    @Test
    func folderIconSharesTheRowCenterline() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")
        cell.iconType = .folder

        let iconRect = cell.folderIconRectForTesting(in: rowBounds)

        #expect(abs(iconRect.midY - rowBounds.midY) <= 0.5)
        #expect(iconRect.height == 13)
    }

    @Test
    func shortcutBadgeReservesSpaceWithoutMovingTitleOffCenter() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")
        cell.iconType = .folder
        cell.shortcutText = "⌃⌥⌘1"
        cell.shortcutStyle = .command

        let titleRect = cell.titleRect(forBounds: rowBounds)
        let badgeRect = cell.shortcutBadgeRectForTesting(in: rowBounds)

        #expect(titleRect.maxX <= badgeRect.minX - CPYSnippetsEditorCell.Metrics.shortcutSpacing)
        #expect(abs(titleRect.midY - rowBounds.midY) <= 0.5)
        #expect(abs(badgeRect.midY - rowBounds.midY) <= 0.5)
    }

    @Test
    func itemNumberShortcutBadgeUsesReadableMinimumWidth() {
        let cell = CPYSnippetsEditorCell(textCell: "test1")
        cell.iconType = .none
        cell.shortcutText = "1"
        cell.shortcutStyle = .itemNumber

        let badgeRect = cell.shortcutBadgeRectForTesting(in: rowBounds)

        #expect(CPYSnippetsEditorCell.Metrics.shortcutMinWidth == 22)
        #expect(badgeRect.width == 22)
        #expect(abs(badgeRect.midY - rowBounds.midY) <= 0.5)
    }

    @Test
    func commandShortcutBadgeUsesReadableMinimumWidth() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")
        cell.iconType = .folder
        cell.shortcutText = "⌘"
        cell.shortcutStyle = .command

        let badgeRect = cell.shortcutBadgeRectForTesting(in: rowBounds)

        #expect(CPYSnippetsEditorCell.Metrics.commandShortcutMinWidth == 24)
        #expect(CPYSnippetsEditorCell.Metrics.commandShortcutHorizontalPadding == 6)
        #expect(badgeRect.width == 24)
        #expect(abs(badgeRect.midY - rowBounds.midY) <= 0.5)
    }
}
