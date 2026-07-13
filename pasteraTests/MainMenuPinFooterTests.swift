//
//  MainMenuPinFooterTests.swift
//
//  Clipy
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MainMenuOneDriveFooterTests {
    @Test
    func mainMenuPanelPlacesOneDriveStatusInFooterWithoutQuitOrPin() throws {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notRunning(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil, shortcutText: "⌃⌥⌘1") { _ in },
                    .separator,
                    .action(title: "Preferences", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuPinButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuQuitButton"))
        let statusFrames = controller.mainMenuOneDriveStatusButtonFramesForTesting
        #expect(statusFrames.count == 1)
        let statusFrame = try #require(statusFrames.first)
        let folderRowFrame = try #require(controller.mainMenuSnippetRowFrameForTesting(title: "AI Prompt"))
        let folderTitleFrame = try #require(controller.mainMenuSnippetTitleFrameForTesting(title: "AI Prompt"))
        let preferencesRowFrame = try #require(controller.mainMenuActionRowFrameForTesting(title: "Preferences"))

        #expect(statusFrame.maxX <= MainMenuPanelLayout.width - MainMenuPanelLayout.oneDriveStatusTrailingInset)
        #expect(abs(statusFrame.midY - (
            MainMenuPanelLayout.bottomInset + MainMenuPanelLayout.toolbarHeight / 2
        )) <= 1)
        #expect(preferencesRowFrame.minY >= MainMenuPanelLayout.bottomInset + MainMenuPanelLayout.toolbarHeight)
        #expect(MainMenuPanelLayout.headerHeight == 40)
        #expect(MainMenuPanelLayout.snippetFolderRowHeight == 25)
        #expect(folderRowFrame.height == MainMenuPanelLayout.snippetFolderRowHeight)
        #expect(preferencesRowFrame.height == MainMenuPanelLayout.rowHeight)
        #expect(abs(folderTitleFrame.midY - MainMenuPanelLayout.snippetFolderRowHeight / 2) <= 1)
        #expect(controller.visibleFrame?.size == NSSize(
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.fixedHeight
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
                    .action(title: "Preferences", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        let titleAvailableWidth = try #require(
            controller.mainMenuSnippetTitleAvailableWidthForTesting(title: "AI Prompt")
        )
        let preferencesTitleAvailableWidth = try #require(
            controller.mainMenuActionTitleAvailableWidthForTesting(title: "Preferences")
        )

        #expect(MainMenuPanelLayout.width == 282)
        #expect(titleAvailableWidth >= menuTitleWidth("AI Prompt"))
        #expect(preferencesTitleAvailableWidth >= menuTitleWidth("Preferences"))
    }

    @Test
    func visibleMainMenuPanelBackgroundProtectsReadabilityFromOpacityChange() throws {
        let suiteName = "MainMenuOneDriveFooterTests.opacity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.94, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        try withDependencies {
            $0.mainQueue = .immediate
            $0.pasteboardHistoryRepository = MainMenuEmptyHistoryRepository()
            $0.snippetRepository = MainMenuEmptySnippetRepository()
        } operation: {
            let manager = MenuManager()
            manager.setup()
            manager.showMainMenuPanelForTesting(at: NSPoint(x: 180, y: 700))
            defer {
                manager.closeMainMenuPanelForTesting()
                manager.removeStatusItemForTesting()
            }

            #expect((manager.mainMenuPanelBackgroundAlphaForTesting ?? 0) >= 0.98)

            CPYWindowAppearance.setOpacity(0.82, defaults: defaults)

            #expect((manager.mainMenuPanelBackgroundAlphaForTesting ?? 0) >= 0.98)
        }
    }

    @Test
    func mainMenuDoesNotShowClearHistoryAction() throws {
        let suiteName = "MainMenuOneDriveFooterTests.clearHistory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: Constants.UserDefaults.addClearHistoryMenuItem)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let titles = withDependencies {
            $0.snippetRepository = MainMenuEmptySnippetRepository()
        } operation: {
            MenuManager().mainMenuPanelActionTitlesForTesting
        }

        #expect(!titles.contains(String(localized: "Clear History")))
        #expect(!titles.contains(String(localized: "Quit Pastera")))
        #expect(!titles.contains(String(localized: "Edit Snippets")))
    }

    @Test
    func mainMenuOneDriveStatusButtonReflectsOfflineAndRunningStates() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notRunning(
            appURL: appURL
        ))
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [.action(title: "Preferences", image: nil) {}]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuOneDriveStatusToolTipForTesting?.contains("未运行") == true)
        #expect(controller.mainMenuOneDriveStatusTintColorForTesting?.isEqual(NSColor.secondaryLabelColor) == true)

        oneDriveService.status = .running(appURL: appURL)
        controller.reloadOneDriveStatusIfVisible()

        #expect(controller.mainMenuOneDriveStatusToolTipForTesting?.contains("正在运行") == true)
        #expect(controller.mainMenuOneDriveStatusTintColorForTesting?.isEqual(NSColor.systemBlue) == true)
    }

    @Test
    func downArrowFromHoveredHistorySelectsSnippetFolderAndOpensIt() throws {
        var openHistoryCount = 0
        var openedSnippetTitles = [String]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetTitles.append("AI Prompt")
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "History")

        #expect(controller.handleMainMenuNavigationForTesting(try makeArrowEvent(keyCode: 125)))

        #expect(controller.selectedMainMenuTitleForTesting == "AI Prompt")
        #expect(openHistoryCount == 0)
        #expect(openedSnippetTitles == ["AI Prompt"])
    }

    @Test
    func upArrowFromHoveredSnippetFolderSelectsHistoryAndOpensIt() throws {
        var openHistoryCount = 0
        var openedSnippetCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetCount += 1
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "AI Prompt")

        #expect(controller.handleMainMenuNavigationForTesting(try makeArrowEvent(keyCode: 126)))

        #expect(controller.selectedMainMenuTitleForTesting == "History")
        #expect(openHistoryCount == 1)
        #expect(openedSnippetCount == 0)
    }

    @Test
    func returnKeyConfirmsSelectedHistoryRow() throws {
        var openHistoryCount = 0
        var openedSnippetCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetCount += 1
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "History")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 36, characters: "\r")))

        #expect(openHistoryCount == 1)
        #expect(openedSnippetCount == 0)
        #expect(controller.selectedMainMenuTitleForTesting == "History")
    }

    @Test
    func spaceKeyConfirmsSelectedSnippetFolderRow() throws {
        var openHistoryCount = 0
        var openedSnippetTitles = [String]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetTitles.append("AI Prompt")
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "AI Prompt")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 49, characters: " ")))

        #expect(openHistoryCount == 0)
        #expect(openedSnippetTitles == ["AI Prompt"])
        #expect(controller.selectedMainMenuTitleForTesting == "AI Prompt")
    }

    @Test
    func returnKeyConfirmsSelectedActionRow() throws {
        var didOpenHistory = false
        var didOpenSnippet = false
        var didSelectAction = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        didOpenSnippet = true
                    },
                    .separator,
                    .action(title: "Preferences", image: nil) {
                        didSelectAction = true
                    }
                ]
            },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "Preferences")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 36, characters: "\r")))

        #expect(didSelectAction)
        #expect(!didOpenHistory)
        #expect(!didOpenSnippet)
    }

    @Test
    func commandFExpandsMainMenuSearch() throws {
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(
            keyCode: 3,
            characters: "f",
            modifierFlags: .command
        )))
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
            + MainMenuPanelLayout.toolbarHeight
            + MainMenuPanelLayout.bottomInset
    }

    private func menuTitleWidth(_ title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .medium)
        ]).width)
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

    private func makeKeyboardEvent(
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

}

