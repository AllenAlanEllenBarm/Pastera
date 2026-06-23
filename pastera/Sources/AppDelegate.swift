//
//  AppDelegate.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Dependencies
import LoginServiceKit
import Magnet
import RealmSwift
import RxCocoa
import RxSwift
import Screeen
import Sparkle

@NSApplicationMain
class AppDelegate: NSObject, NSMenuItemValidation {

    // MARK: - Properties
    private(set) var updaterController: SPUStandardUpdaterController?
    private let screenshotObserver = ScreenShotObserver()
    private let disposeBag = DisposeBag()
    private var historySearchWindowController: HistorySearchWindowController?
    private var setupGuideWindowController: PasteraSetupGuideWindowController?
    private let syncCoordinator = SyncCoordinator.shared

    @Dependency(\.context)
    var context
    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository
    @Dependency(\.snippetRepository)
    private var snippetRepository

    // MARK: - Init
    override func awakeFromNib() {
        super.awakeFromNib()
        // Migrate Realm
        Realm.migration()
        prepareDependencies { values in
            try! values.bootstrapDatabase()
        }
    }

    // MARK: - NSMenuItem Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.clearAllHistory) {
            return pasteboardHistoryRepository.hasHistories()
        }
        return true
    }

    // MARK: - Menu Actions
    @objc func showPreferenceWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYPreferencesWindowController.sharedController.showWindow(self)
    }

    @objc func showSnippetEditorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYSnippetsEditorWindowController.sharedController.showWindow(self)
    }

    @objc func showHistorySearchWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if historySearchWindowController == nil {
            historySearchWindowController = HistorySearchWindowController()
        }
        historySearchWindowController?.showWindow(self)
        historySearchWindowController?.window?.makeKeyAndOrderFront(self)
    }

    @objc func terminate() {
        terminateApplication()
    }

    @objc func clearAllHistory() {
        let result = PasteraConfirmationController.runModal(options: PasteraConfirmationOptions(
            title: String(localized: "Clear History"),
            message: String(localized: "Are you sure you want to clear your clipboard history?"),
            confirmTitle: String(localized: "Clear History"),
            cancelTitle: String(localized: "Cancel"),
            isDestructive: true
        ))
        guard result.confirmed else { return }

        AppEnvironment.current.clipService.clearAll()
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        CPYUtilities.sendCustomLog(with: "selectClipMenuItem")
        let selectionRequest = sender.representedObject as? PasteboardHistorySelectionRequest
        let historyID = selectionRequest?.id ?? sender.representedObject as? PasteboardHistory.ID
        guard let id = historyID, let history = pasteboardHistoryRepository.fetchHistory(id: id) else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: history, restoring: selectionRequest?.targetContext)
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        let selectionRequest = sender.representedObject as? SnippetSelectionRequest
        let snippetID = selectionRequest?.id ?? sender.representedObject as? Snippet.ID
        guard let id = snippetID, let snippet = snippetRepository.fetchSnippet(id: id) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.pasteText(snippet.content, restoring: selectionRequest?.targetContext)
    }

    func terminateApplication() {
        syncCoordinator.stop()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Login Item Methods
    private func promptToAddLoginItems() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Launch Pastera on system startup?")
        alert.informativeText = String(localized: "You can change this setting in the Preferences if you want")
        alert.addButton(withTitle: String(localized: "Launch on system startup"))
        alert.addButton(withTitle: String(localized: "Don't Launch"))
        alert.showsSuppressionButton = true
        NSApp.activate(ignoringOtherApps: true)

        //  Launch on system startup
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.loginItem)
            AppEnvironment.current.defaults.synchronize()
            reflectLoginItemState()
        }
        // Do not show this message again
        if alert.suppressionButton?.state == NSControl.StateValue.on {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.suppressAlertForLoginItem)
            AppEnvironment.current.defaults.synchronize()
        }
    }

    private func toggleAddingToLoginItems(_ isEnable: Bool) {
        if isEnable {
            LoginServiceKit.addLoginItems()
        } else {
            LoginServiceKit.removeLoginItems()
        }
    }

    private func reflectLoginItemState() {
        let isInLoginItems = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem)
        toggleAddingToLoginItems(isInLoginItems)
    }
}

