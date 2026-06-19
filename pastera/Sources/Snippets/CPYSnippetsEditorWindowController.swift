//
//  CPYSnippetsEditorWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/05/18.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Dependencies
import KeyHolder
import Magnet
import AEXML

private final class PasteraSnippetEditorWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class CPYSnippetsEditorWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = CPYSnippetsEditorWindowController()

    enum Layout {
        static let defaultWindowSize = NSSize(width: 680, height: 400)
        static let minimumWindowSize = NSSize(width: 600, height: 340)
        static let toolbarHeight: CGFloat = 48
        static let toolbarInset: CGFloat = 12
        static let splitInset: CGFloat = 8
        static let leftPaneWidth: CGFloat = 220
        static let detailInset: CGFloat = 8
        static let outlineRowHeight: CGFloat = 25
        static let folderShortcutHeight: CGFloat = 42
    }

    private let rootView = NSView()
    private let toolbarView = NSView()
    private let toolbarScrollView = NSScrollView()
    private let toolbarStackView = NSStackView()
    private var toolbarButtons = [PasteraToolbarButton]()
    private let splitView = CPYSplitView()
    private let outlineView = NSOutlineView()
    private let outlineScrollView = NSScrollView()
    private let folderSettingView = NSView()
    private let folderTitleTextField = NSTextField()
    private let folderShortcutRecordView = RecordView(frame: .zero)
    private let textView = CPYPlaceHolderTextView(frame: .zero)
    private let textScrollView = NSScrollView()
    private let emptyStateLabel = NSTextField(labelWithString: "")

    @Dependency(\.snippetRepository)
    private var snippetRepository
    private var folders = [EditorSnippetFolder]()
    private var didLoadFolders = false
    private var hasShownWindow = false
    private var defaultsObserver: NSObjectProtocol?
    private var isEditingOutlineTitle = false
    private var selectedFolder: EditorSnippetFolder? {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        return item as? EditorSnippetFolder ?? outlineView.parent(forItem: item) as? EditorSnippetFolder
    }

    // MARK: - Window Life Cycle
    init() {
        let window = PasteraSnippetEditorWindow(
            contentRect: NSRect(origin: .zero, size: Layout.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Pastera - Snippet Editor")
        window.minSize = Layout.minimumWindowSize
        super.init(window: window)
        window.onKeyDown = { [weak self] event in
            self?.handleKeyboardEvent(event) ?? false
        }
        setupWindow()
        installOpacityObserver()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        loadFoldersIfNeeded()
        if !hasShownWindow {
            window?.center()
            hasShownWindow = true
        }
        CPYWindowAppearance.apply(to: window)
        refreshAppearanceColors()
        window?.makeKeyAndOrderFront(self)
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }
}

// MARK: - IBActions
extension CPYSnippetsEditorWindowController {
    @IBAction private func addSnippetButtonTapped(_ sender: AnyObject) {
        guard let folder = selectedFolder, let snippet = snippetRepository.insertSnippet(to: folder.id) else {
            NSSound.beep()
            return
        }
        let editorSnippet = EditorSnippet(snippet: snippet)
        folder.snippets.append(editorSnippet)
        outlineView.reloadData()
        outlineView.expandItem(folder)
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: editorSnippet)), byExtendingSelection: false)
        changeItemFocus()
        beginEditingSelectedOutlineTitleOnNextRunLoop()
    }

    @IBAction private func addFolderButtonTapped(_ sender: AnyObject) {
        guard let folder = snippetRepository.insertFolder() else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.hotKeyService.registerDefaultSnippetHotKeyIfAvailable(
            forIdentifier: folder.id.uuidString
        )
        let editorFolder = EditorSnippetFolder(folder: folder)
        folders.append(editorFolder)
        outlineView.reloadData()
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: editorFolder)), byExtendingSelection: false)
        changeItemFocus()
        beginEditingSelectedOutlineTitleOnNextRunLoop()
    }

    @IBAction private func deleteButtonTapped(_ sender: AnyObject) {
        deleteSelectedItem(requiresConfirmation: true)
    }

    private func deleteSelectedItem(requiresConfirmation: Bool) {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep()
            return
        }

        if requiresConfirmation {
            let result = PasteraConfirmationController.runModal(options: PasteraConfirmationOptions(
                title: String(localized: "Delete Item"),
                message: String(localized: "Are you sure want to delete this item?"),
                confirmTitle: String(localized: "Delete Item"),
                cancelTitle: String(localized: "Cancel"),
                isDestructive: true
            ))
            guard result.confirmed else { return }
        }

        if let folder = item as? EditorSnippetFolder {
            folders.removeAll(where: { $0.id == folder.id })
            snippetRepository.deleteFolder(folder.id)
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: folder.id.uuidString)
        } else if let snippet = item as? EditorSnippet, let folder = outlineView.parent(forItem: item) as? EditorSnippetFolder {
            folder.snippets.removeAll(where: { $0.id == snippet.id })
            snippetRepository.deleteSnippet(snippet.id)
        }
        outlineView.reloadData()
        changeItemFocus()
    }

    @IBAction private func changeStatusButtonTapped(_ sender: AnyObject) {
        toggleSelectedItemStatus()
    }

    private func toggleSelectedItemStatus() {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep()
            return
        }
        if let folder = item as? EditorSnippetFolder {
            folder.isEnabled.toggle()
            snippetRepository.updateFolderIsEnabled(folder.id, isEnabled: folder.isEnabled)
        } else if let snippet = item as? EditorSnippet {
            snippet.isEnabled.toggle()
            snippetRepository.updateSnippetIsEnabled(snippet.id, isEnabled: snippet.isEnabled)
        }
        outlineView.reloadData()
        changeItemFocus()
    }

    @IBAction private func importSnippetButtonTapped(_ sender: AnyObject) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.allowedFileTypes = [Constants.Xml.fileType]
        let returnCode = panel.runModal()

        if returnCode != NSApplication.ModalResponse.OK { return }

        let fileURLs = panel.urls
        guard let url = fileURLs.first else { return }
        guard let data = try? Data(contentsOf: url) else { return }

        do {
            var options = AEXMLOptions()
            options.parserSettings.shouldTrimWhitespace = false
            let xmlDocument = try AEXMLDocument(xml: data, options: options)
            let folders = xmlDocument[Constants.Xml.rootElement]
                .children
                .map { folderElement in
                    let title = folderElement[Constants.Xml.titleElement].value ?? "untitled folder"
                    let snippets = folderElement[Constants.Xml.snippetsElement][Constants.Xml.snippetElement]
                        .all?
                        .map { (title: $0[Constants.Xml.titleElement].value ?? "untitled snippet", content: $0[Constants.Xml.contentElement].value ?? "") } ?? []
                    return (title: title, snippets: snippets)
                }
            guard let folderDetails = snippetRepository.insertFolders(folders) else {
                NSSound.beep()
                return
            }
            self.folders.append(contentsOf: folderDetails.map(EditorSnippetFolder.init))
            outlineView.reloadData()
        } catch {
            NSSound.beep()
        }
    }

    @IBAction private func exportSnippetButtonTapped(_ sender: AnyObject) {
        let xmlDocument = AEXMLDocument()
        let rootElement = xmlDocument.addChild(name: Constants.Xml.rootElement)

        folders.forEach { folder in
            let folderElement = rootElement.addChild(name: Constants.Xml.folderElement)

            folderElement.addChild(name: Constants.Xml.titleElement, value: folder.title)

            let snippetsElement = folderElement.addChild(name: Constants.Xml.snippetsElement)
            folder.snippets
                .forEach { snippet in
                    let snippetElement = snippetsElement.addChild(name: Constants.Xml.snippetElement)
                    snippetElement.addChild(name: Constants.Xml.titleElement, value: snippet.title)
                    snippetElement.addChild(name: Constants.Xml.contentElement, value: snippet.content)
                }
        }

        let panel = NSSavePanel()
        panel.accessoryView = nil
        panel.canSelectHiddenExtension = true
        panel.allowedFileTypes = [Constants.Xml.fileType]
        panel.allowsOtherFileTypes = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.nameFieldStringValue = "snippets"
        let returnCode = panel.runModal()

        if returnCode != NSApplication.ModalResponse.OK { return }

        guard let data = xmlDocument.xml.data(using: String.Encoding.utf8) else { return }
        guard let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }
}

