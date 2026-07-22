//
//  PreferenceWindowShellTests.swift
//
//  Pastera
//

import AppKit
import Combine
import Dependencies
import DependenciesTestSupport
import Testing
@testable import Pastera

@MainActor
@Suite(
    .serialized,
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PreferenceWindowShellTests {
    @Test
    func windowUsesApprovedFrameSidebarPagesAndAutosave() throws {
        let autosaveName = "PreferenceWindowShellTests.\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(autosaveName)")
        defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(autosaveName)") }

        let (controller, _) = makeController(frameAutosaveName: autosaveName)
        defer { controller.close() }
        controller.showWindow(nil)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        #expect(controller.window?.frame.size == NSSize(width: 760, height: 600))
        #expect(controller.window?.minSize == NSSize(width: 680, height: 480))
        #expect(controller.preferenceSidebarWidthForTesting == 188)
        #expect(controller.preferenceSidebarTitlesForTesting == [
            "基础设置",
            "历史记录",
            "提示词优化",
            "脚本",
            "快捷键",
            "密码箱",
            "忽略应用",
            "Agent 集成",
            "云同步",
            "软件更新",
            "关于"
        ])
        #expect(controller.preferenceSidebarSymbolNamesForTesting == [
            "gearshape",
            "clock.arrow.circlepath",
            "wand.and.stars",
            "curlybraces.square",
            "keyboard",
            "lock.shield",
            "app.badge.checkmark",
            "terminal",
            "icloud",
            "arrow.triangle.2.circlepath",
            "info.circle"
        ])
        #expect(controller.preferenceSidebarGroupTitlesForTesting.isEmpty)
        #expect(controller.preferenceSidebarGroupSeparatorCountForTesting == 1)
        #expect(controller.preferencePageTopInsetForTesting == 14)
        #expect(controller.preferenceSidebarRowHeightForTesting == 40)
        #expect(controller.preferenceSidebarInsetForTesting == 16)
        #expect(controller.preferenceSidebarFontSizeForTesting == 14)
        #expect(controller.preferenceSidebarIconSlotWidthForTesting == 26)
        #expect(controller.preferenceSidebarIconPointSizeForTesting == 20)
        let iconDrawRects = controller.preferenceSidebarIconDrawRectsForTesting
        #expect(iconDrawRects.count == PasteraPreferencePaneID.allCases.count)
        #expect(iconDrawRects.allSatisfy { $0.width > 0 && $0.height > 0 })
        #expect(iconDrawRects.allSatisfy { $0.width <= 20 && $0.height <= 20 })
        #expect(controller.preferenceSidebarButtonHeightsForTesting.allSatisfy { 40...44 ~= $0 })
        #expect(controller.preferenceSelectedSidebarIconTintForTesting == .labelColor)
        #expect(controller.preferenceSelectedSidebarTitleColorForTesting == .labelColor)
        #expect(controller.preferenceFrameAutosaveNameForTesting == autosaveName)
    }

    @Test
    func sidebarUsesStableSpacingBetweenNavigationGroups() throws {
        let (controller, _) = makeController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let excludedAppsFrame = try #require(
            controller.preferenceSidebarButtonFrameForTesting(paneID: .excludedApps)
        )
        let syncFrame = try #require(
            controller.preferenceSidebarButtonFrameForTesting(paneID: .sync)
        )
        let agentIntegrationsFrame = try #require(
            controller.preferenceSidebarButtonFrameForTesting(paneID: .agentIntegrations)
        )
        let aboutFrame = try #require(
            controller.preferenceSidebarButtonFrameForTesting(paneID: .about)
        )
        let softwareUpdateFrame = try #require(
            controller.preferenceSidebarButtonFrameForTesting(paneID: .softwareUpdate)
        )

        #expect(aboutFrame.minY > 16)
        #expect(softwareUpdateFrame.minY > aboutFrame.maxY)
        #expect(syncFrame.minY > softwareUpdateFrame.maxY)
        #expect(agentIntegrationsFrame.minY > syncFrame.maxY)
        #expect(excludedAppsFrame.minY - agentIntegrationsFrame.maxY >= 8)
        #expect(excludedAppsFrame.minY - agentIntegrationsFrame.maxY <= 14)
    }

    @Test
    func commandFAndTwoStageEscapePreserveThePriorPaneThenClose() throws {
        let (controller, _) = makeController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(paneID: .shortcuts)

        let commandF = try makeKeyEvent(keyCode: 3, characters: "f", modifierFlags: [.command])
        let escape = try makeKeyEvent(keyCode: 53, characters: "\u{1B}")

        #expect(controller.handlePreferenceKeyboardEventForTesting(commandF))
        #expect(controller.preferenceSearchFieldIsFocusedForTesting)

        controller.setPreferenceSearchQueryForTesting(pasteraPreferenceString("Clear History"))
        #expect(controller.preferenceSearchResultsVisibleForTesting)
        #expect(controller.selectedPreferencePaneIDForTesting == .shortcuts)

        #expect(controller.handlePreferenceKeyboardEventForTesting(escape))
        #expect(controller.preferenceSearchQueryForTesting.isEmpty)
        #expect(controller.selectedPreferencePaneIDForTesting == .shortcuts)
        #expect(controller.window?.isVisible == true)

        #expect(controller.handlePreferenceKeyboardEventForTesting(escape))
        #expect(controller.window?.isVisible == false)
    }

    @Test
    func closingPreferencesOnlyDeactivatesWhenNoOtherApplicationWindowIsVisible() throws {
        let otherWindow = PreferenceVisibilityWindow()
        var deactivateCount = 0
        let (controller, _) = makeController(
            applicationWindows: { [otherWindow] },
            deactivateApplication: { deactivateCount += 1 }
        )
        defer { controller.close() }

        otherWindow.testIsVisible = true
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(deactivateCount == 0)

        otherWindow.testIsVisible = false
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(deactivateCount == 1)
    }

    @Test
    func pagesAreCachedAndSearchActivationRevealsTheExactAnchor() {
        let (controller, pages) = makeController()
        defer { controller.close() }

        let firstGeneralController = controller.cachedPreferencePageForTesting(paneID: .general)
        #expect(controller.cachedPreferencePageCountForTesting == 1)

        for paneID in PasteraPreferencePaneID.allCases {
            controller.showPreferencePaneForTesting(paneID: paneID)
        }
        #expect(controller.cachedPreferencePageCountForTesting == PasteraPreferencePaneID.allCases.count)

        controller.showPreferencePaneForTesting(paneID: .general)
        #expect(controller.cachedPreferencePageForTesting(paneID: .general) === firstGeneralController)

        controller.showPreferencePaneForTesting(paneID: .shortcuts)
        controller.setPreferenceSearchQueryForTesting(pasteraPreferenceString("Clear History"))
        #expect(controller.activatePreferenceSearchResultForTesting(itemID: "history.clearAll"))
        #expect(controller.selectedPreferencePaneIDForTesting == .history)
        #expect(pages[.history]?.revealCalls == [
            RevealCall(anchorID: "history.clearAll", animated: true)
        ])
    }

    @Test
    func defaultFactoryUsesEveryNativePageAndRevealsEveryAnchor() throws {
        try withDependencies {
            $0.pasteboardHistoryRepository = PreferenceWindowEmptyHistoryRepository()
        } operation: {
            let controller = makeNativeController()
            defer { controller.close() }
            controller.showWindow(nil)

            for paneID in PasteraPreferencePaneID.allCases {
                let page = try #require(PasteraPreferenceCatalog.default.pages.first { $0.paneID == paneID })
                for item in page.searchItems {
                    controller.setPreferenceSearchQueryForTesting(item.title)
                    #expect(controller.activatePreferenceSearchResultForTesting(itemID: item.id))
                    #expect(controller.selectedPreferencePaneIDForTesting == paneID)
                }
            }

            #expect(controller.cachedPreferencePageForTesting(paneID: .general) is CPYGeneralPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .history) is CPYHistoryPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .promptOptimization) is CPYPromptOptimizationPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .scripts) is CPYScriptsPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .shortcuts) is CPYShortcutsPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .passwordVault) is CPYPasswordVaultPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .excludedApps) is CPYExcludeAppPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .agentIntegrations) is CPYAgentIntegrationPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .sync) is CPYSyncPreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .softwareUpdate) is CPYSoftwareUpdatePreferenceViewController)
            #expect(controller.cachedPreferencePageForTesting(paneID: .about) is CPYAboutPreferenceViewController)
        }
    }

    @Test
    func paneFadeUses120MillisecondsAndDisablesMotionWhenRequested() {
        let (animatedController, _) = makeController(reduceMotion: false)
        defer { animatedController.close() }
        animatedController.showPreferencePaneForTesting(paneID: .history)
        #expect(animatedController.lastPaneTransitionDurationForTesting == 0.12)

        let (reducedMotionController, _) = makeController(reduceMotion: true)
        defer { reducedMotionController.close() }
        reducedMotionController.showPreferencePaneForTesting(paneID: .history)
        #expect(reducedMotionController.lastPaneTransitionDurationForTesting == 0)
    }

    @Test
    func autosavedFrameRestoresWithoutFirstShowRecentering() throws {
        let autosaveName = "PreferenceWindowShellTests.Restore.\(UUID().uuidString)"
        let defaultsKey = "NSWindow Frame \(autosaveName)"
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let visibleFrame = try #require(NSScreen.main?.visibleFrame)
        let savedFrame = NSRect(
            x: visibleFrame.minX + 37,
            y: visibleFrame.minY + 53,
            width: 700,
            height: 520
        )
        let (writer, _) = makeController(frameAutosaveName: autosaveName)
        writer.window?.setFrame(savedFrame, display: false)
        writer.window?.saveFrame(usingName: autosaveName)
        writer.close()

        let (restoredController, _) = makeController(frameAutosaveName: autosaveName)
        defer { restoredController.close() }
        restoredController.showWindow(nil)

        #expect(restoredController.window?.frame.origin == savedFrame.origin)
        #expect(restoredController.window?.frame.size == savedFrame.size)
    }

    @Test
    func nativePageUsesShellAsItsOnlyVisibleScrollOwner() {
        let pages = Dictionary(uniqueKeysWithValues: PasteraPreferencePaneID.allCases.map { paneID in
            (paneID, PasteraPreferencePageViewController(paneID: paneID, title: paneID.rawValue))
        })
        let controller = CPYPreferencesWindowController(
            catalog: .default,
            pageControllerProvider: { paneID in pages[paneID]! },
            reduceMotion: { false },
            frameAutosaveName: "PreferenceWindowShellTests.Native.\(UUID().uuidString)"
        )
        defer { controller.close() }

        controller.showWindow(nil)

        #expect(controller.visiblePreferenceScrollViewCountForTesting == 1)
        let generalPage = pages[.general]!
        #expect(generalPage.view.fittingSize.height >= 70)
        #expect(
            controller.selectedPaneDocumentHeightForTesting >= generalPage.view.fittingSize.height - 0.5
        )
    }

    @Test
    func onlyPasswordVaultUsesBalancedVerticalPositioning() {
        withDependencies {
            $0.pasteboardHistoryRepository = PreferenceWindowEmptyHistoryRepository()
        } operation: {
            let controller = makeNativeController()
            defer { controller.close() }
            controller.showWindow(nil)

            for paneID in PasteraPreferencePaneID.allCases {
                controller.showPreferencePaneForTesting(paneID: paneID)
                if paneID == .passwordVault,
                   controller.selectedPaneDocumentHeightForTesting + 32
                    < controller.preferencePaneViewportHeightForTesting {
                    #expect(controller.selectedPaneDocumentOriginForTesting.y > 16)
                    #expect(abs(
                        controller.selectedPaneDocumentOriginForTesting.y
                            - controller.preferencePaneVisibleBottomGapForTesting
                    ) <= 1)
                } else {
                    #expect(controller.selectedPaneDocumentOriginForTesting.y == 16)
                }
            }
        }
    }

    @Test
    func selectedPageRemeasuresWhenValidationContentBecomesVisible() throws {
        let controller = makeNativeController()
        defer { controller.close() }
        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(paneID: .general)
        let page = try #require(
            controller.cachedPreferencePageForTesting(paneID: .general) as? CPYGeneralPreferenceViewController
        )
        let field = try #require(preferenceTextFields(in: page.view).first {
            $0.accessibilityLabel() == pasteraPreferenceString("Menu Title Length")
        })
        let originalHeight = controller.selectedPaneDocumentHeightForTesting

        field.stringValue = "not-a-number"
        #expect(NSApp.sendAction(try #require(field.action), to: field.target, from: field))

        #expect(controller.selectedPaneDocumentHeightForTesting > originalHeight)
        #expect(controller.preferencePaneHasVerticalScrollerForTesting)
    }

    @Test
    func nativePageRevealScrollsExactAnchorAndReplacesTemporaryHighlight() {
        let page = PasteraPreferencePageViewController(paneID: .general, title: "General")
        let documentView = page.view
        documentView.frame = NSRect(x: 0, y: 0, width: 320, height: 1_000)

        let firstAnchor = NSView(frame: NSRect(x: 20, y: 820, width: 260, height: 80))
        let secondAnchor = NSView(frame: NSRect(x: 20, y: 120, width: 260, height: 80))
        documentView.addSubview(firstAnchor)
        documentView.addSubview(secondAnchor)
        page.registerAnchor("general.first", view: firstAnchor)
        page.registerAnchor("general.second", view: secondAnchor)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        scrollView.documentView = documentView
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(page.revealSetting(anchorID: "general.first", animated: true))
        let firstFrame = firstAnchor.convert(firstAnchor.bounds, to: documentView)
        #expect(scrollView.contentView.bounds.intersects(firstFrame))
        #expect(page.highlightedAnchorIDForTesting == "general.first")
        #expect(page.lastRevealAnimatedForTesting == true)
        #expect(page.highlightDurationForTesting == 1.0)

        #expect(page.revealSetting(anchorID: "general.second", animated: false))
        #expect(page.highlightedAnchorIDForTesting == "general.second")
        #expect(page.lastRevealAnimatedForTesting == false)
        #expect(!page.isAnchorHighlightedForTesting("general.first"))
        #expect(page.isAnchorHighlightedForTesting("general.second"))

        page.completeHighlightForTesting()
        #expect(page.highlightedAnchorIDForTesting == nil)
        #expect(!page.isAnchorHighlightedForTesting("general.second"))
        #expect(!page.revealSetting(anchorID: "general.missing", animated: true))
    }

    private func makeController(
        frameAutosaveName: String = "PreferenceWindowShellTests.Default.\(UUID().uuidString)",
        reduceMotion: Bool = false,
        applicationWindows: @escaping () -> [NSWindow] = { [] },
        deactivateApplication: @escaping () -> Void = {}
    ) -> (CPYPreferencesWindowController, [PasteraPreferencePaneID: PreferencePageSpy]) {
        let pages = Dictionary(uniqueKeysWithValues: PasteraPreferencePaneID.allCases.map { paneID in
            (paneID, PreferencePageSpy(paneID: paneID))
        })
        let controller = CPYPreferencesWindowController(
            catalog: .default,
            pageControllerProvider: { paneID in pages[paneID]! },
            reduceMotion: { reduceMotion },
            frameAutosaveName: frameAutosaveName,
            applicationWindows: applicationWindows,
            deactivateApplication: deactivateApplication
        )
        return (controller, pages)
    }

    private func makeNativeController() -> CPYPreferencesWindowController {
        withDependencies {
            $0.pasteboardHistoryRepository = PreferenceWindowEmptyHistoryRepository()
        } operation: {
            CPYPreferencesWindowController(
                frameAutosaveName: "PreferenceWindowShellTests.Native.\(UUID().uuidString)",
                reduceMotion: { true },
                deactivateApplication: {}
            )
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
}

private struct PreferenceWindowEmptyHistoryRepository: PasteboardHistoryRepositoryProtocol {
    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> { Just([]).eraseToAnyPublisher() }
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

private func preferenceTextFields(in view: NSView) -> [NSTextField] {
    view.subviews.compactMap { $0 as? NSTextField }
        + view.subviews.flatMap { preferenceTextFields(in: $0) }
}

private struct RevealCall: Equatable {
    let anchorID: String
    let animated: Bool
}

private final class PreferencePageSpy: NSViewController, PasteraPreferencePage {
    let paneID: PasteraPreferencePaneID
    private(set) var revealCalls = [RevealCall]()

    init(paneID: PasteraPreferencePaneID) {
        self.paneID = paneID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
    }

    func revealSetting(anchorID: String, animated: Bool) -> Bool {
        revealCalls.append(RevealCall(anchorID: anchorID, animated: animated))
        return true
    }
}

private final class PreferenceVisibilityWindow: NSWindow {
    var testIsVisible = false

    override var isVisible: Bool {
        testIsVisible
    }
}
