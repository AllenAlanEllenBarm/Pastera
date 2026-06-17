//
//  CPYWindowAppearanceTests.swift
//
//  Clipy
//

import Cocoa
import Carbon
import Combine
import Dependencies
import Magnet
import Testing
@testable import Pastera

@Suite(.serialized)
struct CPYWindowAppearanceTests {
    @Test
    func designTokensExposeReadableNativePalette() {
        let lightTokens = PasteraDesignTokens.colors(for: NSAppearance(named: .aqua))
        let darkTokens = PasteraDesignTokens.colors(for: NSAppearance(named: .darkAqua))

        #expect(lightTokens.panelBackground.alphaComponent >= 0.94)
        #expect(lightTokens.separator.alphaComponent <= 0.18)
        #expect(lightTokens.selectedRow != lightTokens.hoveredRow)
        #expect(darkTokens.panelBackground != lightTokens.panelBackground)
        #expect(PasteraDesignTokens.Metrics.panelCornerRadius == 16)
        #expect(PasteraDesignTokens.Motion.standardDuration <= 0.16)
    }

    @Test
    func confirmationOptionsPreserveDestructiveAndSuppressionSemantics() {
        let options = PasteraConfirmationOptions(
            title: "Clear History",
            message: "Are you sure you want to clear your clipboard history?",
            confirmTitle: "Clear History",
            cancelTitle: "Cancel",
            isDestructive: true,
            suppressionTitle: "Don't ask again"
        )

        #expect(options.isDestructive)
        #expect(options.confirmTitle == "Clear History")
        #expect(options.cancelTitle == "Cancel")
        #expect(options.suppressionTitle == "Don't ask again")
    }

    @Test
    func normalizedOpacityClampsToSupportedRange() {
        #expect(CPYWindowAppearance.defaultOpacity == 0.94)
        #expect(CPYWindowAppearance.minimumOpacity == 0)
        #expect(CPYWindowAppearance.normalizedOpacity(-0.1) == CPYWindowAppearance.minimumOpacity)
        #expect(CPYWindowAppearance.normalizedOpacity(0.1) == 0.1)
        #expect(CPYWindowAppearance.normalizedOpacity(0.82) == 0.82)
        #expect(CPYWindowAppearance.normalizedOpacity(2.0) == CPYWindowAppearance.maximumOpacity)
    }

    @Test
    func normalizedOpacityUsesDefaultForNonFiniteValues() {
        #expect(CPYWindowAppearance.normalizedOpacity(.nan) == CPYWindowAppearance.defaultOpacity)
        #expect(CPYWindowAppearance.normalizedOpacity(.infinity) == CPYWindowAppearance.defaultOpacity)
    }

    @Test
    func opacityUsesDefaultWhenPreferenceIsMissing() throws {
        let suiteName = "CPYWindowAppearanceTests.default.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(CPYWindowAppearance.opacity(defaults: defaults) == CPYWindowAppearance.defaultOpacity)
    }