@MainActor
@Suite(.serialized)
struct MainMenuOneDriveInstallationFooterTests {
    @Test
    func mainMenuShowsOneDriveStatusButtonWhenOneDriveIsNotInstalled() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notInstalled)
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [.action(title: "Preferences", image: nil) {}]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuOneDriveStatusButton"))
        #expect(controller.mainMenuOneDriveStatusButtonFramesForTesting.count == 1)
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuPinButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuQuitButton"))
    }
}

@Suite(.serialized)
struct MainMenuOneDriveStatusAssetTests {
    @Test
    func oneDriveStatusTemplateAssetKeepsSuppliedLogoMaskWithoutBlueBackground() throws {
        let assetURL = mainMenuProjectRoot()
            .appendingPathComponent(
                "pastera/Resources/Assets.xcassets/StatusIcon/" +
                    "onedrive_status_template.imageset/onedrive_status_template@2x.png"
            )
        let data = try Data(contentsOf: assetURL)
        let image = try #require(NSBitmapImageRep(data: data))

        #expect(image.pixelsWide == 36)
        #expect(image.pixelsHigh == 36)
        #expect(image.hasAlpha)

        var visiblePixels = 0
        var interiorTransparentPixels = 0
        var blueBackgroundPixels = 0
        var minColumn = image.pixelsWide
        var maxColumn = 0
        var minRow = image.pixelsHigh
        var maxRow = 0

        for row in 0..<image.pixelsHigh {
            for column in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent > 0.08 {
                    visiblePixels += 1
                    minColumn = min(minColumn, column)
                    maxColumn = max(maxColumn, column)
                    minRow = min(minRow, row)
                    maxRow = max(maxRow, row)
                    if color.blueComponent > color.redComponent + 0.1,
                       color.blueComponent > color.greenComponent + 0.1 {
                        blueBackgroundPixels += 1
                    }
                }
            }
        }

        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                guard let color = image.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent < 0.04 {
                    interiorTransparentPixels += 1
                }
            }
        }

        #expect(visiblePixels > 250)
        #expect(maxColumn - minColumn + 1 >= 30)
        #expect(maxRow - minRow + 1 >= 21)
        #expect(blueBackgroundPixels == 0)
        #expect(interiorTransparentPixels > 40)
    }

    private func mainMenuProjectRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pastera.xcodeproj").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

