//
//  MainMenuPanelController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/03.
//
//  Copyright © 2015-2026 Clipy Project.
import Cocoa
import KeyHolder
import Magnet

// swiftlint:disable file_length

enum MainMenuPanelLayout {
    static let width: CGFloat = 282
    static let fixedHeight: CGFloat = 356
    static let topInset: CGFloat = 10
    static let bottomInset: CGFloat = 10
    static let rowHeight: CGFloat = 30
    static let compactImageRowHeight: CGFloat = 30
    static let snippetFolderRowHeight: CGFloat = 30
    static let noticeHeight: CGFloat = 52
    static let headerHeight: CGFloat = 40
    static let toolbarHeight: CGFloat = 36
    static let searchHeight: CGFloat = 28
    static let sectionInset: CGFloat = 10
    static let sectionGap: CGFloat = 8
    static let sectionRadius: CGFloat = 12
    static let contentInnerPadding: CGFloat = 8
    static let inlineEditorHeight: CGFloat = 210
    static let folderShortcutEditorHeight: CGFloat = 38
    static let separatorHeight: CGFloat = 1
    static let separatorHorizontalInset: CGFloat = 7
    static let separatorVerticalInset: CGFloat = 3
    static let separatorAlpha: CGFloat = 0.10
    static let oneDriveStatusButtonSize: CGFloat = 28
    static let oneDriveStatusIconSize: CGFloat = 14
    static let oneDriveStatusTrailingInset: CGFloat = 7
    static let toolbarButtonSize: CGFloat = 28
    static let toolbarHorizontalInset: CGFloat = 8
    static let modeButtonWidth: CGFloat = 31
    static let modeControlHeight: CGFloat = 28
    static let cornerRadius: CGFloat = PasteraDesignTokens.Metrics.panelCornerRadius
    static let screenPadding: CGFloat = 8
    static let folderHoverOpenDelay: TimeInterval = 0.45
}

enum MainMenuVisualColors {
    static let panelBackground = NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.135, alpha: 1.0)
    static let panelBorder = NSColor(calibratedWhite: 1.0, alpha: 0.10)
    static let sectionSurface = NSColor(calibratedWhite: 1.0, alpha: 0.036)
    static let headerSurface = NSColor(calibratedWhite: 1.0, alpha: 0.050)
    static let contentSurface = NSColor(calibratedWhite: 1.0, alpha: 0.035)
    static let footerSurface = NSColor(calibratedWhite: 1.0, alpha: 0.040)
    static let sectionBorder = NSColor(calibratedWhite: 1.0, alpha: 0.070)
    static let toolbarSurface = NSColor(calibratedWhite: 1.0, alpha: 0.050)
    static let controlSurface = NSColor(calibratedWhite: 1.0, alpha: 0.052)
    static let controlBorder = NSColor(calibratedWhite: 1.0, alpha: 0.085)
    static let hoveredRow = NSColor(calibratedWhite: 1.0, alpha: 0.060)
    static let selectedRow = NSColor(calibratedWhite: 1.0, alpha: 0.105)
    static let accentFill = NSColor.controlAccentColor.withAlphaComponent(0.16)
    static let separator = NSColor(calibratedWhite: 1.0, alpha: 0.095)
}

enum MainMenuPanelItem {
    case separator
    case notice(title: String, message: String, image: NSImage?)
    case snippetFolder(title: String, image: NSImage?, shortcutText: String? = nil, onOpen: (NSRect?) -> Void)
    case action(title: String, image: NSImage?, shortcutText: String? = nil, onSelect: () -> Void)
}

struct MainMenuHistoryDataSource {
    typealias StateUpdate = (inout HistoryMenuPaginationState) -> Void
    typealias RowBuilder = (PasteboardHistoryDetail, Int, @escaping () -> Void) -> HistoryMenuRowView

    let currentState: () -> HistoryMenuPaginationState
    let updateState: (StateUpdate) -> Void
    let fetchPage: () -> HistoryMenuPage
    let makeRowView: RowBuilder
    let selectHistory: (PasteboardHistory.ID, PasteTargetContext?) -> Void
    let fetchEditableText: (PasteboardHistory.ID) -> String?
    let updateTextHistory: (PasteboardHistory.ID, String) -> Bool

    init(
        currentState: @escaping () -> HistoryMenuPaginationState,
        updateState: @escaping (StateUpdate) -> Void,
        fetchPage: @escaping () -> HistoryMenuPage,
        makeRowView: @escaping RowBuilder,
        selectHistory: @escaping (PasteboardHistory.ID, PasteTargetContext?) -> Void,
        fetchEditableText: @escaping (PasteboardHistory.ID) -> String? = { _ in nil },
        updateTextHistory: @escaping (PasteboardHistory.ID, String) -> Bool = { _, _ in false }
    ) {
        self.currentState = currentState
        self.updateState = updateState
        self.fetchPage = fetchPage
        self.makeRowView = makeRowView
        self.selectHistory = selectHistory
        self.fetchEditableText = fetchEditableText
        self.updateTextHistory = updateTextHistory
    }
}

struct MainMenuSnippetDataSource {
    let fetchFolderDetails: () -> [SnippetFolderDetail]
    let fetchFolderDetail: (SnippetFolder.ID) -> SnippetFolderDetail?
    let selectSnippet: (Snippet.ID, PasteTargetContext?) -> Void
    let createFolder: (String) -> SnippetFolder?
    let createSnippet: (SnippetFolder.ID, String, String) -> Snippet?
    let updateFolderTitle: (SnippetFolder.ID, String) -> Bool
    let updateSnippetTitle: (Snippet.ID, String) -> Void
    let updateSnippetContent: (Snippet.ID, String) -> Bool
    let deleteFolder: (SnippetFolder.ID) -> Void
    let deleteSnippet: (Snippet.ID) -> Void
    let folderKeyCombo: (SnippetFolder.ID) -> KeyCombo?
    let updateFolderKeyCombo: (SnippetFolder.ID, KeyCombo) -> Void
    let clearFolderKeyCombo: (SnippetFolder.ID) -> Void

    init(
        fetchFolderDetails: @escaping () -> [SnippetFolderDetail],
        fetchFolderDetail: @escaping (SnippetFolder.ID) -> SnippetFolderDetail?,
        selectSnippet: @escaping (Snippet.ID, PasteTargetContext?) -> Void,
        createFolder: @escaping (String) -> SnippetFolder? = { _ in nil },
        createSnippet: @escaping (SnippetFolder.ID, String, String) -> Snippet? = { _, _, _ in nil },
        updateFolderTitle: @escaping (SnippetFolder.ID, String) -> Bool = { _, _ in false },
        updateSnippetTitle: @escaping (Snippet.ID, String) -> Void = { _, _ in },
        updateSnippetContent: @escaping (Snippet.ID, String) -> Bool = { _, _ in false },
        deleteFolder: @escaping (SnippetFolder.ID) -> Void = { _ in },
        deleteSnippet: @escaping (Snippet.ID) -> Void = { _ in },
        folderKeyCombo: @escaping (SnippetFolder.ID) -> KeyCombo? = { _ in nil },
        updateFolderKeyCombo: @escaping (SnippetFolder.ID, KeyCombo) -> Void = { _, _ in },
        clearFolderKeyCombo: @escaping (SnippetFolder.ID) -> Void = { _ in }
    ) {
        self.fetchFolderDetails = fetchFolderDetails
        self.fetchFolderDetail = fetchFolderDetail
        self.selectSnippet = selectSnippet
        self.createFolder = createFolder
        self.createSnippet = createSnippet
        self.updateFolderTitle = updateFolderTitle
        self.updateSnippetTitle = updateSnippetTitle
        self.updateSnippetContent = updateSnippetContent
        self.deleteFolder = deleteFolder
        self.deleteSnippet = deleteSnippet
        self.folderKeyCombo = folderKeyCombo
        self.updateFolderKeyCombo = updateFolderKeyCombo
        self.clearFolderKeyCombo = clearFolderKeyCombo
    }
}

struct MainMenuPasswordVaultDataSource {
    let fetchFolders: () throws -> [PasswordVaultFolder]
    let fetchEntries: () throws -> [PasswordVaultEntry]
    let copyPassword: (PasswordVaultEntry.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let loadDraft: (PasswordVaultEntry.ID, @escaping (Result<PasswordVaultDraft, PasswordVaultError>) -> Void) -> Void
    let createEntry: (PasswordVaultDraft, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let updateEntry: (PasswordVaultEntry.ID, PasswordVaultDraft, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let deleteEntry: (PasswordVaultEntry.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let createFolder: (String) throws -> PasswordVaultFolder
    let renameFolder: (PasswordVaultFolder.ID, String) throws -> PasswordVaultFolder
    let deleteFolder: (PasswordVaultFolder.ID) throws -> Void
}

private final class MainMenuPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
    }
}

final class MainMenuPanelController: NSObject, NSWindowDelegate, NSSearchFieldDelegate {
    private enum DisplayMode {
        case history
        case snippets
        case passwordVault
    }

    fileprivate enum KeyboardEntryRole {
        case none
        case snippetFolder(SnippetFolder.ID)
        case snippet(Snippet.ID)
    }

    private enum InlineEditorState {
        case history(PasteboardHistory.ID, originalText: String, draftText: String, error: String?)
        case snippetFolder(SnippetFolder.ID, originalTitle: String, draftTitle: String, error: String?)
        case newSnippetFolder(draftTitle: String, error: String?)
        case newSnippet(SnippetFolder.ID, draftTitle: String, draftContent: String, error: String?)
        case snippet(
            Snippet.ID,
            originalTitle: String,
            originalContent: String,
            draftTitle: String,
            draftContent: String,
            error: String?
        )
    }

    private struct KeyboardEntry {
        let title: String
        let role: KeyboardEntryRole
        let view: () -> NSView?
        let setSelected: (Bool) -> Void
        let openChildPanel: (() -> Void)?
        let confirm: () -> Void
    }

    private struct EmbeddedContent {
        let headerTitle: String
        let headerSubtitle: String?
        let showsBackButton: Bool
        let canGoToPreviousPage: Bool
        let canGoToNextPage: Bool
        let typeFilter: HistoryMenuTypeFilter?
        let rows: [EmbeddedRow]
    }

    private struct EmbeddedRow {
        let title: String
        let view: NSView
        let confirm: () -> Void
        let role: KeyboardEntryRole
        let participatesInNavigation: Bool

        init(
            title: String,
            view: NSView,
            confirm: @escaping () -> Void,
            role: KeyboardEntryRole = .none,
            participatesInNavigation: Bool = true
        ) {
            self.title = title
            self.view = view
            self.confirm = confirm
            self.role = role
            self.participatesInNavigation = participatesInNavigation
        }
    }

    private struct EmbeddedRenderItem {
        let view: NSView
        let height: CGFloat
        let row: EmbeddedRow?
    }

    private enum PasswordVaultEditorState {
        case create(PasswordVaultDraft, error: String?)
        case edit(PasswordVaultEntry.ID, PasswordVaultDraft, error: String?)
    }

    private enum PasswordVaultFolderEditorState {
        case create(error: String?)
        case rename(PasswordVaultFolder, error: String?)
    }

    private let historyTitle: String
    private let historyImage: NSImage?
    private let historyShortcutText: String?
    private let snippetTitle: String
    private let snippetImage: NSImage?
    private let itemsProvider: () -> [MainMenuPanelItem]
    private let onOpenHistory: () -> Void
    private let onOpenSnippets: () -> Void
    private let historyDataSource: MainMenuHistoryDataSource?
    private let snippetDataSource: MainMenuSnippetDataSource?
    private let passwordVaultDataSource: MainMenuPasswordVaultDataSource?
    private let oneDriveStatusService: OneDriveProcessStatusServicing
    private let onOpenPreferences: () -> Void
    private let onCloseChildPanels: () -> Void
    private var deleteConfirmationRunner: (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult = {
        PasteraConfirmationController.runModal(options: $0, sourceWindow: $1)
    }

    private let contentView = NSView()
    private let searchField = NSSearchField()
    private var panel: MainMenuPanel?
    private var keyboardEntries = [KeyboardEntry]()
    private var selectedKeyboardEntryIndex: Int?
    private var isPinned = true
    private var selectedMode: DisplayMode = .history
    private var expandedSnippetFolderID: SnippetFolder.ID?
    private var isWorkspaceEditing = false
    private var inlineEditorState: InlineEditorState?
    private var inlineEditorView: MainMenuInlineEditorView?
    private var editingFolderShortcutID: SnippetFolder.ID?
    private var folderShortcutEditorView: MainMenuFolderShortcutEditorView?
    private var snippetSearchQuery = ""
    private var passwordVaultSearchQuery = ""
    private var expandedPasswordVaultFolderID: PasswordVaultFolder.ID?
    private var passwordVaultEditorState: PasswordVaultEditorState?
    private var passwordVaultFolderEditorState: PasswordVaultFolderEditorState?
    private var passwordVaultStatusMessage: String?
    private var visibleHistoryIDs = [PasteboardHistory.ID]()
    private var visibleSnippetIDs = [Snippet.ID]()
    private var visibleMainMenuRowTitles = [String]()
    private var currentSnippetFolderTitle: String?
    private var isSearchVisible = false
    private var keepsVisibleWhileChildPanelOpen = false
    private var pasteTargetContext: PasteTargetContext?
    private weak var oneDriveStatusButton: MainMenuOneDriveStatusButton?

    private var usesEmbeddedContent: Bool {
        historyDataSource != nil || snippetDataSource != nil || passwordVaultDataSource != nil
    }

    init(
        historyTitle: String,
        historyImage: NSImage?,
        historyShortcutText: String? = nil,
        snippetTitle: String,
        snippetImage: NSImage?,
        itemsProvider: @escaping () -> [MainMenuPanelItem],
        onOpenHistory: @escaping () -> Void,
        onOpenSnippets: @escaping () -> Void,
        historyDataSource: MainMenuHistoryDataSource? = nil,
        snippetDataSource: MainMenuSnippetDataSource? = nil,
        passwordVaultDataSource: MainMenuPasswordVaultDataSource? = nil,
        oneDriveStatusService: OneDriveProcessStatusServicing = AppEnvironment.current.oneDriveProcessStatusService,
        onOpenPreferences: @escaping () -> Void = {
            NSApp.sendAction(#selector(AppDelegate.showPreferenceWindow), to: nil, from: nil)
        },
        onCloseChildPanels: @escaping () -> Void = {}
    ) {
        self.historyTitle = historyTitle
        self.historyImage = historyImage
        self.historyShortcutText = historyShortcutText
        self.snippetTitle = snippetTitle
        self.snippetImage = snippetImage
        self.itemsProvider = itemsProvider
        self.onOpenHistory = onOpenHistory
        self.onOpenSnippets = onOpenSnippets
        self.historyDataSource = historyDataSource
        self.snippetDataSource = snippetDataSource
        self.passwordVaultDataSource = passwordVaultDataSource
        self.oneDriveStatusService = oneDriveStatusService
        self.onOpenPreferences = onOpenPreferences
        self.onCloseChildPanels = onCloseChildPanels
        super.init()
    }

    func show(at screenPoint: NSPoint, pinned: Bool = false, pasteTargetContext: PasteTargetContext? = nil) {
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        isSearchVisible = false
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        if !panel.isVisible || !pinned {
            position(panel, near: screenPoint)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(anchoredTo menuFrame: NSRect, pinned: Bool = true, pasteTargetContext: PasteTargetContext? = nil) {
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? self.pasteTargetContext ?? PasteTargetContext.capture()
        isSearchVisible = false
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, anchoredTo: menuFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(attachedToStatusItemFrame statusItemFrame: NSRect, pinned: Bool = false, pasteTargetContext: PasteTargetContext? = nil) {
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        isSearchVisible = false
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, attachedToStatusItemFrame: statusItemFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func close() -> Bool {
        guard commitInlineEditorFromCurrentDraft() else { return false }
        keepsVisibleWhileChildPanelOpen = false
        editingFolderShortcutID = nil
        panel?.orderOut(nil)
        return true
    }

    private func handlePanelCancel() {
        if passwordVaultEditorState != nil {
            discardPasswordVaultEditor()
            return
        }
        if passwordVaultFolderEditorState != nil {
            passwordVaultFolderEditorState = nil
            reloadContentKeepingTopLeft()
            return
        }
        if editingFolderShortcutID != nil {
            discardFolderShortcutEditor()
            return
        }
        if inlineEditorState != nil {
            discardInlineEditor()
            return
        }
        if isWorkspaceEditing {
            isWorkspaceEditing = false
            reloadContentKeepingTopLeft()
            return
        }
        _ = close()
    }

    var isVisibleForTesting: Bool {
        panel?.isVisible == true
    }

    var visibleFrame: NSRect? {
        guard panel?.isVisible == true else { return nil }
        return panel?.frame
    }

    func reloadContentIfVisible() {
        guard let panel, panel.isVisible else { return }
        let topLeftPoint = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        reloadContent()
        panel.setFrameTopLeftPoint(topLeftPoint)
    }

    func refreshAppearanceIfVisible() {
        guard panel?.isVisible == true else { return }
        applyVisualFoundation()
    }

    var childPasteTargetContext: PasteTargetContext? {
        pasteTargetContext
    }

#if DEBUG
    var pasteTargetProcessIdentifierForTesting: pid_t? {
        pasteTargetContext?.processIdentifier
    }
#endif

    func openHistoryFromMainMenu() {
        guard usesEmbeddedContent else {
            onOpenHistory()
            return
        }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        selectedMode = .history
        reloadContentIfVisible()
        onCloseChildPanels()
    }

    func openSnippetsFromMainMenu() {
        guard usesEmbeddedContent else {
            onOpenSnippets()
            return
        }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        selectedMode = .snippets
        expandedSnippetFolderID = nil
        reloadContentIfVisible()
        onCloseChildPanels()
    }

    func openSnippetFolderFromMainMenu(_ folderID: SnippetFolder.ID) {
        guard usesEmbeddedContent else {
            onOpenSnippets()
            return
        }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        selectedMode = .snippets
        expandedSnippetFolderID = folderID
        reloadContentIfVisible()
        onCloseChildPanels()
    }

    func openPasswordVaultFromMainMenu() {
        guard passwordVaultDataSource != nil else { return }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        selectedMode = .passwordVault
        reloadContentIfVisible()
        onCloseChildPanels()
    }

    private func openLegacyHistoryFromMainMenu() {
        onOpenHistory()
    }

    private func openLegacySnippetsFromMainMenu() {
        onOpenSnippets()
    }

    func beginChildPanelPresentation() {
        keepsVisibleWhileChildPanelOpen = true
        if let panel {
            panel.hidesOnDeactivate = false
        }
    }

    func endChildPanelPresentation() {
        keepsVisibleWhileChildPanelOpen = false
        if let panel {
            applyBehavior(to: panel)
        }
    }
}

extension MainMenuPanelController {
    private func makePanelIfNeeded() -> MainMenuPanel {
        if let panel { return panel }

        let panel = MainMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.fixedHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.handlePanelCancel() }
        panel.onKeyDown = { [weak self] event in self?.handleKeyboardNavigation(event) ?? false }
        panel.delegate = self
        panel.contentView = contentView
        applyBehavior(to: panel)
        self.panel = panel
        return panel
    }

    private func applyBehavior(to panel: MainMenuPanel) {
        let behavior = MainMenuPanelBehavior(isPinned: isPinned)
        panel.level = behavior.level
        panel.collectionBehavior = behavior.collectionBehavior
        panel.hidesOnDeactivate = behavior.hidesOnDeactivate
        panel.isMovableByWindowBackground = behavior.isMovableByWindowBackground
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned, !keepsVisibleWhileChildPanelOpen else { return }
        panel?.orderOut(nil)
    }

    private func applyVisualFoundation() {
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = MainMenuPanelLayout.cornerRadius
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = MainMenuVisualColors.panelBackground.cgColor
        contentView.layer?.borderColor = MainMenuVisualColors.panelBorder.cgColor
        contentView.layer?.borderWidth = 1
    }

    private func reloadContent() {
        inlineEditorView = nil
        guard usesEmbeddedContent else {
            reloadLegacyContent()
            return
        }
        reloadEmbeddedContent()
    }

    // swiftlint:disable:next function_body_length
    private func reloadLegacyContent() {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        keyboardEntries.removeAll()
        selectedKeyboardEntryIndex = nil
        resetVisibleRows()
        applyVisualFoundation()

        let items = itemsProvider()
        let height = MainMenuPanelLayout.fixedHeight
        applyCurrentContentSize()

        var currentY = height - MainMenuPanelLayout.topInset - MainMenuPanelLayout.headerHeight
        let headerView = MainMenuHeaderItemView(
            title: historyTitle,
            image: historyImage,
            shortcutText: historyShortcutText
        )
        headerView.allowsWindowDrag = isPinned
        headerView.frame = NSRect(x: 0, y: currentY, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.headerHeight)
        headerView.onOpen = { [weak self] in self?.openHistoryFromMainMenu() }
        headerView.onHoverOpen = { [weak self] in self?.openHistoryFromMainMenu() }
        let historyEntryIndex = appendKeyboardEntry(
            title: historyTitle,
            view: headerView,
            openChildPanel: { [weak self] in self?.openHistoryFromMainMenu() },
            confirm: { [weak self] in self?.openHistoryFromMainMenu() }
        )
        headerView.onHoverFocus = { [weak self] in
            self?.selectKeyboardEntry(at: historyEntryIndex, triggerChildPanel: false)
        }
        contentView.addSubview(headerView)

        currentY -= MainMenuPanelLayout.separatorVerticalInset + MainMenuPanelLayout.separatorHeight
        addSeparator(at: currentY)
        currentY -= MainMenuPanelLayout.separatorVerticalInset

        for item in items {
            switch item {
            case .separator:
                currentY -= MainMenuPanelLayout.separatorVerticalInset
                addSeparator(at: currentY)
                currentY -= MainMenuPanelLayout.separatorVerticalInset
            case let .notice(title, message, image):
                currentY -= MainMenuPanelLayout.noticeHeight
                let noticeView = MainMenuPanelNoticeView(title: title, message: message, image: image)
                noticeView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.noticeHeight
                )
                contentView.addSubview(noticeView)
            case let .snippetFolder(title, image, shortcutText, onOpen):
                currentY -= MainMenuPanelLayout.snippetFolderRowHeight
                let rowView = MainMenuPanelRowView(
                    title: title,
                    image: image,
                    shortcutText: shortcutText,
                    rowKind: .snippetFolder,
                    rowHeight: MainMenuPanelLayout.snippetFolderRowHeight,
                    showsChevron: true,
                    onHoverOpen: onOpen,
                    onConfirm: onOpen
                )
                rowView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.snippetFolderRowHeight
                )
                let entryIndex = appendKeyboardEntry(
                    title: title,
                    view: rowView,
                    openChildPanel: { [weak rowView] in onOpen(rowView?.screenFrameForOpening) },
                    confirm: { [weak rowView] in onOpen(rowView?.screenFrameForOpening) }
                )
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
                contentView.addSubview(rowView)
            case let .action(title, image, shortcutText, onSelect):
                currentY -= MainMenuPanelLayout.rowHeight
                let rowView = MainMenuPanelRowView(
                    title: title,
                    image: image,
                    shortcutText: shortcutText,
                    rowKind: .action
                ) { _ in onSelect() }
                rowView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.rowHeight
                )
                let entryIndex = appendKeyboardEntry(
                    title: title,
                    view: rowView,
                    openChildPanel: { [weak self] in self?.onCloseChildPanels() },
                    confirm: onSelect
                )
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
                contentView.addSubview(rowView)
            }
        }

        if isSearchVisible {
            addSearchField(at: fixedSearchY)
        }
        addToolbar(at: fixedToolbarY)
    }

    private func reloadEmbeddedContent() {
        HistoryMenuRowView.hidePreviews()
        inlineEditorView = nil
        folderShortcutEditorView = nil
        contentView.subviews.forEach { $0.removeFromSuperview() }
        keyboardEntries.removeAll()
        selectedKeyboardEntryIndex = nil
        resetVisibleRows()
        applyVisualFoundation()

        let content = makeEmbeddedContent()
        let notices = noticeItems()
        applyCurrentContentSize()

        addEmbeddedHeader(content, frame: headerBlockFrame)
        addEmbeddedViewport(content, notices: notices, frame: contentBlockFrame)
        if let searchFieldFrame {
            addSearchField(frame: searchFieldFrame)
        }
        addToolbar(frame: footerDockFrame)
    }

    private var fixedToolbarY: CGFloat {
        MainMenuPanelLayout.bottomInset
    }

    private var fixedSearchY: CGFloat {
        fixedToolbarY + MainMenuPanelLayout.toolbarHeight
    }

    private var searchFieldFrame: NSRect? {
        guard isSearchVisible, usesEmbeddedContent else { return nil }
        return NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: MainMenuPanelLayout.bottomInset,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.searchHeight
        )
    }

    private var searchDrawerHeight: CGFloat {
        guard isSearchVisible, usesEmbeddedContent else { return 0 }
        return MainMenuPanelLayout.bottomInset +
            MainMenuPanelLayout.searchHeight +
            MainMenuPanelLayout.sectionGap
    }

    private var mainContentVerticalOffset: CGFloat {
        searchDrawerHeight
    }

    private var currentContentSize: NSSize {
        NSSize(
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.fixedHeight + mainContentVerticalOffset
        )
    }

    private var headerBlockFrame: NSRect {
        NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: mainContentVerticalOffset +
                MainMenuPanelLayout.fixedHeight -
                MainMenuPanelLayout.sectionInset -
                MainMenuPanelLayout.headerHeight,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.headerHeight
        )
    }

    private var footerDockFrame: NSRect {
        return NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: mainContentVerticalOffset + MainMenuPanelLayout.bottomInset,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.toolbarHeight
        )
    }

    private var contentBlockFrame: NSRect {
        let top = headerBlockFrame.minY - MainMenuPanelLayout.sectionGap
        let bottom = footerDockFrame.maxY + MainMenuPanelLayout.sectionGap
        return NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: bottom,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: max(0, top - bottom)
        )
    }

