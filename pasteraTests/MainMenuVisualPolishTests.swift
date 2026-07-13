//
//  MainMenuVisualPolishTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MainMenuVisualPolishTests {
    @Test
    func mainMenuKeepsOpaqueDarkFoundationIndependentOfGlobalOpacity() throws {
        let suiteName = "MainMenuVisualPolishTests.opacity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.35, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        #expect(controller.contentBackgroundAlphaForTesting >= 0.98)
        #expect(controller.contentBackgroundLuminanceForTesting < 0.16)
    }

    @Test
    func embeddedHeaderSeparatesTitleTypeFilterAndPagination() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        let frames = try #require(controller.mainMenuEmbeddedHeaderFramesForTesting)
        let titleFrame = try #require(frames["title"])
        let typeFrame = try #require(frames["typeFilter"])
        let previousFrame = try #require(frames["previous"])
        let pageFrame = try #require(frames["page"])
        let pageTextFrame = try #require(frames["pageText"])
        let nextFrame = try #require(frames["next"])
        let controlGroupFrame = typeFrame
            .union(previousFrame)
            .union(pageFrame)
            .union(nextFrame)

        #expect(!titleFrame.intersects(typeFrame))
        #expect(typeFrame.minX >= titleFrame.maxX + 6)
        #expect(controlGroupFrame.width <= 116)
        #expect(typeFrame.maxX == previousFrame.minX)
        #expect(previousFrame.maxX == pageFrame.minX)
        #expect(pageFrame.maxX == nextFrame.minX)
        #expect(previousFrame.size == NSSize(width: 22, height: 26))
        #expect(pageFrame.height == previousFrame.height)
        #expect(pageFrame.minY == previousFrame.minY)
        #expect(nextFrame.size == NSSize(width: 22, height: 26))
        #expect(abs(previousFrame.midY - pageFrame.midY) <= 0.5)
        #expect(abs(nextFrame.midY - pageFrame.midY) <= 0.5)
        #expect(pageTextFrame.minY > pageFrame.minY)
        #expect(pageTextFrame.maxY < pageFrame.maxY)
        #expect(abs(previousFrame.midY - pageTextFrame.midY) <= 0.5)
        #expect(abs(nextFrame.midY - pageTextFrame.midY) <= 0.5)

        let cornerRadii = try #require(controller.mainMenuEmbeddedHeaderCornerRadiiForTesting)
        #expect(cornerRadii["typeFilter"] == 13)
        #expect(cornerRadii["next"] == 11)
    }

    @Test
    func footerToolbarUsesUnifiedHitAreas() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        let frames = controller.mainMenuToolbarButtonFramesForTesting
        let unifiedButtonIDs = [
            "mainMenuSearchButton",
            "mainMenuOneDriveStatusButton",
            "mainMenuPreferencesButton"
        ]

        for identifier in unifiedButtonIDs {
            let frame = try #require(frames[identifier])
            #expect(frame.size == NSSize(
                width: MainMenuPanelLayout.toolbarButtonSize,
                height: MainMenuPanelLayout.toolbarButtonSize
            ))
        }

        let historyFrame = try #require(frames["mainMenuHistoryModeButton"])
        let snippetFrame = try #require(frames["mainMenuSnippetModeButton"])
        let oneDriveFrame = try #require(frames["mainMenuOneDriveStatusButton"])
        #expect(frames["mainMenuShortcutsButton"] == nil)
        #expect(historyFrame.height == MainMenuPanelLayout.modeControlHeight)
        #expect(snippetFrame.height == MainMenuPanelLayout.modeControlHeight)
        #expect(historyFrame.width == 31)
        #expect(snippetFrame.width == 31)
        #expect(oneDriveFrame.minX - snippetFrame.maxX >= 10)
        #expect(abs(historyFrame.midY - snippetFrame.midY) <= 0.5)
        #expect(abs(historyFrame.midY - frames["mainMenuOneDriveStatusButton"]!.midY) <= 0.5)
    }

    @Test
    func shortcutsArePresentedByTheirOwningComponents() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuToolbarToolTipForTesting(identifier: "mainMenuSearchButton")?.contains("⌘F") == true)
        #expect(controller.mainMenuHeaderToolTipsForTesting["previous"]?.contains("←") == true)
        #expect(controller.mainMenuHeaderToolTipsForTesting["next"]?.contains("→") == true)
        #expect(controller.mainMenuHeaderToolTipsForTesting["typeFilter"]?.contains("Tab") == true)

        let rowToolTip = try #require(controller.mainMenuRowToolTipForTesting(title: "First copied value"))
        #expect(rowToolTip.contains("↩"))
        #expect(rowToolTip.contains("1"))
    }

    @Test
    func embeddedMainMenuUsesThreeInsetSurfaceBlocks() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuPanelContentSizeForTesting == NSSize(width: 282, height: 332))

        let sections = try #require(controller.mainMenuEmbeddedSectionFramesForTesting)
        let headerFrame = try #require(sections["header"])
        let contentFrame = try #require(sections["content"])
        let footerFrame = try #require(sections["footer"])

        #expect(headerFrame == NSRect(x: 7, y: 289, width: 268, height: 36))
        #expect(contentFrame.minX == 7)
        #expect(contentFrame.width == 268)
        #expect(footerFrame == NSRect(x: 7, y: 6, width: 268, height: 34))
        #expect(headerFrame.minY - contentFrame.maxY >= 5)
        #expect(contentFrame.minY - footerFrame.maxY >= 5)
        #expect(!headerFrame.intersects(contentFrame))
        #expect(!contentFrame.intersects(footerFrame))
        #expect(controller.mainMenuEmbeddedSeparatorCountForTesting == 0)
    }

    @Test
    func embeddedRowsStayInsideContentSurface() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        let sections = try #require(controller.mainMenuEmbeddedSectionFramesForTesting)
        let contentFrame = try #require(sections["content"])
        let firstRowFrame = try #require(controller.mainMenuFirstVisibleRowFrameForTesting)
        controller.selectMainMenuItemForTesting(title: "First copied value")
        let selectedRowFrame = try #require(controller.mainMenuSelectedRowFrameForTesting)

        #expect(firstRowFrame.minX >= contentFrame.minX + 3)
        #expect(firstRowFrame.maxX <= contentFrame.maxX - 3)
        #expect(firstRowFrame.maxY <= contentFrame.maxY - 3)
        #expect(firstRowFrame.minY >= contentFrame.minY + 3)
        #expect(selectedRowFrame.minX >= contentFrame.minX + 3)
        #expect(selectedRowFrame.maxX <= contentFrame.maxX - 3)
    }

    @Test
    func embeddedSearchSlidesBelowMainPanelWithoutMovingMainContent() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        let initialFrame = try #require(controller.visibleFrame)
        let initialSections = try #require(controller.mainMenuEmbeddedSectionFramesForTesting)
        let initialContentFrame = try #require(initialSections["content"])
        let initialFooterFrame = try #require(initialSections["footer"])
        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))

        let expandedFrame = try #require(controller.visibleFrame)
        let searchFrame = try #require(controller.mainMenuSearchFieldFrameForTesting)
        let sections = try #require(controller.mainMenuEmbeddedSectionFramesForTesting)
        let contentFrame = try #require(sections["content"])
        let footerFrame = try #require(sections["footer"])
        let extensionHeight = MainMenuPanelLayout.bottomInset
            + MainMenuPanelLayout.searchHeight
            + MainMenuPanelLayout.sectionGap

        #expect(expandedFrame.minX == initialFrame.minX)
        #expect(expandedFrame.maxY == initialFrame.maxY)
        #expect(expandedFrame.width == initialFrame.width)
        #expect(expandedFrame.height == initialFrame.height + extensionHeight)
        #expect(searchFrame == NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: MainMenuPanelLayout.bottomInset,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.searchHeight
        ))
        #expect(extensionHeight - searchFrame.maxY == MainMenuPanelLayout.sectionGap)
        #expect(footerFrame.minY - extensionHeight == MainMenuPanelLayout.bottomInset)
        #expect(contentFrame.minY - footerFrame.maxY >= MainMenuPanelLayout.sectionGap)
        #expect(!searchFrame.intersects(contentFrame))
        #expect(!searchFrame.intersects(footerFrame))
        #expect(contentFrame.height == initialContentFrame.height)
        #expect(contentFrame.minY == initialContentFrame.minY + extensionHeight)
        #expect(footerFrame.minY == initialFooterFrame.minY + extensionHeight)
        #expect(expandedFrame.minY + contentFrame.minY == initialFrame.minY + initialContentFrame.minY)
        #expect(expandedFrame.minY + footerFrame.minY == initialFrame.minY + initialFooterFrame.minY)
    }

    @Test
    func compactVisualTokensAvoidLargeSaturatedBlueBlocks() {
        #expect(MainMenuPanelLayout.width == 282)
        #expect(MainMenuPanelLayout.fixedHeight == 332)
        #expect(MainMenuPanelLayout.headerHeight == 40)
        #expect(MainMenuPanelLayout.toolbarHeight == 34)
        #expect(MainMenuPanelLayout.rowHeight == 30)
        #expect(MainMenuPanelLayout.compactImageRowHeight == 30)
        #expect(MainMenuPanelLayout.sectionInset == 10)
        #expect(MainMenuPanelLayout.sectionGap == 8)
        #expect(MainMenuPanelLayout.contentInnerPadding == 8)
        #expect(MainMenuPanelLayout.sectionRadius == 12)
        #expect(MainMenuPanelLayout.toolbarHeight == 36)
        #expect(MainMenuPanelLayout.toolbarButtonSize == 28)
        #expect(MainMenuVisualColors.panelBackground.alphaComponent == 1)
        #expect(MainMenuVisualColors.selectedRow.alphaComponent <= 0.16)
        #expect(MainMenuVisualColors.accentFill.alphaComponent <= 0.18)
    }

    @Test
    func historyRowDeleteButtonOnlyAppearsOnHoverOrFocus() throws {
        let row = HistoryMenuRowView(title: "Copied value", image: nil, onDelete: {}, onConfirm: {})
        let deleteButton = try #require(historyRowDeleteButton(in: row))

        #expect(deleteButton.isHidden)

        row.mouseEntered(with: try makeMouseEvent(type: .mouseEntered))
        #expect(!deleteButton.isHidden)

        row.mouseExited(with: try makeMouseEvent(type: .mouseExited))
        #expect(deleteButton.isHidden)

        #expect(row.becomeFirstResponder())
        #expect(!deleteButton.isHidden)
    }

    @Test
    func compactHistoryRowDeleteButtonOnlyAppearsOnHover() throws {
        let row = HistoryMenuRowView(
            title: "Copied value",
            image: nil,
            layoutStyle: .compactMainMenu,
            onDelete: {},
            onConfirm: {}
        )
        let deleteButton = try #require(historyRowDeleteButton(in: row))

        #expect(deleteButton.isHidden)

        #expect(row.becomeFirstResponder())
        #expect(deleteButton.isHidden)
        #expect(row.deleteFromKeyboard())

        row.mouseEntered(with: try makeMouseEvent(type: .mouseEntered))
        #expect(!deleteButton.isHidden)
    }

    private func makeHistoryController() -> MainMenuPanelController {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-1"),
                title: "First copied value",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var state = HistoryMenuPaginationState()
        return MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { state },
                updateState: { update in update(&state) },
                fetchPage: { HistoryMenuPage.result([detail], pageSize: 10) },
                makeRowView: { detail, index, onConfirm in
                    HistoryMenuRowView(
                        title: detail.history.title,
                        image: nil,
                        shortcutText: "\(index + 1)",
                        onConfirm: onConfirm
                    )
                },
                selectHistory: { _, _ in }
            )
        )
    }

    private func historyRowDeleteButton(in row: HistoryMenuRowView) -> NSButton? {
        row.subviews
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "historyRowDeleteButton" }
    }

    private func makeMouseEvent(type: NSEvent.EventType) throws -> NSEvent {
        try #require(NSEvent.enterExitEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        ))
    }

    private func makeCommandFEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "f",
            charactersIgnoringModifiers: "f",
            isARepeat: false,
            keyCode: 3
        ))
    }
}
