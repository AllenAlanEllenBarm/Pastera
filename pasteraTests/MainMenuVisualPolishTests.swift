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
    func ocrActivityRailUsesFixedHeightAndRealQueueStates() {
        let view = MainMenuOCRActivityView(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        #expect(MainMenuOCRActivityView.height == 32)

        view.render(.indexing(remaining: 12))
        #expect(!view.isHidden)
        #expect(view.accessibilityLabel() == String(localized: "Recognizing image text"))
        #expect(view.accessibilityValue() as? String == String.localizedStringWithFormat(
            String(localized: "%lld items remaining"), 12
        ))

        view.render(.idle)
        #expect(view.isHidden)
    }

    @Test
    func mainMenuFoundationUsesConfiguredOpacity() throws {
        let suiteName = "MainMenuVisualPolishTests.opacity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.35, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        #expect(abs(controller.contentBackgroundAlphaForTesting - 0.35) < 0.001)
        #expect(controller.contentBackgroundLuminanceForTesting < 0.16)
    }

    @Test
    func embeddedHeaderUsesCurrentTypeAsCompactFilterControl() throws {
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
        let paginationFrame = previousFrame.union(pageFrame).union(nextFrame)

        #expect(titleFrame.width == 0)
        #expect(typeFrame.minX == MainMenuPanelLayout.sectionInset + 9)
        #expect(typeFrame.width == 175)
        #expect(typeFrame.maxX + 11 <= previousFrame.minX)
        #expect(paginationFrame.width == 80)
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
        #expect(cornerRadii["typeFilter"] == 8)
        #expect(cornerRadii["next"] == 11)
    }

    @Test
    func typeFilterUsesCompactIconRailWithoutOpeningAChildPanel() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        let frames = controller.mainMenuTypeFilterItemFramesForTesting
        #expect(frames.count == HistoryMenuTypeFilter.allCases.count)
        #expect(Set(frames.map(\.minX)).count == HistoryMenuTypeFilter.allCases.count)
        #expect(Set(frames.map(\.minY)).count == 1)
        #expect(frames.allSatisfy { $0.size == NSSize(width: 21, height: 26) })
        #expect(controller.mainMenuSelectedTypeFilterTitlesForTesting == [HistoryMenuTypeFilter.all.title])
        #expect(HistoryMenuTypeFilter.displayCases.suffix(2) == [.pdf, .otherFiles])
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
    func footerToolbarUsesOneSelectedModeAndQuietUtilityFeedback() throws {
        let toolbar = MainMenuToolbarView(
            frame: NSRect(x: 0, y: 0, width: 262, height: MainMenuPanelLayout.toolbarHeight),
            configuration: MainMenuToolbarViewConfiguration(
                selectedMode: .history,
                oneDriveStatus: .notInstalled
            ),
            actions: MainMenuToolbarActions(
                onSearch: {},
                onHistory: {},
                onSnippets: {},
                onPasswordVault: {},
                onOneDrive: {},
                onPreferences: {}
            )
        )

        let history = try #require(toolbar.buttonVisualStateForTesting(identifier: "mainMenuHistoryModeButton"))
        let snippets = try #require(toolbar.buttonVisualStateForTesting(identifier: "mainMenuSnippetModeButton"))
        let search = try #require(toolbar.buttonVisualStateForTesting(identifier: "mainMenuSearchButton"))
        #expect(history.backgroundAlpha > 0)
        #expect(snippets.backgroundAlpha == 0)
        #expect(search.backgroundAlpha == 0)

        toolbar.setHoveredForTesting(true, identifier: "mainMenuSearchButton")
        let hoveredSearch = try #require(toolbar.buttonVisualStateForTesting(identifier: "mainMenuSearchButton"))
        #expect(hoveredSearch.backgroundAlpha > 0)
        #expect(hoveredSearch.backgroundAlpha < history.backgroundAlpha)
    }

    @Test
    func footerModeHintsUseConfiguredShortcutsAndReplaceNativeToolTips() throws {
        let service = HotKeyService()
        service.resetMenuShortcutsToDefaults()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }

        let toolbar = MainMenuToolbarView(
            frame: NSRect(x: 0, y: 0, width: 284, height: MainMenuPanelLayout.toolbarHeight),
            configuration: MainMenuToolbarViewConfiguration(
                selectedMode: .history,
                oneDriveStatus: .notInstalled
            ),
            actions: MainMenuToolbarActions(
                onSearch: {},
                onHistory: {},
                onSnippets: {},
                onPasswordVault: {},
                onOneDrive: {},
                onPreferences: {}
            )
        )

        let expectations: [(String, String?)] = [
            ("mainMenuHistoryModeButton", PasteraShortcutFormatter.string(for: service.historyKeyCombo)),
            ("mainMenuSnippetModeButton", PasteraShortcutFormatter.string(for: service.snippetKeyCombo)),
            ("mainMenuPasswordVaultModeButton", PasteraShortcutFormatter.string(for: service.passwordVaultKeyCombo))
        ]
        for (identifier, shortcut) in expectations {
            #expect(toolbar.hoverTipForTesting(identifier: identifier)?.shortcut == shortcut)
            #expect(shortcut?.isEmpty == false)
            #expect(toolbar.nativeToolTipForTesting(identifier: identifier) == nil)
        }
    }

    @Test
    func shortcutsArePresentedByTheirOwningComponents() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuToolbarToolTipForTesting(identifier: "mainMenuSearchButton")?.contains("⌘F") == true)
        #expect(controller.mainMenuHeaderToolTipsForTesting["previous"]?.contains("←") == true)
        #expect(controller.mainMenuHeaderToolTipsForTesting["next"]?.contains("→") == true)
        #expect(controller.mainMenuHeaderToolTipsForTesting["typeFilter"] == HistoryMenuTypeFilter.all.title)

        let rowToolTip = try #require(controller.mainMenuRowToolTipForTesting(title: "First copied value"))
        #expect(rowToolTip.contains("↩"))
        #expect(rowToolTip.contains("1"))
    }

    @Test
    func embeddedMainMenuUsesContinuousChromeWithoutNestedSurfaceCards() throws {
        let controller = makeHistoryController()
        controller.show(at: NSPoint(x: 160, y: 640), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuPanelContentSizeForTesting == NSSize(
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.fixedHeight
        ))

        let sections = try #require(controller.mainMenuEmbeddedSectionFramesForTesting)
        let headerFrame = try #require(sections["header"])
        let contentFrame = try #require(sections["content"])
        let footerFrame = try #require(sections["footer"])

        #expect(headerFrame == NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: MainMenuPanelLayout.fixedHeight - MainMenuPanelLayout.sectionInset - MainMenuPanelLayout.headerHeight,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.headerHeight
        ))
        #expect(contentFrame.minX == MainMenuPanelLayout.sectionInset)
        #expect(contentFrame.width == MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2)
        #expect(footerFrame == NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: MainMenuPanelLayout.bottomInset,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.toolbarHeight
        ))
        #expect(headerFrame.minY - contentFrame.maxY == MainMenuPanelLayout.sectionGap)
        #expect(contentFrame.minY - footerFrame.maxY == MainMenuPanelLayout.sectionGap)
        #expect(!headerFrame.intersects(contentFrame))
        #expect(!contentFrame.intersects(footerFrame))
        #expect(controller.mainMenuEmbeddedSeparatorCountForTesting == 0)

        let chrome = controller.mainMenuEmbeddedChromeForTesting
        #expect(chrome["header"]?.backgroundAlpha == 0)
        #expect(chrome["header"]?.borderWidth == 0)
        #expect(chrome["content"]?.backgroundAlpha == 0)
        #expect(chrome["content"]?.borderWidth == 0)
        #expect(chrome["footer"]?.backgroundAlpha == 0)
        #expect(chrome["footer"]?.borderWidth == 0)
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
        #expect(MainMenuPanelLayout.width == 300)
        #expect(MainMenuPanelLayout.fixedHeight == 356)
        #expect(MainMenuPanelLayout.headerHeight == 38)
        #expect(MainMenuPanelLayout.toolbarHeight == 40)
        #expect(MainMenuPanelLayout.rowHeight == 32)
        #expect(MainMenuPanelLayout.compactImageRowHeight == 32)
        #expect(MainMenuPanelLayout.sectionInset == 8)
        #expect(MainMenuPanelLayout.sectionGap == 4)
        #expect(MainMenuPanelLayout.contentInnerPadding == 3)
        #expect(MainMenuPanelLayout.sectionRadius == 12)
        #expect(MainMenuPanelLayout.toolbarHeight == 40)
        #expect(MainMenuPanelLayout.toolbarButtonSize == 30)
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