    private func applyCurrentContentSize() {
        let size = currentContentSize
        contentView.frame = NSRect(origin: .zero, size: size)
        panel?.setContentSize(size)
    }

    private func applyCurrentContentSizeKeepingTopLeft() {
        let topLeft = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        applyCurrentContentSize()
        if let topLeft {
            panel?.setFrameTopLeftPoint(topLeft)
        }
    }

    private func addEmbeddedViewport(_ content: EmbeddedContent, notices: [MainMenuPanelItem], frame: NSRect) {
        let surfaceView = MainMenuSurfaceView(
            frame: frame,
            identifier: "mainMenuContentBlock",
            fillColor: MainMenuVisualColors.contentSurface
        )
        let scrollFrame = surfaceView.bounds.insetBy(
            dx: MainMenuPanelLayout.contentInnerPadding,
            dy: MainMenuPanelLayout.contentInnerPadding
        )
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed

        let renderItems = embeddedRenderItems(content, notices: notices)
        let documentHeight = max(scrollFrame.height, renderItems.reduce(CGFloat(0)) { $0 + $1.height })
        let documentView = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: scrollFrame.width,
            height: documentHeight
        ))
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor.clear.cgColor

        var currentY = documentHeight
        for item in renderItems {
            currentY -= item.height
            item.view.frame = NSRect(x: 0, y: currentY, width: scrollFrame.width, height: item.height)
            documentView.addSubview(item.view)
            guard let row = item.row else { continue }
            guard row.participatesInNavigation else { continue }
            let entryIndex = appendKeyboardEntry(
                title: row.title,
                view: row.view,
                openChildPanel: nil,
                role: row.role,
                confirm: row.confirm
            )
            if let rowView = row.view as? MainMenuPanelRowView {
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
            } else if let rowView = row.view as? MainMenuEmbeddedEmptyRowView {
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
            }
            visibleMainMenuRowTitles.append(row.title)
        }

        scrollView.documentView = documentView
        let topOffset = max(0, documentHeight - scrollFrame.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: topOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        surfaceView.addSubview(scrollView)
        contentView.addSubview(surfaceView)
    }

    private func embeddedRenderItems(
        _ content: EmbeddedContent,
        notices: [MainMenuPanelItem]
    ) -> [EmbeddedRenderItem] {
        var items = [EmbeddedRenderItem]()
        for item in notices {
            switch item {
            case .separator:
                items.append(EmbeddedRenderItem(
                    view: NSView(frame: NSRect(
                        x: 0,
                        y: 0,
                        width: MainMenuPanelLayout.width,
                        height: MainMenuPanelLayout.sectionGap
                    )),
                    height: MainMenuPanelLayout.sectionGap,
                    row: nil
                ))
            case let .notice(title, message, image):
                items.append(EmbeddedRenderItem(
                    view: MainMenuPanelNoticeView(title: title, message: message, image: image),
                    height: MainMenuPanelLayout.noticeHeight,
                    row: nil
                ))
            case .snippetFolder, .action:
                break
            }
        }
        items.append(contentsOf: content.rows.map { row in
            EmbeddedRenderItem(
                view: row.view,
                height: max(row.view.frame.height, MainMenuPanelLayout.rowHeight),
                row: row
            )
        })
        return items
    }

    private func preferredHeight(for items: [MainMenuPanelItem]) -> CGFloat {
        let rowHeights = items.reduce(CGFloat(0)) { total, item in
            switch item {
            case .separator:
                return total + MainMenuPanelLayout.separatorHeight + MainMenuPanelLayout.separatorVerticalInset * 2
            case .notice:
                return total + MainMenuPanelLayout.noticeHeight
            case .snippetFolder:
                return total + MainMenuPanelLayout.snippetFolderRowHeight
            case .action:
                return total + MainMenuPanelLayout.rowHeight
            }
        }
        return MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + rowHeights
            + MainMenuPanelLayout.toolbarHeight
            + (isSearchVisible ? MainMenuPanelLayout.searchHeight : 0)
            + MainMenuPanelLayout.bottomInset
    }

    private func preferredHeight(for content: EmbeddedContent, notices: [MainMenuPanelItem]) -> CGFloat {
        let noticeHeight = notices.reduce(CGFloat(0)) { total, item in
            switch item {
            case .separator:
                return total + MainMenuPanelLayout.separatorHeight + MainMenuPanelLayout.separatorVerticalInset * 2
            case .notice:
                return total + MainMenuPanelLayout.noticeHeight
            case .snippetFolder, .action:
                return total
            }
        }
        let rowsHeight = content.rows.reduce(CGFloat(0)) { total, row in
            total + max(row.view.frame.height, MainMenuPanelLayout.rowHeight)
        }
        return MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + noticeHeight
            + rowsHeight
            + MainMenuPanelLayout.toolbarHeight
            + (isSearchVisible ? MainMenuPanelLayout.searchHeight : 0)
            + MainMenuPanelLayout.bottomInset
    }

    private func makeEmbeddedContent() -> EmbeddedContent {
        switch selectedMode {
        case .history:
            if let inlineEditorState, case .history = inlineEditorState {
                return mergedEditor(makeInlineEditorContent(inlineEditorState), list: makeHistoryContent())
            }
            return makeHistoryContent()
        case .snippets:
            if let inlineEditorState, case .history = inlineEditorState {
                return makeSnippetContent()
            } else if let inlineEditorState, case .newSnippetFolder = inlineEditorState {
                return mergedEditorAtEnd(makeInlineEditorContent(inlineEditorState), list: makeSnippetContent())
            } else if let inlineEditorState {
                return mergedEditor(makeInlineEditorContent(inlineEditorState), list: makeSnippetContent())
            }
            return makeSnippetContent()
        case .passwordVault:
            if let passwordVaultEditorState {
                return mergedEditor(makePasswordVaultEditorContent(passwordVaultEditorState), list: makePasswordVaultContent())
            }
            if let passwordVaultFolderEditorState {
                switch passwordVaultFolderEditorState {
                case .create:
                    return mergedEditorAtEnd(
                        makePasswordVaultFolderEditorContent(passwordVaultFolderEditorState),
                        list: makePasswordVaultContent()
                    )
                case .rename:
                    return mergedEditor(makePasswordVaultFolderEditorContent(passwordVaultFolderEditorState), list: makePasswordVaultContent())
                }
            }
            return makePasswordVaultContent()
        }
    }

    private func mergedEditor(_ editor: EmbeddedContent, list: EmbeddedContent) -> EmbeddedContent {
        EmbeddedContent(
            headerTitle: list.headerTitle, headerSubtitle: list.headerSubtitle, showsBackButton: false,
            canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil,
            rows: editor.rows + list.rows
        )
    }

    private func mergedEditorAtEnd(_ editor: EmbeddedContent, list: EmbeddedContent) -> EmbeddedContent {
        EmbeddedContent(
            headerTitle: list.headerTitle, headerSubtitle: list.headerSubtitle, showsBackButton: false,
            canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil,
            rows: list.rows + editor.rows
        )
    }

    private func makeInlineEditorContent(_ state: InlineEditorState) -> EmbeddedContent {
        if case let .newSnippetFolder(draftTitle, _) = state {
            let editor = PasswordVaultFolderEditorView(
                name: draftTitle,
                onSave: { [weak self] title in
                    self?.inlineEditorState = .newSnippetFolder(draftTitle: title, error: nil)
                    _ = self?.commitInlineEditorFromCurrentDraft()
                },
                onCancel: { [weak self] in self?.discardInlineEditor() }
            )
            inlineEditorView = nil
            return EmbeddedContent(
                headerTitle: String(localized: "Snippet"), headerSubtitle: nil, showsBackButton: false,
                canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil,
                rows: [EmbeddedRow(title: String(localized: "Folder"), view: editor, confirm: {})]
            )
        }
        let configuration: MainMenuInlineEditorView.Configuration
        let headerTitle: String
        switch state {
        case let .history(_, _, draftText, error):
            headerTitle = String(localized: "Edit History")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: nil,
                titlePlaceholder: nil,
                contentValue: draftText,
                errorMessage: error
            )
        case let .snippetFolder(_, _, draftTitle, error):
            headerTitle = String(localized: "Edit Folder")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: draftTitle,
                titlePlaceholder: String(localized: "Folder Name"),
                contentValue: nil,
                errorMessage: error
            )
        case .newSnippetFolder:
            preconditionFailure("New snippet folders use the compact row editor")
        case let .newSnippet(_, draftTitle, draftContent, error):
            headerTitle = String(localized: "New Snippet")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: draftTitle, titlePlaceholder: String(localized: "Snippet Title"),
                contentValue: draftContent, errorMessage: error
            )
        case let .snippet(_, _, _, draftTitle, draftContent, error):
            headerTitle = String(localized: "Edit Snippet")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: draftTitle,
                titlePlaceholder: String(localized: "Snippet Title"),
                contentValue: draftContent,
                errorMessage: error
            )
        }
        let editorView = MainMenuInlineEditorView(
            configuration: configuration,
            onCommit: { [weak self] in
                _ = self?.commitInlineEditorFromCurrentDraft()
            },
            onDiscard: { [weak self] in
                self?.discardInlineEditor()
            }
        )
        inlineEditorView = editorView
        return EmbeddedContent(
            headerTitle: headerTitle,
            headerSubtitle: nil,
            showsBackButton: false,
            canGoToPreviousPage: false,
            canGoToNextPage: false,
            typeFilter: nil,
            rows: [
                EmbeddedRow(
                    title: headerTitle,
                    view: editorView,
                    confirm: {}
                )
            ]
        )
    }

    private func makeHistoryContent() -> EmbeddedContent {
        guard let historyDataSource else {
            return EmbeddedContent(
                headerTitle: historyTitle,
                headerSubtitle: nil,
                showsBackButton: false,
                canGoToPreviousPage: false,
                canGoToNextPage: false,
                typeFilter: nil,
                rows: [emptyRow(title: String(localized: "No History"))]
            )
        }

        var page = historyDataSource.fetchPage()
        if page.details.isEmpty && page.error == nil && historyDataSource.currentState().pageIndex > 0 {
            historyDataSource.updateState { $0.resetPage() }
            page = historyDataSource.fetchPage()
        }
        let state = historyDataSource.currentState()
        let rows: [EmbeddedRow]
        if let error = page.error {
            rows = [emptyRow(title: error.historyMenuTitle)]
        } else if page.details.isEmpty {
            let title = state.hasActiveSearchOptions ? String(localized: "No Results") : String(localized: "No History")
            rows = [emptyRow(title: title)]
        } else {
            rows = page.details.enumerated().map { index, detail in
                visibleHistoryIDs.append(detail.history.id)
                let rowView = historyDataSource.makeRowView(detail, index) { [weak self] in
                    self?.confirmHistorySelection(detail.history.id)
                }
                return EmbeddedRow(
                    title: detail.history.title,
                    view: rowView,
                    confirm: { [weak self] in self?.confirmHistorySelection(detail.history.id) }
                )
            }
        }

        return EmbeddedContent(
            headerTitle: state.typeFilter.title,
            headerSubtitle: "\(state.displayPage)",
            showsBackButton: false,
            canGoToPreviousPage: state.pageIndex > 0,
            canGoToNextPage: page.hasNextPage,
            typeFilter: state.typeFilter,
            rows: rows
        )
    }

    func beginEditingHistory(_ historyID: PasteboardHistory.ID) {
        guard let text = historyDataSource?.fetchEditableText(historyID) else { return }
        editingFolderShortcutID = nil
        inlineEditorState = .history(historyID, originalText: text, draftText: text, error: nil)
        reloadContentKeepingTopLeft()
    }

    private func beginEditingSnippetFolder(_ folderID: SnippetFolder.ID) {
        guard let detail = snippetDataSource?.fetchFolderDetails().first(where: { $0.folder.id == folderID }) else {
            return
        }
        editingFolderShortcutID = nil
        inlineEditorState = .snippetFolder(
            folderID,
            originalTitle: detail.folder.title,
            draftTitle: detail.folder.title,
            error: nil
        )
        reloadContentKeepingTopLeft()
    }

    private func beginEditingSnippet(_ snippetID: Snippet.ID) {
        guard let snippet = snippetDataSource?.fetchFolderDetails()
            .flatMap(\.snippets)
            .first(where: { $0.id == snippetID }) else {
            return
        }
        editingFolderShortcutID = nil
        inlineEditorState = .snippet(
            snippetID,
            originalTitle: snippet.title,
            originalContent: snippet.content,
            draftTitle: snippet.title,
            draftContent: snippet.content,
            error: nil
        )
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingSnippetFolder() {
        inlineEditorState = .newSnippetFolder(draftTitle: "", error: nil)
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingSnippet(in requestedFolderID: SnippetFolder.ID? = nil) {
        let folderID = requestedFolderID ?? expandedSnippetFolderID ?? enabledSnippetFolderDetails().first?.folder.id
        guard let folderID else {
            beginCreatingSnippetFolder()
            return
        }
        inlineEditorState = .newSnippet(folderID, draftTitle: "", draftContent: "", error: nil)
        reloadContentKeepingTopLeft()
    }

    @discardableResult
    private func commitInlineEditorFromCurrentDraft() -> Bool {
        guard inlineEditorState != nil else { return true }
        let draft = currentInlineEditorDraft()
        return commitInlineEditor(title: draft.title, content: draft.content)
    }

    private func currentInlineEditorDraft() -> (title: String, content: String) {
        if let inlineEditorView {
            return (inlineEditorView.draftTitle, inlineEditorView.draftContent)
        }
        switch inlineEditorState {
        case let .history(_, _, draftText, _):
            return ("", draftText)
        case let .snippetFolder(_, _, draftTitle, _):
            return (draftTitle, "")
        case let .snippet(_, _, _, draftTitle, draftContent, _):
            return (draftTitle, draftContent)
        case let .newSnippetFolder(draftTitle, _):
            return (draftTitle, "")
        case let .newSnippet(_, draftTitle, draftContent, _):
            return (draftTitle, draftContent)
        case nil:
            return ("", "")
        }
    }

    @discardableResult
    private func commitInlineEditor(title: String, content: String) -> Bool {
        guard let inlineEditorState else { return true }
        switch inlineEditorState {
        case .newSnippetFolder:
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, let folder = snippetDataSource?.createFolder(trimmedTitle) else {
                self.inlineEditorState = .newSnippetFolder(
                    draftTitle: title, error: String(localized: "Unable to create this folder.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            expandedSnippetFolderID = folder.id
        case let .newSnippet(folderID, _, _, _):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty,
                  snippetDataSource?.createSnippet(folderID, trimmedTitle, content) != nil else {
                self.inlineEditorState = .newSnippet(
                    folderID, draftTitle: title, draftContent: content,
                    error: String(localized: "Unable to create this snippet.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            expandedSnippetFolderID = folderID
        case let .history(historyID, originalText, _, _):
            guard content != originalText else {
                self.inlineEditorState = nil
                reloadContentKeepingTopLeft()
                return true
            }
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.inlineEditorState = .history(
                    historyID,
                    originalText: originalText,
                    draftText: content,
                    error: String(localized: "History text cannot be empty.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            guard historyDataSource?.updateTextHistory(historyID, content) == true else {
                self.inlineEditorState = .history(
                    historyID,
                    originalText: originalText,
                    draftText: content,
                    error: String(localized: "Unable to edit this history item.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
        case let .snippetFolder(folderID, originalTitle, _, _):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedTitle != originalTitle else {
                self.inlineEditorState = nil
                reloadContentKeepingTopLeft()
                return true
            }
            guard !trimmedTitle.isEmpty else {
                self.inlineEditorState = .snippetFolder(
                    folderID,
                    originalTitle: originalTitle,
                    draftTitle: title,
                    error: String(localized: "Folder name cannot be empty.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            guard snippetDataSource?.updateFolderTitle(folderID, trimmedTitle) == true else {
                self.inlineEditorState = .snippetFolder(
                    folderID,
                    originalTitle: originalTitle,
                    draftTitle: title,
                    error: String(localized: "A folder with this name already exists.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
        case let .snippet(snippetID, originalTitle, originalContent, _, _, _):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedTitle != originalTitle || content != originalContent else {
                self.inlineEditorState = nil
                reloadContentKeepingTopLeft()
                return true
            }
            guard !trimmedTitle.isEmpty else {
                self.inlineEditorState = .snippet(
                    snippetID,
                    originalTitle: originalTitle,
                    originalContent: originalContent,
                    draftTitle: title,
                    draftContent: content,
                    error: String(localized: "Snippet title cannot be empty.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            if content != originalContent,
               snippetDataSource?.updateSnippetContent(snippetID, content) != true {
                self.inlineEditorState = .snippet(
                    snippetID,
                    originalTitle: originalTitle,
                    originalContent: originalContent,
                    draftTitle: title,
                    draftContent: content,
                    error: String(localized: "A snippet with this content already exists in this folder.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            if trimmedTitle != originalTitle {
                snippetDataSource?.updateSnippetTitle(snippetID, trimmedTitle)
            }
        }

        self.inlineEditorState = nil
        reloadContentKeepingTopLeft()
        return true
    }

    private func discardInlineEditor() {
        inlineEditorState = nil
        reloadContentKeepingTopLeft()
    }

    private func beginEditingFolderShortcut(_ folderID: SnippetFolder.ID) {
        guard snippetDataSource?.fetchFolderDetails().contains(where: { $0.folder.id == folderID }) == true else {
            return
        }
        inlineEditorState = nil
        editingFolderShortcutID = folderID
        expandedSnippetFolderID = folderID
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(folderID)
    }

    private func recordFolderShortcut(_ keyCombo: KeyCombo) {
        guard let editingFolderShortcutID else { return }
        snippetDataSource?.updateFolderKeyCombo(editingFolderShortcutID, keyCombo)
        self.editingFolderShortcutID = nil
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(editingFolderShortcutID)
    }

    private func clearFolderShortcut(_ folderID: SnippetFolder.ID) {
        snippetDataSource?.clearFolderKeyCombo(folderID)
        if editingFolderShortcutID == folderID {
            editingFolderShortcutID = nil
        }
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(folderID)
    }

    private func clearEditingFolderShortcut() {
        guard let editingFolderShortcutID else { return }
        clearFolderShortcut(editingFolderShortcutID)
    }

    private func discardFolderShortcutEditor() {
        let folderID = editingFolderShortcutID
        editingFolderShortcutID = nil
        reloadContentKeepingTopLeft()
        if let folderID {
            selectSnippetFolderRowIfVisible(folderID)
        }
    }

    private func makeSnippetContent() -> EmbeddedContent {
        let details = enabledSnippetFolderDetails()
        guard !details.isEmpty else {
            expandedSnippetFolderID = nil
            currentSnippetFolderTitle = nil
            return EmbeddedContent(
                headerTitle: snippetTitle,
                headerSubtitle: nil,
                showsBackButton: false,
                canGoToPreviousPage: false,
                canGoToNextPage: false,
                typeFilter: nil,
                rows: isWorkspaceEditing ? snippetCreateRows(hasFolders: false) : [emptyRow(title: String(localized: "No Snippets"))]
            )
        }

        if let expandedID = expandedSnippetFolderID, !details.contains(where: { $0.folder.id == expandedID }) {
            expandedSnippetFolderID = details.first?.folder.id
        } else if expandedSnippetFolderID == nil && !isWorkspaceEditing {
            expandedSnippetFolderID = details.first?.folder.id
        }

        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = details.flatMap { detail -> [EmbeddedRow] in
            let isExpanded = detail.folder.id == expandedSnippetFolderID
            let folderTitleMatches = !query.isEmpty && detail.folder.title.localizedCaseInsensitiveContains(query)
            let folderKeyCombo = snippetDataSource?.folderKeyCombo(detail.folder.id)
            let folderShortcutText = PasteraShortcutFormatter.string(for: folderKeyCombo)
            let folderRow = EmbeddedRow(
                title: detail.folder.title,
                view: MainMenuPanelRowView(
                    title: detail.folder.title,
                    image: folderRowImage(),
                    shortcutText: folderShortcutText,
                    rowKind: .snippetFolder,
                    rowHeight: MainMenuPanelLayout.snippetFolderRowHeight,
                    showsChevron: true,
                    isExpanded: isExpanded,
                    shortcutPlacement: .trailingCommand,
                    onEdit: { [weak self] in
                        self?.beginEditingSnippetFolder(detail.folder.id)
                    },
                    onEditShortcut: { [weak self] in
                        self?.beginEditingFolderShortcut(detail.folder.id)
                    },
                    onClearShortcut: folderKeyCombo == nil ? nil : { [weak self] in
                        self?.clearFolderShortcut(detail.folder.id)
                    },
                    onDelete: { [weak self] in
                        self?.confirmDeleteSnippetFolder(detail.folder.id)
                    },
                    onDoubleClick: { [weak self] in self?.beginEditingSnippetFolder(detail.folder.id) },
                    deleteTitle: String(localized: "Delete Folder"),
                    onConfirm: { [weak self] _ in
                        self?.expandSnippetFolder(detail.folder.id)
                    }
                ),
                confirm: { [weak self] in self?.expandSnippetFolder(detail.folder.id) },
                role: .snippetFolder(detail.folder.id)
            )
            guard isExpanded else { return [folderRow] }

            currentSnippetFolderTitle = detail.folder.title
            let snippets = enabledSnippets(in: detail, folderTitleMatches: folderTitleMatches)
            visibleSnippetIDs = snippets.map(\.id)
            let shortcutEditorRows: [EmbeddedRow]
            if editingFolderShortcutID == detail.folder.id {
                shortcutEditorRows = [
                    EmbeddedRow(
                        title: "\(detail.folder.title) Shortcut",
                        view: makeFolderShortcutEditorView(for: detail.folder.id, keyCombo: folderKeyCombo),
                        confirm: {},
                        role: .none
                    )
                ]
            } else {
                shortcutEditorRows = []
            }
            let snippetRows = snippets.enumerated().map { index, snippet in
                EmbeddedRow(
                    title: snippet.title,
                    view: MainMenuPanelRowView(
                        title: snippet.title,
                        image: nil,
                        shortcutText: numericShortcutText(forRowIndex: index),
                        rowKind: .action,
                        indentationLevel: 1,
                        shortcutPlacement: .leadingItemNumber,
                        onEdit: { [weak self] in
                            self?.beginEditingSnippet(snippet.id)
                        },
                        onDelete: { [weak self] in
                            self?.confirmDeleteSnippet(snippet.id)
                        },
                        onDoubleClick: { [weak self] in self?.beginEditingSnippet(snippet.id) },
                        deleteTitle: String(localized: "Delete Snippet"),
                        onConfirm: { [weak self] _ in
                            self?.confirmSnippetSelection(snippet.id)
                        }
                    ),
                    confirm: { [weak self] in self?.confirmSnippetSelection(snippet.id) },
                    role: .snippet(snippet.id)
                )
            }
            let contextualRows = isWorkspaceEditing && query.isEmpty
                ? [snippetInFolderCreateRow(folderID: detail.folder.id)] : []
            return [folderRow] + shortcutEditorRows + snippetRows + contextualRows
        }

        if currentSnippetFolderTitle == nil,
           let expandedSnippetFolderID,
           let detail = details.first(where: { $0.folder.id == expandedSnippetFolderID }) {
            currentSnippetFolderTitle = detail.folder.title
        }

        return EmbeddedContent(
            headerTitle: snippetTitle,
            headerSubtitle: nil,
            showsBackButton: false,
            canGoToPreviousPage: false,
            canGoToNextPage: false,
            typeFilter: nil,
            rows: rows + (isWorkspaceEditing && expandedSnippetFolderID == nil ? snippetCreateRows(hasFolders: false) : [])
        )
    }

    private func snippetCreateRows(hasFolders: Bool) -> [EmbeddedRow] {
        guard isWorkspaceEditing, inlineEditorState == nil else { return [] }
        let view = MainMenuCreateActionsView(
            primaryTitle: hasFolders ? String(localized: "+ New Snippet") : String(localized: "Create Your First Folder"),
            primaryIdentifier: hasFolders ? "mainMenuContentCreateSnippetButton" : "mainMenuContentCreateSnippetFolderButton",
            secondaryTitle: hasFolders ? String(localized: "New Folder") : nil,
            secondaryIdentifier: hasFolders ? "mainMenuContentCreateSnippetFolderButton" : nil,
            onPrimary: { [weak self] in
                if hasFolders { self?.beginCreatingSnippet() } else { self?.beginCreatingSnippetFolder() }
            },
            onSecondary: hasFolders ? { [weak self] in self?.beginCreatingSnippetFolder() } : nil
        )
        return [EmbeddedRow(title: String(localized: "Create"), view: view, confirm: {}, participatesInNavigation: false)]
    }

    private func snippetInFolderCreateRow(folderID: SnippetFolder.ID) -> EmbeddedRow {
        let view = MainMenuCreateActionsView(
            primaryTitle: String(localized: "+ New Snippet in This Folder"),
            primaryIdentifier: "mainMenuCreateSnippetInFolderButton",
            onPrimary: { [weak self] in self?.beginCreatingSnippet(in: folderID) }
        )
        return EmbeddedRow(title: String(localized: "New Snippet"), view: view, confirm: {}, participatesInNavigation: false)
    }

    private func folderRowImage() -> NSImage? {
        NSImage(systemSymbolName: "folder", accessibilityDescription: String(localized: "Folder"))
    }

    private func makePasswordVaultContent() -> EmbeddedContent {
        let folders: [PasswordVaultFolder]
        let entries: [PasswordVaultEntry]
        do {
            folders = try passwordVaultDataSource?.fetchFolders() ?? []
            entries = try passwordVaultDataSource?.fetchEntries() ?? []
        } catch {
            return EmbeddedContent(
                headerTitle: String(localized: "Password Vault"),
                headerSubtitle: nil,
                showsBackButton: false,
                canGoToPreviousPage: false,
                canGoToNextPage: false,
                typeFilter: nil,
                rows: [emptyRow(title: String(localized: "Password Vault Unavailable"))]
            )
        }
        if let expandedID = expandedPasswordVaultFolderID, !folders.contains(where: { $0.id == expandedID }) {
            expandedPasswordVaultFolderID = folders.first?.id
        } else if expandedPasswordVaultFolderID == nil && !isWorkspaceEditing {
            expandedPasswordVaultFolderID = folders.first?.id
        }
        let query = passwordVaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingEntries = entries.filter { query.isEmpty || $0.matches(query) }
        let rows = folders.flatMap { folder -> [EmbeddedRow] in
            let folderEntries = matchingEntries.filter { $0.folderID == folder.id }
            guard query.isEmpty || !folderEntries.isEmpty || folder.name.localizedCaseInsensitiveContains(query) else { return [] }
            let isExpanded = query.isEmpty ? folder.id == expandedPasswordVaultFolderID : true
            let folderRow = EmbeddedRow(
                title: folder.name,
                view: MainMenuPanelRowView(
                    title: folder.name,
                    image: folderRowImage(),
                    rowKind: .snippetFolder,
                    showsChevron: true,
                    isExpanded: isExpanded,
                    onEdit: { [weak self] in self?.passwordVaultFolderEditorState = .rename(folder, error: nil); self?.reloadContentKeepingTopLeft() },
                    onDelete: { [weak self] in self?.deletePasswordVaultFolder(folder.id) },
                    onDoubleClick: { [weak self] in
                        self?.passwordVaultFolderEditorState = .rename(folder, error: nil)
                        self?.reloadContentKeepingTopLeft()
                    },
                    deleteTitle: String(localized: "Delete Folder"),
                    onConfirm: { [weak self] _ in self?.togglePasswordVaultFolder(folder.id) }
                ),
                confirm: { [weak self] in self?.togglePasswordVaultFolder(folder.id) }
            )
            guard isExpanded else { return [folderRow] }
            let entryRows = folderEntries.map { entry in
                EmbeddedRow(
                    title: entry.title,
                    view: MainMenuPanelRowView(
                        title: entry.title,
                        image: MainMenuModeIcons.passwordVault(),
                        rowKind: .action,
                        indentationLevel: 1,
                        onEdit: { [weak self] in self?.beginEditingPasswordVaultEntry(entry.id) },
                        onDelete: { [weak self] in self?.deletePasswordVaultEntry(entry.id) },
                        onDoubleClick: { [weak self] in self?.beginEditingPasswordVaultEntry(entry.id) },
                        deleteTitle: String(localized: "Delete Password"),
                        onConfirm: { [weak self] _ in self?.copyPasswordVaultEntry(entry.id) }
                    ),
                    confirm: { [weak self] in self?.copyPasswordVaultEntry(entry.id) }
                )
            }
            let contextualRows = isWorkspaceEditing && query.isEmpty
                ? [passwordInFolderCreateRow(folderID: folder.id)] : []
            return [folderRow] + entryRows + contextualRows
        }
        let trailingCreateRows = isWorkspaceEditing && expandedPasswordVaultFolderID == nil
            ? passwordVaultCreateRows(hasFolders: false) : []
        let visibleRows = passwordVaultStatusMessage.map { [emptyRow(title: $0)] + rows + trailingCreateRows }
            ?? (rows + trailingCreateRows)
        return EmbeddedContent(
            headerTitle: String(localized: "Password Vault"),
            headerSubtitle: nil,
            showsBackButton: false,
            canGoToPreviousPage: false,
            canGoToNextPage: false,
            typeFilter: nil,
            rows: visibleRows.isEmpty
                ? [emptyRow(title: String(localized: query.isEmpty ? "No Passwords" : "No Results"))]
                : visibleRows
        )
    }

    private func passwordVaultCreateRows(hasFolders: Bool) -> [EmbeddedRow] {
        guard isWorkspaceEditing, passwordVaultEditorState == nil, passwordVaultFolderEditorState == nil else { return [] }
        let view = MainMenuCreateActionsView(
            primaryTitle: hasFolders ? String(localized: "+ New Password") : String(localized: "Create Your First Folder"),
            primaryIdentifier: hasFolders ? "mainMenuContentCreatePasswordButton" : "mainMenuContentCreatePasswordFolderButton",
            secondaryTitle: hasFolders ? String(localized: "New Folder") : nil,
            secondaryIdentifier: hasFolders ? "mainMenuContentCreatePasswordFolderButton" : nil,
            onPrimary: { [weak self] in
                if hasFolders { self?.beginCreatingPasswordVaultEntry() } else { self?.beginCreatingPasswordVaultFolder() }
            },
            onSecondary: hasFolders ? { [weak self] in self?.beginCreatingPasswordVaultFolder() } : nil
        )
        return [EmbeddedRow(title: String(localized: "Create"), view: view, confirm: {}, participatesInNavigation: false)]
    }

    private func passwordInFolderCreateRow(folderID: PasswordVaultFolder.ID) -> EmbeddedRow {
        let view = MainMenuCreateActionsView(
            primaryTitle: String(localized: "+ New Password in This Folder"),
            primaryIdentifier: "mainMenuCreatePasswordInFolderButton",
            onPrimary: { [weak self] in self?.beginCreatingPasswordVaultEntry(in: folderID) }
        )
        return EmbeddedRow(title: String(localized: "New Password"), view: view, confirm: {}, participatesInNavigation: false)
    }

    private func makePasswordVaultEditorContent(_ state: PasswordVaultEditorState) -> EmbeddedContent {
        let folders = (try? passwordVaultDataSource?.fetchFolders()) ?? []
        let draft: PasswordVaultDraft
        let error: String?
        switch state {
        case let .create(value, message): (draft, error) = (value, message)
        case let .edit(_, value, message): (draft, error) = (value, message)
        }
        let editor = PasswordVaultEditorView(
            draft: draft,
            folders: folders,
            errorMessage: error,
            onSave: { [weak self] draft in self?.savePasswordVaultDraft(draft) },
            onCancel: { [weak self] in self?.discardPasswordVaultEditor() }
        )
        return EmbeddedContent(
            headerTitle: String(localized: "Password Vault"), headerSubtitle: nil, showsBackButton: false,
            canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil,
            rows: [EmbeddedRow(title: String(localized: "Password"), view: editor, confirm: {})]
        )
    }

    private func makePasswordVaultFolderEditorContent(_ state: PasswordVaultFolderEditorState) -> EmbeddedContent {
        let name: String
        let error: String?
        switch state {
        case let .create(message): (name, error) = ("", message)
        case let .rename(folder, message): (name, error) = (folder.name, message)
        }
        let editor = PasswordVaultFolderEditorView(
            name: name,
            onSave: { [weak self] name in self?.savePasswordVaultFolder(name: name) },
            onCancel: { [weak self] in self?.passwordVaultFolderEditorState = nil; self?.reloadContentKeepingTopLeft() }
        )
        let rows = error.map { [emptyRow(title: $0), EmbeddedRow(title: String(localized: "Folder"), view: editor, confirm: {})] }
            ?? [EmbeddedRow(title: String(localized: "Folder"), view: editor, confirm: {})]
        return EmbeddedContent(
            headerTitle: String(localized: "Folder"), headerSubtitle: nil, showsBackButton: false,
            canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil, rows: rows
        )
    }

    private func deletePasswordVaultEntry(_ id: PasswordVaultEntry.ID) {
        passwordVaultDataSource?.deleteEntry(id) { [weak self] result in
            self?.handlePasswordVaultResult(result)
        }
    }

    private func togglePasswordVaultFolder(_ folderID: PasswordVaultFolder.ID) {
        expandedPasswordVaultFolderID = expandedPasswordVaultFolderID == folderID ? nil : folderID
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingPasswordVaultEntry(in requestedFolderID: PasswordVaultFolder.ID? = nil) {
        let folders = (try? passwordVaultDataSource?.fetchFolders()) ?? []
        guard let folderID = requestedFolderID ?? expandedPasswordVaultFolderID ?? folders.first?.id else {
            passwordVaultFolderEditorState = .create(error: nil)
            reloadContentKeepingTopLeft()
            return
        }
        passwordVaultEditorState = .create(PasswordVaultDraft(
            folderID: folderID, title: "", website: "", username: "", note: "", password: ""
        ), error: nil)
        reloadContentKeepingTopLeft()
    }

    private func beginEditingPasswordVaultEntry(_ id: PasswordVaultEntry.ID) {
        passwordVaultDataSource?.loadDraft(id) { [weak self] result in
            switch result {
            case let .success(draft):
                self?.passwordVaultEditorState = .edit(id, draft, error: nil)
                self?.reloadContentKeepingTopLeft()
            case .failure(.userCancelled):
                break
            case let .failure(error):
                self?.passwordVaultStatusMessage = self?.passwordVaultMessage(error)
                self?.reloadContentKeepingTopLeft()
            }
        }
    }

    private func savePasswordVaultDraft(_ draft: PasswordVaultDraft) {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updatePasswordVaultEditorError(String(localized: "Enter a name."), draft: draft)
            return
        }
        guard !draft.password.isEmpty else {
            updatePasswordVaultEditorError(String(localized: "Enter a password."), draft: draft)
            return
        }
        switch passwordVaultEditorState {
        case .create:
            passwordVaultDataSource?.createEntry(draft) { [weak self] result in
                self?.finishPasswordVaultSave(result, draft: draft)
            }
        case let .edit(id, _, _):
            passwordVaultDataSource?.updateEntry(id, draft) { [weak self] result in
                self?.finishPasswordVaultSave(result, draft: draft)
            }
        case nil:
            break
        }
    }

    private func finishPasswordVaultSave(_ result: Result<Void, PasswordVaultError>, draft: PasswordVaultDraft) {
        switch result {
        case .success:
            passwordVaultEditorState = nil
            expandedPasswordVaultFolderID = draft.folderID
        case .failure(.userCancelled):
            return
        case let .failure(error):
            updatePasswordVaultEditorError(passwordVaultMessage(error), draft: draft)
            return
        }
        reloadContentKeepingTopLeft()
    }

    private func updatePasswordVaultEditorError(_ message: String, draft: PasswordVaultDraft) {
        switch passwordVaultEditorState {
        case .create:
            passwordVaultEditorState = .create(draft, error: message)
        case let .edit(id, _, _):
            passwordVaultEditorState = .edit(id, draft, error: message)
        case nil:
            break
        }
        reloadContentKeepingTopLeft()
    }

    private func discardPasswordVaultEditor() {
        passwordVaultEditorState = nil
        reloadContentKeepingTopLeft()
    }

    private func copyPasswordVaultEntry(_ id: PasswordVaultEntry.ID) {
        passwordVaultDataSource?.copyPassword(id) { [weak self] result in
            self?.handlePasswordVaultResult(result)
        }
    }

    private func handlePasswordVaultResult(_ result: Result<Void, PasswordVaultError>) {
        switch result {
        case .success, .failure(.userCancelled):
            passwordVaultStatusMessage = nil
        case let .failure(error):
            passwordVaultStatusMessage = passwordVaultMessage(error)
        }
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingPasswordVaultFolder() {
        passwordVaultFolderEditorState = .create(error: nil)
        reloadContentKeepingTopLeft()
    }

    private func savePasswordVaultFolder(name: String) {
        do {
            switch passwordVaultFolderEditorState {
            case .create:
                let folder = try passwordVaultDataSource?.createFolder(name)
                expandedPasswordVaultFolderID = folder?.id
            case let .rename(folder, _):
                _ = try passwordVaultDataSource?.renameFolder(folder.id, name)
            case nil:
                return
            }
            passwordVaultFolderEditorState = nil
            reloadContentKeepingTopLeft()
        } catch let error as PasswordVaultError {
            switch passwordVaultFolderEditorState {
            case .create:
                passwordVaultFolderEditorState = .create(error: passwordVaultMessage(error))
            case let .rename(folder, _):
                passwordVaultFolderEditorState = .rename(folder, error: passwordVaultMessage(error))
            case nil:
                break
            }
            reloadContentKeepingTopLeft()
        } catch {
            passwordVaultStatusMessage = String(localized: "Password Vault Unavailable")
        }
    }

    private func deletePasswordVaultFolder(_ id: PasswordVaultFolder.ID) {
        do {
            try passwordVaultDataSource?.deleteFolder(id)
            if expandedPasswordVaultFolderID == id { expandedPasswordVaultFolderID = nil }
        } catch let error as PasswordVaultError {
            passwordVaultStatusMessage = passwordVaultMessage(error)
        } catch {
            passwordVaultStatusMessage = String(localized: "Password Vault Unavailable")
        }
        reloadContentKeepingTopLeft()
    }

    private func passwordVaultMessage(_ error: PasswordVaultError) -> String {
        switch error {
        case .invalidTitle: return String(localized: "Enter a name.")
        case .invalidPassword: return String(localized: "Enter a password.")
        case .duplicateFolder: return String(localized: "A folder with this name already exists.")
        case .folderNotEmpty: return String(localized: "Move or delete the passwords in this folder first.")
        case .folderNotFound, .entryNotFound: return String(localized: "This item no longer exists.")
        case .authenticationFailed: return String(localized: "Authentication failed.")
        case .corruptedData: return String(localized: "This Keychain item cannot be read.")
        case .duplicateEntry: return String(localized: "This password already exists.")
        case .keychainUnavailable: return String(localized: "The macOS Keychain is unavailable.")
        case .userCancelled: return ""
        }
    }

    private func makeFolderShortcutEditorView(for folderID: SnippetFolder.ID, keyCombo: KeyCombo?) -> NSView {
        let view = MainMenuFolderShortcutEditorView(
            keyCombo: keyCombo,
            onChange: { [weak self] keyCombo in
                self?.recordFolderShortcut(keyCombo)
            },
            onClear: { [weak self] in
                self?.clearFolderShortcut(folderID)
            }
        )
        folderShortcutEditorView = view
        return view
    }

    private func enabledSnippetFolderDetails() -> [SnippetFolderDetail] {
        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = snippetDataSource?.fetchFolderDetails().filter { $0.folder.isEnabled } ?? []
        guard !query.isEmpty else { return details }
        return details.filter { detail in
            detail.folder.title.localizedCaseInsensitiveContains(query) ||
                detail.snippets.contains {
                    $0.isEnabled &&
                        ($0.title.localizedCaseInsensitiveContains(query) ||
                         $0.content.localizedCaseInsensitiveContains(query))
                }
        }
    }

    private func enabledSnippets(in detail: SnippetFolderDetail, folderTitleMatches: Bool = false) -> [Snippet] {
        let snippets = detail.snippets.filter(\.isEnabled)
        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !folderTitleMatches else { return snippets }
        return snippets.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    private func emptyRow(title: String) -> EmbeddedRow {
        EmbeddedRow(
            title: title,
            view: MainMenuEmbeddedEmptyRowView(title: title),
            confirm: {}
        )
    }

    private func noticeItems() -> [MainMenuPanelItem] {
        itemsProvider().filter { item in
            switch item {
            case .notice, .separator:
                return true
            case .snippetFolder, .action:
                return false
            }
        }
    }

    private func resetVisibleRows() {
        visibleHistoryIDs.removeAll()
        visibleSnippetIDs.removeAll()
        visibleMainMenuRowTitles.removeAll()
        currentSnippetFolderTitle = nil
    }

    private func addEmbeddedHeader(_ content: EmbeddedContent, frame: NSRect) {
        let supportsWorkspaceEditing = selectedMode == .snippets || selectedMode == .passwordVault
        let header = MainMenuEmbeddedHeaderView(
            frame: frame,
            title: content.headerTitle,
            subtitle: content.headerSubtitle,
            showsBackButton: content.showsBackButton,
            canGoToPreviousPage: content.canGoToPreviousPage,
            canGoToNextPage: content.canGoToNextPage,
            typeFilter: content.typeFilter,
            showsEditButton: supportsWorkspaceEditing,
            isEditing: isWorkspaceEditing,
            onBack: { [weak self] in self?.returnToSnippetFolders() },
            onPreviousPage: { [weak self] in self?.goToPreviousHistoryPage() },
            onNextPage: { [weak self] in self?.goToNextHistoryPage() },
            onTypeFilter: { [weak self] typeFilter in self?.updateHistoryTypeFilter(typeFilter) },
            onToggleEditing: { [weak self] in self?.toggleWorkspaceEditing() }
        )
        contentView.addSubview(header)
    }

    private func toggleWorkspaceEditing() {
        isWorkspaceEditing.toggle()
        if !isWorkspaceEditing {
            inlineEditorState = nil
            passwordVaultEditorState = nil
            passwordVaultFolderEditorState = nil
        }
        reloadContentKeepingTopLeft()
    }

    private func addToolbar(at verticalPosition: CGFloat) {
        addToolbar(frame: NSRect(
            x: 0,
            y: verticalPosition,
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.toolbarHeight
        ))
    }

    private func addToolbar(frame: NSRect) {
        let toolbar = MainMenuToolbarView(
            frame: frame,
            configuration: MainMenuToolbarViewConfiguration(
                selectedMode: {
                    switch selectedMode {
                    case .history: return .history
                    case .snippets: return .snippets
                    case .passwordVault: return .passwordVault
                    }
                }(),
                oneDriveStatus: oneDriveStatusService.currentStatus()
            ),
            actions: MainMenuToolbarActions(
                onSearch: { [weak self] in self?.toggleSearchField() },
                onHistory: { [weak self] in self?.openHistoryFromToolbar() },
                onSnippets: { [weak self] in self?.openSnippetsFromToolbar() },
                onPasswordVault: { [weak self] in self?.openPasswordVaultFromToolbar() },
                onOneDrive: { [weak self] in self?.openOneDriveFromToolbar() },
                onPreferences: { [weak self] in self?.onOpenPreferences() }
            )
        )
        contentView.addSubview(toolbar)
        oneDriveStatusButton = toolbar.oneDriveStatusButton
    }

    private func updateEmbeddedSearchLayout() {
        guard usesEmbeddedContent else { return }
        applyCurrentContentSizeKeepingTopLeft()
        guard let headerBlock = firstSubview(identifier: "mainMenuHeaderBlock", in: contentView),
              let contentBlock = firstSubview(identifier: "mainMenuContentBlock", in: contentView),
              let footerDock = firstSubview(identifier: "mainMenuFooterDock", in: contentView) else {
            reloadContentKeepingTopLeft()
            return
        }

        headerBlock.frame = headerBlockFrame
        contentBlock.frame = contentBlockFrame
        updateEmbeddedScrollFrame(in: contentBlock)
        footerDock.frame = footerDockFrame
        if let searchFieldFrame {
            addSearchField(frame: searchFieldFrame)
        } else {
            searchField.removeFromSuperview()
        }
    }

    private func updateEmbeddedScrollFrame(in contentBlock: NSView) {
        guard let scrollView = contentBlock.subviews.compactMap({ $0 as? NSScrollView }).first else { return }
        let scrollFrame = contentBlock.bounds.insetBy(
            dx: MainMenuPanelLayout.contentInnerPadding,
            dy: MainMenuPanelLayout.contentInnerPadding
        )
        scrollView.frame = scrollFrame
        if let documentView = scrollView.documentView {
            documentView.frame.size.width = scrollFrame.width
            documentView.subviews.forEach { $0.frame.size.width = scrollFrame.width }
            let topOffset = max(0, documentView.frame.height - scrollFrame.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: topOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func firstSubview(identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = firstSubview(identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    private func addSearchField(at verticalPosition: CGFloat) {
        addSearchField(frame: NSRect(
            x: MainMenuPanelLayout.toolbarHorizontalInset,
            y: verticalPosition + 1,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.toolbarHorizontalInset * 2,
            height: MainMenuPanelLayout.searchHeight - 2
        ))
    }

    private func addSearchField(frame: NSRect) {
        searchField.removeFromSuperview()
        searchField.identifier = NSUserInterfaceItemIdentifier("mainMenuSearchField")
        searchField.placeholderString = String(localized: "Search...")
        searchField.font = .systemFont(ofSize: 12, weight: .regular)
        searchField.controlSize = .regular
        searchField.focusRingType = .default
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        searchField.stringValue = currentSearchQuery()
        searchField.frame = frame
        contentView.addSubview(searchField, positioned: .above, relativeTo: nil)
    }

    @objc private func searchFieldAction(_ sender: NSSearchField) {
        updateSearchQuery(sender.stringValue)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField, field === searchField else { return }
        updateSearchQuery(searchField.stringValue)
    }

    private func currentSearchQuery() -> String {
        switch selectedMode {
        case .history:
            return historyDataSource?.currentState().query ?? ""
        case .snippets:
            return snippetSearchQuery
        case .passwordVault:
            return passwordVaultSearchQuery
        }
    }

    private func updateSearchQuery(_ query: String) {
        guard usesEmbeddedContent else { return }
        editingFolderShortcutID = nil
        switch selectedMode {
        case .history:
            historyDataSource?.updateState { $0.updateQuery(query) }
        case .snippets:
            snippetSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        case .passwordVault:
            passwordVaultSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        reloadContentKeepingTopLeft()
        if searchField.superview != nil {
            panel?.makeFirstResponder(searchField)
        }
    }

    private func reloadContentKeepingTopLeft() {
        let topLeftPoint = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        reloadContent()
        if let topLeftPoint {
            panel?.setFrameTopLeftPoint(topLeftPoint)
        }
    }

    private func updateOneDriveStatusButton(_ status: OneDriveProcessStatus) {
        if let oneDriveStatusButton {
            oneDriveStatusButton.configure(status: status)
        } else {
            reloadContentIfVisible()
        }
    }

    private func addSeparator(at verticalPosition: CGFloat) {
        let separator = makeSeparatorView(width: MainMenuPanelLayout.width)
        separator.frame.origin.y = verticalPosition
        contentView.addSubview(separator)
    }

    private func makeSeparatorView(width: CGFloat) -> NSView {
        let separator = NSView(frame: NSRect(
            x: MainMenuPanelLayout.separatorHorizontalInset,
            y: 0,
            width: width - MainMenuPanelLayout.separatorHorizontalInset * 2,
            height: MainMenuPanelLayout.separatorHeight
        ))
        separator.identifier = NSUserInterfaceItemIdentifier("mainMenuSeparator")
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: MainMenuPanelLayout.separatorAlpha).cgColor
        return separator
    }

    private func position(_ panel: NSPanel, near screenPoint: NSPoint) {
        let visibleFrame = NSScreen.screens
            .first { $0.frame.contains(screenPoint) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let originX = min(
            max(screenPoint.x - MainMenuPanelLayout.width / 2, visibleFrame.minX + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxX - MainMenuPanelLayout.width - MainMenuPanelLayout.screenPadding
        )
        let originY = min(
            max(screenPoint.y - panel.frame.height, visibleFrame.minY + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxY - panel.frame.height - MainMenuPanelLayout.screenPadding
        )
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func position(_ panel: NSPanel, anchoredTo menuFrame: NSRect) {
        panel.setFrameTopLeftPoint(NSPoint(x: menuFrame.minX, y: menuFrame.maxY))
    }

    private func position(_ panel: NSPanel, attachedToStatusItemFrame statusItemFrame: NSRect) {
        let visibleFrame = NSScreen.screens
            .first { $0.frame.intersects(statusItemFrame) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let originX = min(
            max(statusItemFrame.midX - panel.frame.width / 2, visibleFrame.minX + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxX - panel.frame.width - MainMenuPanelLayout.screenPadding
        )
        let topY = statusItemFrame.minY
        panel.setFrameTopLeftPoint(NSPoint(x: originX, y: topY))
    }

    func reloadOneDriveStatusIfVisible() {
        guard panel?.isVisible == true else { return }
        updateOneDriveStatusButton(oneDriveStatusService.currentStatus())
    }

    private func showSearchField() {
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        isWorkspaceEditing = false
        guard !isSearchVisible else {
            panel?.makeFirstResponder(searchField)
            return
        }
        isSearchVisible = true
        if usesEmbeddedContent {
            updateEmbeddedSearchLayout()
        } else {
            addSearchField(at: fixedSearchY)
        }
        panel?.makeFirstResponder(searchField)
    }

    private func toggleSearchField() {
        if isSearchVisible {
            hideSearchField()
        } else {
            showSearchField()
        }
    }

    private func hideSearchField() {
        guard isSearchVisible else { return }
        isSearchVisible = false
        searchField.removeFromSuperview()
        panel?.makeFirstResponder(nil)
        if usesEmbeddedContent {
            updateEmbeddedSearchLayout()
        }
    }

    private func openOneDriveFromToolbar() {
        _ = oneDriveStatusService.openOneDrive()
        updateOneDriveStatusButton(oneDriveStatusService.currentStatus())
    }

    private func openHistoryFromToolbar() {
        openHistoryFromMainMenu()
    }

    private func openSnippetsFromToolbar() {
        openSnippetsFromMainMenu()
    }

    private func openPasswordVaultFromToolbar() {
        openPasswordVaultFromMainMenu()
    }

    private func expandSnippetFolder(_ folderID: SnippetFolder.ID) {
        editingFolderShortcutID = nil
        expandedSnippetFolderID = folderID
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(folderID)
    }

    private func returnToSnippetFolders() {
        guard selectedMode == .snippets else { return }
        expandedSnippetFolderID = nil
        reloadContentKeepingTopLeft()
    }

    private func selectSnippetFolderRowIfVisible(_ folderID: SnippetFolder.ID) {
        guard let index = keyboardEntries.firstIndex(where: {
            if case let .snippetFolder(id) = $0.role {
                return id == folderID
            }
            return false
        }) else { return }
        selectKeyboardEntry(at: index, triggerChildPanel: false)
    }

    private func selectSnippetRowIfVisible(_ snippetID: Snippet.ID) {
        guard let index = keyboardEntries.firstIndex(where: {
            if case let .snippet(id) = $0.role {
                return id == snippetID
            }
            return false
        }) else { return }
        selectKeyboardEntry(at: index, triggerChildPanel: false)
    }

    private func expandSelectedSnippetFolder() -> Bool {
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex),
              case let .snippetFolder(folderID) = keyboardEntries[selectedKeyboardEntryIndex].role else {
            return false
        }
        expandSnippetFolder(folderID)
        return true
    }

    private func selectExpandedSnippetFolderFromSnippetRow() -> Bool {
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex),
              case .snippet = keyboardEntries[selectedKeyboardEntryIndex].role,
              let expandedSnippetFolderID else {
            return false
        }
        selectSnippetFolderRowIfVisible(expandedSnippetFolderID)
        return true
    }

    private func confirmHistorySelection(_ historyID: PasteboardHistory.ID) {
        let targetContext = pasteTargetContext
        close()
        historyDataSource?.selectHistory(historyID, targetContext)
    }

    private func confirmSnippetSelection(_ snippetID: Snippet.ID) {
        let targetContext = pasteTargetContext
        close()
        snippetDataSource?.selectSnippet(snippetID, targetContext)
    }

    private func confirmDeleteSnippetFolder(_ folderID: SnippetFolder.ID) {
        guard inlineEditorState == nil,
              let detail = snippetDataSource?.fetchFolderDetails().first(where: { $0.folder.id == folderID }) else {
            return
        }
        let snippetCount = detail.snippets.count
        let snippetCountText = snippetCount == 1 ? "1 snippet" : "\(snippetCount) snippets"
        let result = deleteConfirmationRunner(PasteraConfirmationOptions(
            title: String(localized: "Delete Folder"),
            message: String(localized: "Delete \"\(detail.folder.title)\" and its \(snippetCountText)? This cannot be undone."),
            confirmTitle: String(localized: "Delete Folder"),
            cancelTitle: String(localized: "Cancel"),
            isDestructive: true
        ), panel)
        guard result.confirmed else { return }

        snippetDataSource?.deleteFolder(folderID)
        if expandedSnippetFolderID == folderID {
            expandedSnippetFolderID = nil
        }
        reloadContentKeepingTopLeft()
        if let expandedSnippetFolderID {
            selectSnippetFolderRowIfVisible(expandedSnippetFolderID)
        }
    }

    private func confirmDeleteSnippet(_ snippetID: Snippet.ID) {
        guard inlineEditorState == nil,
              let context = snippetContext(for: snippetID) else {
            return
        }
        let result = deleteConfirmationRunner(PasteraConfirmationOptions(
            title: String(localized: "Delete Snippet"),
            message: String(localized: "Delete \"\(context.snippet.title)\" from \"\(context.detail.folder.title)\"? This cannot be undone."),
            confirmTitle: String(localized: "Delete Snippet"),
            cancelTitle: String(localized: "Cancel"),
            isDestructive: true
        ), panel)
        guard result.confirmed else { return }

        snippetDataSource?.deleteSnippet(snippetID)
        expandedSnippetFolderID = context.detail.folder.id
        reloadContentKeepingTopLeft()
        selectSnippetRowAfterDeletion(folderID: context.detail.folder.id, deletedIndex: context.index)
    }

    private func snippetContext(
        for snippetID: Snippet.ID
    ) -> (detail: SnippetFolderDetail, snippet: Snippet, index: Int)? {
        for detail in snippetDataSource?.fetchFolderDetails() ?? [] {
            guard let index = detail.snippets.firstIndex(where: { $0.id == snippetID }) else { continue }
            return (detail, detail.snippets[index], index)
        }
        return nil
    }

    private func selectSnippetRowAfterDeletion(folderID: SnippetFolder.ID, deletedIndex: Int) {
        guard let detail = enabledSnippetFolderDetails().first(where: { $0.folder.id == folderID }) else { return }
        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderTitleMatches = !query.isEmpty && detail.folder.title.localizedCaseInsensitiveContains(query)
        let snippets = enabledSnippets(in: detail, folderTitleMatches: folderTitleMatches)
        guard let snippet = snippets[safe: min(deletedIndex, snippets.count - 1)] else {
            selectSnippetFolderRowIfVisible(folderID)
            return
        }
        selectSnippetRowIfVisible(snippet.id)
    }

    private func goToPreviousHistoryPage() {
        guard selectedMode == .history else { return }
        guard (historyDataSource?.currentState().pageIndex ?? 0) > 0 else { return }
        historyDataSource?.updateState { $0.goToPreviousPage() }
        reloadContentKeepingTopLeft()
    }

    private func goToNextHistoryPage() {
        guard selectedMode == .history, let historyDataSource else { return }
        let page = historyDataSource.fetchPage()
        historyDataSource.updateState { $0.goToNextPage(if: page.hasNextPage) }
        reloadContentKeepingTopLeft()
    }

    private func updateHistoryTypeFilter(_ typeFilter: HistoryMenuTypeFilter) {
        guard selectedMode == .history else { return }
        guard commitInlineEditorFromCurrentDraft() else { return }
        historyDataSource?.updateState { $0.updateTypeFilter(typeFilter) }
        reloadContentKeepingTopLeft()
    }

    private func numericShortcutText(forRowIndex index: Int) -> String? {
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        return PasteraShortcutFormatter.numericString(forRowIndex: index, startsAtZero: startsAtZero)
    }

    private func confirmNumberShortcut(_ event: NSEvent) -> Bool {
        guard usesEmbeddedContent else { return false }
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        switch selectedMode {
        case .history:
            guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
                for: event,
                startsAtZero: startsAtZero,
                rowCount: visibleHistoryIDs.count
            ) else { return false }
            confirmHistorySelection(visibleHistoryIDs[rowIndex])
            return true
        case .snippets:
            guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
                    for: event,
                    startsAtZero: startsAtZero,
                    rowCount: visibleSnippetIDs.count
            ) else { return false }
            confirmSnippetSelection(visibleSnippetIDs[rowIndex])
            return true
        case .passwordVault:
            return false
        }
    }
}

extension MainMenuPanelController {
    func handleKeyboardNavigationFromChild(_ event: NSEvent) -> Bool {
        handleKeyboardNavigation(event)
    }

    fileprivate func handleKeyboardNavigation(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }
        if handleFolderShortcutEditorKey(event) {
            return true
        }
        if handleInlineEditorKey(event) {
            return true
        }
        if handleSearchEscape(event) {
            return true
        }
        if isSearchShortcut(event) {
            showSearchField()
            return true
        }
        if confirmNumberShortcut(event) {
            return true
        }
        if handleSnippetDeleteShortcut(event) {
            return true
        }
        if usesEmbeddedContent, selectedMode == .snippets {
            switch event.keyCode {
            case 123:
                return selectExpandedSnippetFolderFromSnippetRow()
            case 124:
                return expandSelectedSnippetFolder()
            default:
                break
            }
        }
        if usesEmbeddedContent, selectedMode == .history {
            switch event.keyCode {
            case 123:
                goToPreviousHistoryPage()
                return true
            case 124:
                goToNextHistoryPage()
                return true
            default:
                break
            }
        }
        let direction: Int
        switch event.keyCode {
        case 125:
            direction = 1
        case 126:
            direction = -1
        case 36, 49, 76:
            guard let selectedKeyboardEntryIndex,
                  keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else { return false }
            keyboardEntries[selectedKeyboardEntryIndex].confirm()
            return true
        default:
            return false
        }
        guard !keyboardEntries.isEmpty else { return false }

        let currentIndex: Int
        if let selectedKeyboardEntryIndex {
            currentIndex = selectedKeyboardEntryIndex
        } else {
            currentIndex = direction > 0 ? -1 : keyboardEntries.count
        }

        let nextIndex = min(max(currentIndex + direction, 0), keyboardEntries.count - 1)
        selectKeyboardEntry(at: nextIndex, triggerChildPanel: true)
        return true
    }

    private func handleInlineEditorKey(_ event: NSEvent) -> Bool {
        guard inlineEditorState != nil else { return false }
        if event.keyCode == 53 {
            discardInlineEditor()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        if flags.contains(.command) {
            _ = commitInlineEditorFromCurrentDraft()
            return true
        }
        if inlineEditorView?.shouldCommitPlainReturn == true {
            _ = commitInlineEditorFromCurrentDraft()
            return true
        }
        return false
    }

    private func handleFolderShortcutEditorKey(_ event: NSEvent) -> Bool {
        guard editingFolderShortcutID != nil else { return false }
        if event.keyCode == 53 {
            discardFolderShortcutEditor()
            return true
        }
        return false
    }

    private func handleSnippetDeleteShortcut(_ event: NSEvent) -> Bool {
        guard inlineEditorState == nil,
              editingFolderShortcutID == nil,
              usesEmbeddedContent,
              selectedMode == .snippets,
              isCommandDeleteShortcut(event),
              let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else {
            return false
        }

        switch keyboardEntries[selectedKeyboardEntryIndex].role {
        case let .snippetFolder(folderID):
            confirmDeleteSnippetFolder(folderID)
            return true
        case let .snippet(snippetID):
            confirmDeleteSnippet(snippetID)
            return true
        case .none:
            return false
        }
    }

    private func isCommandDeleteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)
        return flags == .command && event.charactersIgnoringModifiers?.lowercased() == "d"
    }

    private func isSearchShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 3 && flags.contains(.command)
    }

    private func handleSearchEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, isSearchVisible else { return false }
        if currentSearchQuery().isEmpty {
            hideSearchField()
        } else {
            searchField.stringValue = ""
            updateSearchQuery("")
        }
        return true
    }

    @discardableResult
    fileprivate func appendKeyboardEntry(
        title: String,
        view: NSView,
        openChildPanel: (() -> Void)?,
        role: KeyboardEntryRole = .none,
        confirm: @escaping () -> Void
    ) -> Int {
        let index = keyboardEntries.count
        keyboardEntries.append(KeyboardEntry(
            title: title,
            role: role,
            view: { [weak view] in view },
            setSelected: { [weak view] selected in
                if let headerView = view as? MainMenuHeaderItemView {
                    headerView.setKeyboardSelected(selected)
                } else if let rowView = view as? MainMenuPanelRowView {
                    rowView.setKeyboardSelected(selected)
                } else if selected, let rowView = view as? HistoryMenuRowView {
                    rowView.window?.makeFirstResponder(rowView)
                } else if let rowView = view as? MainMenuEmbeddedEmptyRowView {
                    rowView.setKeyboardSelected(selected)
                }
                if selected, let view {
                    view.scrollToVisible(view.bounds)
                }
            },
            openChildPanel: openChildPanel,
            confirm: confirm
        ))
        return index
    }

    fileprivate func selectKeyboardEntry(at index: Int, triggerChildPanel: Bool) {
        guard keyboardEntries.indices.contains(index) else { return }
        if let selectedKeyboardEntryIndex,
           selectedKeyboardEntryIndex != index,
           keyboardEntries.indices.contains(selectedKeyboardEntryIndex) {
            keyboardEntries[selectedKeyboardEntryIndex].setSelected(false)
        }
        selectedKeyboardEntryIndex = index
        keyboardEntries[index].setSelected(true)
        if triggerChildPanel {
            keyboardEntries[index].openChildPanel?()
        }
    }
}

private final class MainMenuSurfaceView: NSView {
    init(frame frameRect: NSRect, identifier: String, fillColor: NSColor) {
        super.init(frame: frameRect)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        wantsLayer = true
        layer?.cornerRadius = MainMenuPanelLayout.sectionRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = MainMenuVisualColors.sectionBorder.cgColor
        layer?.borderWidth = 0.5
    }

    required init?(coder: NSCoder) { nil }
}

private final class MainMenuCenteredLabelCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let heightDelta = drawingRect.height - textSize.height
        if heightDelta > 0 {
            drawingRect.origin.y += heightDelta / 2
            drawingRect.size.height = textSize.height
        }
        return drawingRect
    }
}

private final class MainMenuCenteredLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        cell = MainMenuCenteredLabelCell(textCell: "")
    }

    required init?(coder: NSCoder) { nil }
}

private final class MainMenuEmbeddedHeaderView: NSView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 9
        static let buttonHeight: CGFloat = 26
        static let navButtonWidth: CGFloat = 22
        static let buttonSpacing: CGFloat = 3
        static let titleTrailingSpacing: CGFloat = 6
        static let pageLabelWidth: CGFloat = 36
        static let typeWidth: CGFloat = 26
        static let controlGroupWidth: CGFloat = 106
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = MainMenuCenteredLabel()
    private let backButton = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let typeButton = NSButton()
    private let editButton = NSButton()
    private let onBack: () -> Void
    private let onPreviousPage: () -> Void
    private let onNextPage: () -> Void
    private let onTypeFilter: (HistoryMenuTypeFilter) -> Void
    private let onToggleEditing: () -> Void
    private var selectedTypeFilter: HistoryMenuTypeFilter?

    init(
        frame frameRect: NSRect,
        title: String,
        subtitle: String?,
        showsBackButton: Bool,
        canGoToPreviousPage: Bool,
        canGoToNextPage: Bool,
        typeFilter: HistoryMenuTypeFilter?,
        showsEditButton: Bool,
        isEditing: Bool,
        onBack: @escaping () -> Void,
        onPreviousPage: @escaping () -> Void,
        onNextPage: @escaping () -> Void,
        onTypeFilter: @escaping (HistoryMenuTypeFilter) -> Void,
        onToggleEditing: @escaping () -> Void
    ) {
        self.onBack = onBack
        self.onPreviousPage = onPreviousPage
        self.onNextPage = onNextPage
        self.onTypeFilter = onTypeFilter
        self.onToggleEditing = onToggleEditing
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("mainMenuHeaderBlock")
        setup(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            canGoToPreviousPage: canGoToPreviousPage,
            canGoToNextPage: canGoToNextPage,
            typeFilter: typeFilter,
            showsEditButton: showsEditButton,
            isEditing: isEditing
        )
    }

    required init?(coder: NSCoder) { nil }

    // swiftlint:disable:next function_parameter_count
    private func setup(
        title: String,
        subtitle: String?,
        showsBackButton: Bool,
        canGoToPreviousPage: Bool,
        canGoToNextPage: Bool,
        typeFilter: HistoryMenuTypeFilter?,
        showsEditButton: Bool,
        isEditing: Bool
    ) {
        wantsLayer = true
        layer?.cornerRadius = MainMenuPanelLayout.sectionRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = MainMenuVisualColors.headerSurface.cgColor
        layer?.borderColor = MainMenuVisualColors.sectionBorder.cgColor
        layer?.borderWidth = 0.5

        if showsEditButton {
            configureButton(editButton, symbolName: isEditing ? "checkmark" : "pencil", action: #selector(editClicked(_:)))
            editButton.identifier = NSUserInterfaceItemIdentifier("mainMenuWorkspaceEditButton")
            editButton.toolTip = isEditing ? String(localized: "Done") : String(localized: "Edit")
            editButton.setAccessibilityLabel(editButton.toolTip ?? "")
            editButton.frame = NSRect(
                x: bounds.maxX - Metrics.horizontalInset - Metrics.buttonHeight,
                y: bounds.midY - Metrics.buttonHeight / 2,
                width: Metrics.buttonHeight,
                height: Metrics.buttonHeight
            )
            styleNavigationButton(editButton)
            addSubview(editButton)
        }

        configureButton(backButton, symbolName: "chevron.left", action: #selector(backClicked(_:)))
        backButton.isHidden = !showsBackButton
        backButton.frame = NSRect(
            x: Metrics.horizontalInset,
            y: bounds.midY - Metrics.buttonHeight / 2,
            width: Metrics.navButtonWidth,
            height: Metrics.buttonHeight
        )
        addSubview(backButton)

        let titleLeading = showsBackButton
            ? backButton.frame.maxX + Metrics.buttonSpacing
            : Metrics.horizontalInset
        let hasPagination = subtitle != nil || canGoToPreviousPage || canGoToNextPage
        let controlGroupFrame = NSRect(
            x: bounds.maxX - Metrics.horizontalInset - Metrics.controlGroupWidth,
            y: bounds.midY - Metrics.buttonHeight / 2,
            width: Metrics.controlGroupWidth,
            height: Metrics.buttonHeight
        )
        let typeFrame = NSRect(
            x: controlGroupFrame.minX,
            y: controlGroupFrame.minY,
            width: Metrics.typeWidth,
            height: Metrics.buttonHeight
        )
        let previousButtonFrame = NSRect(
            x: typeFrame.maxX,
            y: controlGroupFrame.minY,
            width: Metrics.navButtonWidth,
            height: Metrics.buttonHeight
        )
        let subtitleFrame = NSRect(
            x: previousButtonFrame.maxX,
            y: controlGroupFrame.minY,
            width: Metrics.pageLabelWidth,
            height: Metrics.buttonHeight
        )
        let nextButtonFrame = NSRect(
            x: subtitleFrame.maxX,
            y: controlGroupFrame.minY,
            width: Metrics.navButtonWidth,
            height: Metrics.buttonHeight
        )
        let titleTrailing = typeFilter == nil
            ? (hasPagination ? previousButtonFrame.minX : (showsEditButton ? editButton.frame.minX : bounds.maxX - Metrics.horizontalInset))
            : typeFrame.minX
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(
            x: titleLeading,
            y: bounds.midY - 9,
            width: max(48, titleTrailing - titleLeading - Metrics.titleTrailingSpacing),
            height: 18
        )
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.textColor = .labelColor
        subtitleLabel.alignment = .center
        subtitleLabel.frame = subtitleFrame

        configureButton(previousButton, symbolName: "chevron.left", action: #selector(previousClicked(_:)))
        previousButton.toolTip = "\(String(localized: "Previous Page")) · ← / ⌃B"
        previousButton.setAccessibilityLabel(previousButton.toolTip ?? "")
        previousButton.isEnabled = canGoToPreviousPage
        previousButton.frame = previousButtonFrame
        styleNavigationButton(previousButton)

        configureButton(nextButton, symbolName: "chevron.right", action: #selector(nextClicked(_:)))
        nextButton.toolTip = "\(String(localized: "Next Page")) · → / ⌃F"
        nextButton.setAccessibilityLabel(nextButton.toolTip ?? "")
        nextButton.isEnabled = canGoToNextPage
        nextButton.frame = nextButtonFrame
        styleNavigationButton(nextButton)

        if let typeFilter {
            configureTypeButton(selectedFilter: typeFilter)
            typeButton.frame = typeFrame
            styleNavigationButton(typeButton)
            addSubview(typeButton)
        }
        if hasPagination {
            addSubview(previousButton)
            addSubview(subtitleLabel)
            addSubview(nextButton)
        }
    }

    @objc private func editClicked(_ sender: NSButton) { onToggleEditing() }

    private func configureButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
    }

    private func styleNavigationButton(_ button: NSButton) {
        button.wantsLayer = true
        button.layer?.cornerRadius = min(button.frame.width, button.frame.height) / 2
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = button.isEnabled
            ? MainMenuVisualColors.controlSurface.cgColor
            : NSColor.clear.cgColor
        button.alphaValue = button.isEnabled ? 1 : 0.45
    }

    private func configureTypeButton(selectedFilter: HistoryMenuTypeFilter) {
        selectedTypeFilter = selectedFilter
        typeButton.setButtonType(.momentaryPushIn)
        typeButton.bezelStyle = .inline
        typeButton.isBordered = false
        typeButton.image = NSImage(
            systemSymbolName: "line.3.horizontal.decrease.circle",
            accessibilityDescription: String(localized: "Type Filter")
        )
        typeButton.image?.isTemplate = true
        typeButton.imagePosition = .imageOnly
        typeButton.contentTintColor = .secondaryLabelColor
        typeButton.target = self
        typeButton.action = #selector(typeFilterClicked(_:))
        typeButton.toolTip = "\(String(localized: "Type Filter")) · Tab"
        typeButton.setAccessibilityLabel(typeButton.toolTip ?? "")
    }

    @objc private func backClicked(_ sender: NSButton) {
        onBack()
    }

    @objc private func previousClicked(_ sender: NSButton) {
        onPreviousPage()
    }

    @objc private func nextClicked(_ sender: NSButton) {
        onNextPage()
    }

    @objc private func typeFilterClicked(_ sender: NSButton) {
        let menu = NSMenu()
        HistoryMenuTypeFilter.allCases.forEach { filter in
            let item = NSMenuItem(title: filter.title, action: #selector(typeFilterItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = filter.rawValue
            item.state = filter == selectedTypeFilter ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func typeFilterItemClicked(_ sender: NSMenuItem) {
        guard let filter = HistoryMenuTypeFilter(rawValue: sender.tag) else { return }
        onTypeFilter(filter)
    }
}

private final class MainMenuInlineEditorTitleField: NSTextField {
    var onDiscard: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onDiscard?()
    }
}

private final class MainMenuInlineEditorTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onDiscard: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDiscard?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76, flags.contains(.command) {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class MainMenuInlineEditorView: NSControl, NSTextFieldDelegate, NSTextViewDelegate {
    struct Configuration {
        let titleValue: String?
        let titlePlaceholder: String?
        let contentValue: String?
        let errorMessage: String?
    }

    private enum Metrics {
        static let inset: CGFloat = 9
        static let gap: CGFloat = 7
        static let fieldHeight: CGFloat = 26
        static let errorHeight: CGFloat = 16
        static let minimumContentHeight: CGFloat = 112
    }

    private let titleField = MainMenuInlineEditorTitleField()
    private let scrollView = NSScrollView()
    private let textView = MainMenuInlineEditorTextView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let showsTitleField: Bool
    private let showsContentField: Bool
    private let onCommit: () -> Void
    private let onDiscard: () -> Void

    var draftTitle: String {
        titleField.stringValue
    }

    var draftContent: String {
        textView.string
    }

    var shouldCommitPlainReturn: Bool {
        guard showsTitleField else { return false }
        return !showsContentField || titleField.currentEditor() != nil || window?.firstResponder === titleField
    }

    var buttonTitlesForTesting: [String] {
        []
    }

    init(
        configuration: Configuration,
        onCommit: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.showsTitleField = configuration.titleValue != nil
        self.showsContentField = configuration.contentValue != nil
        self.onCommit = onCommit
        self.onDiscard = onDiscard
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MainMenuPanelLayout.width,
            height: Self.preferredHeight(for: configuration)
        ))
        setup(configuration: configuration)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()

        let contentWidth = bounds.width - Metrics.inset * 2
        var top = bounds.maxY - Metrics.inset
        let hasError = !errorLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        errorLabel.isHidden = !hasError
        let errorY = Metrics.inset
        errorLabel.frame = NSRect(
            x: Metrics.inset,
            y: errorY,
            width: contentWidth,
            height: hasError ? Metrics.errorHeight : 0
        )
        let fieldBottom = hasError ? errorLabel.frame.maxY + Metrics.gap : Metrics.inset

        if showsTitleField {
            top -= Metrics.fieldHeight
            titleField.frame = NSRect(
                x: Metrics.inset,
                y: top,
                width: contentWidth,
                height: Metrics.fieldHeight
            )
            top -= Metrics.gap
        }

        if showsContentField {
            let contentHeight = max(Metrics.minimumContentHeight, top - fieldBottom)
            scrollView.frame = NSRect(
                x: Metrics.inset,
                y: fieldBottom,
                width: contentWidth,
                height: contentHeight
            )
            textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(contentHeight, textView.frame.height))
            textView.minSize = NSSize(width: 0, height: contentHeight)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
        }
    }

    func updateDraft(title: String?, content: String?) {
        if let title, showsTitleField {
            titleField.stringValue = title
        }
        if let content, showsContentField {
            textView.string = content
        }
    }

    private func setup(configuration: Configuration) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.030).cgColor

        titleField.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorTitleField")
        titleField.stringValue = configuration.titleValue ?? ""
        titleField.placeholderString = configuration.titlePlaceholder
        titleField.font = .systemFont(ofSize: 12, weight: .regular)
        titleField.bezelStyle = .roundedBezel
        titleField.delegate = self
        titleField.target = self
        titleField.action = #selector(titleCommitted(_:))
        titleField.onDiscard = { [weak self] in self?.onDiscard() }
        titleField.isHidden = !showsTitleField
        if showsTitleField {
            addSubview(titleField)
        }

        textView.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorContentTextView")
        textView.string = configuration.contentValue ?? ""
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.045)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.delegate = self
        textView.onCommit = { [weak self] in self?.onCommit() }
        textView.onDiscard = { [weak self] in self?.onDiscard() }
        scrollView.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorContentScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.isHidden = !showsContentField
        if showsContentField {
            addSubview(scrollView)
        }

        errorLabel.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorErrorLabel")
        errorLabel.stringValue = configuration.errorMessage ?? ""
        errorLabel.font = .systemFont(ofSize: 11, weight: .regular)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        addSubview(errorLabel)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.showsTitleField {
                self.window?.makeFirstResponder(self.titleField)
            } else if self.showsContentField {
                self.window?.makeFirstResponder(self.textView)
            }
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        onCommit()
    }

    func textDidEndEditing(_ notification: Notification) {
        onCommit()
    }

    @objc private func titleCommitted(_ sender: NSTextField) {
        onCommit()
    }

    private static func preferredHeight(for configuration: Configuration) -> CGFloat {
        let showsTitleField = configuration.titleValue != nil
        let showsContentField = configuration.contentValue != nil
        let hasError = !(configuration.errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var height = Metrics.inset * 2
        if showsTitleField {
            height += Metrics.fieldHeight
        }
        if showsTitleField && showsContentField {
            height += Metrics.gap
        }
        if showsContentField {
            height += Metrics.minimumContentHeight
        }
        if hasError {
            height += Metrics.gap + Metrics.errorHeight
        }
        return max(MainMenuPanelLayout.rowHeight, height)
    }
}

private final class MainMenuEmbeddedEmptyRowView: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    private var isKeyboardSelected = false
    private var isMouseInside = false
    private var trackingArea: NSTrackingArea?
    var onHoverFocus: (() -> Void)?

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.rowHeight))
        setup(title: title)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        onHoverFocus?()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        updateAppearance()
    }

    func setKeyboardSelected(_ selected: Bool) {
        isKeyboardSelected = selected
        updateAppearance()
    }

    private func setup(title: String) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(
            x: 10,
            y: bounds.midY - 8,
            width: MainMenuPanelLayout.width - 20,
            height: 16
        )
        addSubview(titleLabel)
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isMouseInside || isKeyboardSelected)
            ? MainMenuVisualColors.hoveredRow.cgColor
            : NSColor.clear.cgColor
    }
}

private final class MainMenuFolderShortcutEditorView: NSView, RecordViewDelegate {
    private enum Metrics {
        static let horizontalInset: CGFloat = 22
        static let labelWidth: CGFloat = 52
        static let recordHeight: CGFloat = 24
        static let clearButtonSize: CGFloat = 20
        static let spacing: CGFloat = 7
    }

    private let label = NSTextField(labelWithString: String(localized: "Shortcut"))
    private let recordView = RecordView(frame: .zero)
    private let clearButton = NSButton()
    private let onChange: (KeyCombo) -> Void
    private let onClear: () -> Void

    init(keyCombo: KeyCombo?, onChange: @escaping (KeyCombo) -> Void, onClear: @escaping () -> Void) {
        self.onChange = onChange
        self.onClear = onClear
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.folderShortcutEditorHeight
        ))
        setup(keyCombo: keyCombo)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self.recordView)
            _ = self.recordView.beginRecording()
        }
    }

    private func setup(keyCombo: KeyCombo?) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail

        recordView.delegate = self
        recordView.keyCombo = keyCombo
        recordView.identifier = NSUserInterfaceItemIdentifier("mainMenuFolderShortcutRecordView")
        PasteraRecordViewStyler.apply(to: recordView)

        clearButton.identifier = NSUserInterfaceItemIdentifier("mainMenuFolderShortcutClearButton")
        clearButton.setButtonType(.momentaryPushIn)
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.toolTip = String(localized: "Clear Shortcut")
        clearButton.setAccessibilityLabel(String(localized: "Clear Shortcut"))
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked(_:))

        [label, recordView, clearButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: Metrics.labelWidth),

            recordView.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: Metrics.spacing),
            recordView.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordView.heightAnchor.constraint(equalToConstant: Metrics.recordHeight),

            clearButton.leadingAnchor.constraint(equalTo: recordView.trailingAnchor, constant: Metrics.spacing),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: Metrics.clearButtonSize),
            clearButton.heightAnchor.constraint(equalToConstant: Metrics.clearButtonSize)
        ])
    }

    @objc private func clearButtonClicked(_ sender: NSButton) {
        onClear()
    }

    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let keyCombo else {
            onClear()
            return
        }
        onChange(keyCombo)
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}

    #if DEBUG
    func recordKeyComboForTesting(_ keyCombo: KeyCombo) {
        onChange(keyCombo)
    }

    func clearForTesting() {
        onClear()
    }
    #endif
}

private final class MainMenuActionButton: NSButton {
    var onAction: (() -> Void)?

    func connectAction() {
        target = self
        action = #selector(clicked(_:))
    }

    @objc private func clicked(_ sender: NSButton) { onAction?() }
}

private final class MainMenuCreateActionsView: NSView {
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?
    private var primaryMenuTitle = ""
    private var secondaryMenuTitle = ""

    init(
        primaryTitle: String,
        primaryIdentifier: String,
        secondaryTitle: String? = nil,
        secondaryIdentifier: String? = nil,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.rowHeight))
        primaryAction = onPrimary
        secondaryAction = onSecondary
        primaryMenuTitle = primaryTitle
        secondaryMenuTitle = secondaryTitle ?? ""
        let primary = makeButton(
            title: primaryTitle,
            identifier: "mainMenuContextCreateButton",
            symbolName: "plus",
            isPrimary: false
        )
        primary.onAction = { [weak self, weak primary] in self?.showCreateMenu(from: primary) }
        addSubview(primary)

        let xPosition: CGFloat = 10
        primary.frame = NSRect(x: xPosition, y: 3, width: 24, height: 24)
    }

    required init?(coder: NSCoder) { nil }

    private func showCreateMenu(from button: NSButton?) {
        guard let button else { return }
        if secondaryAction == nil {
            primaryAction?()
            return
        }
        let menu = NSMenu()
        let primaryItem = NSMenuItem(title: primaryMenuTitle, action: #selector(primarySelected(_:)), keyEquivalent: "")
        primaryItem.target = self
        menu.addItem(primaryItem)
        let secondaryItem = NSMenuItem(title: secondaryMenuTitle, action: #selector(secondarySelected(_:)), keyEquivalent: "")
        secondaryItem.target = self
        menu.addItem(secondaryItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    @objc private func primarySelected(_ sender: NSMenuItem) { primaryAction?() }
    @objc private func secondarySelected(_ sender: NSMenuItem) { secondaryAction?() }

    private func makeButton(
        title: String,
        identifier: String,
        symbolName: String,
        isPrimary: Bool
    ) -> MainMenuActionButton {
        let button = MainMenuActionButton(title: "", target: nil, action: nil)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.layer?.backgroundColor = isPrimary
            ? NSColor.controlAccentColor.withAlphaComponent(0.82).cgColor
            : MainMenuVisualColors.controlSurface.cgColor
        button.layer?.borderColor = MainMenuVisualColors.controlBorder.cgColor
        button.layer?.borderWidth = 0.5
        button.contentTintColor = isPrimary ? .white : .secondaryLabelColor
        button.connectAction()
        return button
    }
}

// swiftlint:disable:next type_body_length
private final class MainMenuPanelRowView: NSControl {
    enum RowKind {
        case snippetFolder
        case action
    }

    enum ShortcutPlacement {
        case trailingCommand
        case leadingItemNumber
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 10
        static let iconSize: CGFloat = 14
        static let iconSpacing: CGFloat = 7
        static let titleAccessorySpacing: CGFloat = 5
        static let accessoryChevronSpacing: CGFloat = 5
        static let chevronSize: CGFloat = 7
        static let accessoryButtonSize: CGFloat = 20
        static let indentationWidth: CGFloat = 14
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let shortcutButton = NSButton()
    private let chevronView = NSImageView()
    private let editButton = NSButton()
    private let deleteButton = NSButton()
    private let showsChevron: Bool
    private let isExpanded: Bool
    private let rowKind: RowKind
    private let rowTitle: String
    private let deleteTitle: String
    private let indentationLevel: Int
    private let shortcutPlacement: ShortcutPlacement
    private let onHoverOpen: ((NSRect?) -> Void)?
    private let onEdit: (() -> Void)?
    private let onEditShortcut: (() -> Void)?
    private let onClearShortcut: (() -> Void)?
    private let onDelete: (() -> Void)?
    private let onDoubleClick: (() -> Void)?
    private let onConfirm: (NSRect?) -> Void
    private var trackingArea: NSTrackingArea?
    private var hoverOpenWorkItem: DispatchWorkItem?
    private var isMouseInside = false
    private var isKeyboardSelected = false
    private var didDragWindow = false
    private var pendingSingleClick: DispatchWorkItem?
    var onHoverFocus: (() -> Void)?

    init(
        title: String,
        image: NSImage?,
        shortcutText: String? = nil,
        rowKind: RowKind = .action,
        rowHeight: CGFloat = MainMenuPanelLayout.rowHeight,
        showsChevron: Bool = false,
        isExpanded: Bool = false,
        indentationLevel: Int = 0,
        shortcutPlacement: ShortcutPlacement = .trailingCommand,
        onHoverOpen: ((NSRect?) -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onEditShortcut: (() -> Void)? = nil,
        onClearShortcut: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        deleteTitle: String? = nil,
        onConfirm: @escaping (NSRect?) -> Void
    ) {
        self.rowTitle = title
        self.rowKind = rowKind
        self.showsChevron = showsChevron
        self.isExpanded = isExpanded
        self.deleteTitle = deleteTitle ?? String(localized: "Delete")
        self.indentationLevel = indentationLevel
        self.shortcutPlacement = shortcutPlacement
        self.onHoverOpen = onHoverOpen
        self.onEdit = onEdit
        self.onEditShortcut = onEditShortcut
        self.onClearShortcut = onClearShortcut
        self.onDelete = onDelete
        self.onDoubleClick = onDoubleClick
        self.onConfirm = onConfirm
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: rowHeight))
        setup(title: title, image: image, shortcutText: shortcutText)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        onHoverFocus?()
        updateAppearance()
        scheduleHoverOpenIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        cancelHoverOpen()
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        didDragWindow = true
        cancelHoverOpen()
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragWindow else {
            didDragWindow = false
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        if let onDoubleClick, titleLabel.frame.contains(location) {
            if event.clickCount >= 2 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
                onDoubleClick()
                return
            }
            let workItem = DispatchWorkItem { [weak self] in self?.onConfirm(self?.screenFrameForOpening) }
            pendingSingleClick = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
            return
        }
        if !shortcutButton.isHidden, shortcutButton.frame.contains(location) {
            editShortcut()
            return
        }
        if shortcutPlacement == .trailingCommand,
           !shortcutBadge.isHidden,
           shortcutBadge.frame.contains(location),
           onEditShortcut != nil {
            editShortcut()
            return
        }
        guard editButton.isHidden || !editButton.frame.contains(location) else { return }
        guard deleteButton.isHidden || !deleteButton.frame.contains(location) else { return }
        cancelHoverOpen()
        onConfirm(screenFrameForOpening)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeContextMenu()
    }

    private func makeContextMenu() -> NSMenu? {
        guard onEdit != nil || onEditShortcut != nil || onClearShortcut != nil || onDelete != nil else { return nil }
        let menu = NSMenu()
        let editItem = NSMenuItem(title: String(localized: "Edit"), action: #selector(editMenuItemClicked(_:)), keyEquivalent: "")
        if onEdit != nil {
            editItem.target = self
            menu.addItem(editItem)
        }
        if onEditShortcut != nil {
            let item = NSMenuItem(
                title: String(localized: "Edit Shortcut"),
                action: #selector(editShortcutMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if onClearShortcut != nil {
            let item = NSMenuItem(
                title: String(localized: "Clear Shortcut"),
                action: #selector(clearShortcutMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if onDelete != nil {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(deleteMenuItemClicked(_:)), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }
        return menu
    }

    func setKeyboardSelected(_ selected: Bool) {
        guard isKeyboardSelected != selected else { return }
        isKeyboardSelected = selected
        updateAppearance()
    }

    private func setup(title: String, image: NSImage?, shortcutText: String?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = image == nil
        imageView.contentTintColor = .secondaryLabelColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        shortcutBadge.shortcutText = shortcutText
        shortcutBadge.style = shortcutPlacement == .leadingItemNumber ? .itemNumber : .command
        let itemShortcut = shortcutPlacement == .leadingItemNumber ? shortcutText : nil
        toolTip = mainMenuShortcutToolTip(title: title, includesPlainText: rowKind == .action,
                                          itemShortcut: itemShortcut)
        setAccessibilityHelp(toolTip)

        chevronView.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = .tertiaryLabelColor
        chevronView.isHidden = !showsChevron

        shortcutButton.identifier = NSUserInterfaceItemIdentifier("mainMenuRowShortcutButton")
        shortcutButton.setButtonType(.momentaryPushIn)
        shortcutButton.bezelStyle = .inline
        shortcutButton.isBordered = false
        shortcutButton.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        shortcutButton.imagePosition = .imageOnly
        shortcutButton.contentTintColor = .tertiaryLabelColor
        shortcutButton.toolTip = String(localized: "Edit Shortcut")
        shortcutButton.setAccessibilityLabel(String(localized: "Edit Shortcut"))
        shortcutButton.target = self
        shortcutButton.action = #selector(shortcutButtonClicked(_:))
        shortcutButton.isHidden = true

        editButton.identifier = NSUserInterfaceItemIdentifier("mainMenuRowEditButton")
        editButton.setButtonType(.momentaryPushIn)
        editButton.bezelStyle = .inline
        editButton.isBordered = false
        editButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        editButton.imagePosition = .imageOnly
        editButton.contentTintColor = .tertiaryLabelColor
        editButton.toolTip = String(localized: "Edit")
        editButton.setAccessibilityLabel(String(localized: "Edit"))
        editButton.target = self
        editButton.action = #selector(editButtonClicked(_:))
        editButton.isHidden = true

        deleteButton.identifier = NSUserInterfaceItemIdentifier("mainMenuRowDeleteButton")
        deleteButton.setButtonType(.momentaryPushIn)
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .tertiaryLabelColor
        let deleteTooltip = "\(deleteTitle) (⌘D)"
        deleteButton.toolTip = deleteTooltip
        deleteButton.setAccessibilityLabel(deleteTooltip)
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked(_:))
        deleteButton.isHidden = true

        [imageView, titleLabel, shortcutBadge, shortcutButton, editButton, deleteButton, chevronView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let leadingInset = Metrics.horizontalInset + CGFloat(indentationLevel) * Metrics.indentationWidth
        let shortcutButtonWidth: CGFloat = onEditShortcut == nil ? 0 : Metrics.accessoryButtonSize
        let shortcutButtonSpacing: CGFloat = onEditShortcut == nil ? 0 : Metrics.titleAccessorySpacing
        let shortcutEditSpacing: CGFloat = onEditShortcut == nil || onEdit == nil ? 0 : Metrics.titleAccessorySpacing
        let editButtonWidth: CGFloat = onEdit == nil ? 0 : Metrics.accessoryButtonSize
        let editButtonSpacing: CGFloat = onEdit == nil || onDelete == nil ? 0 : Metrics.titleAccessorySpacing
        let deleteButtonWidth: CGFloat = onDelete == nil ? 0 : Metrics.accessoryButtonSize
        let trailingAccessoryAnchor = shortcutPlacement == .leadingItemNumber
            ? shortcutButton.leadingAnchor
            : shortcutBadge.leadingAnchor

        var constraints = [
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: image == nil ? 0 : Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: image == nil ? 0 : Metrics.iconSize),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAccessoryAnchor,
                constant: -Metrics.titleAccessorySpacing
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutButton.trailingAnchor.constraint(
                equalTo: editButton.leadingAnchor,
                constant: -shortcutEditSpacing
            ),
            shortcutButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutButton.widthAnchor.constraint(equalToConstant: shortcutButtonWidth),
            shortcutButton.heightAnchor.constraint(equalToConstant: Metrics.accessoryButtonSize),

            editButton.trailingAnchor.constraint(
                equalTo: deleteButton.leadingAnchor,
                constant: -editButtonSpacing
            ),
            editButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: editButtonWidth),
            editButton.heightAnchor.constraint(equalToConstant: Metrics.accessoryButtonSize),

            deleteButton.trailingAnchor.constraint(
                equalTo: showsChevron ? chevronView.leadingAnchor : trailingAnchor,
                constant: showsChevron ? -Metrics.accessoryChevronSpacing : -Metrics.horizontalInset
            ),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: deleteButtonWidth),
            deleteButton.heightAnchor.constraint(equalToConstant: Metrics.accessoryButtonSize),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: showsChevron ? Metrics.chevronSize : 0),
            chevronView.heightAnchor.constraint(equalToConstant: showsChevron ? Metrics.chevronSize : 0)
        ]

        if shortcutPlacement == .leadingItemNumber {
            constraints.append(shortcutBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset))
            if image == nil {
                constraints.append(imageView.leadingAnchor.constraint(equalTo: shortcutBadge.trailingAnchor))
                constraints.append(titleLabel.leadingAnchor.constraint(
                    equalTo: shortcutBadge.trailingAnchor,
                    constant: Metrics.titleAccessorySpacing
                ))
            } else {
                constraints.append(imageView.leadingAnchor.constraint(
                    equalTo: shortcutBadge.trailingAnchor,
                    constant: Metrics.iconSpacing
                ))
                constraints.append(titleLabel.leadingAnchor.constraint(
                    equalTo: imageView.trailingAnchor,
                    constant: Metrics.iconSpacing
                ))
            }
        } else {
            constraints.append(imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset))
            constraints.append(titleLabel.leadingAnchor.constraint(
                equalTo: image == nil ? leadingAnchor : imageView.trailingAnchor,
                constant: image == nil ? leadingInset : Metrics.iconSpacing
            ))
            constraints.append(shortcutBadge.trailingAnchor.constraint(
                equalTo: shortcutButton.leadingAnchor,
                constant: -shortcutButtonSpacing
            ))
        }

        NSLayoutConstraint.activate(constraints)

        updateAppearance()
    }

    fileprivate var screenFrameForOpening: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    private func scheduleHoverOpenIfNeeded() {
        guard let onHoverOpen else { return }
        cancelHoverOpen()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isMouseInside else { return }
            onHoverOpen(self.screenFrameForOpening)
        }
        hoverOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + MainMenuPanelLayout.folderHoverOpenDelay, execute: workItem)
    }

    private func cancelHoverOpen() {
        hoverOpenWorkItem?.cancel()
        hoverOpenWorkItem = nil
    }

    @objc private func editButtonClicked(_ sender: NSButton) {
        cancelHoverOpen()
        onEdit?()
    }

    @objc private func shortcutButtonClicked(_ sender: NSButton) {
        editShortcut()
    }

    @objc private func editMenuItemClicked(_ sender: NSMenuItem) {
        cancelHoverOpen()
        onEdit?()
    }

    @objc private func editShortcutMenuItemClicked(_ sender: NSMenuItem) {
        editShortcut()
    }

    @objc private func clearShortcutMenuItemClicked(_ sender: NSMenuItem) {
        clearShortcut()
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        delete()
    }

    @objc private func deleteMenuItemClicked(_ sender: NSMenuItem) {
        delete()
    }

    private func delete() {
        cancelHoverOpen()
        onDelete?()
    }

    private func editShortcut() {
        cancelHoverOpen()
        onEditShortcut?()
    }

    private func clearShortcut() {
        cancelHoverOpen()
        onClearShortcut?()
    }

    private func updateAppearance() {
        let isEmphasized = isMouseInside || isKeyboardSelected
        layer?.backgroundColor = isEmphasized
            ? MainMenuVisualColors.hoveredRow.cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = .labelColor
        imageView.contentTintColor = isEmphasized ? .labelColor : .secondaryLabelColor
        shortcutBadge.setState(isEmphasized: isEmphasized)
        shortcutButton.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
        shortcutButton.isHidden = onEditShortcut == nil || !isEmphasized
        editButton.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
        editButton.isHidden = onEdit == nil || !isEmphasized
        deleteButton.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
        deleteButton.isHidden = onDelete == nil || !isEmphasized
        chevronView.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
    }

    #if DEBUG
    var contextMenuTitlesForTesting: [String] {
        makeContextMenu()?.items.compactMap { $0.isSeparatorItem ? nil : $0.title } ?? []
    }

    var buttonIdentifiersForTesting: [String] {
        [shortcutButton, editButton, deleteButton].compactMap { $0.identifier?.rawValue }
    }
    #endif
}

#if DEBUG
extension MainMenuPanelController {
    var mainMenuPanelContentSizeForTesting: NSSize {
        contentView.layoutSubtreeIfNeeded()
        return contentView.bounds.size
    }

    var mainMenuOneDriveStatusButtonFramesForTesting: [NSRect] {
        contentView.layoutSubtreeIfNeeded()
        return mainMenuOneDriveStatusButtonsForTesting.map { button in
            button.superview?.convert(button.frame, to: contentView) ?? .zero
        }
    }

    var mainMenuToolbarButtonFramesForTesting: [String: NSRect] {
        contentView.layoutSubtreeIfNeeded()
        return Dictionary(uniqueKeysWithValues: collectButtons(in: contentView).compactMap { button in
            guard let identifier = button.identifier?.rawValue else { return nil }
            return (identifier, button.superview?.convert(button.frame, to: contentView) ?? .zero)
        })
    }

    func mainMenuToolbarToolTipForTesting(identifier: String) -> String? {
        collectButtons(in: contentView)
            .first { $0.identifier?.rawValue == identifier }?
            .toolTip
    }

    var mainMenuHeaderToolTipsForTesting: [String: String] {
        contentView.subviews
            .compactMap { $0 as? MainMenuEmbeddedHeaderView }
            .first?
            .toolTipsForTesting ?? [:]
    }

    func mainMenuRowToolTipForTesting(title: String) -> String? {
        if let toolTip = rowViewsForTesting.first(where: { $0.rowTitleForTesting == title })?.toolTip {
            return toolTip
        }
        return collectViews(in: contentView)
            .compactMap { $0 as? HistoryMenuRowView }
            .first { $0.textValuesForTesting.contains(title) }?
            .toolTip
    }

    var mainMenuEmbeddedSectionFramesForTesting: [String: NSRect]? {
        contentView.layoutSubtreeIfNeeded()
        let views = collectViews(in: contentView)
        let identifiers = [
            "header": "mainMenuHeaderBlock",
            "content": "mainMenuContentBlock",
            "footer": "mainMenuFooterDock"
        ]
        var frames = [String: NSRect]()
        for (key, identifier) in identifiers {
            guard let view = views.first(where: { $0.identifier?.rawValue == identifier }) else {
                return nil
            }
            frames[key] = view.superview?.convert(view.frame, to: contentView) ?? .zero
        }
        return frames
    }

    var mainMenuEmbeddedSeparatorCountForTesting: Int {
        contentView.layoutSubtreeIfNeeded()
        return collectViews(in: contentView)
            .filter { $0.identifier?.rawValue == "mainMenuSeparator" }
            .count
    }

    var mainMenuSearchFieldFrameForTesting: NSRect? {
        contentView.layoutSubtreeIfNeeded()
        guard searchField.superview != nil else { return nil }
        return searchField.superview?.convert(searchField.frame, to: contentView) ?? .zero
    }

    var mainMenuFirstVisibleRowFrameForTesting: NSRect? {
        contentView.layoutSubtreeIfNeeded()
        return collectVisibleRowViews(in: contentView).first.map { row in
            row.superview?.convert(row.frame, to: contentView) ?? .zero
        }
    }

    var mainMenuSelectedRowFrameForTesting: NSRect? {
        contentView.layoutSubtreeIfNeeded()
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex),
              let view = keyboardEntries[selectedKeyboardEntryIndex].view() else {
            return nil
        }
        return view.superview?.convert(view.frame, to: contentView) ?? .zero
    }

    var mainMenuEmbeddedHeaderFramesForTesting: [String: NSRect]? {
        contentView.layoutSubtreeIfNeeded()
        guard let headerView = contentView.subviews.compactMap({ $0 as? MainMenuEmbeddedHeaderView }).first else {
            return nil
        }
        return headerView.framesForTesting.mapValues { headerView.convert($0, to: contentView) }
    }

    var mainMenuEmbeddedHeaderCornerRadiiForTesting: [String: CGFloat]? {
        contentView.layoutSubtreeIfNeeded()
        guard let headerView = contentView.subviews.compactMap({ $0 as? MainMenuEmbeddedHeaderView }).first else {
            return nil
        }
        return headerView.cornerRadiiForTesting
    }

    var mainMenuButtonIdentifiersForTesting: [String] {
        contentView.layoutSubtreeIfNeeded()
        return collectButtons(in: contentView).compactMap { $0.identifier?.rawValue }
    }

    var mainMenuButtonImageNamesForTesting: [String: String] {
        contentView.layoutSubtreeIfNeeded()
        return Dictionary(uniqueKeysWithValues: collectButtons(in: contentView).compactMap { button in
            guard let identifier = button.identifier?.rawValue,
                  let imageName = button.image?.name() else { return nil }
            return (identifier, imageName)
        })
    }

    func mainMenuActionRowFrameForTesting(title: String) -> NSRect? {
        rowViewsForTesting
            .first { $0.rowKindForTesting == .action && $0.rowTitleForTesting == title }
            .map { $0.superview?.convert($0.frame, to: contentView) ?? .zero }
    }

    func mainMenuSnippetRowFrameForTesting(title: String) -> NSRect? {
        rowViewsForTesting
            .first { $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title }
            .map { $0.superview?.convert($0.frame, to: contentView) ?? .zero }
    }

    func mainMenuSnippetTitleFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleFrameForTesting
    }

    func mainMenuActionTitleFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .action && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleFrameForTesting
    }

    func mainMenuRowShortcutFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: { $0.rowTitleForTesting == title }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.shortcutFrameForTesting
    }

    func mainMenuRowShortcutTextForTesting(title: String) -> String? {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .shortcutTextForTesting
    }

    func mainMenuSnippetTitleAvailableWidthForTesting(title: String) -> CGFloat? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleAvailableWidthForTesting
    }

    func mainMenuActionTitleAvailableWidthForTesting(title: String) -> CGFloat? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .action && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleAvailableWidthForTesting
    }

    func mainMenuRowContextMenuTitlesForTesting(title: String) -> [String] {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .contextMenuTitlesForTesting ?? []
    }

    func mainMenuRowButtonIdentifiersForTesting(title: String) -> [String] {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .buttonIdentifiersForTesting ?? []
    }

    func mainMenuRowHasImageForTesting(title: String) -> Bool {
        rowViewsForTesting.first { $0.rowTitleForTesting == title }?.hasImageForTesting ?? false
    }

    func performMainMenuRowDoubleClickForTesting(title: String) {
        rowViewsForTesting.first { $0.rowTitleForTesting == title }?.performDoubleClickForTesting()
    }

    var mainMenuPasswordEditorIsVisibleForTesting: Bool { passwordVaultEditorState != nil }

    var mainMenuOneDriveStatusTintColorForTesting: NSColor? {
        mainMenuOneDriveStatusButtonsForTesting.first?.contentTintColor
    }

    var mainMenuOneDriveStatusToolTipForTesting: String? {
        mainMenuOneDriveStatusButtonsForTesting.first?.toolTip
    }

    func performMainMenuOneDriveStatusClickForTesting() {
        mainMenuOneDriveStatusButtonsForTesting.first?.performClick(nil)
    }

    func performMainMenuSearchClickForTesting() {
        collectButtons(identifier: "mainMenuSearchButton").first?.performClick(nil)
    }

    func updateMainMenuSearchQueryForTesting(_ query: String) {
        updateSearchQuery(query)
    }

    var selectedMainMenuTitleForTesting: String? {
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else { return nil }
        return keyboardEntries[selectedKeyboardEntryIndex].title
    }

    var mainMenuVisibleRowTitlesForTesting: [String] {
        visibleMainMenuRowTitles
    }

    var mainMenuSelectedModeForTesting: String {
        switch selectedMode {
        case .history:
            return "history"
        case .snippets:
            return "snippets"
        case .passwordVault:
            return "passwordVault"
        }
    }

    var mainMenuSnippetFolderTitleForTesting: String? {
        currentSnippetFolderTitle
    }

    var mainMenuExpandedSnippetFolderIDForTesting: SnippetFolder.ID? {
        expandedSnippetFolderID
    }

    var mainMenuEditorTitleForTesting: String? {
        switch inlineEditorState {
        case let .snippetFolder(_, _, draftTitle, _):
            return draftTitle
        case let .snippet(_, _, _, draftTitle, _, _):
            return draftTitle
        case let .newSnippetFolder(draftTitle, _), let .newSnippet(_, draftTitle, _, _):
            return draftTitle
        case .history, nil:
            return nil
        }
    }

    var mainMenuEditorContentForTesting: String? {
        switch inlineEditorState {
        case let .history(_, _, draftText, _):
            return draftText
        case let .snippet(_, _, _, _, draftContent, _):
            return draftContent
        case let .newSnippet(_, _, draftContent, _):
            return draftContent
        case .snippetFolder, .newSnippetFolder, nil:
            return nil
        }
    }

    var mainMenuEditorErrorForTesting: String? {
        switch inlineEditorState {
        case let .history(_, _, _, error),
             let .snippetFolder(_, _, _, error),
             let .snippet(_, _, _, _, _, error),
             let .newSnippetFolder(_, error),
             let .newSnippet(_, _, _, error):
            return error
        case nil:
            return nil
        }
    }

    var mainMenuEditorButtonTitlesForTesting: [String] {
        inlineEditorView?.buttonTitlesForTesting ?? []
    }

    var isMainMenuSearchFieldVisibleForTesting: Bool {
        isSearchVisible
    }

    var isMainMenuSearchFieldFocusedForTesting: Bool {
        panel?.firstResponder === searchField || searchField.currentEditor() != nil
    }

    var contentBackgroundAlphaForTesting: CGFloat {
        CGFloat(contentView.layer?.backgroundColor?.alpha ?? 0)
    }

    var contentBackgroundLuminanceForTesting: CGFloat {
        guard let cgColor = contentView.layer?.backgroundColor,
              let components = cgColor.components else {
            return 1
        }
        let red = components.count >= 3 ? components[0] : components[0]
        let green = components.count >= 3 ? components[1] : components[0]
        let blue = components.count >= 3 ? components[2] : components[0]
        return red * 0.2126 + green * 0.7152 + blue * 0.0722
    }

    func selectMainMenuItemForTesting(title: String) {
        guard let index = keyboardEntries.firstIndex(where: { $0.title == title }) else { return }
        selectKeyboardEntry(at: index, triggerChildPanel: false)
    }

    func beginEditingHistoryForTesting(id: PasteboardHistory.ID) {
        beginEditingHistory(id)
    }

    func beginEditingSnippetFolderForTesting(id: SnippetFolder.ID) {
        beginEditingSnippetFolder(id)
    }

    func beginEditingSnippetForTesting(id: Snippet.ID) {
        beginEditingSnippet(id)
    }

    func beginCreatingSnippetForTesting() { beginCreatingSnippet() }
    func beginCreatingSnippetFolderForTesting() { beginCreatingSnippetFolder() }
    func toggleWorkspaceEditingForTesting() { toggleWorkspaceEditing() }

    func beginEditingSnippetFolderShortcutForTesting(id: SnippetFolder.ID) {
        beginEditingFolderShortcut(id)
    }

    var isMainMenuFolderShortcutEditorVisibleForTesting: Bool {
        folderShortcutEditorView?.superview != nil
    }

    func recordMainMenuFolderShortcutForTesting(_ keyCombo: KeyCombo) {
        folderShortcutEditorView?.recordKeyComboForTesting(keyCombo)
    }

    func clearMainMenuFolderShortcutForTesting() {
        folderShortcutEditorView?.clearForTesting()
    }

    func updateMainMenuEditorDraftForTesting(title: String? = nil, content: String? = nil) {
        inlineEditorView?.updateDraft(title: title, content: content)
        switch inlineEditorState {
        case let .history(id, originalText, draftText, error):
            inlineEditorState = .history(
                id,
                originalText: originalText,
                draftText: content ?? draftText,
                error: error
            )
        case let .snippetFolder(id, originalTitle, draftTitle, error):
            inlineEditorState = .snippetFolder(
                id,
                originalTitle: originalTitle,
                draftTitle: title ?? draftTitle,
                error: error
            )
        case let .snippet(id, originalTitle, originalContent, draftTitle, draftContent, error):
            inlineEditorState = .snippet(
                id,
                originalTitle: originalTitle,
                originalContent: originalContent,
                draftTitle: title ?? draftTitle,
                draftContent: content ?? draftContent,
                error: error
            )
        case let .newSnippetFolder(draftTitle, error):
            inlineEditorState = .newSnippetFolder(draftTitle: title ?? draftTitle, error: error)
        case let .newSnippet(folderID, draftTitle, draftContent, error):
            inlineEditorState = .newSnippet(
                folderID, draftTitle: title ?? draftTitle, draftContent: content ?? draftContent, error: error
            )
        case nil:
            break
        }
    }

    @discardableResult
    func commitMainMenuEditorForTesting() -> Bool {
        commitInlineEditorFromCurrentDraft()
    }

    func discardMainMenuEditorForTesting() {
        discardInlineEditor()
    }

    func setMainMenuDeleteConfirmationRunnerForTesting(
        _ runner: @escaping (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult
    ) {
        deleteConfirmationRunner = runner
    }

    func handleMainMenuNavigationForTesting(_ event: NSEvent) -> Bool {
        handleKeyboardNavigation(event)
    }

    private var rowViewsForTesting: [MainMenuPanelRowView] {
        contentView.layoutSubtreeIfNeeded()
        return collectRowViews(in: contentView)
    }

    private var mainMenuOneDriveStatusButtonsForTesting: [NSButton] {
        collectButtons(identifier: "mainMenuOneDriveStatusButton")
    }

    private func collectButtons(identifier: String) -> [NSButton] {
        collectButtons(in: contentView)
            .filter { $0.identifier?.rawValue == identifier && !$0.isHidden }
    }

    private func collectButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        for subview in view.subviews {
            buttons.append(contentsOf: collectButtons(in: subview))
        }
        return buttons
    }

    private func collectViews(in view: NSView) -> [NSView] {
        var views = view.subviews
        for subview in view.subviews {
            views.append(contentsOf: collectViews(in: subview))
        }
        return views
    }

    private func collectRowViews(in view: NSView) -> [MainMenuPanelRowView] {
        var rows = view.subviews.compactMap { $0 as? MainMenuPanelRowView }
        for subview in view.subviews {
            rows.append(contentsOf: collectRowViews(in: subview))
        }
        return rows
    }

    private func collectVisibleRowViews(in view: NSView) -> [NSView] {
        var rows = view.subviews.filter {
            $0 is HistoryMenuRowView ||
                $0 is MainMenuPanelRowView ||
                $0 is MainMenuEmbeddedEmptyRowView
        }
        for subview in view.subviews {
            rows.append(contentsOf: collectVisibleRowViews(in: subview))
        }
        return rows
    }
}