    @Test
    func opacityReadsAndClampsStoredPreference() throws {
        let suiteName = "CPYWindowAppearanceTests.stored.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(0.2, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        #expect(CPYWindowAppearance.opacity(defaults: defaults) == 0.2)

        defaults.set(0.72, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        #expect(CPYWindowAppearance.opacity(defaults: defaults) == 0.72)

        defaults.set(-0.2, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        #expect(CPYWindowAppearance.opacity(defaults: defaults) == CPYWindowAppearance.minimumOpacity)
    }

    @Test @MainActor
    func applyingWindowAppearancePreservesTitlebarTransparency() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { retainWindowForAppKitTest(window) }

        window.titlebarAppearsTransparent = false
        CPYWindowAppearance.apply(to: window)
        #expect(window.titlebarAppearsTransparent == false)

        window.titlebarAppearsTransparent = true
        CPYWindowAppearance.apply(to: window)
        #expect(window.titlebarAppearsTransparent == true)
    }

    @Test @MainActor
    func applyingWindowAppearanceUsesOpacityForStandardWindows() throws {
        let suiteName = "CPYWindowAppearanceTests.opaque.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { retainWindowForAppKitTest(window) }

        defaults.set(0, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        window.contentView = NSView(frame: window.contentView?.bounds ?? .zero)

        CPYWindowAppearance.apply(to: window, defaults: defaults)

        #expect(window.isOpaque == false)
        #expect(abs(window.backgroundColor.alphaComponent - 0) < 0.001)
        #expect(abs(Double(window.contentView?.layer?.backgroundColor?.alpha ?? 0) - 0) < 0.001)
    }

    @Test @MainActor
    func applyingWindowAppearanceKeepsPanelsTranslucent() throws {
        let suiteName = "CPYWindowAppearanceTests.panel.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { retainWindowForAppKitTest(panel) }

        defaults.set(0.82, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        panel.contentView = NSView(frame: panel.contentView?.bounds ?? .zero)

        CPYWindowAppearance.apply(to: panel, defaults: defaults)

        #expect(panel.isOpaque == false)
        #expect(abs(panel.backgroundColor.alphaComponent - 0.82) < 0.001)
        #expect(panel.contentView?.layer?.backgroundColor == NSColor.clear.cgColor)
    }

    @Test @MainActor
    func applyingWindowAppearanceKeepsTopNavigationBackgroundOpaque() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { retainWindowForAppKitTest(window) }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let paneView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 184))
        let navigationView = NSView(frame: NSRect(x: 0, y: 184, width: 320, height: 56))
        contentView.addSubview(paneView)
        contentView.addSubview(navigationView)
        window.contentView = contentView

        CPYWindowAppearance.apply(to: window)

        #expect((contentView.layer?.backgroundColor?.alpha ?? 0) < 1)
        #expect((contentView.layer?.backgroundColor?.alpha ?? 0) >= CGFloat(CPYWindowAppearance.minimumOpacity))
        #expect(paneView.layer?.backgroundColor == nil)
        #expect(navigationView.layer?.backgroundColor?.alpha ?? 0 < 1)
    }