// MARK: - Item Selected
private extension CPYSnippetsEditorWindowController {
    struct ToolbarItem {
        let title: String
        let symbolName: String
        let action: Selector
    }

    func setupWindow() {
        window?.collectionBehavior = .canJoinAllSpaces
        CPYWindowAppearance.apply(to: window)
        setupRootView()
        setupToolbar()
        setupSplitView()
        setupOutlineView()
        setupDetailViews()
        installKeyViewLoop()
    }

    func setupRootView() {
        let tokens = currentColorSet()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        window?.contentView = rootView

        toolbarView.wantsLayer = true
        toolbarView.layer?.backgroundColor = tokens.surface.cgColor
        splitView.separatorColor = tokens.separator

        [toolbarView, splitView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            toolbarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: Layout.toolbarHeight),

            splitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Layout.splitInset),
            splitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Layout.splitInset),
            splitView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: Layout.splitInset),
            splitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Layout.splitInset)
        ])
    }

    func setupToolbar() {
        toolbarStackView.orientation = .horizontal
        toolbarStackView.spacing = 7
        toolbarStackView.alignment = .centerY
        toolbarStackView.translatesAutoresizingMaskIntoConstraints = true
        toolbarScrollView.translatesAutoresizingMaskIntoConstraints = false
        toolbarScrollView.drawsBackground = false
        toolbarScrollView.backgroundColor = .clear
        toolbarScrollView.borderType = .noBorder
        toolbarScrollView.hasVerticalScroller = false
        toolbarScrollView.hasHorizontalScroller = true
        toolbarScrollView.autohidesScrollers = true
        let toolbarDocumentView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 1, height: Layout.toolbarHeight)))
        toolbarDocumentView.addSubview(toolbarStackView)
        toolbarScrollView.documentView = toolbarDocumentView
        toolbarView.addSubview(toolbarScrollView)

        let buttons = [
            ToolbarItem(title: String(localized: "Add Snippet"), symbolName: "doc.badge.plus", action: #selector(addSnippetButtonTapped(_:))),
            ToolbarItem(title: String(localized: "Add Folder"), symbolName: "folder.badge.plus", action: #selector(addFolderButtonTapped(_:))),
            ToolbarItem(title: String(localized: "Delete"), symbolName: "trash", action: #selector(deleteButtonTapped(_:))),
            ToolbarItem(title: String(localized: "Enable/Disable"), symbolName: "power", action: #selector(changeStatusButtonTapped(_:))),
            ToolbarItem(title: String(localized: "Import"), symbolName: "square.and.arrow.down", action: #selector(importSnippetButtonTapped(_:))),
            ToolbarItem(title: String(localized: "Export"), symbolName: "square.and.arrow.up", action: #selector(exportSnippetButtonTapped(_:)))
        ]

        buttons.forEach { item in
            let button = PasteraToolbarButton(title: item.title, symbolName: item.symbolName, target: self, action: item.action)
            toolbarButtons.append(button)
            toolbarStackView.addArrangedSubview(button)
        }
        toolbarDocumentView.frame.size = NSSize(width: toolbarStackView.fittingSize.width, height: Layout.toolbarHeight); toolbarStackView.frame = toolbarDocumentView.bounds

        NSLayoutConstraint.activate([
            toolbarScrollView.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: Layout.toolbarInset),
            toolbarScrollView.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -Layout.toolbarInset),
            toolbarScrollView.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            toolbarScrollView.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor)
        ])
    }

    func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self

        let leftPane = NSView()
        let rightPane = NSView()
        [leftPane, rightPane].forEach {
            $0.wantsLayer = true
            $0.layer?.backgroundColor = NSColor.clear.cgColor
            splitView.addArrangedSubview($0)
        }

        leftPane.translatesAutoresizingMaskIntoConstraints = false
        leftPane.widthAnchor.constraint(equalToConstant: Layout.leftPaneWidth).isActive = true
    }

    func setupOutlineView() {
        guard let leftPane = splitView.arrangedSubviews.first else { return }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snippet"))
        column.title = ""
        column.isEditable = true
        column.dataCell = CPYSnippetsEditorCell(textCell: "")

        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.frame = NSRect(x: 0, y: 0, width: Layout.leftPaneWidth - 6, height: 320)
        outlineView.rowHeight = Layout.outlineRowHeight
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)
        outlineView.backgroundColor = .clear
        outlineView.allowsEmptySelection = false
        outlineView.allowsMultipleSelection = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(outlineItemDoubleClicked(_:))
        outlineView.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)])

        outlineScrollView.translatesAutoresizingMaskIntoConstraints = false
        outlineScrollView.drawsBackground = false
        outlineScrollView.backgroundColor = .clear
        outlineScrollView.borderType = .noBorder
        outlineScrollView.hasVerticalScroller = true
        outlineScrollView.documentView = outlineView
        leftPane.addSubview(outlineScrollView)

        NSLayoutConstraint.activate([
            outlineScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            outlineScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: -6),
            outlineScrollView.topAnchor.constraint(equalTo: leftPane.topAnchor),
            outlineScrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor)
        ])
    }

    func setupDetailViews() {
        guard splitView.arrangedSubviews.count > 1 else { return }
        let detailPane = splitView.arrangedSubviews[1]
        setupFolderSettingView()
        setupTextEditor()

        emptyStateLabel.stringValue = String(localized: "Select a snippet or folder")
        emptyStateLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center

        [folderSettingView, textScrollView, emptyStateLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            detailPane.addSubview($0)
        }

        NSLayoutConstraint.activate([
            folderSettingView.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: Layout.detailInset),
            folderSettingView.trailingAnchor.constraint(lessThanOrEqualTo: detailPane.trailingAnchor, constant: -Layout.detailInset),
            folderSettingView.topAnchor.constraint(equalTo: detailPane.topAnchor),
            folderSettingView.heightAnchor.constraint(equalToConstant: Layout.folderShortcutHeight),

            textScrollView.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: Layout.detailInset),
            textScrollView.trailingAnchor.constraint(equalTo: detailPane.trailingAnchor, constant: -Layout.detailInset),
            textScrollView.topAnchor.constraint(equalTo: detailPane.topAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: detailPane.bottomAnchor),

            emptyStateLabel.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: Layout.detailInset),
            emptyStateLabel.trailingAnchor.constraint(equalTo: detailPane.trailingAnchor, constant: -Layout.detailInset),
            emptyStateLabel.centerYAnchor.constraint(equalTo: detailPane.centerYAnchor)
        ])
        changeItemFocus()
    }

    func setupFolderSettingView() {
        let tokens = currentColorSet()
        folderSettingView.wantsLayer = true
        folderSettingView.layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        folderSettingView.layer?.backgroundColor = tokens.surface.cgColor
        folderSettingView.layer?.borderColor = tokens.separator.cgColor
        folderSettingView.layer?.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth

        let shortcutLabel = NSTextField(labelWithString: String(localized: "Shortcut"))
        shortcutLabel.font = .systemFont(ofSize: 12, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor

        folderShortcutRecordView.delegate = self
        PasteraRecordViewStyler.apply(to: folderShortcutRecordView, colors: tokens)

        [shortcutLabel, folderShortcutRecordView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            folderSettingView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            shortcutLabel.leadingAnchor.constraint(equalTo: folderSettingView.leadingAnchor, constant: 10),
            shortcutLabel.centerYAnchor.constraint(equalTo: folderSettingView.centerYAnchor),

            folderShortcutRecordView.leadingAnchor.constraint(equalTo: shortcutLabel.trailingAnchor, constant: 8),
            folderShortcutRecordView.trailingAnchor.constraint(equalTo: folderSettingView.trailingAnchor, constant: -8),
            folderShortcutRecordView.centerYAnchor.constraint(equalTo: folderSettingView.centerYAnchor),
            folderShortcutRecordView.widthAnchor.constraint(equalToConstant: 210),
            folderShortcutRecordView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    func setupTextEditor() {
        textView.font = NSFont.systemFont(ofSize: 13.5)
        textView.frame = NSRect(x: 0, y: 0, width: 420, height: 320)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.isRichText = false
        textView.delegate = self
        textView.placeHolderText = String(localized: "Please fill in the contents of the snippet")
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textScrollView.drawsBackground = true
        textScrollView.backgroundColor = currentColorSet().elevatedSurface
        textScrollView.borderType = .lineBorder
        textScrollView.hasVerticalScroller = true
        textScrollView.documentView = textView
        PasteraSemanticViewStyler.apply(to: textView, appearance: window?.effectiveAppearance)
    }

    func installOpacityObserver() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: CPYWindowAppearance.opacityDidChangeNotification,
            object: AppEnvironment.current.defaults,
            queue: .main
        ) { [weak self] _ in
            CPYWindowAppearance.apply(to: self?.window)
            self?.refreshAppearanceColors()
        }
    }

    func refreshAppearanceColors() {
        let tokens = currentColorSet()
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        toolbarView.layer?.backgroundColor = tokens.surface.cgColor
        splitView.separatorColor = tokens.separator
        outlineView.backgroundColor = .clear
        outlineScrollView.backgroundColor = .clear
        folderSettingView.layer?.backgroundColor = tokens.surface.cgColor
        folderSettingView.layer?.borderColor = tokens.separator.cgColor
        PasteraRecordViewStyler.apply(to: folderShortcutRecordView, colors: tokens)
        textScrollView.backgroundColor = tokens.elevatedSurface
        textView.backgroundColor = tokens.elevatedSurface
        emptyStateLabel.textColor = .secondaryLabelColor
        PasteraSemanticViewStyler.apply(to: rootView, appearance: window?.effectiveAppearance)
        outlineView.reloadData()
    }

    func currentColorSet() -> PasteraDesignTokens.ColorSet {
        PasteraDesignTokens.colors(
            for: window?.effectiveAppearance,
            opacity: CGFloat(CPYWindowAppearance.opacity())
        )
    }

    func loadFoldersIfNeeded() {
        guard !didLoadFolders else { return }
        didLoadFolders = true
        folders = snippetRepository.fetchFolderDetails().map(EditorSnippetFolder.init)
        outlineView.reloadData()
        if let folder = folders.first {
            outlineView.expandItem(folder)
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
        }
        changeItemFocus()
    }

    func changeItemFocus() {
        // Reset TextView Undo/Redo history
        textView.undoManager?.removeAllActions()
        installKeyViewLoop()
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            folderSettingView.isHidden = true
            textScrollView.isHidden = true
            emptyStateLabel.isHidden = false
            folderShortcutRecordView.keyCombo = nil
            return
        }
        if let folder = item as? EditorSnippetFolder {
            textView.string = ""
            folderShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.id.uuidString)
            folderSettingView.isHidden = false
            textScrollView.isHidden = true
            emptyStateLabel.isHidden = true
        } else if let snippet = item as? EditorSnippet {
            textView.string = snippet.content
            folderShortcutRecordView.keyCombo = nil
            folderSettingView.isHidden = true
            textScrollView.isHidden = false
            emptyStateLabel.isHidden = true
        }
    }

    @objc func outlineItemDoubleClicked(_ sender: NSOutlineView) {
        beginEditingOutlineTitle(at: sender.clickedRow)
    }

    func beginEditingSelectedOutlineTitleOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.beginEditingOutlineTitle(at: self?.outlineView.selectedRow ?? -1)
        }
    }

    func beginEditingOutlineTitle(at row: Int) {
        guard row >= 0, row < outlineView.numberOfRows else { return }
        isEditingOutlineTitle = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    func shortcutText(for item: Any) -> String? {
        if let folder = item as? EditorSnippetFolder {
            return PasteraShortcutFormatter.string(
                for: AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.id.uuidString)
            )
        }

        guard let snippet = item as? EditorSnippet,
              snippet.isEnabled,
              let folder = folders.first(where: { $0.id == snippet.folderID }) else {
            return nil
        }

        let enabledSnippets = folder.snippets.filter(\.isEnabled)
        guard let shortcutIndex = enabledSnippets.firstIndex(where: { $0.id == snippet.id }) else {
            return nil
        }
        return numericShortcutText(forRowIndex: shortcutIndex)
    }

    func numericShortcutText(forRowIndex index: Int) -> String? {
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        return PasteraShortcutFormatter.numericString(forRowIndex: index, startsAtZero: startsAtZero)
    }

    func installKeyViewLoop() {
        let detailControl: NSView = folderSettingView.isHidden ? textView : folderShortcutRecordView
        let chain: [NSView] = toolbarButtons + [outlineView, detailControl]
        guard chain.count > 1 else { return }
        for index in chain.indices {
            chain[index].nextKeyView = chain[(index + 1) % chain.count]
        }
    }

    func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 48, !event.modifierFlags.contains(.option) {
            let chain: [NSView] = toolbarButtons + [outlineView, folderSettingView.isHidden ? textView : folderShortcutRecordView]
            guard let responder = window?.firstResponder as? NSView,
                  let index = chain.firstIndex(where: { responder === $0 || responder.isDescendant(of: $0) }) else { return false }
            let offset = event.modifierFlags.contains(.shift) ? -1 : 1
            window?.makeFirstResponder(chain[(index + offset + chain.count) % chain.count])
            return true
        }
        if let button = window?.firstResponder as? PasteraToolbarButton {
            switch event.keyCode {
            case 36, 49, 76:
                button.performClick(nil)
                return true
            default:
                return false
            }
        }

        guard shouldHandleOutlineKeyEvent else { return false }

        switch event.keyCode {
        case 36, 76:
            beginEditingOutlineTitle(at: outlineView.selectedRow)
            return true
        case 49:
            toggleSelectedItemStatus()
            return true
        case 51:
            deleteSelectedItem(requiresConfirmation: false)
            return true
        case 123:
            collapseSelectedOutlineItem()
            return true
        case 124:
            expandSelectedOutlineItem()
            return true
        default:
            return false
        }
    }

    var shouldHandleOutlineKeyEvent: Bool {
        guard outlineView.selectedRow >= 0 else { return false }
        guard let firstResponder = window?.firstResponder as? NSView else { return true }
        if firstResponder === outlineView { return true }
        if firstResponder === textView || firstResponder === folderShortcutRecordView { return false }
        return firstResponder.isDescendant(of: outlineView)
    }

    func expandSelectedOutlineItem() {
        guard let item = outlineView.item(atRow: outlineView.selectedRow),
              outlineView.isExpandable(item) else { return }
        outlineView.expandItem(item)
    }

    func collapseSelectedOutlineItem() {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return }
        if outlineView.isExpandable(item), outlineView.isItemExpanded(item) {
            outlineView.collapseItem(item)
            return
        }
        guard let parent = outlineView.parent(forItem: item) else { return }
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: parent)), byExtendingSelection: false)
        changeItemFocus()
    }
}

