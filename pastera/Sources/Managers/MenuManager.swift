//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Combine
import Dependencies
import RxCocoa
import RxSwift

private final class HistoryBrowserMenu: NSMenu {
    weak var headerView: HistoryMenuHeaderView?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if headerView?.handleMenuTrackingKeyDown(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct HistoryItemPresentation {
    let title: String
    let image: NSImage?
    let toolTip: String?
}

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    fileprivate var snippetMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = NSImage(resource: .iconFolder)
    fileprivate let snippetIcon = NSImage(resource: .iconText)
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    fileprivate var historyMenuState = HistoryMenuPaginationState()
    var historyPanelController: HistoryBrowserPanelController?
    var snippetPanelController: SnippetBrowserPanelController?
    var mainMenuPanelController: MainMenuPanelController?
    var isMainMenuPinned = false
    var panelDismissLocalMonitor: Any?
    var panelDismissGlobalMonitor: Any?
    static let panelDismissMouseEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository
    @Dependency(\.snippetRepository)
    private var snippetRepository
    @Dependency(\.mainQueue)
    private var mainQueue
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
    }

    deinit {
        removePanelDismissMonitors()
    }

    func setup() {
        bind()
    }

}

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType) {
        if type == .main {
            showMainMenuPanel(at: NSEvent.mouseLocation)
            return
        }

        if type == .history {
            showHistoryBrowserPanel(at: NSEvent.mouseLocation)
            return
        }

        if type == .snippet {
            showSnippetBrowserPanel(at: NSEvent.mouseLocation)
            return
        }

        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        case .snippet:
            menu = snippetMenu
        }
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func popUpSnippetFolder(_ folderDetail: SnippetFolderDetail) {
        showSnippetFolderPanel(folderDetail.folder.id, at: NSEvent.mouseLocation)
    }
}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        pasteboardHistoryRepository.observeHistories()
            .receive(on: mainQueue)
            .sink { [weak self] _ in self?.createClipMenu() }
            .store(in: &cancellables)
        snippetRepository.observeFolderDetails()
            .receive(on: mainQueue)
            .sink { [weak self] _ in self?.createClipMenu() }
            .store(in: &cancellables)
        // Menu icon
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.showStatusItem, retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            })
            .disposed(by: disposeBag)
        // Sort clips
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.reorderClipsAfterPasting, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                guard let wSelf = self else { return }
                wSelf.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings
        let defaults = AppEnvironment.current.defaults
        var menuChangedObservables = [Observable<Void>]()
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addClearHistoryMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showIconInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInline, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInsideFolder, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxMenuItemTitleLength, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsTitleStartWithZero, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsAreMarkedWithNumbers, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showToolTipOnMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showImageInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addNumericKeyEquivalents, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxLengthOfToolTip, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showColorPreviewInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        Observable.merge(menuChangedObservables)
            .throttle(.seconds(1), scheduler: MainScheduler.instance)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Menus
private extension MenuManager {
     func createClipMenu() {
        clipMenu = NSMenu(title: Constants.Application.name)
        historyMenu = HistoryBrowserMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)

        addHistoryItems(clipMenu!, asSubmenu: true)
        addHistoryItems(historyMenu!, asSubmenu: false)

        clipMenu?.addItem(makeSnippetBrowserMenuItem())
        addSnippetItems(snippetMenu!, separateMenu: false)

