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
    func preferenceWindowRestoresDefaultFrameSize() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        let window = try #require(controller.window)
        window.setFrame(NSRect(x: 20, y: 30, width: 1400, height: 900), display: false)

        window.performZoom(nil)

        #expect(window.frame.size == controller.defaultPreferenceWindowFrameSizeForTesting)
    }

    @Test
    func sidebarUsesApprovedTitlesAndDistinctServiceIcons() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)

        let titles = controller.preferenceSidebarTitlesForTesting
        let symbolNames = controller.preferenceSidebarSymbolNamesForTesting
        let syncIndex = try #require(titles.firstIndex(of: "云同步"))
        let aboutIndex = try #require(titles.firstIndex(of: "关于"))

        #expect(titles == ["基础设置", "历史记录", "脚本", "快捷键", "忽略应用", "云同步", "关于"])
        #expect(!titles.contains("Types"))
        #expect(!titles.contains("Exclude"))
        #expect(!titles.contains("Update"))
        #expect(!titles.contains("Beta"))
        #expect(!titles.contains("测试"))
        #expect(symbolNames.count == titles.count)
        #expect(symbolNames[syncIndex] != symbolNames[aboutIndex])
    }
}

@MainActor
@Suite(.serialized)
struct PreferencePaneAlignmentTests {
    @Test
    func generalGroupsUseSemanticHeaderIconsAndStableRowRhythm() throws {
        let page = CPYGeneralPreferenceViewController()
        page.loadView()
        page.view.frame = NSRect(x: 0, y: 0, width: 520, height: 900)
        page.view.layoutSubtreeIfNeeded()

        let groups = preferenceGroups(in: page.view)
        #expect(groups.count == 4)
        for group in groups {
            let icons = descendantImageViews(in: group).filter {
                $0.accessibilityIdentifier() == "preference.group.icon"
            }
            let rows = descendantSettingRows(in: group)
            let separators = descendantViews(in: group).filter {
                $0.accessibilityIdentifier() == "preference.group.separator"
            }
            #expect(icons.count == 1)
            #expect(!rows.isEmpty)
            #expect(rows.allSatisfy { $0.frame.height >= 48 })
            #expect(!separators.isEmpty)
            #expect(separators.allSatisfy { ($0.layer?.backgroundColor?.alpha ?? 1) <= 0.15 })
        }
    }

