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
    fileprivate var historyPanelController: HistoryBrowserPanelController?
    fileprivate var mainMenuPanelController: MainMenuPanelController?
    fileprivate var isMainMenuPinned = false

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
        let folderMenu = NSMenu(title: folderDetail.folder.title)
        // Folder title
        let labelItem = NSMenuItem(title: folderDetail.folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        // Snippets
        var index = firstIndexOfMenuItems()
        folderDetail.snippets
            .filter { $0.isEnabled }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index)
                folderMenu.addItem(subMenuItem)
                index += 1
            }
        folderMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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

        addSnippetItems(clipMenu!, separateMenu: true)
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

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
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
            isPinned: isMainMenuPinned
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

    func showHistoryBrowserPanel(at screenPoint: NSPoint) {
        let panelController = historyPanelController ?? makeHistoryPanelController()
        historyPanelController = panelController
        if let mainMenuFrame = mainMenuPanelController?.visibleFrame {
            panelController.setPinned(true)
            panelController.show(attachedTo: mainMenuFrame)
        } else {
            panelController.setPinned(false)
            panelController.show(at: screenPoint)
        }
    }

    func showMainMenuPanel(at screenPoint: NSPoint) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        panelController.show(at: screenPoint, pinned: isMainMenuPinned)
    }

    func showMainMenuPanel(anchoredTo menuFrame: NSRect?, fallbackPoint: NSPoint) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        if let menuFrame {
            panelController.show(anchoredTo: menuFrame, pinned: true)
        } else {
            panelController.show(at: fallbackPoint, pinned: true)
        }
    }

    func showMainMenuPanel(attachedToStatusItemFrame statusItemFrame: NSRect) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        panelController.show(attachedToStatusItemFrame: statusItemFrame, pinned: isMainMenuPinned)
    }

    func setMainMenuPinned(_ pinned: Bool) {
        isMainMenuPinned = pinned
        if !pinned {
            mainMenuPanelController?.close()
        }
        createClipMenu()
    }

    func makeHistoryPanelController() -> HistoryBrowserPanelController {
        HistoryBrowserPanelController(
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
    }

    func makeMainMenuPanelController() -> MainMenuPanelController {
        MainMenuPanelController(
            historyTitle: String(localized: "History"),
            historyImage: AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu) ? folderIcon : nil,
            itemsProvider: { [weak self] in self?.makeMainMenuPanelItems() ?? [] },
            onOpenHistory: { [weak self] in self?.showHistoryBrowserPanel(at: NSEvent.mouseLocation) },
            onPinnedChange: { [weak self] pinned in self?.setMainMenuPinned(pinned) }
        )
    }

    func makeMainMenuPanelItems() -> [MainMenuPanelItem] {
        var items = [MainMenuPanelItem]()

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            items.append(.action(title: String(localized: "Clear History"), image: nil) {
                NSApp.sendAction(#selector(AppDelegate.clearAllHistory), to: nil, from: nil)
            })
        }

        items.append(.action(title: String(localized: "Edit Snippets"), image: nil) {
            NSApp.sendAction(#selector(AppDelegate.showSnippetEditorWindow), to: nil, from: nil)
        })
        items.append(.action(title: String(localized: "Preferences"), image: nil) {
            NSApp.sendAction(#selector(AppDelegate.showPreferenceWindow), to: nil, from: nil)
        })
        items.append(.separator)
        items.append(.action(title: String(localized: "Quit Pastera"), image: nil) {
            NSApp.sendAction(#selector(AppDelegate.terminate), to: nil, from: nil)
        })

        return items
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
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)

        var keyEquivalent = ""

        if addNumbericKeyEquivalents && (index <= kMaxKeyEquivalents) {
            let isStartFromZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)

            var shortCutNumber = (isStartFromZero) ? index : index + 1
            if shortCutNumber == kMaxKeyEquivalents {
                shortCutNumber = 0
            }
            keyEquivalent = "\(shortCutNumber)"
        }

        let presentation = makeHistoryItemPresentation(historyDetail, listNumber: listNumber)

        let menuItem = NSMenuItem(title: presentation.title, action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: keyEquivalent)
        menuItem.representedObject = history.id

        if let toolTip = presentation.toolTip {
            menuItem.toolTip = toolTip
        }

        menuItem.image = presentation.image

        menuItem.view = HistoryMenuRowView(title: menuItem.title, image: menuItem.image) { [weak menuItem] in
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
        let presentation = makeHistoryItemPresentation(historyDetail, listNumber: listNumber)
        return HistoryMenuRowView(title: presentation.title, image: presentation.image, onConfirm: onConfirm)
    }

    func makeHistoryItemPresentation(_ historyDetail: PasteboardHistoryDetail, listNumber: Int) -> HistoryItemPresentation {
        let history = historyDetail.history
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowToolTip = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        let isShowImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let primaryPboardType = history.primaryType
        let clipString = history.title
        var title = menuItemTitle(trimTitle(clipString), listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

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

    func selectHistory(_ historyID: PasteboardHistory.ID, restoring application: NSRunningApplication?) {
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

                var i = firstIndex
                detail.snippets
                    .filter { $0.isEnabled }
                    .forEach { snippet in
                        let subMenuItem = makeSnippetMenuItem(snippet, listNumber: i)
                        if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                            subMenu.addItem(subMenuItem)
                            i += 1
                        }
                    }
            }
    }

    func makeSnippetMenuItem(_ snippet: Snippet, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.id
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil

        return menuItem
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

    func showMainMenuPanelForTesting(at screenPoint: NSPoint) {
        isMainMenuPinned = true
        showMainMenuPanel(at: screenPoint)
    }

    func showHistoryBrowserPanelForTesting(at screenPoint: NSPoint) {
        showHistoryBrowserPanel(at: screenPoint)
    }

    func closeHistoryBrowserPanelForTesting() {
        historyPanelController?.close()
    }
}
#endif
