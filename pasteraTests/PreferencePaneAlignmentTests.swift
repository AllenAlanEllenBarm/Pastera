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
        let screenshotFrame = try #require(textFrames.first { ["Screenshot", "屏幕截图"].contains($0.text) }?.frame)
        let checkboxFrames = preferenceButtons(in: contentView)
            .filter {
                [
                    "Paste as PlainText",
                    "Delete history",
                    "Paste and delete history",
                    "Save screenshots in history",
                    "以纯文本格式粘贴",
                    "删除历史",
                    "粘贴并删除历史",
                    "在历史中保存屏幕截图"
                ].contains($0.title)
            }
            .map { contentView.convert($0.frame, from: $0.superview) }
            .filter { $0.minX >= paneMinX }
        let popupFrames = preferencePopUpFrames(in: contentView)
            .filter { $0.minX >= paneMinX }

        #expect(abs(introFrame.midX - paneFrame.midX) <= 1)
        #expect(checkboxFrames.count == 4)
        #expect(popupFrames.count == 3)
        for frame in [actionFrame, screenshotFrame] + checkboxFrames {
            #expect(abs(frame.minX - actionFrame.minX) <= 1)
        }
        let paneMaxX = paneFrame.maxX
        for frame in popupFrames {
            #expect(frame.maxX >= paneMaxX - 4)
        }
    }

    @Test
    func menuPaneRemovesRetiredControlsAndCompactsRemainingRows() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Menu")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let buttonFrames = preferenceButtons(in: contentView)
            .map { button in
                (title: button.title, frame: contentView.convert(button.frame, from: button.superview))
            }
            .filter { $0.frame.minX >= paneMinX }
        let textFields = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let removedTitles: Set<String> = [
            "Add a menu item to clear clipboard history",
            "在菜单项中添加清空历史",
            "Show alert panel before clear history",
            "清空历史前显示警告面板",
            "Mark menu items with numbers",
            "用数字标记菜单项",
            "Menu items' title starts with 0",
            "菜单项标题从0开始"
        ]
        let removedTexts: Set<String> = [
            "Number of items place inline:",
            "不放进文件夹的菜单项个数：",
            "Number of items place inside a folder:",
            "每个文件夹中项的个数：",
            "Width:",
            "宽度：",
            "Height:",
            "高度："
        ]
        _ = try #require(buttonFrames.first {
            ["Add key equivalents to numeric keys", "添加等效于数字键的按键"].contains($0.title)
        })
        _ = try #require(buttonFrames.first {
            ["Show Image", "显示图像"].contains($0.title)
        })
        _ = try #require(buttonFrames.first {
            ["Show tool tip on a menu item", "为菜单项显示工具提示"].contains($0.title)
        })
        _ = try #require(buttonFrames.first {
            ["Show color code preview", "为颜色代码显示预览"].contains($0.title)
        })

        #expect(buttonFrames.allSatisfy { !removedTitles.contains($0.title) })
        #expect(textFields.allSatisfy { !removedTexts.contains($0.text) })
        #expect(controller.selectedPaneDocumentHeightForTesting <= 430.5)
        #expect((controller.minimumVisibleControlVerticalGapForTesting ?? 0) >= 11.5)
        for frame in buttonFrames.map(\.frame) {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
    }

    @Test
    func generalPaneShowsClearHistoryWarningNearClearHistoryAction() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let buttonFrames = preferenceButtons(in: contentView)
            .map { button in
                (title: button.title, frame: contentView.convert(button.frame, from: button.superview))
            }
            .filter { $0.frame.minX >= paneMinX }
        let clearHistoryFrame = try #require(buttonFrames.first {
            ["Clear History", "清除历史", "清空历史"].contains($0.title)
        }?.frame)
        let warningFrame = try #require(buttonFrames.first {
            ["Show alert panel before clear history", "清空历史前显示警告面板"].contains($0.title)
        }?.frame)

        #expect(abs(warningFrame.minX - clearHistoryFrame.minX) <= 2)
        #expect(abs(warningFrame.midY - clearHistoryFrame.midY) <= 44)
        for frame in [clearHistoryFrame, warningFrame] {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
    }

    @Test
    func syncPaneUsesChineseGuidanceAndControlsStayWithinPaneBounds() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Sync")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let syncButtonTitles: Set<String> = [
            "自动同步",
            "显示",
            "立即同步",
            "上传剪切板历史",
            "导入剪切板历史",
            "上传片段",
            "导入片段"
        ]
        let removedButtonTitles: Set<String> = [
            "使用 OneDrive",
            "选择...",
            "解锁",
            "生成口令"
        ]
        let guidanceText = "Pastera 通过你电脑上的 OneDrive 文件夹同步；" +
            "Pastera 不连接 Microsoft 账号，也不保存云端副本。" +
            "开启“上传”只会同步之后的新变化；导入不会删除本地数据。"
        let expectedTexts: Set<String> = [
            "云同步",
            guidanceText,
            "同步位置",
            "手动同步",
            "上次同步",
            "导入 / 上传",
            "状态"
        ]
        let syncButtonFrames = preferenceButtons(in: contentView)
            .filter { syncButtonTitles.contains($0.title) }
            .map { button in
                contentView.convert(button.frame, from: button.superview)
            }
        let removedButtons = preferenceButtons(in: contentView)
            .filter { removedButtonTitles.contains($0.title) }
        let textFields = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let visibleTexts = Set(textFields.map(\.text))
        let statusFrames = textFields
            .filter {
                ["上次同步", "导入 / 上传", "状态"].contains($0.text)
            }
            .map(\.frame)

        #expect(expectedTexts.isSubset(of: visibleTexts))
        #expect(syncButtonFrames.count == syncButtonTitles.count)
        #expect(removedButtons.isEmpty)
        #expect(!visibleTexts.contains("同步口令"))
        #expect(!visibleTexts.contains("位置操作"))
        #expect(statusFrames.count == 3)
        for frame in syncButtonFrames + statusFrames {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
    }

    @Test
    func syncPaneManualSyncPromptsToInstallOneDriveWhenDefaultLocationIsMissing() throws {
        let defaults = AppEnvironment.current.defaults
        let syncKeys = [
            Constants.UserDefaults.syncAutomaticEnabled,
            Constants.UserDefaults.syncRootPath,
            Constants.UserDefaults.syncHistoryUploadEnabled,
            Constants.UserDefaults.syncHistoryImportEnabled,
            Constants.UserDefaults.syncSnippetUploadEnabled,
            Constants.UserDefaults.syncSnippetImportEnabled,
            Constants.UserDefaults.syncHistoryUploadEnabledAt,
            Constants.UserDefaults.syncSnippetUploadEnabledAt
        ]
        let previousValues = syncKeys.reduce(into: [String: Any]()) { values, key in
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
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

        syncKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()

        let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { .notFound })
        controller.loadView()
        controller.viewDidLoad()
        controller.view.layoutSubtreeIfNeeded()
        let syncButton = try #require(preferenceButtons(in: controller.view).first { $0.title == "立即同步" })

        syncButton.performClick(nil)
        controller.view.layoutSubtreeIfNeeded()

        let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
        #expect(visibleTexts.contains("请先安装并登录 OneDrive。"))
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
}