    @Test
    func nativeTask5AnchorsStayInsideTheirPageBounds() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }
        controller.showWindow(nil)

        let anchors: [(PasteraPreferencePaneID, [String])] = [
            (.sync, ["sync.oneDriveStatus", "sync.rootFolder", "sync.fileTypes", "sync.actions"]),
            (.about, ["about.version", "about.github", "about.license", "about.sparkle"])
        ]
        for (paneID, anchorIDs) in anchors {
            controller.showPreferencePaneForTesting(paneID: paneID)
            let paneBounds = NSRect(
                origin: .zero,
                size: NSSize(
                    width: controller.selectedPaneDocumentWidthForTesting,
                    height: controller.selectedPaneDocumentHeightForTesting
                )
            )
            for anchorID in anchorIDs {
                let frame = try #require(controller.selectedPaneDescendantFrameForTesting(
                    accessibilityIdentifier: anchorID
                ))
                #expect(frame.minX >= paneBounds.minX - 0.5)
                #expect(frame.maxX <= paneBounds.maxX + 0.5)
                #expect(frame.minY >= paneBounds.minY - 0.5)
                #expect(frame.maxY <= paneBounds.maxY + 0.5)
            }
        }
    }

    @Test
    func excludedAppsNativePaneKeepsTitleAndTableInsideContentBounds() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(paneID: .excludedApps)

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let titleFrame = try #require(controller.selectedPaneTextFrameForTesting(
            matching: ["Excluded Apps", "忽略应用"]
        ))
        let tableFrame = try #require(controller.selectedPaneDescendantFrameForTesting(
            accessibilityIdentifier: "exclude.apps.scroll"
        ))
        let paneBounds = NSRect(
            origin: .zero,
            size: NSSize(
                width: controller.selectedPaneDocumentWidthForTesting,
                height: controller.selectedPaneDocumentHeightForTesting
            )
        )

        #expect(titleFrame.minX >= -0.5)
        #expect(titleFrame.maxX <= controller.selectedPaneDocumentWidthForTesting + 0.5)
        #expect(titleFrame.minY >= -0.5)
        #expect(titleFrame.maxY <= controller.selectedPaneDocumentHeightForTesting + 0.5)
        #expect(tableFrame.minX >= paneBounds.minX - 0.5)
        #expect(tableFrame.maxX <= paneBounds.maxX + 0.5)
        #expect(tableFrame.minY >= paneBounds.minY - 0.5)
        #expect(tableFrame.maxY <= paneBounds.maxY + 0.5)
        #expect(tableFrame.width >= controller.selectedPaneDocumentWidthForTesting - 100)
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
                "Main",
                "History",
                "Search",
                "Previous Page",
                "Next Page",
                "Snippets",
                "Password Vault",
                "主体",
                "历史",
                "搜索",
                "上一页",
                "下一页",
                "片段",
                "密码箱"
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
        let searchLabel = try #require(rowLabels.first {
            ["Search", "搜索"].contains($0.text)
        })
        let previousPageLabel = try #require(rowLabels.first {
            ["Previous Page", "上一页"].contains($0.text)
        })
        let nextPageLabel = try #require(rowLabels.first {
            ["Next Page", "下一页"].contains($0.text)
        })
        let nextPageFrameInPane = try #require(controller.selectedPaneTextFrameForTesting(
            matching: ["Next Page", "下一页"]
        ))

        #expect(sectionTitles.count == 2)
        #expect(rowLabels.count == 7)
        #expect(recordFrames.count == 7)
        #expect(!textFrames.contains {
            ["Clear History:", "清空历史：", "清除历史："].contains($0.text)
        })
        #expect(abs(menuTitle.frame.minX - historyPanelTitle.frame.minX) <= 1)
        #expect(menuTitle.frame.maxY > historyPanelTitle.frame.maxY)
        #expect(searchLabel.frame.maxY > previousPageLabel.frame.maxY)
        #expect(previousPageLabel.frame.maxY > nextPageLabel.frame.maxY)
        #expect(nextPageFrameInPane.minY >= -0.5)
        #expect(nextPageFrameInPane.maxY <= controller.selectedPaneDocumentHeightForTesting + 0.5)

        let labelColumns = Set(rowLabels.map { Int(($0.frame.minX / 2).rounded()) })
        let recordColumns = Set(recordFrames.map { Int(($0.minX / 2).rounded()) })
        let paneMaxX = paneFrame.maxX
        #expect(labelColumns.count == 1)
        #expect(recordColumns.count == 1)
        for frame in recordFrames {
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

    private func preferenceGroups(in view: NSView) -> [PasteraPreferenceGroupView] {
        view.subviews.compactMap { $0 as? PasteraPreferenceGroupView }
            + view.subviews.flatMap { preferenceGroups(in: $0) }
    }

    private func descendantImageViews(in view: NSView) -> [NSImageView] {
        view.subviews.compactMap { $0 as? NSImageView }
            + view.subviews.flatMap { descendantImageViews(in: $0) }
    }

    private func descendantSettingRows(in view: NSView) -> [PasteraPreferenceSettingRowView] {
        view.subviews.compactMap { $0 as? PasteraPreferenceSettingRowView }
            + view.subviews.flatMap { descendantSettingRows(in: $0) }
    }

    private func descendantViews(in view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendantViews(in: $0) }
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
    func generalPaneContainsOnlyApprovedNativeGeneralSettings() throws {
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
        let launchFrame = try frame(of: [pasteraPreferenceString("Launch on Login")], in: buttonFrames)
        let colorPreviewFrame = try frame(
            of: [pasteraPreferenceString("Show color code preview")],
            in: buttonFrames
        )
        let automaticPasteFrame = try frame(of: [pasteraPreferenceString("Automatic Paste")], in: buttonFrames)
        let automaticPasteInfoFrame = try frame(
            of: [pasteraPreferenceString("Automatic Paste Permission Info")],
            in: buttonFrames
        )
        let remoteFrame = try frame(
            of: [pasteraPreferenceString("Pause shortcuts during remote control")],
            in: buttonFrames
        )
        let opacityFrame = try textFrame(of: [pasteraPreferenceString("Transparency")], in: textFields)
        let menuTitleLengthFrame = try textFrame(
            of: [pasteraPreferenceString("Number of characters in the menu:")],
            in: textFields
        )
        let visibleControlsFrame = [
            launchFrame,
            opacityFrame,
            menuTitleLengthFrame,
            colorPreviewFrame,
            automaticPasteFrame,
            automaticPasteInfoFrame,
            remoteFrame
        ].reduce(NSRect.null) { $0.union($1) }
        #expect(!sidebarButtonTitles.contains { ["Menu", "菜单"].contains($0) })
        #expect(buttonFrames.allSatisfy { !removedButtonTitles.contains($0.title) })
        #expect(textFields.allSatisfy { !removedTextTitles.contains($0.text) })
        #expect(!buttonFrames.contains { ["Clear History", "清除历史", "清空历史"].contains($0.title) })
        #expect(!buttonFrames.contains { ["Place already copied history at the top", "把已经粘贴的历史置顶"].contains($0.title) })
        #expect(!textFields.contains { ["Image/file limit:", "图片/文件上限："].contains($0.text) })
        #expect(!visibleControlsFrame.isNull)
        let generalPage = try #require(
            controller.cachedPreferencePageForTesting(paneID: .general) as? CPYGeneralPreferenceViewController
        )
        #expect((task3MinimumNativePreferenceGroupGap(in: generalPage.view) ?? 0) >= 11.5)
        for frame in [
            launchFrame,
            opacityFrame,
            menuTitleLengthFrame,
            colorPreviewFrame,
            automaticPasteFrame,
            automaticPasteInfoFrame,
            remoteFrame
        ] {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
        #expect(automaticPasteInfoFrame.minX > automaticPasteFrame.minX)
        #expect(abs(automaticPasteInfoFrame.midY - automaticPasteFrame.midY) <= 2)
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
            (
                title: button.accessibilityLabel() ?? button.title,
                frame: view.convert(button.frame, from: button.superview)
            )
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
struct SyncPreferenceOneDriveLocationTests { // swiftlint:disable:this type_body_length
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
            #expect(visibleTexts.contains(pasteraPreferenceString("OneDrive Available")))
            #expect(!visibleTexts.contains("已使用 OneDrive 默认同步位置。"))
            #expect(visibleTexts.contains(pasteraPreferenceString("OneDrive Status")))
            #expect(!visibleTexts.contains("可用"))
            #expect(!visibleTexts.contains(where: { $0.contains("Library/CloudStorage") }))
            #expect(preferenceButtons(in: controller.view).contains {
                $0.title == pasteraPreferenceString("Change")
            })
        }
    }

    @Test
    func syncPaneDoesNotRescanDefaultOneDriveLocationWhenAppBecomesActive() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }
        var resolution = SyncDefaultFolderResolution.notFound

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { resolution })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("未检测到 OneDrive"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == nil)

            resolution = .found(SyncDefaultFolderCandidate(
                oneDriveRootURL: oneDriveRootURL,
                syncRootURL: defaultRootURL,
                displayName: "OneDrive",
                isOneDriveBacked: true
            ))
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            controller.view.layoutSubtreeIfNeeded()

            visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("未检测到 OneDrive"))
            #expect(!visibleTexts.contains("OneDrive 可用"))
            #expect(!visibleTexts.contains("已使用 OneDrive 默认同步位置。"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == nil)
            #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
        }
    }

    @Test
    func syncPaneMarksSavedRootUnavailableWithoutRecreatingItWhenAppBecomesActive() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: defaultRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(defaultRootURL.path, forKey: Constants.UserDefaults.syncRootPath)
            defaults.synchronize()

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
            let window = SyncPreferenceVisibilityWindow()
            window.contentView = controller.view
            window.testIsVisible = true
            defer { window.contentView = nil }
            controller.view.layoutSubtreeIfNeeded()

            var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("OneDrive 可用"))

            try FileManager.default.removeItem(at: defaultRootURL)
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            controller.view.layoutSubtreeIfNeeded()

            visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("OneDrive 不可用"))
            #expect(!visibleTexts.contains("所选 OneDrive 文件夹不可用。"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
            #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
            #expect(preferenceButtons(in: controller.view).first {
                $0.title == pasteraPreferenceString("Show in Finder")
            }?.isEnabled == false)
        }
    }

    @Test
    func syncPanePreservesMissingSavedRootAcrossRepeatedOneDriveLifecycleCycles() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(defaultRootURL.path, forKey: Constants.UserDefaults.syncRootPath)
            defaults.synchronize()

            for _ in 0..<3 {
                try FileManager.default.createDirectory(at: defaultRootURL, withIntermediateDirectories: true)
                var controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
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
                var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
                #expect(visibleTexts.contains("OneDrive 可用"))
                #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)

                try FileManager.default.removeItem(at: defaultRootURL)
                controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
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
                visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
                #expect(visibleTexts.contains("OneDrive 不可用"))
                #expect(!visibleTexts.contains("所选 OneDrive 文件夹不可用。"))
                #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
                #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
            }
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
            #expect(!Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
                .contains("请选择 OneDrive 中可写的文件夹。"))

            selectedURL = customRootURL
            changeButton.performClick(nil)

            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == customRootURL.standardizedFileURL.path)
            let validTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!validTexts.contains("同步位置已更新，并通过 OneDrive 文件夹检查。"))
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
    func syncPaneGranularScopeSwitchesWriteTheirDefaultsWithoutAutomaticFlags() throws {
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
            let historyUploadSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Upload History")
            })
            let historyImportSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Import History")
            })

            historyUploadSwitch.performClick(nil)

            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticEnabled))

            historyImportSwitch.performClick(nil)

            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticEnabled))
        }
    }

    @Test
    func syncPaneFileTypeCheckboxesReplaceFileSwitchesAndDeriveFileScopesFromHistoryDirections() throws {
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
            let labels = Set(preferenceSwitchButtons(in: controller.view).compactMap { $0.accessibilityLabel() })
            #expect(!labels.contains("上传文件"))
            #expect(!labels.contains("同步文件"))
            let fileTypeLabels: Set<String> = [
                pasteraPreferenceString("Images"),
                pasteraPreferenceString("Common Document Types")
            ]
            let fileTypeCheckboxes = preferenceButtons(in: controller.view).filter {
                fileTypeLabels.contains($0.accessibilityLabel() ?? "")
            }
            #expect(fileTypeCheckboxes.count == 2)
            #expect(!preferenceButtons(in: controller.view).contains { $0.accessibilityLabel() == "Finder 文件" })
            #expect(!preferenceButtons(in: controller.view).contains {
                ["PDF", "RTF", "RTFD"].contains($0.accessibilityLabel() ?? "")
            })
            #expect(fileTypeCheckboxes.allSatisfy { $0.state == .off })

            let historyUploadSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Upload History")
            })
            let historyImportSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Import History")
            })
            let commonTextCheckbox = try #require(fileTypeCheckboxes.first {
                $0.accessibilityLabel() == pasteraPreferenceString("Common Document Types")
            })

            historyUploadSwitch.performClick(nil)
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))

            commonTextCheckbox.performClick(nil)

            #expect(commonTextCheckbox.state == .on)
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))

            historyImportSwitch.performClick(nil)
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))

            commonTextCheckbox.performClick(nil)

            #expect(commonTextCheckbox.state == .off)
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))
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
            Constants.UserDefaults.syncSnippetImportEnabled,
            Constants.UserDefaults.syncFileUploadEnabled,
            Constants.UserDefaults.syncFileImportEnabled,
            Constants.UserDefaults.syncFileTypes
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
            pasteraPreferenceString("Upload History"),
            pasteraPreferenceString("Import History"),
            pasteraPreferenceString("Upload Snippets"),
            pasteraPreferenceString("Import Snippets")
        ]
        return preferenceButtons(in: view).filter {
            switchLabels.contains($0.accessibilityLabel() ?? "")
        }
    }
}

private final class SyncPreferenceVisibilityWindow: NSWindow {
    var testIsVisible = false

    override var isVisible: Bool {
        testIsVisible
    }
}