    @Test @MainActor
    func applyingWindowAppearanceKeepsTopNavigationItemBackgroundsOpaque() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { retainWindowForAppKitTest(window) }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let navigationView = NSView(frame: NSRect(x: 0, y: 184, width: 320, height: 56))
        let navigationItemView = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 56))
        navigationView.addSubview(navigationItemView)
        contentView.addSubview(navigationView)
        window.contentView = contentView

        CPYWindowAppearance.apply(to: window)

        #expect(navigationView.layer?.backgroundColor?.alpha ?? 0 < 1)
        #expect(navigationItemView.layer?.backgroundColor?.alpha ?? 0 < 1)
    }

    @Test @MainActor
    func applyToVisibleWindowsOnlyUpdatesManagedClipyWindows() throws {
        let suiteName = "CPYWindowAppearanceTests.visible.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let managedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let unmanagedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer {
            retainWindowForAppKitTest(managedWindow)
            retainWindowForAppKitTest(unmanagedWindow)
        }

        defaults.set(0.9, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        CPYWindowAppearance.apply(to: managedWindow, defaults: defaults)
        unmanagedWindow.backgroundColor = .systemRed
        unmanagedWindow.isOpaque = true
        managedWindow.orderFront(nil)
        unmanagedWindow.orderFront(nil)

        defaults.set(0.45, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        CPYWindowAppearance.applyToVisibleWindows(defaults: defaults)

        let managedAlpha = Double(managedWindow.backgroundColor.alphaComponent)
        #expect(abs(managedAlpha - 0.45) < 0.001)
        #expect(unmanagedWindow.backgroundColor == .systemRed)
        #expect(unmanagedWindow.isOpaque)
    }

    @Test @MainActor
    func generalPreferenceOpacityControlDoesNotShiftExistingPaneContent() {
        let controller = CPYGeneralPreferenceViewController(
            nibName: "CPYGeneralPreferenceViewController",
            bundle: nil
        )

        let paneView = controller.view
        let buttons = paneView.subviews.compactMap { $0 as? NSButton }
        let buttonTitles = Set(buttons.map(\.title))
        let launchButton = buttons.first { ["Launch on Login", "登录时打开"].contains($0.title) }
        let clearButton = buttons.first { $0.title == String(localized: "Clear History") }
        let warningButton = buttons.first { $0.title == String(localized: "Show alert panel before clear history") }
        let removedTitles: Set<String> = [
            "Input \"⌘ + V\" after menu item selection",
            "Send crash report and error log (reflected at the next launch)"
        ]

        #expect(Int(paneView.frame.height.rounded()) == 162)
        #expect(buttonTitles.isDisjoint(with: removedTitles))
        #expect(Int((launchButton?.frame.maxY ?? 0).rounded()) == 144)
        #expect(abs((clearButton?.frame.minX ?? 0) - (launchButton?.frame.minX ?? 0)) <= 2)
        #expect(abs((warningButton?.frame.minX ?? 0) - (launchButton?.frame.minX ?? 0)) <= 2)
    }

    @Test @MainActor
    func preferenceWindowKeepsLegacyPaneTextReadableInDarkMode() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        controller.window?.appearance = darkAppearance
        controller.showWindow(nil)

        let labels = enabledLabelTextFields(in: try #require(controller.window?.contentView))
        #expect(labels.count >= 4)

        for label in labels {
            let brightness = perceivedBrightness(label.textColor, appearance: darkAppearance)
            #expect(
                brightness >= 0.50,
                "Expected readable text for '\(label.stringValue)', brightness: \(brightness)"
            )
        }
    }

    @Test @MainActor
    func preferenceWindowUsesDarkTranslucentSidebarColors() throws {
        let suiteName = "CPYWindowAppearanceTests.preferenceDark.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.82, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        controller.window?.appearance = darkAppearance
        controller.showWindow(nil)

        #expect(abs(controller.rootBackgroundAlphaForTesting - 0.82) < 0.001)
        #expect(controller.sidebarBackgroundBrightnessForTesting < 0.35)
    }

    @Test @MainActor
    func snippetEditorUsesDarkTranslucentWorkbenchColors() throws {
        let suiteName = "CPYWindowAppearanceTests.snippetDark.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.82, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        try withDependencies {
            $0.snippetRepository = SnippetEditorStaticSnippetRepository(details: [])
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            let darkAppearance = try #require(NSAppearance(named: .darkAqua))
            controller.window?.appearance = darkAppearance
            controller.showWindow(nil)

            #expect(abs(controller.rootBackgroundAlphaForTesting - 0.82) < 0.001)
            #expect(controller.toolbarBackgroundBrightnessForTesting < 0.35)
            #expect(controller.textEditorBackgroundBrightnessForTesting < 0.35)
        }
    }

    @Test @MainActor
    func snippetEditorUsesCompactWorkbenchMetrics() {
        #expect(CPYSnippetsEditorWindowController.Layout.defaultWindowSize == NSSize(width: 680, height: 400))
        #expect(CPYSnippetsEditorWindowController.Layout.minimumWindowSize == NSSize(width: 600, height: 340))
        #expect(CPYSnippetsEditorWindowController.Layout.toolbarHeight == 48)
        #expect(CPYSnippetsEditorWindowController.Layout.leftPaneWidth == 220)
        #expect(CPYSnippetsEditorWindowController.Layout.detailInset == 8)
    }

    @Test @MainActor
    func snippetEditorMovesNameEditingIntoOutline() {
        let controller = CPYSnippetsEditorWindowController()
        defer { controller.close() }

        #expect(controller.usesOutlineDoubleClickEditingForTests)
        #expect(!controller.showsFolderTitleFieldForTesting)
        #expect(controller.showsSnippetContentEditorOnlyForTesting)
    }

    @Test @MainActor
    func snippetEditorCellAllowsInlineTitleEditing() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")

        #expect(cell.isEditable)
        #expect(cell.isSelectable)
        #expect(cell.sendsActionOnEndEditing)
    }

    @Test @MainActor
    func snippetEditorCellUsesSemanticTitleColors() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")

        cell.isItemEnabled = true
        #expect(cell.titleTextColorForTesting(isHighlighted: false) == .labelColor)
        #expect(cell.titleTextColorForTesting(isHighlighted: true) == .selectedMenuItemTextColor)

        cell.isItemEnabled = false
        #expect(cell.titleTextColorForTesting(isHighlighted: false) == .disabledControlTextColor)
        #expect(cell.titleTextColorForTesting(isHighlighted: true) == .disabledControlTextColor)
    }

    @Test @MainActor
    func snippetEditorCellReservesTrailingSpaceForShortcutBadge() {
        let cell = CPYSnippetsEditorCell(textCell: "AI Prompt")
        let bounds = NSRect(x: 0, y: 0, width: 180, height: 28)
        let titleRectWithoutShortcut = cell.titleRect(forBounds: bounds)

        cell.shortcutText = "⇧⌘B"
        let titleRectWithShortcut = cell.titleRect(forBounds: bounds)

        #expect(cell.shortcutTextForTesting == "⇧⌘B")
        #expect(titleRectWithShortcut.width < titleRectWithoutShortcut.width)
        #expect(cell.shortcutBadgeRectForTesting(in: bounds).maxX <= bounds.maxX - CPYSnippetsEditorCell.Metrics.shortcutTrailingInset)
    }

    @Test @MainActor
    func snippetEditorCellUsesCompactItemNumberShortcutBadgeMetrics() {
        #expect(CPYSnippetsEditorCell.Metrics.shortcutHeight == 16)
        #expect(CPYSnippetsEditorCell.Metrics.shortcutMinWidth == 22)
        #expect(CPYSnippetsEditorCell.Metrics.shortcutCornerRadius == 4)
    }

    @Test @MainActor
    func snippetEditorOutlineDisplaysFolderAndNumericShortcutBadges() throws {
        try withSnippetEditorNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            let folderID = SnippetFolder.ID(rawValue: UUID())
            let firstSnippetID = Snippet.ID(rawValue: UUID())
            let disabledSnippetID = Snippet.ID(rawValue: UUID())
            let secondSnippetID = Snippet.ID(rawValue: UUID())
            let keyCombo = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | shiftKey))
            let hotKeyService = AppEnvironment.current.hotKeyService
            let previousFolderCombo = hotKeyService.snippetKeyCombo(forIdentifier: folderID.uuidString)
            hotKeyService.registerSnippetHotKey(with: folderID.uuidString, keyCombo: keyCombo)
            defer {
                if let previousFolderCombo {
                    hotKeyService.registerSnippetHotKey(with: folderID.uuidString, keyCombo: previousFolderCombo)
                } else {
                    hotKeyService.unregisterSnippetHotKey(with: folderID.uuidString)
                }
            }

            let detail = SnippetFolderDetail(
                folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(
                        id: firstSnippetID,
                        folderID: folderID,
                        title: "First",
                        content: "One",
                        index: 0,
                        isEnabled: true
                    ),
                    Snippet(
                        id: disabledSnippetID,
                        folderID: folderID,
                        title: "Disabled",
                        content: "Hidden",
                        index: 1,
                        isEnabled: false
                    ),
                    Snippet(
                        id: secondSnippetID,
                        folderID: folderID,
                        title: "Second",
                        content: "Two",
                        index: 2,
                        isEnabled: true
                    )
                ]
            )

            withDependencies {
                $0.snippetRepository = SnippetEditorStaticSnippetRepository(details: [detail])
            } operation: {
                let controller = CPYSnippetsEditorWindowController()
                defer { controller.close() }

                #expect(controller.outlineShortcutTextsForTesting == ["⇧⌘B", "1", "2"])
            }
        }
    }

    @Test @MainActor
    func snippetEditorAssignsDefaultShortcutWhenAddingFolder() throws {
        try withSnippetEditorTemporaryFolderHotKeys {
            let folderID = SnippetFolder.ID(rawValue: UUID())
            let folder = SnippetFolder(id: folderID, title: "untitled folder", index: 0, isEnabled: true)
            defer { AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: folderID.uuidString) }

            withDependencies {
                $0.snippetRepository = SnippetEditorInsertingSnippetRepository(folder: folder)
            } operation: {
                let controller = CPYSnippetsEditorWindowController()
                defer { controller.close() }

                controller.addFolderForTesting()
            }

            let keyCombo = try #require(AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folderID.uuidString))
            #expect(keyCombo.QWERTYKeyCode == 12)
            #expect(keyCombo.modifiers == cmdKey | optionKey)
            #expect(keyCombo.keyEquivalent.uppercased() == "Q")
        }
    }

}