private extension MainMenuEmbeddedHeaderView {
    var framesForTesting: [String: NSRect] {
        var frames = [
            "title": titleLabel.frame
        ]
        if typeButton.superview != nil {
            frames["typeFilter"] = typeButton.frame
        }
        if previousButton.superview != nil {
            frames["previous"] = previousButton.frame
        }
        if subtitleLabel.superview != nil {
            frames["page"] = subtitleLabel.frame
            let textFrame = subtitleLabel.cell?.drawingRect(forBounds: subtitleLabel.bounds) ?? subtitleLabel.bounds
            frames["pageText"] = subtitleLabel.convert(textFrame, to: self)
        }
        if nextButton.superview != nil {
            frames["next"] = nextButton.frame
        }
        if backButton.superview != nil && !backButton.isHidden {
            frames["back"] = backButton.frame
        }
        return frames
    }

    var cornerRadiiForTesting: [String: CGFloat] {
        [
            "typeFilter": typeButton.layer?.cornerRadius ?? 0,
            "previous": previousButton.layer?.cornerRadius ?? 0,
            "next": nextButton.layer?.cornerRadius ?? 0
        ]
    }

    var toolTipsForTesting: [String: String] {
        [
            "typeFilter": typeButton.toolTip,
            "previous": previousButton.toolTip,
            "next": nextButton.toolTip
        ].compactMapValues { $0 }
    }
}