// MARK: - NSSplitView Delegate
extension CPYSnippetsEditorWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMinimumPosition + 150
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMaximumPosition / 2
    }
}

// MARK: - NSOutlineView DataSource
extension CPYSnippetsEditorWindowController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return folders.count
        } else if let folder = item as? EditorSnippetFolder {
            return folder.snippets.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? EditorSnippetFolder).map { !$0.snippets.isEmpty } ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? EditorSnippetFolder).map { $0.snippets[index] as Any } ?? folders[index] as Any
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        (item as? EditorSnippetFolder).map { $0.title } ?? (item as? EditorSnippet).map { $0.title } ?? ""
    }

    // MARK: - Drag and Drop
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        if let folder = item as? EditorSnippetFolder, let index = folders.firstIndex(where: { $0.id == folder.id }) {
            let draggedData = DraggedData(type: .folder, folderID: folder.id, snippetID: nil, index: index)
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: true) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else if let snippet = item as? EditorSnippet, let folder = outlineView.parent(forItem: snippet) as? EditorSnippetFolder {
            guard let index = folder.snippets.firstIndex(where: { $0.id == snippet.id }) else { return nil }
            let draggedData = DraggedData(type: .snippet, folderID: folder.id, snippetID: snippet.id, index: index)
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: true) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else {
            return nil
        }
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return NSDragOperation() }
        guard let draggedData = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [DraggedData.self, NSUUID.self], from: data) as? DraggedData else { return NSDragOperation() }

        switch draggedData.type {
        case .folder where item == nil:
            return .move
        case .snippet where item is EditorSnippetFolder:
            return .move
        default:
            return NSDragOperation()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return false }
        guard let draggedData = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [DraggedData.self, NSUUID.self], from: data) as? DraggedData else { return false }

        switch draggedData.type {
        case .folder where index != draggedData.index && index >= 0:
            guard let folder = folders.first(where: { $0.id == draggedData.folderID }) else { return false }
            folders.insert(folder, at: index)
            let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
            folders.remove(at: removedIndex)
            snippetRepository.updateFolderIndexes(folders.map(\.id))
            outlineView.reloadData()
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
            changeItemFocus()
            return true
        case .snippet:
            guard let fromFolder = folders.first(where: { $0.id == draggedData.folderID }) else { return false }
            guard let toFolder = item as? EditorSnippetFolder else { return false }
            guard let snippet = fromFolder.snippets.first(where: { $0.id == draggedData.snippetID }) else { return false }

            if draggedData.folderID == toFolder.id {
                guard index >= 0, index != draggedData.index else { return false }
                // Move to same folder
                fromFolder.snippets.insert(snippet, at: index)
                let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
                fromFolder.snippets.remove(at: removedIndex)
                snippetRepository.updateSnippetIndexes(fromFolder.snippets.map(\.id))
                outlineView.reloadData()
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                changeItemFocus()
                return true
            } else {
                // Move to other folder
                let index = max(0, index)
                toFolder.snippets.insert(snippet, at: index)
                fromFolder.snippets.removeAll(where: { $0.id == snippet.id })
                snippetRepository.moveSnippet(snippet.id, to: toFolder.id, snippetIDs: toFolder.snippets.map(\.id))
                outlineView.reloadData()
                outlineView.expandItem(toFolder)
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                changeItemFocus()
                return true
            }
        default:
            return false
        }
    }
}

