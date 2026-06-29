//
//  SyncPreferenceTopSectionTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct SyncPreferenceTopSectionTests {
    private struct PreferenceTextFieldFrame {
        let text: String
        let frame: NSRect
        let intrinsicWidth: CGFloat
    }

    @Test
    func syncPaneUsesCompactChineseControlsWithoutStatusSummary() throws {
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

        defaults.set(true, forKey: Constants.UserDefaults.syncHistoryUploadEnabled)
        defaults.set(false, forKey: Constants.UserDefaults.syncHistoryImportEnabled)
        defaults.set(true, forKey: Constants.UserDefaults.syncSnippetUploadEnabled)
        defaults.set(false, forKey: Constants.UserDefaults.syncSnippetImportEnabled)
        defaults.set(false, forKey: Constants.UserDefaults.syncFileUploadEnabled)
        defaults.set(false, forKey: Constants.UserDefaults.syncFileImportEnabled)
        defaults.synchronize()

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Sync")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let syncButtonTitles: Set<String> = ["i", "修改", "显示", "立即同步"]
        let fileTypeLabels: Set<String> = ["图片", "常用文本文件类型"]
        let syncSwitchLabels: Set<String> = [
            "上传历史",
            "同步历史",
            "上传片段",
            "同步片段"
        ]
        let removedButtonTitles: Set<String> = [
            "使用 OneDrive",
            "选择...",
            "解锁",
            "生成口令",
            "说明",
            "收起",
            "上传剪切板历史",
            "导入剪切板历史"
        ]
        let guidanceText = "Pastera 通过你电脑上的 OneDrive 文件夹同步；" +
            "Pastera 不连接 Microsoft 账号，也不保存云端副本。" +
            "自动上传会写入本机最新历史和完整片段；自动同步只导入其他设备数据。"
        let expectedTexts = Set<String>([
            "同步位置",
            "手动同步",
            "文件类型",
            "开",
            "关"
        ]).union(syncSwitchLabels)
        let syncButtonFrames = preferenceButtons(in: contentView)
            .filter { syncButtonTitles.contains($0.title) }
            .map { button in
                contentView.convert(button.frame, from: button.superview)
            }
        let infoButton = preferenceButtons(in: contentView).first { $0.title == "i" }
        let redetectButton = preferenceButtons(in: contentView).first {
            $0.accessibilityLabel() == "重新检测 OneDrive"
        }
        let syncSwitchFrames = preferenceSwitchButtons(in: contentView, labels: syncSwitchLabels).map { switchControl in
            contentView.convert(switchControl.frame, from: switchControl.superview)
        }
        let fileTypeFrames = preferenceButtons(in: contentView)
            .filter { fileTypeLabels.contains($0.accessibilityLabel() ?? "") }
            .map { contentView.convert($0.frame, from: $0.superview) }
        let nativeSyncSwitches = preferenceSwitches(in: contentView).filter {
            syncSwitchLabels.contains($0.accessibilityLabel() ?? "")
        }
        let removedButtons = preferenceButtons(in: contentView)
            .filter { removedButtonTitles.contains($0.title) }
        let textFields = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let visibleTexts = Set(textFields.map(\.text))
        let removedStatusTexts: Set<String> = ["上次同步", "导入 / 上传", "状态"]
        let switchRows = Set(syncSwitchFrames.map { Int(($0.midY / 2).rounded()) })
        let switchColumns = Set(syncSwitchFrames.map { Int(($0.midX / 2).rounded()) })
        let oneDriveStatusTexts: Set<String> = ["OneDrive 可用", "OneDrive 不可用", "未检测到 OneDrive"]
        let oneDriveStatusField = try #require(textFields.first { oneDriveStatusTexts.contains($0.text) })
        let oneDriveStatusFrame = oneDriveStatusField.frame
        let oneDriveBadgeFrame = try #require(preferenceViewFrame(
            in: contentView,
            identifier: "oneDriveStatusBadge"
        ))
        let folderLabelFrame = try #require(textFields.first { $0.text == "同步位置" }?.frame)
        let manualSyncFrame = try #require(textFields.first { $0.text == "手动同步" }?.frame)
        let fileTypeLabelFrame = try #require(textFields.first { $0.text == "文件类型" }?.frame)
        let changeFrame = try #require(preferenceButtons(in: contentView).first { $0.title == "修改" }.map {
            contentView.convert($0.frame, from: $0.superview)
        })
        let showFrame = try #require(preferenceButtons(in: contentView).first { $0.title == "显示" }.map {
            contentView.convert($0.frame, from: $0.superview)
        })
        let syncNowFrame = try #require(preferenceButtons(in: contentView).first { $0.title == "立即同步" }.map {
            contentView.convert($0.frame, from: $0.superview)
        })
        let infoFrame = try #require(infoButton.map {
            contentView.convert($0.frame, from: $0.superview)
        })
        let redetectFrame = try #require(redetectButton.map {
            contentView.convert($0.frame, from: $0.superview)
        })

        #expect(expectedTexts.isSubset(of: visibleTexts))
        #expect(!visibleTexts.contains("连接状态"))
        #expect(!visibleTexts.contains("云同步"))
        #expect(!visibleTexts.contains("OneDrive 状态"))
        #expect(!visibleTexts.contains("可用"))
        #expect(!visibleTexts.contains("不可用"))
        #expect(!visibleTexts.contains("自动上传"))
        #expect(!visibleTexts.contains("自动同步"))
        #expect(!visibleTexts.contains(guidanceText))
        #expect(!visibleTexts.contains("已选择 OneDrive 同步位置"))
        #expect(!visibleTexts.contains(where: { $0.contains(" > Pastera > sync") }))
        #expect(!visibleTexts.contains("上传文件"))
        #expect(!visibleTexts.contains("同步文件"))
        #expect(!preferenceButtons(in: contentView).contains {
            ["PDF", "RTF", "RTFD"].contains($0.accessibilityLabel() ?? "")
        })
        #expect(removedStatusTexts.isDisjoint(with: visibleTexts))
        #expect(!preferenceButtons(in: contentView).contains { $0.title == "不上传文件" })
        #expect(!preferenceButtons(in: contentView).contains { $0.accessibilityLabel() == "文件类型" })
        #expect(!preferenceButtons(in: contentView).contains { $0.accessibilityLabel() == "Finder 文件" })
        #expect(infoButton?.toolTip?.contains("OneDrive 文件夹") == true)
        #expect(redetectButton?.toolTip?.contains("重新检测") == true)
        #expect(redetectButton?.title == "检测")
        #expect(redetectFrame.width >= 48)
        #expect(syncButtonFrames.count == syncButtonTitles.count)
        #expect(fileTypeFrames.count == fileTypeLabels.count)
        #expect(syncSwitchFrames.count == syncSwitchLabels.count)
        #expect(nativeSyncSwitches.isEmpty)
        #expect(switchRows.count == 2)
        #expect(switchColumns.count == 2)
        #expect(removedButtons.isEmpty)
        #expect(!visibleTexts.contains("同步口令"))
        #expect(!visibleTexts.contains("位置操作"))
        #expect(oneDriveStatusFrame.maxY >= paneFrame.maxY - 42)
        #expect(oneDriveStatusFrame.width >= oneDriveStatusField.intrinsicWidth)
        #expect(oneDriveBadgeFrame.width >= 174)
        #expect(oneDriveBadgeFrame.contains(redetectFrame))
        #expect(abs(redetectFrame.midY - oneDriveBadgeFrame.midY) <= 1)
        #expect(abs(infoFrame.midY - oneDriveBadgeFrame.midY) <= 1)
        #expect(abs(oneDriveStatusFrame.midY - folderLabelFrame.midY) <= 1)
        #expect(abs(manualSyncFrame.midY - fileTypeLabelFrame.midY) <= 1)
        #expect(abs(manualSyncFrame.midY - syncNowFrame.midY) <= 1)
        #expect(abs(folderLabelFrame.midY - changeFrame.midY) <= 1)
        #expect(abs(changeFrame.midY - showFrame.midY) <= 1)
        #expect(folderLabelFrame.minX >= oneDriveBadgeFrame.maxX + 28)
        #expect(manualSyncFrame.maxX <= fileTypeLabelFrame.minX - 24)
        #expect(redetectFrame.minX >= oneDriveStatusFrame.maxX + 6)
        #expect(redetectFrame.maxX <= oneDriveBadgeFrame.maxX - 6)
        #expect(infoFrame.minX >= oneDriveBadgeFrame.maxX + 4)
        #expect(infoFrame.minX <= oneDriveBadgeFrame.maxX + 10)
        #expect(manualSyncFrame.minY < oneDriveStatusFrame.minY)
        #expect(folderLabelFrame.minY > manualSyncFrame.minY)
        #expect(changeFrame.minX >= folderLabelFrame.maxX + 6)
        #expect(changeFrame.maxX <= showFrame.minX - 6)
        #expect(showFrame.maxX <= paneMaxX)
        #expect(showFrame.width <= 60)
        #expect(syncNowFrame.width <= 100)
        #expect(controller.selectedPaneDocumentHeightForTesting >= 240)
        #expect(controller.selectedPaneDocumentHeightForTesting <= 266)
        for frame in syncButtonFrames + syncSwitchFrames + fileTypeFrames + [redetectFrame] {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
    }

    @Test
    func syncPaneManualSyncPromptsToInstallOneDriveWhenDefaultLocationIsMissing() throws {
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
        #expect(visibleTexts.contains("未检测到 OneDrive"))
        #expect(!visibleTexts.contains("OneDrive 状态"))
        #expect(!visibleTexts.contains("请先安装并登录 OneDrive。"))
    }

    @Test
    func syncPaneManualRedetectDiscoversDefaultOneDriveLocation() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
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
            let redetectButton = try #require(preferenceButtons(in: controller.view).first {
                $0.accessibilityLabel() == "重新检测 OneDrive"
            })

            redetectButton.performClick(nil)
            controller.view.layoutSubtreeIfNeeded()

            visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
            #expect(FileManager.default.fileExists(atPath: defaultRootURL.path))
        }
    }

    private func preferenceTextFieldFrames(
        in view: NSView,
        root: NSView? = nil
    ) -> [PreferenceTextFieldFrame] {
        let rootView = root ?? view
        var values = [PreferenceTextFieldFrame]()
        guard view.isHidden == false, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, textField.stringValue.isEmpty == false {
            values.append(PreferenceTextFieldFrame(
                text: textField.stringValue,
                frame: rootView.convert(textField.frame, from: textField.superview),
                intrinsicWidth: ceil(textField.intrinsicContentSize.width)
            ))
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

    private func preferenceViewFrame(
        in view: NSView,
        identifier: String,
        root: NSView? = nil
    ) -> NSRect? {
        let rootView = root ?? view
        guard view.isHidden == false, view.alphaValue > 0 else { return nil }
        if view.identifier?.rawValue == identifier {
            return rootView.convert(view.frame, from: view.superview)
        }
        for subview in view.subviews {
            if let frame = preferenceViewFrame(in: subview, identifier: identifier, root: rootView) {
                return frame
            }
        }
        return nil
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

    private func cloudStorageURL(homeURL: URL) -> URL {
        homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
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
}
