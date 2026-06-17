//
//  CPYSyncPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/16.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

final class CPYSyncPreferenceViewController: NSViewController {
    private enum Layout {
        static let width: CGFloat = 450
        static let titleHeight: CGFloat = 20
        static let guidanceHeight: CGFloat = 54
        static let headerHeight: CGFloat = 88
        static let sectionInset: CGFloat = 12
        static let rowHeight: CGFloat = 32
        static let rowSpacing: CGFloat = 6
        static let labelWidth: CGFloat = 122
        static let buttonWidth: CGFloat = 110
        static let secondaryButtonWidth: CGFloat = 64
        static let buttonGap: CGFloat = 8
        static let fieldHeight: CGFloat = 24
        static let sectionGap: CGFloat = 14

        static func sectionHeight(rowCount: Int) -> CGFloat {
            sectionInset * 2
                + CGFloat(rowCount) * rowHeight
                + CGFloat(max(0, rowCount - 1)) * rowSpacing
        }

        static var height: CGFloat {
            headerHeight
                + sectionGap
                + sectionHeight(rowCount: 3)
                + sectionGap
                + sectionHeight(rowCount: 4)
                + sectionGap
                + sectionHeight(rowCount: 3)
        }
    }

    private enum Text {
        static let title = "云同步"
        static let guidance = "Pastera 通过你电脑上的 OneDrive 文件夹同步；" +
            "Pastera 不连接 Microsoft 账号，也不保存云端副本。" +
            "开启“上传”只会同步之后的新变化；导入不会删除本地数据。"
        static let automaticSync = "自动同步"
        static let showInFinder = "显示"
        static let uploadHistory = "上传剪切板历史"
        static let importHistory = "导入剪切板历史"
        static let uploadSnippets = "上传片段"
        static let importSnippets = "导入片段"
        static let syncNow = "立即同步"
        static let oneDriveFolder = "同步位置"
        static let manualSync = "手动同步"
        static let defaultFolderApplied = "已使用 OneDrive 默认同步位置。"
        static let syncing = "同步中..."
        static let lastSync = "上次同步"
        static let counts = "导入 / 上传"
        static let status = "状态"
        static let notDetected = "未检测到 OneDrive"
    }

    private let settingsStore = UserDefaultsSyncSettingsStore()
    private var observer: NSObjectProtocol?
    private weak var accountSection: PasteraSettingsSectionView?
    private weak var switchesSection: PasteraSettingsSectionView?
    private weak var statusSection: PasteraSettingsSectionView?
    private weak var automaticSyncRow: PasteraSettingsRowView?
    private weak var folderRow: PasteraSettingsRowView?
    private weak var syncNowRow: PasteraSettingsRowView?
    private weak var historyUploadRow: PasteraSettingsRowView?
    private weak var historyImportRow: PasteraSettingsRowView?
    private weak var snippetUploadRow: PasteraSettingsRowView?
    private weak var snippetImportRow: PasteraSettingsRowView?
    private weak var lastSyncRow: PasteraSettingsRowView?
    private weak var countRow: PasteraSettingsRowView?
    private weak var statusRow: PasteraSettingsRowView?

    private let titleLabel = NSTextField(labelWithString: Text.title)
    private let guidanceLabel = NSTextField(labelWithString: Text.guidance)
    private let automaticSyncButton = NSButton(checkboxWithTitle: Text.automaticSync, target: nil, action: nil)
    private let pathField = NSTextField(labelWithString: "")
    private let showFolderButton = NSButton(title: Text.showInFinder, target: nil, action: nil)
    private let historyUploadButton = NSButton(checkboxWithTitle: Text.uploadHistory, target: nil, action: nil)
    private let historyImportButton = NSButton(checkboxWithTitle: Text.importHistory, target: nil, action: nil)
    private let snippetUploadButton = NSButton(checkboxWithTitle: Text.uploadSnippets, target: nil, action: nil)
    private let snippetImportButton = NSButton(checkboxWithTitle: Text.importSnippets, target: nil, action: nil)
    private let syncNowButton = NSButton(title: Text.syncNow, target: nil, action: nil)
    private let lastSyncValue = NSTextField(labelWithString: "-")
    private let countValue = NSTextField(labelWithString: "-")
    private let statusValue = NSTextField(labelWithString: "-")
    private let defaultFolderResolutionProvider: () -> SyncDefaultFolderResolution
    private let defaultFolderResolver: SyncDefaultFolderResolver
    private let revealInFinder: (URL) -> Void