// MARK: - NSOutlineView Delegate
extension CPYSnippetsEditorWindowController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, item: Any) {
        guard let cell = cell as? CPYSnippetsEditorCell else { return }
        if let folder = item as? EditorSnippetFolder {
            cell.iconType = .folder
            cell.isItemEnabled = folder.isEnabled
            cell.shortcutStyle = .command
        } else if let snippet = item as? EditorSnippet {
            cell.iconType = .none
            cell.isItemEnabled = snippet.isEnabled
            cell.shortcutStyle = .itemNumber
        }
        cell.shortcutText = shortcutText(for: item)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        changeItemFocus()
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let text = fieldEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard let outlineView = control as? NSOutlineView else { return false }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return false }
        if let folder = item as? EditorSnippetFolder {
            folder.title = text
            snippetRepository.updateFolderTitle(folder.id, title: text)
        } else if let snippet = item as? EditorSnippet {
            snippet.title = text
            snippetRepository.updateSnippetTitle(snippet.id, title: text)
        }
        outlineView.reloadItem(item)
        changeItemFocus()
        isEditingOutlineTitle = false
        return true
    }
}

#if DEBUG
extension CPYSnippetsEditorWindowController {
    var rootBackgroundAlphaForTesting: CGFloat {
        CGFloat(rootView.layer?.backgroundColor?.alpha ?? 0)
    }