private extension MainMenuPanelRowView {
    var rowTitleForTesting: String {
        rowTitle
    }

    var rowKindForTesting: RowKind {
        rowKind
    }

    var titleFrameForTesting: NSRect {
        titleLabel.frame
    }

    var shortcutFrameForTesting: NSRect {
        shortcutBadge.frame
    }

    var shortcutTextForTesting: String? {
        shortcutBadge.shortcutText
    }

    var hasImageForTesting: Bool { imageView.image != nil && imageView.superview != nil }

    func performDoubleClickForTesting() { onDoubleClick?() }

    var titleAvailableWidthForTesting: CGFloat {
        let trailingLimit: CGFloat
        if shortcutPlacement == .trailingCommand, !shortcutBadge.isHidden {
            trailingLimit = shortcutBadge.frame.minX - Metrics.titleAccessorySpacing
        } else if !shortcutButton.isHidden {
            trailingLimit = shortcutButton.frame.minX - Metrics.titleAccessorySpacing
        } else if !editButton.isHidden {
            trailingLimit = editButton.frame.minX - Metrics.titleAccessorySpacing
        } else if !deleteButton.isHidden {
            trailingLimit = deleteButton.frame.minX - Metrics.titleAccessorySpacing
        } else if !chevronView.isHidden {
            trailingLimit = chevronView.frame.minX - Metrics.titleAccessorySpacing
        } else {
            trailingLimit = bounds.maxX - Metrics.horizontalInset
        }
        return max(0, trailingLimit - titleLabel.frame.minX)
    }
}
#endif