    init(
        defaultFolderResolver: SyncDefaultFolderResolver = SyncDefaultFolderResolver(),
        defaultFolderResolutionProvider: (() -> SyncDefaultFolderResolution)? = nil,
        revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    ) {
        self.defaultFolderResolver = defaultFolderResolver
        self.defaultFolderResolutionProvider = defaultFolderResolutionProvider ?? { defaultFolderResolver.resolve() }
        self.revealInFinder = revealInFinder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = makeView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindActions()
        let defaultFolderMessage = applyDefaultFolder()
        updateControls()
        updateStatus()
        if let defaultFolderMessage {
            statusValue.stringValue = defaultFolderMessage
        }
        observer = NotificationCenter.default.addObserver(
            forName: SyncCoordinator.statusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatus()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutContent(width: view.bounds.width)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func makeView() -> NSView {
        let host = PasteraSettingsPaneHost(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.frame = NSRect(
            x: 0,
            y: Layout.height - Layout.titleHeight,
            width: Layout.width,
            height: Layout.titleHeight
        )
        host.addSubview(titleLabel)
        guidanceLabel.font = .systemFont(ofSize: 12)
        guidanceLabel.textColor = .secondaryLabelColor
        guidanceLabel.lineBreakMode = .byWordWrapping
        guidanceLabel.maximumNumberOfLines = 0
        host.addSubview(guidanceLabel)

        let accountSection = makeSection(rowCount: 3)
        self.accountSection = accountSection
        addAutomaticSyncRow(to: accountSection, index: 0)
        addFolderRow(to: accountSection, index: 1)
        addSyncNowRow(to: accountSection, index: 2)
        host.addSubview(accountSection)

        let switchesSection = makeSection(rowCount: 4)
        self.switchesSection = switchesSection
        addButtonRow(historyUploadButton, to: switchesSection, index: 0)
        addButtonRow(historyImportButton, to: switchesSection, index: 1)
        addButtonRow(snippetUploadButton, to: switchesSection, index: 2)
        addButtonRow(snippetImportButton, to: switchesSection, index: 3)
        host.addSubview(switchesSection)

        let statusSection = makeSection(rowCount: 3)
        self.statusSection = statusSection
        addStatusRow(title: Text.lastSync, value: lastSyncValue, to: statusSection, index: 0)
        addStatusRow(title: Text.counts, value: countValue, to: statusSection, index: 1)
        addStatusRow(title: Text.status, value: statusValue, to: statusSection, index: 2)
        host.addSubview(statusSection)

        layoutContent(width: Layout.width)
        CPYWindowAppearance.apply(to: host)
        return host
    }

    private func makeSection(rowCount: Int) -> PasteraSettingsSectionView {
        PasteraSettingsSectionView(frame: NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.sectionHeight(rowCount: rowCount)
        ))
    }

    private func makeRow(in section: NSView, index: Int) -> PasteraSettingsRowView {
        let rowY = section.bounds.height
            - Layout.sectionInset
            - Layout.rowHeight
            - CGFloat(index) * (Layout.rowHeight + Layout.rowSpacing)
        let row = PasteraSettingsRowView(frame: NSRect(
            x: Layout.sectionInset,
            y: rowY,
            width: section.bounds.width - Layout.sectionInset * 2,
            height: Layout.rowHeight
        ))
        section.addSubview(row)
        return row
    }

    private func addAutomaticSyncRow(to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        automaticSyncRow = row
        automaticSyncButton.frame = NSRect(x: 0, y: 4, width: row.bounds.width, height: Layout.fieldHeight)
        row.addSubview(automaticSyncButton)
    }

    private func addFolderRow(to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        folderRow = row
        let label = makeLabel(Text.oneDriveFolder)
        label.frame = NSRect(x: 0, y: 7, width: Layout.labelWidth, height: 18)
        pathField.frame = NSRect(
            x: Layout.labelWidth,
            y: 7,
            width: row.bounds.width - Layout.labelWidth - Layout.secondaryButtonWidth - Layout.buttonGap,
            height: 18
        )
        pathField.lineBreakMode = .byTruncatingMiddle
        showFolderButton.frame = NSRect(
            x: row.bounds.width - Layout.secondaryButtonWidth,
            y: 3,
            width: Layout.secondaryButtonWidth,
            height: Layout.fieldHeight
        )
        row.addSubview(label)
        row.addSubview(pathField)
        row.addSubview(showFolderButton)
    }

    private func addSyncNowRow(to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        syncNowRow = row
        let label = makeLabel(Text.manualSync)
        label.frame = NSRect(x: 0, y: 7, width: Layout.labelWidth, height: 18)
        syncNowButton.frame = NSRect(
            x: Layout.labelWidth,
            y: 3,
            width: Layout.buttonWidth,
            height: Layout.fieldHeight
        )
        row.addSubview(label)
        row.addSubview(syncNowButton)
    }

    private func addButtonRow(_ button: NSButton, to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        if button === historyUploadButton {
            historyUploadRow = row
        } else if button === historyImportButton {
            historyImportRow = row
        } else if button === snippetUploadButton {
            snippetUploadRow = row
        } else if button === snippetImportButton {
            snippetImportRow = row
        }
        button.frame = NSRect(x: 0, y: 4, width: row.bounds.width, height: Layout.fieldHeight)
        row.addSubview(button)
    }

    private func addStatusRow(title: String, value: NSTextField, to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        if value === lastSyncValue {
            lastSyncRow = row
        } else if value === countValue {
            countRow = row
        } else if value === statusValue {
            statusRow = row
        }
        let label = makeLabel(title)
        label.frame = NSRect(x: 0, y: 7, width: Layout.labelWidth, height: 18)
        value.frame = NSRect(x: Layout.labelWidth, y: 7, width: row.bounds.width - Layout.labelWidth, height: 18)
        value.lineBreakMode = .byTruncatingTail
        value.textColor = .secondaryLabelColor
        row.addSubview(label)
        row.addSubview(value)
    }

    private func makeLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

private extension CPYSyncPreferenceViewController {
    func bindActions() {
        automaticSyncButton.target = self
        automaticSyncButton.action = #selector(toggleAutomaticSync(_:))
        showFolderButton.target = self
        showFolderButton.action = #selector(showFolderInFinder)
        syncNowButton.target = self
        syncNowButton.action = #selector(syncNow)
        historyUploadButton.target = self
        historyUploadButton.action = #selector(toggleHistoryUpload(_:))
        snippetUploadButton.target = self
        snippetUploadButton.action = #selector(toggleSnippetUpload(_:))
        historyImportButton.target = self
        historyImportButton.action = #selector(toggleImport(_:))
        snippetImportButton.target = self
        snippetImportButton.action = #selector(toggleImport(_:))
    }

    @objc func toggleAutomaticSync(_ sender: NSButton) {
        let enabled = sender.state == .on
        guard enabled else {
            settingsStore.setAutomaticSyncEnabled(false)
            updateControls()
            return
        }
        guard ensureDefaultFolderAvailable() else {
            settingsStore.setAutomaticSyncEnabled(false)
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.enableAllSyncScopesIfNeeded()
        settingsStore.setAutomaticSyncEnabled(true)
        statusValue.stringValue = Text.defaultFolderApplied
        updateControls()
    }

    @objc func showFolderInFinder() {
        guard ensureDefaultFolderAvailable(), let rootURL = settingsStore.settings().rootURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            statusValue.stringValue = SyncCoordinatorError.folderUnavailable.localizedDescription
            return
        }
        revealInFinder(rootURL)
    }

    @objc func syncNow() {
        guard prepareManualSync() else { return }
        syncNowButton.isEnabled = false
        statusValue.stringValue = Text.syncing
        SyncCoordinator.shared.syncNow(reason: .manual)
    }

    @objc func toggleHistoryUpload(_ sender: NSButton) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setHistoryUploadEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleSnippetUpload(_ sender: NSButton) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setSnippetUploadEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleImport(_ sender: NSButton) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        if sender === historyImportButton {
            settingsStore.setHistoryImportEnabled(sender.state == .on)
        } else if sender === snippetImportButton {
            settingsStore.setSnippetImportEnabled(sender.state == .on)
        }
        updateControls()
    }

    func updateControls() {
        let settings = settingsStore.settings()
        automaticSyncButton.state = settings.automaticSyncEnabled ? .on : .off
        pathField.stringValue = settings.rootURL.map(displayName(for:)) ?? Text.notDetected
        showFolderButton.isEnabled = settings.rootURL != nil
        historyUploadButton.state = settings.historyUploadEnabled ? .on : .off
        historyImportButton.state = settings.historyImportEnabled ? .on : .off
        snippetUploadButton.state = settings.snippetUploadEnabled ? .on : .off
        snippetImportButton.state = settings.snippetImportEnabled ? .on : .off
    }

    func updateStatus() {
        let status = SyncCoordinator.shared.status
        if let lastSyncAt = status.lastSyncAt {
            lastSyncValue.stringValue = DateFormatter.localizedString(
                from: lastSyncAt,
                dateStyle: .short,
                timeStyle: .medium
            )
        } else {
            lastSyncValue.stringValue = "-"
        }
        countValue.stringValue = "\(status.importedCount) / \(status.uploadedCount)"
        statusValue.stringValue = status.statusText
        syncNowButton.isEnabled = status.phase != .syncing
    }

    func prepareManualSync() -> Bool {
        guard ensureDefaultFolderAvailable() else {
            return false
        }
        let settings = settingsStore.settings()
        guard settings.hasEnabledWork else {
            statusValue.stringValue = SyncCoordinatorError.noEnabledWork.localizedDescription
            return false
        }
        return true
    }

    func ensureDefaultFolderAvailable() -> Bool {
        if let message = applyDefaultFolder() {
            statusValue.stringValue = message
        }
        return settingsStore.settings().rootURL != nil
    }

    @discardableResult
    func applyDefaultFolder() -> String? {
        switch defaultFolderResolutionProvider() {
        case .found(let candidate):
            return useDefaultFolder(candidate)
        case .notFound:
            settingsStore.setRootURL(nil)
            return SyncCoordinatorError.missingOneDrive.localizedDescription
        case .multiple(let candidates):
            guard let candidate = defaultFolderResolver.preferredCandidate(from: candidates) else {
                settingsStore.setRootURL(nil)
                return SyncCoordinatorError.missingOneDrive.localizedDescription
            }
            return useDefaultFolder(candidate)
        }
    }

    func useDefaultFolder(_ candidate: SyncDefaultFolderCandidate) -> String {
        guard let preparedCandidate = defaultFolderResolver.prepare(candidate) else {
            settingsStore.setRootURL(nil)
            return SyncCoordinatorError.folderUnavailable.localizedDescription
        }
        settingsStore.setRootURL(preparedCandidate.syncRootURL)
        return Text.defaultFolderApplied
    }

    func displayName(for rootURL: URL) -> String {
        oneDriveDisplayName(for: rootURL) ?? Text.notDetected
    }

    func oneDriveDisplayName(for rootURL: URL) -> String? {
        let components = rootURL.standardizedFileURL.pathComponents
        guard let cloudStorageIndex = components.firstIndex(of: "CloudStorage"),
              components.indices.contains(cloudStorageIndex + 1) else {
            return defaultFolderResolver.oneDriveCandidate(containing: rootURL).map { candidate in
                relativeDisplayName(rootURL: rootURL, oneDriveRootURL: candidate.oneDriveRootURL)
            }
        }
        let oneDriveName = components[cloudStorageIndex + 1]
        guard oneDriveName.range(of: "OneDrive", options: [.anchored, .caseInsensitive]) != nil else {
            return nil
        }
        let remainingComponents = components.dropFirst(cloudStorageIndex + 2)
        return ([oneDriveName] + Array(remainingComponents)).joined(separator: " > ")
    }

    func relativeDisplayName(rootURL: URL, oneDriveRootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let oneDrivePath = oneDriveRootURL.standardizedFileURL.path
        guard rootPath.hasPrefix(oneDrivePath) else {
            return oneDriveRootURL.lastPathComponent
        }
        let suffix = rootPath.dropFirst(oneDrivePath.count).split(separator: "/").map(String.init)
        return ([oneDriveRootURL.lastPathComponent] + suffix).joined(separator: " > ")
    }
}

private extension CPYSyncPreferenceViewController {
    func layoutContent(width: CGFloat) {
        let contentWidth = max(320, width)
        let accountHeight = Layout.sectionHeight(rowCount: 3)
        let switchesHeight = Layout.sectionHeight(rowCount: 4)
        let statusHeight = Layout.sectionHeight(rowCount: 3)
        let titleY = Layout.height - Layout.titleHeight - 4

        titleLabel.frame = NSRect(
            x: 0,
            y: titleY,
            width: contentWidth,
            height: Layout.titleHeight
        )
        guidanceLabel.frame = NSRect(
            x: 0,
            y: titleY - 6 - Layout.guidanceHeight,
            width: contentWidth,
            height: Layout.guidanceHeight
        )

        let accountY = Layout.height - Layout.headerHeight - Layout.sectionGap - accountHeight
        accountSection?.frame = NSRect(x: 0, y: accountY, width: contentWidth, height: accountHeight)
        layoutRows([automaticSyncRow, folderRow, syncNowRow], in: accountSection)
        layoutAutomaticSyncRow()
        layoutFolderRow()
        layoutSyncNowRow()

        let switchesY = accountY - Layout.sectionGap - switchesHeight
        switchesSection?.frame = NSRect(x: 0, y: switchesY, width: contentWidth, height: switchesHeight)
        layoutRows([historyUploadRow, historyImportRow, snippetUploadRow, snippetImportRow], in: switchesSection)
        [
            (historyUploadButton, historyUploadRow),
            (historyImportButton, historyImportRow),
            (snippetUploadButton, snippetUploadRow),
            (snippetImportButton, snippetImportRow)
        ].forEach { button, row in
            guard let row else { return }
            button.frame = NSRect(x: 0, y: 4, width: row.bounds.width, height: Layout.fieldHeight)
        }

        statusSection?.frame = NSRect(x: 0, y: 0, width: contentWidth, height: statusHeight)
        layoutRows([lastSyncRow, countRow, statusRow], in: statusSection)
        layoutStatusValue(lastSyncValue, in: lastSyncRow)
        layoutStatusValue(countValue, in: countRow)
        layoutStatusValue(statusValue, in: statusRow)
    }

    func layoutRows(_ rows: [PasteraSettingsRowView?], in section: NSView?) {
        guard let section else { return }
        rows.enumerated().forEach { index, row in
            let rowY = section.bounds.height
                - Layout.sectionInset
                - Layout.rowHeight
                - CGFloat(index) * (Layout.rowHeight + Layout.rowSpacing)
            row?.frame = NSRect(
                x: Layout.sectionInset,
                y: rowY,
                width: section.bounds.width - Layout.sectionInset * 2,
                height: Layout.rowHeight
            )
        }
    }

    func layoutAutomaticSyncRow() {
        guard let row = automaticSyncRow else { return }
        automaticSyncButton.frame = NSRect(x: 0, y: 4, width: row.bounds.width, height: Layout.fieldHeight)
    }

    func layoutFolderRow() {
        guard let row = folderRow else { return }
        let label = row.subviews.compactMap { $0 as? NSTextField }.first { $0 !== pathField }
        let showWidth = min(Layout.secondaryButtonWidth, row.bounds.width)
        let pathWidth = max(1, row.bounds.width - Layout.labelWidth - showWidth - Layout.buttonGap)
        label?.frame = NSRect(x: 0, y: 7, width: Layout.labelWidth, height: 18)
        pathField.frame = NSRect(
            x: Layout.labelWidth,
            y: 7,
            width: pathWidth,
            height: 18
        )
        showFolderButton.frame = NSRect(
            x: row.bounds.width - showWidth,
            y: 3,
            width: showWidth,
            height: Layout.fieldHeight
        )
    }

    func layoutSyncNowRow() {
        guard let row = syncNowRow else { return }
        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        let buttonWidth = min(Layout.buttonWidth, row.bounds.width - Layout.labelWidth)
        label?.frame = NSRect(x: 0, y: 7, width: Layout.labelWidth, height: 18)
        syncNowButton.frame = NSRect(
            x: Layout.labelWidth,
            y: 3,
            width: max(1, buttonWidth),
            height: Layout.fieldHeight
        )
    }

    func layoutStatusValue(_ value: NSTextField, in row: PasteraSettingsRowView?) {
        guard let row else { return }
        let label = row.subviews.compactMap { $0 as? NSTextField }.first { $0 !== value }
        label?.frame = NSRect(x: 0, y: 7, width: Layout.labelWidth, height: 18)
        value.frame = NSRect(
            x: Layout.labelWidth,
            y: 7,
            width: max(1, row.bounds.width - Layout.labelWidth),
            height: 18
        )
    }
}