    var toolbarBackgroundBrightnessForTesting: CGFloat {
        perceivedBrightness(for: toolbarView.layer?.backgroundColor)
    }

    var textEditorBackgroundBrightnessForTesting: CGFloat {
        perceivedBrightness(for: textView.backgroundColor.cgColor)
    }

    var usesOutlineDoubleClickEditingForTests: Bool {
        (outlineView.target as AnyObject?) === self
            && outlineView.doubleAction == #selector(outlineItemDoubleClicked(_:))
    }

    var showsFolderTitleFieldForTesting: Bool {
        folderTitleTextField.superview != nil
    }

    var showsSnippetContentEditorOnlyForTesting: Bool {
        folderTitleTextField.superview == nil && textScrollView.superview != nil
    }

    var outlineShortcutTextsForTesting: [String] {
        loadFoldersIfNeeded()
        return folders.flatMap { folder -> [String] in
            var values = [String]()
            if let folderShortcutText = shortcutText(for: folder) {
                values.append(folderShortcutText)
            }
            values.append(contentsOf: folder.snippets.compactMap { shortcutText(for: $0) })
            return values
        }
    }

    func addFolderForTesting() {
        addFolderButtonTapped(self)
    }

    func focusToolbarButtonForTesting(title: String) {
        guard let button = toolbarButtons.first(where: { $0.title == title }) else { return }
        window?.makeFirstResponder(button)
    }

