//
//  KeyboardAccessibilityTests.swift
//
//  Pastera
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct KeyboardAccessibilityTests {
    @Test
    func shortcutRecordViewsUseDarkElevatedBackgroundInsteadOfWhite() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        controller.window?.appearance = darkAppearance
        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let brightnessValues = controller.preferenceRecordViewBackgroundBrightnessValuesForTesting

        #expect(brightnessValues.count >= 4)
        for brightness in brightnessValues {
            #expect(brightness < 0.40, "RecordView should not keep a white background in dark mode")
        }
    }

    @Test
    func preferencePanesUseComfortableVerticalRhythm() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)

        for paneTitle in ["General", "Types", "Shortcuts", "Update"] {
            controller.showPreferencePaneForTesting(title: paneTitle)
            let minimumGap = try #require(controller.minimumVisibleControlVerticalGapForTesting)
            #expect(minimumGap >= 8, "\(paneTitle) pane controls are visually cramped: \(minimumGap)")
        }
    }

    @Test
    func preferenceSidebarCanSwitchPanesWithKeyboard() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "General")

        let downEvent = try makeKeyEvent(keyCode: 125, characters: "\u{F701}")
        let returnEvent = try makeKeyEvent(keyCode: 36, characters: "\r")

        #expect(controller.handlePreferenceKeyboardEventForTesting(downEvent))
        #expect(controller.selectedPreferencePaneTitleForTesting == "Types")

        #expect(controller.handlePreferenceKeyboardEventForTesting(returnEvent))
        #expect(controller.focusedPreferencePaneControlTitleForTesting != nil)
    }

    @Test
    func preferenceWindowDefaultsKeyboardFocusToSelectedSidebar() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)

        let downEvent = try makeKeyEvent(keyCode: 125, characters: "\u{F701}")

        #expect(controller.focusedPreferenceSidebarTitleForTesting == "General")
        #expect(controller.handlePreferenceKeyboardEventForTesting(downEvent))
        #expect(controller.focusedPreferenceSidebarTitleForTesting == "Types")
        #expect(controller.selectedPreferencePaneTitleForTesting == "Types")
    }

    @Test
    func preferenceSidebarTabSwitchesToNextSidebarPane() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "General")

        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")

        #expect(controller.handlePreferenceKeyboardEventForTesting(tabEvent))
        #expect(controller.focusedPreferenceSidebarTitleForTesting == "Types")
        #expect(controller.selectedPreferencePaneTitleForTesting == "Types")
    }

    @Test
    func preferencePaneSwitchingKeepsWindowSizeStableAndUsesScrollDocuments() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        let initialFrameSize = try #require(controller.window?.frame.size)

        #expect(initialFrameSize == NSSize(width: 600, height: 340))
        #expect(controller.window?.minSize == NSSize(width: 560, height: 320))

        for paneTitle in ["General", "Types", "Exclude", "Shortcuts", "Update"] {
            controller.showPreferencePaneForTesting(title: paneTitle)

            #expect(controller.window?.frame.size == initialFrameSize)
            #expect(controller.preferencePaneUsesScrollDocumentForTesting)
            if paneTitle == "General" {
                #expect(controller.selectedPaneDocumentOriginForTesting.x == 16)
                #expect(controller.selectedPaneDocumentOriginForTesting.y >= 16)
            } else {
                #expect(
                    controller.selectedPaneDocumentOriginForTesting == NSPoint(x: 16, y: 16),
                    "\(paneTitle) pane should be pinned to the top-leading inset"
                )
                let visibleTopGap = try #require(controller.preferencePaneVisibleTopGapForTesting)
                #expect(
                    visibleTopGap <= 28,
                    "\(paneTitle) pane content starts too low: \(visibleTopGap)"
                )
            }
            #expect(controller.selectedPaneDocumentWidthForTesting <= controller.preferencePaneViewportWidthForTesting)
        }
    }

    @Test
    func preferenceWindowUsesCompactSidebarAndWidePaneContent() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Types")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let sidebarView = try #require(preferenceSidebarView(in: contentView))

        #expect(sidebarView.frame.width == 112)
        #expect(controller.selectedPaneDocumentWidthForTesting >= controller.preferencePaneViewportWidthForTesting - 40)

        #expect(
            controller.selectedPaneDocumentOriginForTesting.y == 16,
            "Types pane should start at the top inset"
        )
    }

    @Test
    func typePreferenceCheckboxesAreNotClippedByTheirContainers() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Types")

        let contentView = try #require(controller.window?.contentView)
        let expectedTitles = [
            "文本",
            "富文本",
            "富文本附件",
            "文档",
            "文件",
            "链接",
            "图片内容",
            "图片",
            "常用文本文件类型"
        ]
        let buttons = preferenceButtons(in: contentView)
            .filter { expectedTitles.contains($0.title) }

        #expect(buttons.count == expectedTitles.count)
        #expect(!preferenceButtons(in: contentView).contains { button in
            ["Plain Text", "Rich Text Format (RTF)", "Rich Text Format Directory (RTFD)", "Filenames", "TIFF Image"]
                .contains(button.title)
        })
        for button in buttons {
            let containerBounds = try #require(button.superview?.bounds)
            #expect(button.frame.minX >= 0, "\(button.title) is clipped on the leading edge")
            #expect(button.frame.maxX <= containerBounds.width, "\(button.title) exceeds its container width")
            #expect(button.frame.minY >= 0, "\(button.title) is clipped on the top/bottom edge")
            #expect(button.frame.maxY <= containerBounds.height, "\(button.title) exceeds its container height")
        }
    }

    @Test
    func typePreferenceCheckboxCanBeToggledFromKeyboard() throws {
        let defaults = AppEnvironment.current.defaults
        let originalStoreTypes = defaults.object(forKey: Constants.UserDefaults.storeTypes)
        defer {
            if let originalStoreTypes {
                defaults.set(originalStoreTypes, forKey: Constants.UserDefaults.storeTypes)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.storeTypes)
            }
        }

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "Types")

        let returnEvent = try makeKeyEvent(keyCode: 36, characters: "\r")
        let spaceEvent = try makeKeyEvent(keyCode: 49, characters: " ")

        #expect(controller.handlePreferenceKeyboardEventForTesting(returnEvent))
        #expect(controller.focusedPreferencePaneControlTitleForTesting == "文本")

        let contentView = try #require(controller.window?.contentView)
        let plainTextButton = try #require(preferenceButtons(in: contentView).first { $0.title == "文本" })
        let initialState = plainTextButton.state

        #expect(controller.handlePreferenceKeyboardEventForTesting(spaceEvent))
        #expect(plainTextButton.state != initialState)
    }

    @Test
    func preferenceCompactMenuPaneFitsInsideFixedWindow() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Menu")

        let initialFrameSize = try #require(controller.window?.frame.size)

        #expect(controller.preferencePaneUsesScrollDocumentForTesting)
        #expect(controller.selectedPaneDocumentHeightForTesting <= controller.preferencePaneViewportHeightForTesting + 0.5)
        #expect(controller.window?.frame.size == initialFrameSize)
    }

    @Test
    func preferenceTabAndShiftTabCycleBetweenSidebarAndPane() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "Update")

        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")
        let shiftTabEvent = try makeKeyEvent(keyCode: 48, characters: "\t", modifierFlags: [.shift])

        #expect(controller.handlePreferenceKeyboardEventForTesting(tabEvent))
        #expect(controller.focusedPreferencePaneControlTitleForTesting != nil)

        #expect(controller.handlePreferenceKeyboardEventForTesting(shiftTabEvent))
        #expect(controller.focusedPreferenceSidebarTitleForTesting == "Update")
    }

    @Test
    func preferencePaneArrowKeysMoveBetweenFocusableControls() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "Shortcuts")

        let returnEvent = try makeKeyEvent(keyCode: 36, characters: "\r")
        let downEvent = try makeKeyEvent(keyCode: 125, characters: "\u{F701}")

        #expect(controller.handlePreferenceKeyboardEventForTesting(returnEvent))
        let firstControl = try #require(controller.window?.firstResponder as? NSView)

        #expect(controller.handlePreferenceKeyboardEventForTesting(downEvent))
        let secondControl = try #require(controller.window?.firstResponder as? NSView)
        #expect(secondControl !== firstControl)
    }

    @Test
    func snippetEditorToolbarButtonsCanBeConfirmedFromKeyboard() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folder = SnippetFolder(id: folderID, title: "untitled folder", index: 0, isEnabled: true)
        var didInsertFolder = false
        let spaceEvent = try makeKeyEvent(keyCode: 49, characters: " ")

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(
                details: [],
                insertedFolder: folder,
                onInsertFolder: { didInsertFolder = true }
            )
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.focusToolbarButtonForTesting(title: "Add Folder")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(spaceEvent))
            #expect(didInsertFolder)
        }
    }

    @Test
    func snippetEditorOutlineSupportsKeyboardRenameToggleAndDelete() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "test1",
                    content: "value",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        var toggledSnippetID: Snippet.ID?
        var deletedSnippetID: Snippet.ID?
        let returnEvent = try makeKeyEvent(keyCode: 36, characters: "\r")
        let spaceEvent = try makeKeyEvent(keyCode: 49, characters: " ")
        let deleteEvent = try makeKeyEvent(keyCode: 51, characters: "\u{7F}")

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(
                details: [detail],
                onUpdateSnippetEnabled: { id, _ in toggledSnippetID = id },
                onDeleteSnippet: { id in deletedSnippetID = id }
            )
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.selectSnippetForTesting(id: snippetID)

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(returnEvent))
            #expect(controller.isEditingOutlineTitleForTesting)

            controller.cancelOutlineEditingForTesting()
            #expect(controller.handleSnippetEditorKeyboardEventForTesting(spaceEvent))
            #expect(toggledSnippetID == snippetID)

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(deleteEvent))
            #expect(deletedSnippetID == snippetID)
        }
    }

    @Test
    func snippetEditorTabCyclesThroughToolbarOutlineAndDetail() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "test1",
                    content: "value",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")
        let shiftTabEvent = try makeKeyEvent(keyCode: 48, characters: "\t", modifierFlags: [.shift])

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(details: [detail])
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.focusToolbarButtonForTesting(title: "Export")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(tabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "outline")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(tabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "detail")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(shiftTabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "outline")
        }
    }

    @Test
    func snippetEditorTextViewTabMovesFocusAndOptionTabKeepsTextInput() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "test1",
                    content: "value",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")
        let optionTabEvent = try makeKeyEvent(keyCode: 48, characters: "\t", modifierFlags: [.option])

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(details: [detail])
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.selectSnippetForTesting(id: snippetID)
            controller.focusSnippetTextEditorForTesting()

            #expect(!controller.handleSnippetEditorKeyboardEventForTesting(optionTabEvent))

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(tabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "toolbar")
        }
    }

    @Test
    func snippetEditorToolbarIsHostedInScrollContainer() {
        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(details: [])
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)

            #expect(controller.toolbarUsesScrollContainerForTesting)
        }
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceSidebarView(in contentView: NSView) -> NSView? {
        contentView.subviews
            .filter { $0.frame.minX <= 0.5 && $0.frame.height >= contentView.bounds.height - 1 }
            .sorted { $0.frame.width < $1.frame.width }
            .first
    }
}

private struct SnippetEditorKeyboardRepository: SnippetRepositoryProtocol {
    var details: [SnippetFolderDetail]
    var insertedFolder: SnippetFolder?
    var onInsertFolder: () -> Void = {}
    var onUpdateSnippetEnabled: (Snippet.ID, Bool) -> Void = { _, _ in }
    var onDeleteSnippet: (Snippet.ID) -> Void = { _ in }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just(details).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { details }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { details.first { $0.folder.id == id } }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? {
        onInsertFolder()
        return insertedFolder
    }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func removeDuplicateFoldersAndSnippets() -> Int { 0 }
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool { true }
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? {
        details.flatMap(\.snippets).first { $0.id == id }
    }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool { true }
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {
        onUpdateSnippetEnabled(id, isEnabled)
    }
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {
        onDeleteSnippet(id)
    }
}