@MainActor
private func retainWindowForAppKitTest(_ window: NSWindow) {
    window.makeFirstResponder(nil)
    let retainedContentView = window.contentView
    window.contentView = nil
    window.orderOut(nil)
    CPYWindowAppearanceTestWindowRetainer.retain(window: window, contentView: retainedContentView)
}

private enum CPYWindowAppearanceTestWindowRetainer {
    private static var windows = [NSWindow]()
    private static var contentViews = [NSView]()

    static func retain(window: NSWindow, contentView: NSView?) {
        windows.append(window)
        if let contentView {
            contentViews.append(contentView)
        }
    }
}

private func enabledLabelTextFields(in view: NSView) -> [NSTextField] {
    var fields = [NSTextField]()
    collectEnabledLabelTextFields(in: view, into: &fields)
    return fields
}

private func collectEnabledLabelTextFields(in view: NSView, into fields: inout [NSTextField]) {
    guard !view.isHidden else { return }
    if let textField = view as? NSTextField,
       !textField.isEditable,
       textField.isEnabled,
       !textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        fields.append(textField)
    }
    view.subviews.forEach { collectEnabledLabelTextFields(in: $0, into: &fields) }
}

private func perceivedBrightness(_ color: NSColor?, appearance: NSAppearance) -> CGFloat {
    var rgbColor: NSColor?
    appearance.performAsCurrentDrawingAppearance {
        rgbColor = color?.usingColorSpace(.deviceRGB)
    }
    guard let rgbColor else { return 0 }
    return 0.299 * rgbColor.redComponent
        + 0.587 * rgbColor.greenComponent
        + 0.114 * rgbColor.blueComponent
}

