//
//  MenuManagerTestingSupport.swift
//
//  Clipy
//

import AppKit

#if DEBUG
extension MenuManager {
    var isMainMenuPanelVisibleForTesting: Bool {
        mainMenuPanelController?.isVisibleForTesting == true
    }

    var mainMenuPanelFrameForTesting: NSRect? {
        mainMenuPanelController?.visibleFrame
    }

    var historyBrowserPanelFrameForTesting: NSRect? {
        historyPanelController?.visibleFrame
    }

    var snippetBrowserPanelFrameForTesting: NSRect? { snippetPanelController?.visibleFrame }
    var snippetBrowserRowTitlesForTesting: [String] { snippetPanelController?.rowTitlesForTesting ?? [] }
    var snippetBrowserShortcutTextsForTesting: [String] { snippetPanelController?.rowShortcutTextsForTesting ?? [] }
    var mainMenuTargetPIDForTesting: pid_t? { mainMenuPanelController?.pasteTargetProcessIdentifierForTesting }
    var historyTargetPIDForTesting: pid_t? { historyPanelController?.pasteTargetProcessIdentifierForTesting }
    var snippetTargetPIDForTesting: pid_t? { snippetPanelController?.pasteTargetProcessIdentifierForTesting }
    var hasStatusItemForTesting: Bool { statusItem != nil }
    var statusItemImageForTesting: NSImage? { statusItem?.button?.image }
    var statusItemActionForTesting: Selector? { statusItem?.button?.action }
    var mainMenuPanelBackgroundAlphaForTesting: CGFloat? { mainMenuPanelController?.contentBackgroundAlphaForTesting }
    var historyPanelBackgroundAlphaForTesting: CGFloat? { historyPanelController?.contentBackgroundAlphaForTesting }
    var snippetPanelBackgroundAlphaForTesting: CGFloat? { snippetPanelController?.contentBackgroundAlphaForTesting }

    var mainMenuPanelActionTitlesForTesting: [String] {
        makeMainMenuPanelItems().compactMap { item in
            if case let .action(title, _, _, _) = item {
                return title
            }
            return nil
        }
    }

    var mainMenuPanelShortcutTextsForTesting: [String: String] {
        makeMainMenuPanelItems().reduce(into: [:]) { result, item in
            switch item {
            case .separator:
                return
            case let .snippetFolder(title, _, shortcutText, _),
                 let .action(title, _, shortcutText, _):
                guard let shortcutText else { return }
                result[title] = shortcutText
            }
        }
    }

    var mainMenuSnippetTitlesForTesting: [String] {
        makeMainMenuPanelItems().compactMap { item in
            if case let .snippetFolder(title, _, _, _) = item {
                return title
            }
            return nil
        }
    }

    func makeHistoryRowViewForTesting(_ historyDetail: PasteboardHistoryDetail, index: Int) -> HistoryMenuRowView {
        makeHistoryRowView(historyDetail, index: index) {}
    }

    func makeSnippetMenuItemForTesting(_ snippet: Snippet, listNumber: Int, rowIndex: Int) -> NSMenuItem {
        makeSnippetMenuItem(snippet, listNumber: listNumber, rowIndex: rowIndex)
    }

    func showMainMenuPanelForTesting(at screenPoint: NSPoint) {
        isMainMenuPinned = true
        showMainMenuPanel(at: screenPoint)
    }

    func showMainMenuPanelForTesting(at screenPoint: NSPoint, pasteTargetContext: PasteTargetContext) {
        isMainMenuPinned = true
        showMainMenuPanel(at: screenPoint, pasteTargetContext: pasteTargetContext)
    }

    func showHistoryBrowserPanelForTesting(at screenPoint: NSPoint) {
        showHistoryBrowserPanel(at: screenPoint)
    }

    func showSnippetBrowserPanelForTesting() {
        showSnippetBrowserPanel()
    }

    func showSnippetFolderPanelForTesting(_ folderID: SnippetFolder.ID) {
        showSnippetFolderPanel(folderID, attachedTo: nil)
    }

    func showSnippetFolderPanelForTesting(_ folderID: SnippetFolder.ID, at screenPoint: NSPoint) {
        showSnippetFolderPanel(folderID, at: screenPoint)
    }

    func handlePanelDismissMouseDownForTesting(at screenPoint: NSPoint) {
        handlePanelDismissMouseDown(at: screenPoint)
    }

    func confirmFirstHistoryForTesting() {
        historyPanelController?.confirmFirstHistoryForTesting()
    }

    func focusFirstHistoryForTesting() {
        historyPanelController?.focusFirstHistoryForTesting()
    }

    func confirmFirstSnippetForTesting() {
        snippetPanelController?.confirmFirstSnippetForTesting()
    }

    func closeHistoryBrowserPanelForTesting() {
        historyPanelController?.close()
    }

    func closeSnippetBrowserPanelForTesting() {
        snippetPanelController?.close()
    }

    func closeMainMenuPanelForTesting() {
        mainMenuPanelController?.close()
        historyPanelController?.close()
        snippetPanelController?.close()
    }

    func removeStatusItemForTesting() {
        removeStatusItem()
    }
}
#endif
