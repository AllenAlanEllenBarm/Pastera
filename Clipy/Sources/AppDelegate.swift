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
        let isShowAlert = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
        if isShowAlert {
            let alert = NSAlert()
            alert.messageText = String(localized: "Clear History")
            alert.informativeText = String(localized: "Are you sure you want to clear your clipboard history?")
            alert.addButton(withTitle: String(localized: "Clear History"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.showsSuppressionButton = true

            NSApp.activate(ignoringOtherApps: true)

            let result = alert.runModal()
            if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

            if alert.suppressionButton?.state == NSControl.StateValue.on {
                AppEnvironment.current.defaults.set(false, forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
            }
            AppEnvironment.current.defaults.synchronize()
        }

        AppEnvironment.current.clipService.clearAll()
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        CPYUtilities.sendCustomLog(with: "selectClipMenuItem")
        guard let id = sender.representedObject as? PasteboardHistory.ID, let history = pasteboardHistoryRepository.fetchHistory(id: id) else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: history)
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        guard let id = sender.representedObject as? Snippet.ID, let snippet = snippetRepository.fetchSnippet(id: id) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
        AppEnvironment.current.pasteService.paste()
    }

    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Login Item Methods
    private func promptToAddLoginItems() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Launch Clipy on system startup?")
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

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Environments
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage())
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()

        guard context != .test else { return }

        // SDKs
        CPYUtilities.initSDKs()
        // Check Accessibility Permission
        AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: true)

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

        // Managers
        AppEnvironment.current.menuManager.setup()
        // Screenshot
        screenshotObserver.delegate = self

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
        // Observe Screenshot
        let observerScreenshot = AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.Beta.observerScreenshot, retainSelf: false)
            .compactMap { $0 }
            .share(replay: 1)
        observerScreenshot
            .subscribe(onNext: { [weak self] enabled in
                self?.screenshotObserver.isEnabled = enabled
            })
            .disposed(by: disposeBag)
        observerScreenshot
            .filter { $0 }
            .take(1)
            .subscribe(onNext: { [weak self] _ in
                self?.screenshotObserver.start()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - ScreenShotObserver Delegate
extension AppDelegate: ScreenShotObserverDelegate {
    func screenShotObserver(_ observer: ScreenShotObserver, addedItem item: NSMetadataItem) {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return }
        guard let image = NSImage(contentsOfFile: path) else { return }
        AppEnvironment.current.clipService.create(with: image)
    }
}

private final class HistorySearchWindowController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository

    private let searchField = NSSearchField()
    private let typePopUpButton = NSPopUpButton()
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Search History"
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
        let textField: NSTextField
        if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = cell
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingTail
        }
        textField.stringValue = displayTitle(for: historyDetails[row].history)
        return textField
    }

    @objc private func optionChanged(_ sender: NSButton) {
        scheduleSearch()
    }

    @objc private func typeChanged(_ sender: NSPopUpButton) {
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
        guard let contentView = window?.contentView else { return }
        searchField.delegate = self
        typePopUpButton.addItems(withTitles: ["All", "Text", "Images", "Files", "PDF"])
        typePopUpButton.target = self
        typePopUpButton.action = #selector(typeChanged(_:))
        regexButton.target = self
        regexButton.action = #selector(optionChanged(_:))
        caseButton.target = self
        caseButton.action = #selector(optionChanged(_:))
        loadMoreButton.target = self
        loadMoreButton.action = #selector(loadMore(_:))
        loadMoreButton.isEnabled = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.title = "History"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(pasteSelectedHistory(_:))
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        [searchField, typePopUpButton, regexButton, caseButton, statusLabel, scrollView, loadMoreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: typePopUpButton.leadingAnchor, constant: -8),
            typePopUpButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            typePopUpButton.widthAnchor.constraint(equalToConstant: 96),
            typePopUpButton.trailingAnchor.constraint(equalTo: regexButton.leadingAnchor, constant: -8),
            regexButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            regexButton.trailingAnchor.constraint(equalTo: caseButton.leadingAnchor, constant: -8),
            caseButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            caseButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: loadMoreButton.topAnchor, constant: -8),

            loadMoreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            loadMoreButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
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
                    includesThumbnailAsset: false,
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
        switch typePopUpButton.indexOfSelectedItem {
        case 1:
            return [.string, .deprecatedString]
        case 2:
            return [.tiff, .deprecatedTIFF]
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
        switch history.primaryType {
        case .tiff, .deprecatedTIFF:
            return "(Image)"
        case .pdf, .deprecatedPDF:
            return "(PDF)"
        case .fileURL:
            return "(Files)"
        default:
            return "(Untitled)"
        }
    }
}