private func withSnippetEditorNumericShortcutDefaults(
    enabled: Bool,
    startsAtZero: Bool,
    operation: () throws -> Void
) rethrows {
    let defaults = AppEnvironment.current.defaults
    let shortcutKey = Constants.UserDefaults.addNumericKeyEquivalents
    let startKey = Constants.UserDefaults.menuItemsTitleStartWithZero
    let previousShortcutValue = defaults.object(forKey: shortcutKey)
    let previousStartValue = defaults.object(forKey: startKey)
    defaults.set(enabled, forKey: shortcutKey)
    defaults.set(startsAtZero, forKey: startKey)
    defer {
        restoreSnippetEditorDefault(previousShortcutValue, forKey: shortcutKey)
        restoreSnippetEditorDefault(previousStartValue, forKey: startKey)
    }
    try operation()
}

private func restoreSnippetEditorDefault(_ value: Any?, forKey key: String) {
    let defaults = AppEnvironment.current.defaults
    if let value {
        defaults.set(value, forKey: key)
    } else {
        defaults.removeObject(forKey: key)
    }
}

private func withSnippetEditorTemporaryFolderHotKeys(operation: () throws -> Void) rethrows {
    let defaults = AppEnvironment.current.defaults
    let key = Constants.HotKey.folderKeyCombos
    let previousValue = defaults.object(forKey: key)
    defaults.removeObject(forKey: key)
    defer {
        restoreSnippetEditorDefault(previousValue, forKey: key)
    }
    try operation()
}

private struct SnippetEditorInsertingSnippetRepository: SnippetRepositoryProtocol {
    let folder: SnippetFolder

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { [] }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { nil }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { folder }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func mergeSyncTombstones(_ records: [SyncRecord]) {}
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) {}
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) {}
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}

private struct SnippetEditorStaticSnippetRepository: SnippetRepositoryProtocol {
    let details: [SnippetFolderDetail]

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just(details).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { details }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { details.first { $0.folder.id == id } }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func mergeSyncTombstones(_ records: [SyncRecord]) {}
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) {}
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) {}
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}
