//
//  MainMenuChildNavigationTests.swift
//
//  Clipy
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MainMenuChildNavigationTests {
    @Test
    func arrowKeyInSnippetPanelIsForwardedToMainMenuNavigation() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "Ask GPT",
                    content: "Summarize this",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        var forwardedKeyCodes = [UInt16]()
        let controller = SnippetBrowserPanelController(
            fetchFolders: { [detail.folder] },
            fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
            selectSnippet: { _, _ in }
        )
        controller.onMainMenuNavigationKeyDown = { event in
            forwardedKeyCodes.append(event.keyCode)
            return true
        }

        controller.show(
            folderID: folderID,
            attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220)
        )
        defer { controller.close() }

        #expect(controller.handleKeyDownForTesting(try makeArrowEvent(keyCode: 125)))
        #expect(forwardedKeyCodes == [125])
    }

    private func makeArrowEvent(keyCode: UInt16) throws -> NSEvent {
        let characters: String
        switch keyCode {
        case 125:
            characters = "\u{F701}"
        case 126:
            characters = "\u{F700}"
        default:
            characters = ""
        }
        return try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
