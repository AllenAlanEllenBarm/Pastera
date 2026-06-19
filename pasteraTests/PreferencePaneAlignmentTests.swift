//
//  PreferencePaneAlignmentTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct PreferenceSidebarTests {
    @Test
    func sidebarUsesChineseTitlesAndDistinctSyncUpdateIcons() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)

        let titles = controller.preferenceSidebarTitlesForTesting
        let symbolNames = controller.preferenceSidebarSymbolNamesForTesting
        let syncIndex = try #require(titles.firstIndex(of: "同步"))
        let updateIndex = try #require(titles.firstIndex(of: "更新"))

        #expect(titles == ["通用", "类型", "排除", "快捷键", "同步", "更新", "测试"])
        #expect(!titles.contains("Types"))
        #expect(!titles.contains("Exclude"))
        #expect(!titles.contains("Update"))
        #expect(!titles.contains("Beta"))
        #expect(symbolNames.count == titles.count)
        #expect(symbolNames[syncIndex] != symbolNames[updateIndex])
    }
}

@MainActor
@Suite(.serialized)
struct PreferencePaneAlignmentTests {
    @Test
    func excludePaneTitleAndTableUseSameContentColumn() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Exclude")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let titleFrame = try #require(preferenceTextFieldFrames(in: contentView)
            .first { ["Exclude these applications:", "排除这些程序："].contains($0.text) }?.frame)
        let tableFrame = try #require(preferenceTableScrollFrame(in: contentView))

        #expect(abs(titleFrame.minX - tableFrame.minX) <= 1)
        #expect(tableFrame.width >= controller.selectedPaneDocumentWidthForTesting - 4)
        #expect(
            paneFrame.maxY - titleFrame.maxY <= 24,
            "Exclude pane title should be top-aligned, but top gap is \(paneFrame.maxY - titleFrame.maxY)"
        )
    }

    @Test
    func shortcutsPaneDisplaysHistoryPanelRowsAndAlignsLabelAndRecordColumns() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let textFrames = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let sectionTitles = textFrames.filter {
            [
                "Menu Shortcuts",
                "菜单快捷键",
                "History Panel Shortcuts",
                "历史面板快捷键"
            ].contains($0.text)
        }
        let rowLabels = textFrames.filter {
            [
                "Main:",
                "History:",
                "Search:",
                "Previous Page:",
                "Next Page:",
                "Snippets:",
                "主体：",
                "历史：",
                "搜索：",
                "上一页：",
                "下一页：",
                "片段："
            ].contains($0.text)
        }
        let recordFrames = preferenceRecordViewFrames(in: contentView)
            .filter { $0.minX >= paneMinX }
        let menuTitle = try #require(textFrames.first {
            ["Menu Shortcuts", "菜单快捷键"].contains($0.text)
        })
        let historyPanelTitle = try #require(textFrames.first {
            ["History Panel Shortcuts", "历史面板快捷键"].contains($0.text)
        })
        let snippetsLabel = try #require(rowLabels.first {
            ["Snippets:", "片段："].contains($0.text)
        })
        let searchLabel = try #require(rowLabels.first {
            ["Search:", "搜索："].contains($0.text)
        })
        let previousPageLabel = try #require(rowLabels.first {
            ["Previous Page:", "上一页："].contains($0.text)
        })
        let nextPageLabel = try #require(rowLabels.first {
            ["Next Page:", "下一页："].contains($0.text)
        })
        let nextPageFrameInPane = try #require(controller.selectedPaneTextFrameForTesting(
            matching: ["Next Page:", "下一页："]
        ))

        #expect(sectionTitles.count == 2)
        #expect(rowLabels.count == 6)
        #expect(recordFrames.count == 6)
        #expect(!textFrames.contains {
            ["Clear History:", "清空历史：", "清除历史："].contains($0.text)
        })
        #expect(menuTitle.frame.maxY > snippetsLabel.frame.maxY)
        #expect(snippetsLabel.frame.maxY > historyPanelTitle.frame.maxY)
        #expect(historyPanelTitle.frame.maxY > searchLabel.frame.maxY)
        #expect(searchLabel.frame.maxY > previousPageLabel.frame.maxY)
        #expect(previousPageLabel.frame.maxY > nextPageLabel.frame.maxY)
        #expect(nextPageFrameInPane.minY >= -0.5)
        #expect(nextPageFrameInPane.maxY <= controller.selectedPaneDocumentHeightForTesting + 0.5)

        let labelMinX = try #require(rowLabels.map(\.frame.minX).min())
        for label in rowLabels {
            #expect(abs(label.frame.minX - labelMinX) <= 1)
        }

        let recordMinX = try #require(recordFrames.map(\.minX).min())
        let paneMaxX = paneFrame.maxX
        for frame in recordFrames {
            #expect(abs(frame.minX - recordMinX) <= 1)
            #expect(frame.maxX >= paneMaxX - 4)
        }
    }

    @Test
    func betaPaneIntroIsCenteredAndFormColumnsAlign() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Beta")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let textFrames = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let introFrame = try #require(textFrames.first {
            [
                "Beta settings might be moved to a different pane in future versions.",
                "Beta 测试设置将来可能会被移到其它面板。"
            ].contains($0.text)
        }?.frame)
        let actionFrame = try #require(textFrames.first { ["Action", "操作"].contains($0.text) }?.frame)
        let checkboxFrames = preferenceButtons(in: contentView)
            .filter {
                [
                    "Paste as PlainText",
                    "Delete history",
                    "Paste and delete history",
                    "以纯文本格式粘贴",
                    "删除历史",
                    "粘贴并删除历史"
                ].contains($0.title)
            }
            .map { contentView.convert($0.frame, from: $0.superview) }
            .filter { $0.minX >= paneMinX }
        let removedScreenshotTexts: Set<String> = [
            "Screenshot",
            "屏幕截图"
        ]
        let removedScreenshotButtons: Set<String> = [
            "Save screenshots in history",
            "在历史中保存屏幕截图"
        ]
        let popupFrames = preferencePopUpFrames(in: contentView)
            .filter { $0.minX >= paneMinX }

        #expect(abs(introFrame.midX - paneFrame.midX) <= 1)
        #expect(!textFrames.contains { removedScreenshotTexts.contains($0.text) })
        #expect(!preferenceButtons(in: contentView).contains { removedScreenshotButtons.contains($0.title) })
        #expect(checkboxFrames.count == 3)
        #expect(popupFrames.count == 3)
        for frame in [actionFrame] + checkboxFrames {
            #expect(abs(frame.minX - actionFrame.minX) <= 1)
        }
        #expect(controller.selectedPaneDocumentHeightForTesting <= 170)
        let paneMaxX = paneFrame.maxX
        for frame in popupFrames {
            #expect(frame.maxX >= paneMaxX - 4)
        }
    }

    @Test
    func generalPaneRemovesClearHistoryWarningAndCentersContentVertically() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let buttonFrames = preferenceButtons(in: contentView).map { button in
            (title: button.title, frame: contentView.convert(button.frame, from: button.superview))
        }.filter { $0.frame.minX >= paneMinX }
        let textFrames = preferenceTextFieldFrames(in: contentView).filter { $0.frame.minX >= paneMinX }
        let clearHistoryFrame = try #require(buttonFrames.first { ["Clear History", "清除历史", "清空历史"].contains($0.title) }?.frame)
        let launchFrame = try #require(buttonFrames.first { ["Launch on Login", "登录时打开"].contains($0.title) }?.frame)
        let opacityFrame = try #require(textFrames.first { ["Transparency", "透明度"].contains($0.text) }?.frame)
        let warningFrame = buttonFrames.first { ["Show alert panel before clear history", "清空历史前显示警告面板"].contains($0.title) }?.frame
        let visibleControlsFrame = buttonFrames.map(\.frame).reduce(NSRect.null) { $0.union($1) }

        #expect(warningFrame == nil)
        #expect(abs(visibleControlsFrame.midY - contentView.bounds.midY) <= 6)
        for frame in [launchFrame, clearHistoryFrame, opacityFrame] {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard view.isHidden == false, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, textField.stringValue.isEmpty == false {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceTableScrollFrame(in view: NSView, root: NSView? = nil) -> NSRect? {
        let rootView = root ?? view
        if let scrollView = view as? NSScrollView,
           scrollView.documentView is NSTableView {
            return rootView.convert(scrollView.frame, from: scrollView.superview)
        }
        for subview in view.subviews {
            if let frame = preferenceTableScrollFrame(in: subview, root: rootView) {
                return frame
            }
        }
        return nil
    }

    private func preferenceRecordViewFrames(in view: NSView, root: NSView? = nil) -> [NSRect] {
        let rootView = root ?? view
        var values = [NSRect]()
        if String(describing: type(of: view)).contains("RecordView") {
            values.append(rootView.convert(view.frame, from: view.superview))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceRecordViewFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferencePopUpFrames(in view: NSView, root: NSView? = nil) -> [NSRect] {
        let rootView = root ?? view
        var values = [NSRect]()
        if view is NSPopUpButton {
            values.append(rootView.convert(view.frame, from: view.superview))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferencePopUpFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceSwitches(in view: NSView) -> [NSSwitch] {
        var switches = view.subviews.compactMap { $0 as? NSSwitch }
        view.subviews.forEach { switches.append(contentsOf: preferenceSwitches(in: $0)) }
        return switches
    }

    private func preferenceSwitchButtons(in view: NSView, labels: Set<String>) -> [NSButton] {
        preferenceButtons(in: view).filter {
            labels.contains($0.accessibilityLabel() ?? "")
        }
    }
}

@MainActor
@Suite(.serialized)
struct GeneralPreferenceMergedMenuTests {
    @Test
    func generalPaneContainsMergedMenuSettingsAndCentersContentVertically() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let allButtonFrames = preferenceButtonFrames(in: contentView)
        let sidebarButtonTitles = allButtonFrames
            .filter { $0.frame.maxX < paneMinX }
            .map(\.title)
        let buttonFrames = allButtonFrames.filter { $0.frame.minX >= paneMinX }
        let textFields = preferenceTextFieldFrames(in: contentView).filter { $0.frame.minX >= paneMinX }
        let launchFrame = try frame(of: ["Launch on Login", "登录时打开"], in: buttonFrames)
        let clearHistoryFrame = try frame(of: ["Clear History", "清除历史", "清空历史"], in: buttonFrames)
        let reorderFrame = try frame(of: ["Place already copied history at the top", "把已经粘贴的历史置顶"], in: buttonFrames)
        let moveFrame = try frame(
            of: [
                "Move instead of copying (removes the older one from the list)",
                "移动而非拷贝（第二次粘贴时把旧的项从列表中移除）"
            ],
            in: buttonFrames
        )
        let colorPreviewFrame = try frame(of: ["Show color code preview", "为颜色代码显示预览"], in: buttonFrames)
        let opacityFrame = try textFrame(of: ["Transparency", "透明度"], in: textFields)
        let menuTitleLengthFrame = try textFrame(
            of: ["Number of characters in the menu:", "菜单中字符的个数："],
            in: textFields
        )
        let visibleControlsFrame = [
            launchFrame,
            clearHistoryFrame,
            opacityFrame,
            menuTitleLengthFrame,
            reorderFrame,
            moveFrame,
            colorPreviewFrame
        ].reduce(NSRect.null) { $0.union($1) }

        #expect(!sidebarButtonTitles.contains { ["Menu", "菜单"].contains($0) })
        #expect(buttonFrames.allSatisfy { !removedButtonTitles.contains($0.title) })
        #expect(textFields.allSatisfy { !removedTextTitles.contains($0.text) })
        #expect(abs(visibleControlsFrame.midY - contentView.bounds.midY) <= 6)
        #expect((controller.minimumVisibleControlVerticalGapForTesting ?? 0) >= 11.5)
        for frame in [
            launchFrame,
            clearHistoryFrame,
            opacityFrame,
            menuTitleLengthFrame,
            reorderFrame,
            moveFrame,
            colorPreviewFrame
        ] {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
    }

    private let removedButtonTitles: Set<String> = [
        "Add a menu item to clear clipboard history",
        "在菜单项中添加清空历史",
        "Show alert panel before clear history",
        "清空历史前显示警告面板",
        "Mark menu items with numbers",
        "用数字标记菜单项",
        "Menu items' title starts with 0",
        "菜单项标题从0开始",
        "Display icons in menu items",
        "在菜单项中显示图标",
        "Add key equivalents to numeric keys",
        "添加等效于数字键的按键",
        "Show Image",
        "显示图像",
        "Show tool tip on a menu item",
        "为菜单项显示工具提示"
    ]

    private let removedTextTitles: Set<String> = [
        "Number of items place inline:",
        "不放进文件夹的菜单项个数：",
        "Number of items place inside a folder:",
        "每个文件夹中项的个数：",
        "Width:",
        "宽度：",
        "Height:",
        "高度：",
        "Max length of tool tip string:",
        "工具提示字符串最大长度："
    ]

    private func frame(
        of titles: Set<String>,
        in frames: [(title: String, frame: NSRect)]
    ) throws -> NSRect {
        try #require(frames.first { titles.contains($0.title) }?.frame)
    }

    private func textFrame(
        of titles: Set<String>,
        in frames: [(text: String, frame: NSRect)]
    ) throws -> NSRect {
        try #require(frames.first { titles.contains($0.text) }?.frame)
    }

    private func preferenceButtonFrames(in view: NSView) -> [(title: String, frame: NSRect)] {
        preferenceButtons(in: view).map { button in
            (title: button.title, frame: view.convert(button.frame, from: button.superview))
        }
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard !view.isHidden, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, !textField.stringValue.isEmpty {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceTextFields(in view: NSView) -> [NSTextField] {
        var fields = view.subviews.compactMap { $0 as? NSTextField }
        view.subviews.forEach { fields.append(contentsOf: preferenceTextFields(in: $0)) }
        return fields
    }

}

@MainActor
@Suite(.serialized)
struct SyncPreferenceOneDriveLocationTests {
    @Test
    func syncPaneHidesLongOneDrivePathAndShowsValidatedStatus() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .appendingPathComponent("OneDrive", isDirectory: true)
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent().deletingLastPathComponent()) }

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: rootURL.deletingLastPathComponent().deletingLastPathComponent(),
                    syncRootURL: rootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(visibleTexts.contains("已使用 OneDrive 默认同步位置。"))
            #expect(!visibleTexts.contains("OneDrive 状态"))
            #expect(!visibleTexts.contains("可用"))
            #expect(!visibleTexts.contains(where: { $0.contains("Library/CloudStorage") }))
            #expect(preferenceButtons(in: controller.view).contains { $0.title == "修改" })
        }
    }

    @Test
    func syncPaneKeepsValidatedSavedCustomOneDriveLocation() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let customURL = oneDriveRootURL
            .appendingPathComponent("CustomSync", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: customURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(customURL.path, forKey: Constants.UserDefaults.syncRootPath)
            defaults.synchronize()

            let controller = CPYSyncPreferenceViewController(defaultFolderResolver: SyncDefaultFolderResolver(fileManager: .default), defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: defaultRootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == customURL.standardizedFileURL.path)
            #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
        }
    }

    @Test
    func syncPaneChangeLocationSavesOnlyValidatedOneDriveFolder() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        let customRootURL = oneDriveRootURL.appendingPathComponent("PasteraCustom", isDirectory: true)
        let invalidRootURL = homeURL.appendingPathComponent("PlainFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: invalidRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            var selectedURL = invalidRootURL
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: {
                    .found(SyncDefaultFolderCandidate(
                        oneDriveRootURL: oneDriveRootURL,
                        syncRootURL: defaultRootURL,
                        displayName: "OneDrive",
                        isOneDriveBacked: true
                    ))
                },
                chooseSyncRoot: { _, _ in selectedURL }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()
            let changeButton = try #require(preferenceButtons(in: controller.view).first { $0.title == "修改" })

            changeButton.performClick(nil)

            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
            #expect(Set(preferenceTextFieldFrames(in: controller.view).map(\.text)).contains("请选择 OneDrive 中可写的文件夹。"))

            selectedURL = customRootURL
            changeButton.performClick(nil)

            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == customRootURL.standardizedFileURL.path)
            let validTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(validTexts.contains("同步位置已更新，并通过 OneDrive 文件夹检查。"))
            #expect(validTexts.contains("OneDrive 可用"))
        }
    }

    @Test
    func syncPaneAutomaticallyUsesPersonalOneDriveWhenMultipleAccountsAreDetected() throws {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personalRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let workRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive - Work", isDirectory: true)
        try FileManager.default.createDirectory(at: personalRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let candidates = [
            SyncDefaultFolderCandidate(
                oneDriveRootURL: personalRootURL,
                syncRootURL: recommendedSyncRootURL(oneDriveRootURL: personalRootURL),
                displayName: "OneDrive",
                isOneDriveBacked: true
            ),
            SyncDefaultFolderCandidate(
                oneDriveRootURL: workRootURL,
                syncRootURL: recommendedSyncRootURL(oneDriveRootURL: workRootURL),
                displayName: "OneDrive - Work",
                isOneDriveBacked: true
            )
        ]

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { .multiple(candidates) })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(!visibleTexts.contains("找到多个 OneDrive 账号，请选择要使用的 OneDrive 文件夹。"))
            #expect(FileManager.default.fileExists(atPath: recommendedSyncRootURL(oneDriveRootURL: personalRootURL).path))
            #expect(!FileManager.default.fileExists(atPath: recommendedSyncRootURL(oneDriveRootURL: workRootURL).path))
        }
    }

    @Test
    func syncPaneFirstAutomaticEnableTurnsOnAllSyncScopes() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: defaultRootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()
            let automaticUploadSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == "自动上传"
            })
            let automaticSyncSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == "自动同步"
            })

            automaticUploadSwitch.performClick(nil)

            #expect(defaults.bool(forKey: Constants.UserDefaults.syncAutomaticUploadEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled))

            automaticSyncSwitch.performClick(nil)

            #expect(defaults.bool(forKey: Constants.UserDefaults.syncAutomaticEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled))
        }
    }

    private func cloudStorageURL(homeURL: URL) -> URL {
        homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
    }

    private func recommendedSyncRootURL(oneDriveRootURL: URL) -> URL {
        oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    private func withPreservedSyncDefaults(_ work: () throws -> Void) throws {
        let defaults = AppEnvironment.current.defaults
        let syncKeys = [
            Constants.UserDefaults.syncAutomaticUploadEnabled,
            Constants.UserDefaults.syncAutomaticEnabled,
            Constants.UserDefaults.syncRootPath,
            Constants.UserDefaults.syncHistoryUploadEnabled,
            Constants.UserDefaults.syncHistoryImportEnabled,
            Constants.UserDefaults.syncSnippetUploadEnabled,
            Constants.UserDefaults.syncSnippetImportEnabled
        ]
        let previousValues = syncKeys.reduce(into: [String: Any]()) { values, key in
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        syncKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()
        defer {
            syncKeys.forEach { key in
                if let value = previousValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.synchronize()
        }
        try work()
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard view.isHidden == false, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, textField.stringValue.isEmpty == false {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceSwitches(in view: NSView) -> [NSSwitch] {
        var switches = view.subviews.compactMap { $0 as? NSSwitch }
        view.subviews.forEach { switches.append(contentsOf: preferenceSwitches(in: $0)) }
        return switches
    }

    private func preferenceSwitchButtons(in view: NSView) -> [NSButton] {
        let switchLabels: Set<String> = [
            "自动上传",
            "自动同步",
            "上传历史",
            "同步历史",
            "上传片段",
            "同步片段"
        ]
        return preferenceButtons(in: view).filter {
            switchLabels.contains($0.accessibilityLabel() ?? "")
        }
    }
}