private final class HistorySearchCellView: NSTableCellView {
    private let indexLabel = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with detail: PasteboardHistoryDetail, index: Int) {
        let history = detail.history
        indexLabel.stringValue = "\(index)"
        titleLabel.stringValue = displayTitle(for: history)
        metadataLabel.stringValue = [
            displayType(for: history.primaryType),
            displayDate(for: history.updateAt)
        ].joined(separator: "  |  ")

        if let thumbnailAsset = detail.thumbnailAsset,
           thumbnailAsset.kind == .image,
           let image = NSImage(data: thumbnailAsset.data) {
            iconImageView.image = image
            iconImageView.imageScaling = .scaleProportionallyUpOrDown
        } else {
            iconImageView.image = icon(for: history.primaryType)
            iconImageView.imageScaling = .scaleProportionallyDown
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.clear.cgColor

        indexLabel.alignment = .right
        indexLabel.textColor = .secondaryLabelColor
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 5
        iconImageView.layer?.masksToBounds = true

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)

        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.font = .systemFont(ofSize: 11)

        [indexLabel, iconImageView, titleLabel, metadataLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            indexLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 28),

            iconImageView.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 10),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 36),
            iconImageView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            metadataLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metadataLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
    }

    private func displayTitle(for history: PasteboardHistory) -> String {
        if !history.title.isEmpty {
            return history.title
        }
        if history.primaryType?.isClipyImageType == true {
            return "(Image)"
        }
        switch history.primaryType {
        case .pdf, .deprecatedPDF:
            return "(PDF)"
        case .fileURL:
            return "(Files)"
        default:
            return "(Untitled)"
        }
    }

    private func displayType(for type: NSPasteboard.PasteboardType?) -> String {
        guard let type else { return "Clipboard" }
        if type.isClipyImageType {
            return "Image"
        }
        switch type {
        case .string, .deprecatedString:
            return "Text"
        case .rtf, .deprecatedRTF:
            return "RTF"
        case .rtfd, .deprecatedRTFD:
            return "RTFD"
        case .pdf, .deprecatedPDF:
            return "PDF"
        case .fileURL:
            return "Files"
        case .URL, .deprecatedURL:
            return "URL"
        default:
            return type.rawValue
        }
    }

    private func displayDate(for updateAt: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(updateAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func icon(for type: NSPasteboard.PasteboardType?) -> NSImage? {
        if type?.isClipyImageType == true {
            return NSImage(systemSymbolName: "photo", accessibilityDescription: "Image")
        }
        switch type {
        case .pdf, .deprecatedPDF:
            return NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "PDF")
        case .fileURL:
            return NSImage(systemSymbolName: "folder", accessibilityDescription: "Files")
        case .URL, .deprecatedURL:
            return NSImage(systemSymbolName: "link", accessibilityDescription: "URL")
        default:
            return NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Text")
        }
    }
}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {
    private func showSetupGuideIfNeeded() {
        let accessibilityService = AppEnvironment.current.accessibilityService
        let defaults = AppEnvironment.current.defaults
        let policy = PasteraSetupGuidePolicy(
            arguments: ProcessInfo.processInfo.arguments,
            isAccessibilityTrusted: accessibilityService.isAccessibilityEnabled(isPrompt: false),
            isAutomaticPasteEnabled: defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand),
            didDismissSetupGuide: defaults.bool(forKey: Constants.UserDefaults.setupGuideDismissed)
        )
        guard policy.shouldShowSetupGuide else { return }

        let controller = PasteraSetupGuideWindowController(
            accessibilityService: accessibilityService,
            defaults: defaults
        )
        controller.onClose = { [weak self] in
            self?.setupGuideWindowController = nil
        }
        setupGuideWindowController = controller
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Environments
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage())
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()
        PasteraAppIconProvider.installApplicationIcon()

        guard context != .test else { return }

        // SDKs
        CPYUtilities.initSDKs()
        InstallationLocationService().showMoveToApplicationsAlertIfNeeded()
        showSetupGuideIfNeeded()

        // Show Login Item
        if !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) && !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.suppressAlertForLoginItem) {
            promptToAddLoginItems()
        }

        // Sparkle
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: AppEnvironment.current.defaults.bool(forKey: Constants.Update.enableAutomaticCheck),
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController?.updater.updateCheckInterval = TimeInterval(AppEnvironment.current.defaults.integer(forKey: Constants.Update.checkInterval))
        updaterController?.updater.clearFeedURLFromUserDefaults()

        // Binding Events
        bind()

        // Services
        AppEnvironment.current.clipService.startMonitoring()
        AppEnvironment.current.excludeAppService.startMonitoring()
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()
        syncCoordinator.start()

        // Managers
        AppEnvironment.current.menuManager.setup()
        // Screenshot
        screenshotObserver.delegate = self
        screenshotObserver.isEnabled = true
        screenshotObserver.start()

        // Clean datas every 30 minutes
        Observable<Int>.interval(.seconds(60 * 30), scheduler: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] _ in
                self?.pasteboardHistoryRepository.pruneHistories(settings: HistoryRetentionSettings.current())
            })
            .disposed(by: disposeBag)
    }

}