    func handleSnippetEditorKeyboardEventForTesting(_ event: NSEvent) -> Bool {
        handleKeyboardEvent(event)
    }

    var toolbarUsesScrollContainerForTesting: Bool { toolbarScrollView.superview === toolbarView && toolbarStackView.superview === toolbarScrollView.documentView }

    var focusedSnippetEditorAreaForTesting: String {
        guard let responder = window?.firstResponder as? NSView else { return "none" }
        if responder is PasteraToolbarButton { return "toolbar" }
        if responder === outlineView || responder.isDescendant(of: outlineView) { return "outline" }
        if responder === textView || responder === folderShortcutRecordView { return "detail" }
        return "other"
    }

    func focusSnippetTextEditorForTesting() { window?.makeFirstResponder(textView) }

    func selectSnippetForTesting(id: Snippet.ID) {
        loadFoldersIfNeeded()
        for folder in folders {
            outlineView.expandItem(folder)
            guard let snippet = folder.snippets.first(where: { $0.id == id }) else { continue }
            let row = outlineView.row(forItem: snippet)
            guard row >= 0 else { continue }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            window?.makeFirstResponder(outlineView)
            changeItemFocus()
            return
        }
    }

    var isEditingOutlineTitleForTesting: Bool {
        isEditingOutlineTitle
    }

