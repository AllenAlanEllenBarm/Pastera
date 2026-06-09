//
//  MainMenuPinFooterTests.swift
//
//  Clipy
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MainMenuPinFooterTests {
    @Test
    func mainMenuPanelAlignsPinControlWithQuitRow() throws {
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil, shortcutText: "⌃⌥⌘1") { _ in },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        let pinFrames = controller.mainMenuPinButtonFramesForTesting
        #expect(pinFrames.count == 1)
        let pinFrame = try #require(pinFrames.first)
        let folderRowFrame = try #require(controller.mainMenuSnippetRowFrameForTesting(title: "AI Prompt"))
        let folderTitleFrame = try #require(controller.mainMenuSnippetTitleFrameForTesting(title: "AI Prompt"))
        let quitRowFrame = try #require(controller.mainMenuActionRowFrameForTesting(title: "Quit Pastera"))

        #expect(pinFrame.maxX <= MainMenuPanelLayout.width - MainMenuPanelLayout.pinTrailingInset)
        #expect(abs(pinFrame.midY - quitRowFrame.midY) <= 1)
        #expect(MainMenuPanelLayout.headerHeight == 32)
        #expect(MainMenuPanelLayout.snippetFolderRowHeight == 26)
        #expect(folderRowFrame.height == MainMenuPanelLayout.snippetFolderRowHeight)
        #expect(quitRowFrame.height == MainMenuPanelLayout.rowHeight)
        #expect(abs(folderTitleFrame.midY - MainMenuPanelLayout.snippetFolderRowHeight / 2) <= 1)
        #expect(controller.visibleFrame?.height == expectedMainMenuHeight(
            snippetFolderCount: 1,
            actionRowCount: 1,
            separatorCount: 2
        ))
    }

    @Test
    func mainMenuKeepsReadableFolderTitleAtCompactWidth() throws {
        let folderImage = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            historyShortcutText: "⌃⌘V",
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: folderImage, shortcutText: "⌃⌥⌘1") { _ in },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        let titleAvailableWidth = try #require(
            controller.mainMenuSnippetTitleAvailableWidthForTesting(title: "AI Prompt")
        )
        let quitTitleAvailableWidth = try #require(
            controller.mainMenuActionTitleAvailableWidthForTesting(title: "Quit Pastera")
        )

        #expect(MainMenuPanelLayout.width == 168)
        #expect(titleAvailableWidth >= menuTitleWidth("AI Prompt"))
        #expect(quitTitleAvailableWidth >= menuTitleWidth("Quit Pastera"))
    }

    @Test
    func mainMenuFooterPinTogglesWithoutOpeningHistory() {
        var didOpenHistory = false
        var pinnedValues = [Bool]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {},
            onPinnedChange: { pinnedValues.append($0) }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        controller.performMainMenuPinClickForTesting()

        #expect(pinnedValues == [true])
        #expect(!didOpenHistory)
    }

    private func expectedMainMenuHeight(
        snippetFolderCount: Int,
        actionRowCount: Int,
        separatorCount: Int
    ) -> CGFloat {
        MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + CGFloat(snippetFolderCount) * MainMenuPanelLayout.snippetFolderRowHeight
            + CGFloat(actionRowCount) * MainMenuPanelLayout.rowHeight
            + CGFloat(separatorCount - 1) * (
                MainMenuPanelLayout.separatorHeight
                    + MainMenuPanelLayout.separatorVerticalInset * 2
            )
            + MainMenuPanelLayout.bottomInset
    }

    private func menuTitleWidth(_ title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium)
        ]).width)
    }
}