@MainActor
@Suite(.serialized)
struct MainMenuFooterButtonActionTests {
    @Test
    func mainMenuFooterOneDriveStatusOpensOneDriveWithoutOpeningHistory() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notRunning(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        var didOpenHistory = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        controller.performMainMenuOneDriveStatusClickForTesting()

        #expect(oneDriveService.openCallCount == 1)
        #expect(!didOpenHistory)
    }

    @Test
    func mainMenuFooterDoesNotExposeQuitButton() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notInstalled)
        var didOpenHistory = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuQuitButton"))
        #expect(oneDriveService.openCallCount == 0)
        #expect(!didOpenHistory)
    }
}

@MainActor
@Suite(.serialized)
struct OneDriveProcessStatusServiceTests {
    @Test
    func reportsRunningWhenMainOneDriveProcessIsPresent() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = makeService(
            applicationURL: appURL,
            runningApplications: [
                OneDriveRunningApplicationSnapshot(
                    bundleIdentifier: "com.microsoft.OneDrive-mac",
                    executableURL: appURL.appendingPathComponent("Contents/MacOS/OneDrive"),
                    localizedName: "OneDrive"
                )
            ]
        )

        guard case let .running(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected OneDrive to be running")
            return
        }
        #expect(statusAppURL == appURL)
    }

    @Test
    func fileProviderProcessAloneDoesNotCountAsRunning() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = makeService(
            applicationURL: appURL,
            runningApplications: [
                OneDriveRunningApplicationSnapshot(
                    bundleIdentifier: "com.microsoft.OneDrive-mac.FileProvider",
                    executableURL: appURL.appendingPathComponent(
                        "Contents/PlugIns/OneDrive File Provider.appex/Contents/MacOS/OneDrive File Provider"
                    ),
                    localizedName: "OneDrive File Provider"
                )
            ]
        )

        guard case let .notRunning(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected OneDrive main app to be offline")
            return
        }
        #expect(statusAppURL == appURL)
    }

    @Test
    func installedOneDriveWithoutProcessIsNotRunningAndKeepsAppURL() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = makeService(applicationURL: appURL, runningApplications: [])

        guard case let .notRunning(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected installed OneDrive to be offline")
            return
        }
        #expect(statusAppURL == appURL)
    }

    @Test
    func staleBundleIdentifierApplicationURLIsTreatedAsNotInstalled() {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive-mac" ? appURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { _ in false },
            runningApplicationsProvider: { [] },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter()
        )

        guard case .notInstalled = service.currentStatus() else {
            Issue.record("Expected stale OneDrive application URL to be ignored")
            return
        }
        #expect(!service.openOneDrive())
    }

    @Test
    func missingOneDriveIsNotInstalledAndCannotOpen() {
        let service = makeService(applicationURL: nil, runningApplications: [])

        guard case .notInstalled = service.currentStatus() else {
            Issue.record("Expected missing OneDrive to be not installed")
            return
        }
        #expect(!service.openOneDrive())
    }

    @Test
    func supportsLegacyOneDriveBundleIdentifierLookup() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive" ? appURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { path in
                URL(fileURLWithPath: path).standardizedFileURL.path == appURL.standardizedFileURL.path
            },
            runningApplicationsProvider: { [] },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter()
        )

        guard case let .notRunning(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected legacy bundle id lookup to find installed OneDrive")
            return
        }
        #expect(statusAppURL == appURL)
    }

    private func makeService(
        applicationURL: URL?,
        runningApplications: [OneDriveRunningApplicationSnapshot]
    ) -> OneDriveProcessStatusService {
        OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive-mac" ? applicationURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { path in
                applicationURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
            },
            runningApplicationsProvider: { runningApplications },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter()
        )
    }
}

private final class MainMenuFakeOneDriveProcessStatusService: OneDriveProcessStatusServicing {
    var status: OneDriveProcessStatus
    var openCallCount = 0

    init(status: OneDriveProcessStatus) {
        self.status = status
    }

    func currentStatus() -> OneDriveProcessStatus {
        status
    }

    func openOneDrive() -> Bool {
        openCallCount += 1
        return true
    }

    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation {
        OneDriveProcessStatusObservation {}
    }
}

private struct MainMenuEmptyHistoryRepository: PasteboardHistoryRepositoryProtocol {
    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { false }
    func fetchHistoryDetails(ascending: Bool, includesThumbnailAsset: Bool, limit: Int, offset: Int) -> [PasteboardHistoryDetail] { [] }
    func searchHistoryDetails(query: HistorySearchQuery, includesThumbnailAsset: Bool, limit: Int, offset: Int) throws -> [PasteboardHistoryDetail] { [] }
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { nil }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private struct MainMenuEmptySnippetRepository: SnippetRepositoryProtocol {
    func observeFolders() -> AnyPublisher<[SnippetFolder], Never> {
        Empty().eraseToAnyPublisher()
    }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func fetchFolders() -> [SnippetFolder] { [] }
    func fetchFolderDetails() -> [SnippetFolderDetail] { [] }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { nil }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func removeDuplicateFoldersAndSnippets() -> Int { 0 }
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool { true }
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool { true }
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}