    func cancelOutlineEditingForTesting() {
        isEditingOutlineTitle = false
        window?.endEditing(for: nil)
        window?.makeFirstResponder(outlineView)
    }

    private func perceivedBrightness(for cgColor: CGColor?) -> CGFloat {
        guard let cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) else {
            return 0
        }
        return color.redComponent * 0.299
            + color.greenComponent * 0.587
            + color.blueComponent * 0.114
    }
}
#endif

// MARK: - NSTextView Delegate
extension CPYSnippetsEditorWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return false }
        guard let snippet = outlineView.item(atRow: outlineView.selectedRow) as? EditorSnippet else { return false }

        let string = (textView.string as NSString).replacingCharacters(in: affectedCharRange, with: replacementString)
        snippet.content = string
        snippetRepository.updateSnippetContent(snippet.id, content: string)

        return true
    }
}

// MARK: - RecordView Delegate
extension CPYSnippetsEditorWindowController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        guard selectedFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        guard selectedFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let selectedFolder = selectedFolder else { return }
        guard let keyCombo = keyCombo else {
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: selectedFolder.id.uuidString)
            outlineView.reloadItem(selectedFolder)
            return
        }
        AppEnvironment.current.hotKeyService.registerSnippetHotKey(with: selectedFolder.id.uuidString, keyCombo: keyCombo)
        outlineView.reloadItem(selectedFolder)
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