        clipMenu?.addItem(NSMenuItem.separator())

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            clipMenu?.addItem(NSMenuItem(title: String(localized: "Clear History"), action: #selector(AppDelegate.clearAllHistory)))
        }

        clipMenu?.addItem(NSMenuItem(title: String(localized: "Edit Snippets"), action: #selector(AppDelegate.showSnippetEditorWindow)))
        clipMenu?.addItem(NSMenuItem(title: String(localized: "Preferences"), action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu?.addItem(NSMenuItem.separator())
        clipMenu?.addItem(NSMenuItem(title: String(localized: "Quit Pastera"), action: #selector(AppDelegate.terminate)))

        statusItem?.menu = nil
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return subMenuItem
    }

    func trimTitle(_ title: String?, minimumMaxLength: Int? = nil) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if let minimumMaxLength {
            maxMenuItemTitleLength = max(maxMenuItemTitleLength, minimumMaxLength)
        }
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }
}

// MARK: - Clips
private extension MenuManager {
    func addHistoryItems(_ menu: NSMenu, asSubmenu: Bool) {
        if asSubmenu {
            menu.addItem(makeHistoryBrowserMenuItem())
        } else {
            configureHistoryBrowserMenu(menu)
        }
    }

    func makeHistoryBrowserMenuItem() -> NSMenuItem {
        let historyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let itemView = MainMenuHeaderItemView(
            title: String(localized: "History"),
            image: AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu) ? folderIcon : nil,
            isPinned: isMainMenuPinned,
            shortcutText: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.historyKeyCombo)
        )
        itemView.onOpen = { [weak self, weak historyItem] in
            historyItem?.menu?.cancelTracking()
            DispatchQueue.main.async { [weak self] in
                self?.showHistoryBrowserPanel(at: NSEvent.mouseLocation)
            }
        }
        itemView.onPinnedChange = { [weak self, weak historyItem, weak itemView] pinned, menuFrame in
            historyItem?.menu?.cancelTracking()
            self?.setMainMenuPinned(pinned)
            itemView?.setPinned(pinned)
            DispatchQueue.main.async { [weak self] in
                if pinned {
                    self?.showMainMenuPanel(anchoredTo: menuFrame, fallbackPoint: NSEvent.mouseLocation)
                }
            }
        }
        historyItem.view = itemView
        return historyItem
    }

    @objc func openHistoryBrowserPanelFromMenuItem(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.showHistoryBrowserPanel(at: NSEvent.mouseLocation)
        }
    }

    func makeSnippetBrowserMenuItem() -> NSMenuItem {
        let snippetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let itemView = MainMenuHeaderItemView(
            title: String(localized: "Snippet"),
            image: AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu) ? snippetIcon : nil,
            isPinned: false,
            showsPin: false,
            shortcutText: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.snippetKeyCombo)
        )
        itemView.onOpen = { [weak self, weak snippetItem] in
            snippetItem?.menu?.cancelTracking()
            DispatchQueue.main.async { [weak self] in
                self?.showSnippetBrowserPanel()
            }
        }
        itemView.onHoverOpen = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.showSnippetBrowserPanel()
            }
        }
        snippetItem.view = itemView
        return snippetItem
    }

    func showHistoryBrowserPanel(at screenPoint: NSPoint) {
        snippetPanelController?.close()
        let panelController = historyPanelController ?? makeHistoryPanelController()
        historyPanelController = panelController
        if let mainMenuFrame = mainMenuPanelController?.visibleFrame {
            mainMenuPanelController?.beginChildPanelPresentation()
            panelController.setPinned(true)
            panelController.show(attachedTo: mainMenuFrame)
        } else {
            panelController.setPinned(false)
            panelController.show(at: screenPoint)
        }
        installPanelDismissMonitorsIfNeeded()
    }

    func showMainMenuPanel(at screenPoint: NSPoint) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        panelController.show(at: screenPoint, pinned: isMainMenuPinned)
        installPanelDismissMonitorsIfNeeded()
    }

    func showMainMenuPanel(anchoredTo menuFrame: NSRect?, fallbackPoint: NSPoint) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        if let menuFrame {
            panelController.show(anchoredTo: menuFrame, pinned: true)
        } else {
            panelController.show(at: fallbackPoint, pinned: true)
        }
        installPanelDismissMonitorsIfNeeded()
    }

    func showMainMenuPanel(attachedToStatusItemFrame statusItemFrame: NSRect) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        panelController.show(attachedToStatusItemFrame: statusItemFrame, pinned: isMainMenuPinned)
        installPanelDismissMonitorsIfNeeded()
    }

    func setMainMenuPinned(_ pinned: Bool) {
        isMainMenuPinned = pinned
        if !pinned {
            mainMenuPanelController?.close()
            historyPanelController?.close()
            snippetPanelController?.close()
            removePanelDismissMonitors()
        }
        createClipMenu()
    }

    func makeHistoryPanelController() -> HistoryBrowserPanelController {
        let controller = HistoryBrowserPanelController(
            currentState: { [weak self] in
                self?.historyMenuState ?? HistoryMenuPaginationState()
            },
            updateState: { [weak self] update in
                guard let self else { return }
                update(&self.historyMenuState)
            },
            fetchPage: { [weak self] in
                self?.fetchHistoryMenuPage() ?? HistoryMenuPage()
            },
            makeRowView: { [weak self] detail, index, onConfirm in
                self?.makeHistoryRowView(detail, index: index, onConfirm: onConfirm)
                    ?? HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
            },
            selectHistory: { [weak self] historyID, application in
                self?.selectHistory(historyID, restoring: application)
            }
        )
        controller.onClose = { [weak self] in
            self?.mainMenuPanelController?.endChildPanelPresentation()
        }
        return controller
    }

    func makeMainMenuPanelController() -> MainMenuPanelController {
        MainMenuPanelController(
            historyTitle: String(localized: "History"),
            historyImage: AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu) ? folderIcon : nil,
            historyShortcutText: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.historyKeyCombo),
            snippetTitle: String(localized: "Snippet"),
            snippetImage: AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu) ? snippetIcon : nil,
            itemsProvider: { [weak self] in self?.makeMainMenuPanelItems() ?? [] },
            onOpenHistory: { [weak self] in self?.showHistoryBrowserPanel(at: NSEvent.mouseLocation) },
            onOpenSnippets: { [weak self] in self?.showSnippetBrowserPanel() },
            onPinnedChange: { [weak self] pinned in self?.setMainMenuPinned(pinned) }
        )
    }

    func makeMainMenuPanelItems() -> [MainMenuPanelItem] {
        var items = [MainMenuPanelItem]()

        let enabledSnippetFolders = snippetRepository.fetchFolderDetails()
            .filter { $0.folder.isEnabled }
        if !enabledSnippetFolders.isEmpty {
            let folderImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)
                ? folderIcon
                : nil
            enabledSnippetFolders.forEach { detail in
                let title = trimTitle(detail.folder.title)
                let shortcutText = PasteraShortcutFormatter.string(
                    for: AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: detail.folder.id.uuidString)
                )
                items.append(.snippetFolder(title: title, image: folderImage, shortcutText: shortcutText) { [weak self] anchorFrame in
                    self?.showSnippetFolderPanel(detail.folder.id, attachedTo: anchorFrame)
                })
            }
            items.append(.separator)
        }

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            let title = String(localized: "Clear History")
            let shortcutText = PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.clearHistoryKeyCombo)
            items.append(.action(title: title, image: menuPanelSymbol("trash", accessibilityDescription: title), shortcutText: shortcutText) {
                NSApp.sendAction(#selector(AppDelegate.clearAllHistory), to: nil, from: nil)
            })
        }

        let snippetsTitle = String(localized: "Edit Snippets")
        items.append(.action(title: snippetsTitle, image: menuPanelSymbol("text.quote", accessibilityDescription: snippetsTitle)) {
            NSApp.sendAction(#selector(AppDelegate.showSnippetEditorWindow), to: nil, from: nil)
        })
        let preferencesTitle = String(localized: "Preferences")
        items.append(.action(title: preferencesTitle, image: menuPanelSymbol("gearshape", accessibilityDescription: preferencesTitle)) {
            NSApp.sendAction(#selector(AppDelegate.showPreferenceWindow), to: nil, from: nil)
        })
        items.append(.separator)
        let quitTitle = String(localized: "Quit Pastera")
        items.append(.action(title: quitTitle, image: menuPanelSymbol("power", accessibilityDescription: quitTitle)) {
            NSApp.sendAction(#selector(AppDelegate.terminate), to: nil, from: nil)
        })

        return items
    }

    private func menuPanelSymbol(_ name: String, accessibilityDescription: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }

    func makeSnippetPanelController() -> SnippetBrowserPanelController {
        let controller = SnippetBrowserPanelController(
            fetchDetails: { [weak self] in
                self?.snippetRepository.fetchFolderDetails() ?? []
            },
            selectSnippet: { [weak self] snippetID, application in
                self?.selectSnippet(snippetID, restoring: application)
            }
        )
        controller.onClose = { [weak self] in
            self?.mainMenuPanelController?.endChildPanelPresentation()
        }
        return controller
    }

    func showSnippetBrowserPanel() {
        historyPanelController?.close()
        guard let mainMenuFrame = mainMenuPanelController?.visibleFrame else {
            showSnippetBrowserPanel(at: NSEvent.mouseLocation)
            return
        }

        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        mainMenuPanelController?.beginChildPanelPresentation()
        panelController.show(attachedTo: mainMenuFrame)
        installPanelDismissMonitorsIfNeeded()
    }

    func showSnippetBrowserPanel(at screenPoint: NSPoint) {
        historyPanelController?.close()
        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        panelController.show(at: screenPoint)
        installPanelDismissMonitorsIfNeeded()
    }

    func showSnippetFolderPanel(_ folderID: SnippetFolder.ID, attachedTo anchorFrame: NSRect?) {
        historyPanelController?.close()
        guard let anchorFrame = anchorFrame ?? mainMenuPanelController?.visibleFrame else {
            showSnippetFolderPanel(folderID, at: NSEvent.mouseLocation)
            return
        }

        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        mainMenuPanelController?.beginChildPanelPresentation()
        panelController.show(folderID: folderID, attachedTo: anchorFrame)
        installPanelDismissMonitorsIfNeeded()
    }

    func showSnippetFolderPanel(_ folderID: SnippetFolder.ID, at screenPoint: NSPoint) {
        historyPanelController?.close()
        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        panelController.show(folderID: folderID, at: screenPoint)
        installPanelDismissMonitorsIfNeeded()
    }

    func makeHistoryBrowserMenu() -> NSMenu {
        let menu = HistoryBrowserMenu(title: String(localized: "History"))
        configureHistoryBrowserMenu(menu)
        return menu
    }

    func configureHistoryBrowserMenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        while menu.numberOfItems > 0 {
            menu.removeItem(at: 0)
        }

        let headerView = HistoryMenuHeaderView()
        let headerItem = NSMenuItem()
        headerItem.view = headerView
        (menu as? HistoryBrowserMenu)?.headerView = headerView
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        let updateMenu = { [weak self, weak menu, weak headerView] (update: (inout HistoryMenuPaginationState) -> Void) in
            self?.updateHistoryBrowserMenu(menu, headerView: headerView, update: update)
        }
        headerView.onQueryChange = { query in updateMenu { $0.updateQuery(query) } }
        headerView.onModeChange = { mode in updateMenu { $0.updateMode(mode) } }
        headerView.onCaseSensitiveChange = { caseSensitive in updateMenu { $0.updateCaseSensitive(caseSensitive) } }
        headerView.onTypeFilterChange = { typeFilter in updateMenu { $0.updateTypeFilter(typeFilter) } }
        headerView.onPreviousPage = { updateMenu { $0.goToPreviousPage() } }
        headerView.onNextPage = { [weak self, weak menu, weak headerView] in
            guard let self = self else { return }
            let page = self.fetchHistoryMenuPage()
            self.updateHistoryBrowserMenu(menu, headerView: headerView) { $0.goToNextPage(if: page.hasNextPage) }
        }

        reloadHistoryBrowserResults(in: menu, headerView: headerView)
    }

    func updateHistoryBrowserMenu(_ menu: NSMenu?, headerView: HistoryMenuHeaderView?, update: (inout HistoryMenuPaginationState) -> Void) {
        update(&historyMenuState)
        guard let menu = menu else { return }
        reloadHistoryBrowserResults(in: menu, headerView: headerView)
    }

    func reloadHistoryBrowserResults(in menu: NSMenu, headerView: HistoryMenuHeaderView?) {
        HistoryMenuRowView.hideImagePreview()
        while menu.numberOfItems > 2 {
            menu.removeItem(at: 2)
        }

        var page = fetchHistoryMenuPage()
        if page.details.isEmpty && page.error == nil && historyMenuState.pageIndex > 0 {
            historyMenuState.resetPage()
            page = fetchHistoryMenuPage()
        }

        headerView?.configure(state: historyMenuState, hasNextPage: page.hasNextPage)

        if let error = page.error {
            let errorItem = NSMenuItem(title: error.historyMenuTitle, action: nil)
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            headerView?.connectKeyboardNavigation(to: [])
            return
        }

        guard !page.details.isEmpty else {
            let title = historyMenuState.hasActiveSearchOptions ? String(localized: "No Results") : String(localized: "No History")
            let emptyItem = NSMenuItem(title: title, action: nil)
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            headerView?.connectKeyboardNavigation(to: [])
            return
        }

        let firstIndex = firstIndexOfMenuItems()
        var historyRowViews = [HistoryMenuRowView]()
        for (index, historyDetail) in page.details.enumerated() {
            let listNumber = (firstIndex + index) % kMaxKeyEquivalents
            let menuItem = makeClipMenuItem(historyDetail, index: index, listNumber: listNumber)
            menu.addItem(menuItem)
            if let rowView = menuItem.view as? HistoryMenuRowView {
                historyRowViews.append(rowView)
            }
        }
        headerView?.connectKeyboardNavigation(to: historyRowViews)
    }

    func fetchHistoryMenuPage() -> HistoryMenuPage {
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let isShowImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let limit = historyMenuState.pageSize + 1
        let query = HistorySearchQuery(
            text: historyMenuState.query,
            mode: historyMenuState.mode,
            caseSensitive: historyMenuState.caseSensitive,
            types: historyMenuState.selectedTypes,
            sortOrder: ascending ? .oldestFirst : .newestFirst
        )
        do {
            let details = try pasteboardHistoryRepository.searchHistoryDetails(
                query: query,
                includesThumbnailAsset: isShowImage || isShowColorCode,
                limit: limit,
                offset: historyMenuState.offset
            )
            return .result(details, pageSize: historyMenuState.pageSize)
        } catch let error as HistorySearchError {
            return HistoryMenuPage(error: error)
        } catch {
            return HistoryMenuPage()
        }
    }

    func makeClipMenuItem(_ historyDetail: PasteboardHistoryDetail, index: Int, listNumber: Int) -> NSMenuItem {
        let history = historyDetail.history
        let shortcutText = numericShortcutText(forRowIndex: index)
        let presentation = makeHistoryItemPresentation(
            historyDetail,
            listNumber: listNumber,
            usesLeadingNumber: false
        )

        let menuItem = NSMenuItem(
            title: presentation.title,
            action: #selector(AppDelegate.selectClipMenuItem(_:)),
            keyEquivalent: shortcutText ?? ""
        )
        menuItem.representedObject = history.id

        if let toolTip = presentation.toolTip {
            menuItem.toolTip = toolTip
        }

        menuItem.image = presentation.image

        menuItem.view = HistoryMenuRowView(title: menuItem.title, image: menuItem.image, shortcutText: shortcutText) { [weak menuItem] in
            guard let menuItem else { return }
            menuItem.menu?.cancelTracking()
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(AppDelegate.selectClipMenuItem(_:)), to: nil, from: menuItem)
            }
        }

        return menuItem
    }

    func makeHistoryRowView(_ historyDetail: PasteboardHistoryDetail, index: Int, onConfirm: @escaping () -> Void) -> HistoryMenuRowView {
        let listNumber = (firstIndexOfMenuItems() + index) % kMaxKeyEquivalents
        let shortcutText = numericShortcutText(forRowIndex: index)
        let presentation = makeHistoryItemPresentation(
            historyDetail,
            listNumber: listNumber,
            usesLeadingNumber: false
        )
        return HistoryMenuRowView(title: presentation.title, image: presentation.image, shortcutText: shortcutText, onConfirm: onConfirm)
    }

    func makeHistoryItemPresentation(
        _ historyDetail: PasteboardHistoryDetail,
        listNumber: Int,
        usesLeadingNumber: Bool? = nil
    ) -> HistoryItemPresentation {
        let history = historyDetail.history
        let isMarkWithNumber = usesLeadingNumber ?? false
        let isShowToolTip = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        let isShowImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let primaryPboardType = history.primaryType
        let clipString = history.title
        var title = menuItemTitle(
            trimTitle(clipString, minimumMaxLength: HistoryBrowserLayout.minimumTitlePreviewLength),
            listNumber: listNumber,
            isMarkWithNumber: isMarkWithNumber
        )

        if primaryPboardType?.isClipyImageType == true {
            title = menuItemTitle("(Image)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        } else if primaryPboardType == .pdf || primaryPboardType == .deprecatedPDF {
            title = menuItemTitle("(PDF)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        } else if primaryPboardType == .fileURL {
            title = menuItemTitle("(Files)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        }

        let toolTip: String?
        if isShowToolTip {
            let maxLengthOfToolTip = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
            let toIndex = (clipString.count < maxLengthOfToolTip) ? clipString.count : maxLengthOfToolTip
            toolTip = (clipString as NSString).substring(to: toIndex)
        } else {
            toolTip = nil
        }

        let image: NSImage?
        if isShowImage || isShowColorCode,
           let thumbnailAsset = historyDetail.thumbnailAsset,
           let thumbnailImage = NSImage(data: thumbnailAsset.data),
           (thumbnailAsset.kind == .image && isShowImage) || (thumbnailAsset.kind == .colorCode && isShowColorCode) {
            image = thumbnailImage
        } else {
            image = nil
        }

        return HistoryItemPresentation(title: title, image: image, toolTip: toolTip)
    }

    func numericShortcutText(forRowIndex index: Int) -> String? {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents) else {
            return nil
        }
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        return PasteraShortcutFormatter.numericString(forRowIndex: index, startsAtZero: startsAtZero)
    }

    func selectHistory(_ historyID: PasteboardHistory.ID, restoring application: NSRunningApplication?) {
        dismissMenuPanelsAfterSelection()

        let menuItem = NSMenuItem(title: "", action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = historyID

        if application?.isTerminated == false {
            application?.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.sendAction(#selector(AppDelegate.selectClipMenuItem(_:)), to: nil, from: menuItem)
        }
    }
}

// MARK: - Snippets
private extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        let details = snippetRepository.fetchFolderDetails()
        guard !details.isEmpty else { return }

        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        // Snippet title
        let labelItem = NSMenuItem(title: String(localized: "Snippet"), action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        var subMenuIndex = menu.numberOfItems - 1
        let firstIndex = firstIndexOfMenuItems()
        details
            .filter { $0.folder.isEnabled }
            .forEach { detail in
                let folderTitle = detail.folder.title
                let subMenuItem = makeSubmenuItem(folderTitle)
                menu.addItem(subMenuItem)
                subMenuIndex += 1

                detail.snippets
                    .filter { $0.isEnabled }
                    .enumerated()
                    .forEach { rowIndex, snippet in
                        let subMenuItem = makeSnippetMenuItem(snippet, listNumber: firstIndex + rowIndex, rowIndex: rowIndex)
                        if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                            subMenu.addItem(subMenuItem)
                        }
                    }
            }
    }

    func makeSnippetMenuItem(_ snippet: Snippet, listNumber: Int, rowIndex: Int) -> NSMenuItem {
        let shortcutText = numericShortcutText(forRowIndex: rowIndex)
        let isShowIcon = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: false)

        let menuItem = NSMenuItem(
            title: titleWithMark,
            action: #selector(AppDelegate.selectSnippetMenuItem(_:)),
            keyEquivalent: shortcutText ?? ""
        )
        menuItem.representedObject = snippet.id
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil
        menuItem.keyEquivalentModifierMask = []

        return menuItem
    }

    func selectSnippet(_ snippetID: Snippet.ID, restoring application: NSRunningApplication?) {
        dismissMenuPanelsAfterSelection()

        let menuItem = NSMenuItem(title: "", action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippetID

        if application?.isTerminated == false {
            application?.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.sendAction(#selector(AppDelegate.selectSnippetMenuItem(_:)), to: nil, from: menuItem)
        }
    }
}

// MARK: - Status Item
private extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        if type == .none { return }

        let image: NSImage?
        switch type {
        case .black:
            image = NSImage(resource: .statusbarMenuBlack)
        case .white:
            image = NSImage(resource: .statusbarMenuWhite)
        case .none: return
        }
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        statusItem?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = nil
        statusItem?.button?.image = image
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemButtonClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        guard let frame = sender.window?.frame else {
            showMainMenuPanel(at: NSEvent.mouseLocation)
            return
        }
        showMainMenuPanel(attachedToStatusItemFrame: frame)
    }
}

// MARK: - Settings
private extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}

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

    func showHistoryBrowserPanelForTesting(at screenPoint: NSPoint) {
        showHistoryBrowserPanel(at: screenPoint)
    }

    func showSnippetBrowserPanelForTesting() {
        showSnippetBrowserPanel()
    }

    func showSnippetFolderPanelForTesting(_ folderID: SnippetFolder.ID) {
        showSnippetFolderPanel(folderID, attachedTo: nil)
    }

    func showSnippetFolderPanelForTesting(_ folderID: SnippetFolder.ID, at screenPoint: NSPoint) { showSnippetFolderPanel(folderID, at: screenPoint) }

    func handlePanelDismissMouseDownForTesting(at screenPoint: NSPoint) {
        handlePanelDismissMouseDown(at: screenPoint)
    }

    func confirmFirstHistoryForTesting() {
        historyPanelController?.confirmFirstHistoryForTesting()
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
}
#endif