@MainActor
@Suite(.serialized)
struct SyncPreferenceOneDriveLocationTests {
    @Test
    func syncPaneShowsFriendlyOneDrivePathWithoutExposingLibraryCloudStorage() throws {
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
            #expect(visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(!visibleTexts.contains(where: { $0.contains("Library/CloudStorage") }))
        }
    }

    @Test
    func syncPaneMigratesSavedCustomFolderToDetectedDefaultOneDriveLocation() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let customURL = homeURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("CustomSync", isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
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
            #expect(visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(!visibleTexts.contains("自定义文件夹：CustomSync"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
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
            #expect(visibleTexts.contains("OneDrive > Pastera > sync"))
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
            let automaticButton = try #require(preferenceButtons(in: controller.view).first { $0.title == "自动同步" })

            automaticButton.performClick(nil)

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
            Constants.UserDefaults.syncAutomaticEnabled,
            Constants.UserDefaults.syncRootPath,
            Constants.UserDefaults.syncHistoryUploadEnabled,
            Constants.UserDefaults.syncHistoryImportEnabled,
            Constants.UserDefaults.syncSnippetUploadEnabled,
            Constants.UserDefaults.syncSnippetImportEnabled,
            Constants.UserDefaults.syncHistoryUploadEnabledAt,
            Constants.UserDefaults.syncSnippetUploadEnabledAt
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
}