// MARK: - Bind
private extension AppDelegate {
    func bind() {
        // Login Item
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.loginItem, retainSelf: false)
            .compactMap { $0 }
            .subscribe(onNext: { [weak self] _ in
                self?.reflectLoginItemState()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - ScreenShotObserver Delegate
extension AppDelegate: ScreenShotObserverDelegate {
    func screenShotObserver(_ observer: ScreenShotObserver, addedItem item: NSMetadataItem) {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return }
        AppEnvironment.current.clipService.createScreenshot(from: URL(fileURLWithPath: path))
    }
}

private final class HistorySearchWindowController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository

    private let searchField = NSSearchField()
    private let typeSegmentedControl = NSSegmentedControl(
        labels: ["All", "Text", "Images", "Files", "PDF"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let regexButton = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
    private let caseButton = NSButton(checkboxWithTitle: "Aa", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let loadMoreButton = NSButton(title: "Load More", target: nil, action: nil)
    private var historyDetails = [PasteboardHistoryDetail]()
    private var pendingSearch: DispatchWorkItem?
    private var searchGeneration = 0
    private let pageLimit = 50

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Search History"
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        CPYWindowAppearance.apply(to: window)
        super.init(window: window)
        setupContent()
        reloadSearch()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func controlTextDidChange(_ obj: Notification) {
        scheduleSearch()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        historyDetails.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("HistorySearchCell")
        let cell: HistorySearchCellView
        if let reusedCell = tableView.makeView(withIdentifier: identifier, owner: self) as? HistorySearchCellView {
            cell = reusedCell
        } else {
            cell = HistorySearchCellView()
            cell.identifier = identifier
        }
        cell.configure(with: historyDetails[row], index: row + 1)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        62
    }

    @objc private func optionChanged(_ sender: NSButton) {
        scheduleSearch()
    }

    @objc private func typeChanged(_ sender: Any) {
        scheduleSearch()
    }

    @objc private func loadMore(_ sender: NSButton) {
        reloadSearch(appending: true)
    }

    @objc private func pasteSelectedHistory(_ sender: Any?) {
        let selectedRow = tableView.selectedRow
        guard historyDetails.indices.contains(selectedRow) else { return }
        AppEnvironment.current.pasteService.paste(with: historyDetails[selectedRow].history)
    }

    private func setupContent() {
        guard let window else { return }
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 14
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = contentView
        CPYWindowAppearance.apply(to: window)

        searchField.delegate = self
        searchField.placeholderString = "Search clipboard history"
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 15)

        typeSegmentedControl.selectedSegment = 0
        typeSegmentedControl.segmentStyle = .rounded
        typeSegmentedControl.target = self
        typeSegmentedControl.action = #selector(typeChanged(_:))
        typeSegmentedControl.setWidth(58, forSegment: 0)
        typeSegmentedControl.setWidth(58, forSegment: 1)
        typeSegmentedControl.setWidth(72, forSegment: 2)
        typeSegmentedControl.setWidth(62, forSegment: 3)
        typeSegmentedControl.setWidth(52, forSegment: 4)

        regexButton.target = self
        regexButton.action = #selector(optionChanged(_:))
        regexButton.controlSize = .small
        caseButton.target = self
        caseButton.action = #selector(optionChanged(_:))
        caseButton.controlSize = .small
        caseButton.toolTip = "Case sensitive"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        loadMoreButton.target = self
        loadMoreButton.action = #selector(loadMore(_:))
        loadMoreButton.isEnabled = false
        loadMoreButton.bezelStyle = .rounded

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.title = "History"
        column.resizingMask = .autoresizingMask
        column.width = 640
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(pasteSelectedHistory(_:))
        tableView.target = self
        tableView.rowHeight = 62
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.enclosingScrollView?.drawsBackground = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8

        let optionsStackView = NSStackView(views: [regexButton, caseButton])
        optionsStackView.orientation = .horizontal
        optionsStackView.alignment = .centerY
        optionsStackView.spacing = 8

        [searchField, typeSegmentedControl, optionsStackView, statusLabel, scrollView, loadMoreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: optionsStackView.leadingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            optionsStackView.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            optionsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            typeSegmentedControl.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            typeSegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),

            statusLabel.centerYAnchor.constraint(equalTo: typeSegmentedControl.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: typeSegmentedControl.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: typeSegmentedControl.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            scrollView.bottomAnchor.constraint(equalTo: loadMoreButton.topAnchor, constant: -10),

            loadMoreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            loadMoreButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    private func scheduleSearch() {
        pendingSearch?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadSearch()
        }
        pendingSearch = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func reloadSearch(appending: Bool = false) {
        searchGeneration += 1
        let generation = searchGeneration
        let offset = appending ? historyDetails.count : 0
        let query = HistorySearchQuery(
            text: searchField.stringValue,
            mode: regexButton.state == .on ? .regex : .plain,
            caseSensitive: caseButton.state == .on,
            types: selectedTypes,
            sortOrder: .newestFirst
        )
        statusLabel.stringValue = appending ? "Loading..." : "Searching..."
        loadMoreButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let results = try self.pasteboardHistoryRepository.searchHistoryDetails(
                    query: query,
                    includesThumbnailAsset: true,
                    limit: self.pageLimit,
                    offset: offset
                )
                DispatchQueue.main.async {
                    guard generation == self.searchGeneration else { return }
                    if appending {
                        self.historyDetails.append(contentsOf: results)
                    } else {
                        self.historyDetails = results
                    }
                    self.statusLabel.stringValue = "\(self.historyDetails.count) results"
                    self.loadMoreButton.isEnabled = results.count == self.pageLimit
                    self.tableView.reloadData()
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.searchGeneration else { return }
                    self.historyDetails = []
                    self.statusLabel.stringValue = "Invalid search pattern"
                    self.loadMoreButton.isEnabled = false
                    self.tableView.reloadData()
                }
            }
        }
    }

    private var selectedTypes: Set<NSPasteboard.PasteboardType> {
        switch typeSegmentedControl.selectedSegment {
        case 1:
            return [.string, .deprecatedString]
        case 2:
            return NSPasteboard.PasteboardType.clipyImageTypes
        case 3:
            return [.fileURL]
        case 4:
            return [.pdf, .deprecatedPDF]
        default:
            return []
        }
    }

    private func displayTitle(for history: PasteboardHistory) -> String {
        if !history.title.isEmpty {
            return history.title
        }
        if history.primaryType?.isClipyImageType == true {
            return "(Image)"
        }
        switch history.primaryType {
        case .pdf, .deprecatedPDF:
            return "(PDF)"
        case .fileURL:
            return "(Files)"
        default:
            return "(Untitled)"
        }
    }
}
