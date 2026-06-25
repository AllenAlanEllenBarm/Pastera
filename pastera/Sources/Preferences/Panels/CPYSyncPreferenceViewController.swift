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

// swiftlint:disable file_length

final class PasteraSyncSwitch: NSButton {
    static let onTrackColor = NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 46, height: 24)
    }

    override func setNextState() {
        super.setNextState()
        needsDisplay = true
    }

    override func performClick(_ sender: Any?) {
        super.performClick(sender)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 1, dy: 1)
        let radius = trackRect.height / 2
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.48
        let isOn = state == .on
        let trackColor = isOn ? Self.onTrackColor : offTrackColor
        trackColor.withAlphaComponent(trackColor.alphaComponent * enabledAlpha).setFill()
        trackPath.fill()

        let thumbDiameter = max(1, trackRect.height - 4)
        let thumbX = isOn
            ? trackRect.maxX - thumbDiameter - 2
            : trackRect.minX + 2
        let thumbRect = NSRect(
            x: thumbX,
            y: trackRect.midY - thumbDiameter / 2,
            width: thumbDiameter,
            height: thumbDiameter
        )
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        thumbColor.withAlphaComponent(enabledAlpha).setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func configure() {
        title = ""
        setButtonType(.switch)
        isBordered = false
        imagePosition = .noImage
        focusRingType = .none
    }

    private var offTrackColor: NSColor {
        isDarkAppearance
            ? NSColor(calibratedWhite: 1.0, alpha: 0.14)
            : NSColor(calibratedWhite: 0.0, alpha: 0.16)
    }

    private var thumbColor: NSColor {
        isDarkAppearance
            ? NSColor(calibratedWhite: 0.92, alpha: 1.0)
            : NSColor(calibratedWhite: 0.98, alpha: 1.0)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

final class CPYSyncPreferenceViewController: NSViewController {
    private enum Layout {
        static let width: CGFloat = 450
        static let topInset: CGFloat = 4
        static let bottomInset: CGFloat = 28
        static let sectionInset: CGFloat = 12
        static let rowHeight: CGFloat = 32
        static let rowSpacing: CGFloat = 6
        static let accountRowCount = 2
        static let accountLabelWidth: CGFloat = 74
        static let accountColumnGap: CGFloat = 20
        static let buttonWidth: CGFloat = 96
        static let secondaryButtonWidth: CGFloat = 58
        static let buttonGap: CGFloat = 8
        static let infoButtonSize: CGFloat = 16
        static let infoButtonGap: CGFloat = 6
        static let fieldHeight: CGFloat = 24
        static let switchWidth: CGFloat = 46
        static let switchHeight: CGFloat = 24
        static let switchStateWidth: CGFloat = 24
        static let switchStateGap: CGFloat = 6
        static let switchColumnGap: CGFloat = 20
        static let sectionGap: CGFloat = 12

        static func sectionHeight(rowCount: Int) -> CGFloat {
            sectionInset * 2
                + CGFloat(rowCount) * rowHeight
                + CGFloat(max(0, rowCount - 1)) * rowSpacing
        }

        static var height: CGFloat {
            topInset
                + bottomInset
                + sectionGap
                + sectionHeight(rowCount: accountRowCount)
                + sectionHeight(rowCount: 2)
        }
    }

    private enum Text {
        static let uploadHistory = "上传历史"
        static let importHistory = "同步历史"
        static let uploadSnippets = "上传片段"
        static let importSnippets = "同步片段"
        static let fileTypes = "文件类型"
        static let syncInfo = "i"
        static let syncInfoLabel = "同步说明"
        static let syncInfoText = "Pastera 使用你电脑上的 OneDrive 文件夹同步，不连接 Microsoft 账号。选择同步位置时会检查它是否在 OneDrive 文件夹内，并确认 Pastera 可以写入检测文件；云端是否上传完成，请看 OneDrive 客户端状态。"
        static let redetectOneDrive = "重新检测 OneDrive"
        static let redetectOneDriveTooltip = "重新检测本地 OneDrive 文件夹和写入权限。"
        static let switchOn = "开"
        static let switchOff = "关"
        static let changeFolder = "修改"
        static let showInFinder = "显示"
        static let syncNow = "立即同步"
        static let oneDriveStatus = "连接状态"
        static let oneDriveFolder = "同步位置"
        static let manualSync = "手动同步"
        static let notDetected = "未检测到 OneDrive"
    }

    private struct FileTypeOption {
        let type: PasteboardAvailableType
        let title: String
        let accessibilityLabel: String
        let symbolName: String
    }

    private let settingsStore = UserDefaultsSyncSettingsStore()
    private var syncActivityObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var switchRows = [
        (row: PasteraSettingsRowView, label: NSTextField, stateLabel: NSTextField, control: PasteraSyncSwitch)
    ]()
    private weak var accountSection: PasteraSettingsSectionView?
    private weak var switchesSection: PasteraSettingsSectionView?
    private weak var oneDriveStatusRow: PasteraSettingsRowView?
    private weak var folderRow: PasteraSettingsRowView?
    private weak var folderLabel: NSTextField?
    private weak var fileTypeLabel: NSTextField?
    private weak var syncNowRow: PasteraSettingsRowView?

    private let syncInfoButton = NSButton(title: Text.syncInfo, target: nil, action: nil)
    private let redetectOneDriveButton = NSButton(title: "", target: nil, action: nil)
    private let historyUploadSwitch = PasteraSyncSwitch()
    private let historyImportSwitch = PasteraSyncSwitch()
    private let snippetUploadSwitch = PasteraSyncSwitch()
    private let snippetImportSwitch = PasteraSyncSwitch()
    private var fileTypeButtons = [NSButton]()
    private let oneDriveStatusBadge = PasteraOneDriveStatusBadge()
    private let changeFolderButton = NSButton(title: Text.changeFolder, target: nil, action: nil)
    private let showFolderButton = NSButton(title: Text.showInFinder, target: nil, action: nil)
    private let syncNowButton = NSButton(title: Text.syncNow, target: nil, action: nil)
    private let defaultFolderResolutionProvider: () -> SyncDefaultFolderResolution
    private let defaultFolderResolver: SyncDefaultFolderResolver
    private let revealInFinder: (URL) -> Void
    private let chooseSyncRoot: (NSWindow?, URL?) -> URL?
    private var infoPopover: NSPopover?
    private let fileTypeOptions: [FileTypeOption] = [
        FileTypeOption(type: .tiff, title: "", accessibilityLabel: "图片", symbolName: "photo"),
        FileTypeOption(type: .pdf, title: "", accessibilityLabel: "PDF", symbolName: "doc.richtext"),
        FileTypeOption(type: .rtf, title: "", accessibilityLabel: "RTF", symbolName: "text.alignleft"),
        FileTypeOption(type: .rtfd, title: "", accessibilityLabel: "RTFD", symbolName: "doc.text.image")
    ]

    init(
        defaultFolderResolver: SyncDefaultFolderResolver = SyncDefaultFolderResolver(),
        defaultFolderResolutionProvider: (() -> SyncDefaultFolderResolution)? = nil,
        revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        chooseSyncRoot: @escaping (NSWindow?, URL?) -> URL? = { _, currentRootURL in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = Text.changeFolder
            panel.message = "选择 OneDrive 中的一个文件夹作为 Pastera 同步位置。"
            panel.directoryURL = currentRootURL
            return panel.runModal() == .OK ? panel.url : nil
        }
    ) {
        self.defaultFolderResolver = defaultFolderResolver
        self.defaultFolderResolutionProvider = defaultFolderResolutionProvider ?? { defaultFolderResolver.resolve() }
        self.revealInFinder = revealInFinder
        self.chooseSyncRoot = chooseSyncRoot
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
        refreshDefaultFolderAvailability()
        syncActivityObserver = NotificationCenter.default.addObserver(
            forName: SyncCoordinator.statusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateSyncActivityState()
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.refreshSavedFolderStatus()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutContent(width: view.bounds.width)
    }

    deinit {
        if let syncActivityObserver {
            NotificationCenter.default.removeObserver(syncActivityObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    private func makeView() -> NSView {
        let host = PasteraSettingsPaneHost(frame: NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.height
        ))
        syncInfoButton.bezelStyle = .circular
        syncInfoButton.font = .systemFont(ofSize: 11, weight: .semibold)
        syncInfoButton.setAccessibilityLabel(Text.syncInfoLabel)
        syncInfoButton.toolTip = Text.syncInfoText
        redetectOneDriveButton.bezelStyle = .circular
        redetectOneDriveButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: Text.redetectOneDrive
        )
        redetectOneDriveButton.imagePosition = .imageOnly
        redetectOneDriveButton.setAccessibilityLabel(Text.redetectOneDrive)
        redetectOneDriveButton.toolTip = Text.redetectOneDriveTooltip
        let accountSection = makeSection(rowCount: Layout.accountRowCount)
        self.accountSection = accountSection
        oneDriveStatusRow = makeRow(in: accountSection, index: 0)
        oneDriveStatusRow?.addSubview(makeLabel(Text.oneDriveStatus))
        oneDriveStatusRow?.addSubview(oneDriveStatusBadge)
        oneDriveStatusRow?.addSubview(redetectOneDriveButton)
        oneDriveStatusRow?.addSubview(syncInfoButton)
        addFolderRow(to: accountSection, index: 0)
        addSyncNowRow(to: accountSection, index: 1)
        host.addSubview(accountSection)

        let switchesSection = makeSection(rowCount: 2)
        self.switchesSection = switchesSection
        addSwitchRow(title: Text.uploadHistory, control: historyUploadSwitch, to: switchesSection, index: 0)
        addSwitchRow(title: Text.importHistory, control: historyImportSwitch, to: switchesSection, index: 1)
        addSwitchRow(title: Text.uploadSnippets, control: snippetUploadSwitch, to: switchesSection, index: 2)
        addSwitchRow(title: Text.importSnippets, control: snippetImportSwitch, to: switchesSection, index: 3)
        host.addSubview(switchesSection)

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

    private func addFolderRow(to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        folderRow = row
        let label = makeLabel(Text.oneDriveFolder)
        folderLabel = label
        let fileTypeLabel = makeLabel(Text.fileTypes)
        self.fileTypeLabel = fileTypeLabel
        row.addSubview(label)
        row.addSubview(changeFolderButton)
        row.addSubview(showFolderButton)
        row.addSubview(fileTypeLabel)
        fileTypeButtons = fileTypeOptions.map(makeFileTypeCheckbox)
        fileTypeButtons.forEach { row.addSubview($0) }
    }

    private func addSyncNowRow(to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        syncNowRow = row
        let label = makeLabel(Text.manualSync)
        row.addSubview(label)
        row.addSubview(syncNowButton)
    }

    private func addSwitchRow(title: String, control: PasteraSyncSwitch, to section: NSView, index: Int) {
        let row = makeRow(in: section, index: index)
        let label = makeLabel(title)
        let stateLabel = NSTextField(labelWithString: Text.switchOff)
        stateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stateLabel.alignment = .right
        stateLabel.textColor = .secondaryLabelColor
        control.setAccessibilityLabel(title)
        row.addSubview(label)
        row.addSubview(control)
        row.addSubview(stateLabel)
        switchRows.append((row, label, stateLabel, control))
    }

    private func makeLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeFileTypeCheckbox(_ option: FileTypeOption) -> NSButton {
        let button = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(toggleFileTypeCheckbox(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(option.type.rawValue)
        button.setAccessibilityLabel(option.accessibilityLabel)
        button.toolTip = option.accessibilityLabel
        button.image = NSImage(systemSymbolName: option.symbolName, accessibilityDescription: option.accessibilityLabel)
        button.imagePosition = .imageOnly
        button.alignment = .center
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.lineBreakMode = .byTruncatingTail
        return button
    }
}

extension CPYSyncPreferenceViewController {
    func refreshDefaultFolderAvailability() {
        applyDefaultFolder()
        updateControls()
        updateSyncActivityState()
    }

    func refreshSavedFolderStatus() {
        _ = updateControls()
        updateSyncActivityState()
    }
}

private extension CPYSyncPreferenceViewController {
    func bindActions() {
        historyUploadSwitch.target = self
        historyUploadSwitch.action = #selector(toggleHistoryUpload(_:))
        historyImportSwitch.target = self
        historyImportSwitch.action = #selector(toggleHistoryImport(_:))
        snippetUploadSwitch.target = self
        snippetUploadSwitch.action = #selector(toggleSnippetUpload(_:))
        snippetImportSwitch.target = self
        snippetImportSwitch.action = #selector(toggleSnippetImport(_:))
        syncInfoButton.target = self
        syncInfoButton.action = #selector(showSyncInfo(_:))
        redetectOneDriveButton.target = self
        redetectOneDriveButton.action = #selector(redetectOneDrive)
        changeFolderButton.target = self
        changeFolderButton.action = #selector(changeFolder)
        showFolderButton.target = self
        showFolderButton.action = #selector(showFolderInFinder)
        syncNowButton.target = self
        syncNowButton.action = #selector(syncNow)
    }

    @objc func showSyncInfo(_ sender: NSButton) {
        if infoPopover?.isShown == true {
            infoPopover?.close()
            return
        }

        let label = NSTextField(wrappingLabelWithString: Text.syncInfoText)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.frame = NSRect(x: 12, y: 12, width: 280, height: 78)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 102))
        contentView.addSubview(label)

        let controller = NSViewController()
        controller.view = contentView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        infoPopover = popover
    }

    @objc func redetectOneDrive() {
        refreshDefaultFolderAvailability()
    }

    @objc func showFolderInFinder() {
        guard ensureDefaultFolderAvailable(), let rootURL = settingsStore.settings().rootURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        revealInFinder(rootURL)
    }

    @objc func changeFolder() {
        let currentRootURL = settingsStore.settings().rootURL
        guard let selectedURL = chooseSyncRoot(view.window, currentRootURL) else {
            return
        }
        applyCustomSyncRoot(selectedURL)
    }

    @objc func syncNow() {
        guard prepareManualSync() else { return }
        syncNowButton.isEnabled = false
        SyncCoordinator.shared.syncNow(reason: .manual)
    }

    @objc func toggleHistoryUpload(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setHistoryUploadEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleHistoryImport(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setHistoryImportEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleSnippetUpload(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setSnippetUploadEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleSnippetImport(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setSnippetImportEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleFileTypeCheckbox(_ sender: NSButton) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        guard let rawValue = sender.identifier?.rawValue,
              let type = PasteboardAvailableType(rawValue: rawValue) else {
            return
        }
        settingsStore.setFileTypeEnabled(type, enabled: sender.state == .on)
        updateControls()
    }

    @discardableResult
    func updateControls() -> Bool {
        let settings = settingsStore.settings()
        let rootIsAvailable = updateOneDriveStatus(rootURL: settings.rootURL)
        showFolderButton.isEnabled = rootIsAvailable
        updateSwitch(historyUploadSwitch, isOn: settings.historyUploadEnabled)
        updateSwitch(historyImportSwitch, isOn: settings.historyImportEnabled)
        updateSwitch(snippetUploadSwitch, isOn: settings.snippetUploadEnabled)
        updateSwitch(snippetImportSwitch, isOn: settings.snippetImportEnabled)
        updateFileTypeCheckboxes(settings: settings)
        return rootIsAvailable
    }

    func updateSwitch(_ control: PasteraSyncSwitch, isOn: Bool) {
        control.state = isOn ? .on : .off
        control.setAccessibilityValue(isOn ? Text.switchOn : Text.switchOff)
        control.needsDisplay = true
        guard let switchRow = switchRows.first(where: { $0.control === control }) else {
            return
        }
        switchRow.stateLabel.stringValue = isOn ? Text.switchOn : Text.switchOff
        switchRow.stateLabel.textColor = isOn ? PasteraSyncSwitch.onTrackColor : .secondaryLabelColor
    }

    func updateFileTypeCheckboxes(settings: SyncSettings) {
        for button in fileTypeButtons {
            guard let rawValue = button.identifier?.rawValue,
                  let type = PasteboardAvailableType(rawValue: rawValue) else {
                continue
            }
            button.state = settings.fileAssetTypes.contains(type) ? .on : .off
        }
    }

    @discardableResult
    func updateOneDriveStatus(rootURL: URL?) -> Bool {
        guard let rootURL else {
            oneDriveStatusBadge.state = .notDetected
            folderRow?.toolTip = nil
            changeFolderButton.toolTip = nil
            showFolderButton.toolTip = nil
            layoutOneDriveStatusRow()
            return false
        }
        var isDirectory: ObjCBool = false
        let isAvailable = FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && isOneDriveBacked(rootURL)
            && FileManager.default.isWritableFile(atPath: rootURL.path)
        oneDriveStatusBadge.state = isAvailable ? .available : .unavailable
        let displayName = displayName(for: rootURL)
        folderRow?.toolTip = displayName
        changeFolderButton.toolTip = displayName
        showFolderButton.toolTip = displayName
        layoutOneDriveStatusRow()
        return isAvailable
    }

    func updateSyncActivityState() {
        let status = SyncCoordinator.shared.status
        syncNowButton.isEnabled = status.phase != .syncing
    }

    func prepareManualSync() -> Bool {
        guard ensureDefaultFolderAvailable() else {
            return false
        }
        let settings = settingsStore.settings()
        guard settings.hasEnabledWork else {
            return false
        }
        return true
    }

    func ensureDefaultFolderAvailable() -> Bool {
        applyDefaultFolder()
        guard let rootURL = settingsStore.settings().rootURL else {
            return false
        }
        return isSyncRootAvailable(rootURL)
    }

    func applyDefaultFolder() {
        if let rootURL = settingsStore.settings().rootURL {
            if !isSyncRootAvailable(rootURL) {
                updateControls()
            }
            return
        }
        switch defaultFolderResolutionProvider() {
        case .found(let candidate):
            useDefaultFolder(candidate)
        case .notFound:
            settingsStore.setRootURL(nil)
        case .multiple(let candidates):
            guard let candidate = defaultFolderResolver.preferredCandidate(from: candidates) else {
                settingsStore.setRootURL(nil)
                return
            }
            useDefaultFolder(candidate)
        }
    }

    func useDefaultFolder(_ candidate: SyncDefaultFolderCandidate) {
        guard let preparedCandidate = defaultFolderResolver.prepare(candidate) else {
            settingsStore.setRootURL(nil)
            return
        }
        settingsStore.setRootURL(preparedCandidate.syncRootURL)
    }

    func applyCustomSyncRoot(_ selectedURL: URL) {
        let rootURL = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        guard isSyncRootAvailable(rootURL), canWriteSyncProbe(at: rootURL) else {
            updateControls()
            return
        }
        settingsStore.setRootURL(rootURL)
        updateControls()
    }

    func isSyncRootAvailable(_ rootURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && isOneDriveBacked(rootURL)
            && FileManager.default.isWritableFile(atPath: rootURL.path)
    }

    func isOneDriveBacked(_ rootURL: URL) -> Bool {
        let components = rootURL.standardizedFileURL.pathComponents
        if let cloudStorageIndex = components.firstIndex(of: "CloudStorage"),
           components.indices.contains(cloudStorageIndex + 1) {
            let oneDriveName = components[cloudStorageIndex + 1]
            guard oneDriveName.range(of: "OneDrive", options: [.anchored, .caseInsensitive]) != nil else {
                return false
            }
            return oneDriveName.range(of: "Shared Libraries", options: [.caseInsensitive]) == nil
                && oneDriveName.range(of: "CloudTemp", options: [.caseInsensitive]) == nil
        }
        return defaultFolderResolver.oneDriveCandidate(containing: rootURL) != nil
    }

    func canWriteSyncProbe(at rootURL: URL) -> Bool {
        let probeURL = rootURL.appendingPathComponent(".pastera-sync-check", isDirectory: false)
        let payload = UUID().uuidString
        do {
            try payload.write(to: probeURL, atomically: true, encoding: .utf8)
            let checkedPayload = try String(contentsOf: probeURL, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeURL)
            return checkedPayload == payload
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            return false
        }
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
        let contentHeight = Layout.height
        if isViewLoaded, view.frame.height != contentHeight {
            view.frame.size.height = contentHeight
        }
        var sectionTopY = contentHeight - Layout.topInset
        sectionTopY = layoutSection(
            accountSection,
            rowCount: Layout.accountRowCount,
            topY: sectionTopY,
            contentWidth: contentWidth
        )
        layoutAccountRows()
        layoutOneDriveStatusRow()
        layoutFolderRow()
        layoutSyncNowRow()

        sectionTopY -= Layout.sectionGap
        sectionTopY = layoutSection(switchesSection, rowCount: 2, topY: sectionTopY, contentWidth: contentWidth)
        layoutSwitchRows(in: switchesSection)
    }

    func layoutSection(
        _ section: PasteraSettingsSectionView?,
        rowCount: Int,
        topY: CGFloat,
        contentWidth: CGFloat
    ) -> CGFloat {
        let sectionHeight = Layout.sectionHeight(rowCount: rowCount)
        section?.frame = NSRect(x: 0, y: topY - sectionHeight, width: contentWidth, height: sectionHeight)
        return topY - sectionHeight
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

    func layoutAccountRows() {
        guard let section = accountSection else { return }
        let availableWidth = max(1, section.bounds.width - Layout.sectionInset * 2)
        let columnWidth = floor(max(1, (availableWidth - Layout.accountColumnGap) / 2))
        let topRowY = section.bounds.height - Layout.sectionInset - Layout.rowHeight
        let bottomRowY = topRowY - Layout.rowHeight - Layout.rowSpacing
        oneDriveStatusRow?.frame = NSRect(
            x: Layout.sectionInset,
            y: topRowY,
            width: columnWidth,
            height: Layout.rowHeight
        )
        syncNowRow?.frame = NSRect(
            x: Layout.sectionInset + columnWidth + Layout.accountColumnGap,
            y: topRowY,
            width: columnWidth,
            height: Layout.rowHeight
        )
        folderRow?.frame = NSRect(
            x: Layout.sectionInset,
            y: bottomRowY,
            width: availableWidth,
            height: Layout.rowHeight
        )
    }

    func layoutFolderRow() {
        guard let row = folderRow else { return }
        let availableWidth = max(1, row.bounds.width)
        let columnWidth = floor(max(1, (availableWidth - Layout.accountColumnGap) / 2))
        let fileColumnX = columnWidth + Layout.accountColumnGap
        let showWidth = min(Layout.secondaryButtonWidth, columnWidth)
        let changeWidth = min(Layout.secondaryButtonWidth, columnWidth)
        let actionGroupWidth = showWidth + changeWidth + Layout.buttonGap
        let actionMinX = min(
            Layout.accountLabelWidth,
            max(0, columnWidth - actionGroupWidth)
        )
        folderLabel?.frame = NSRect(
            x: 0,
            y: centeredY(height: 18, in: row),
            width: max(1, actionMinX - Layout.buttonGap),
            height: 18
        )
        changeFolderButton.frame = NSRect(
            x: actionMinX,
            y: centeredY(height: Layout.fieldHeight, in: row),
            width: changeWidth,
            height: Layout.fieldHeight
        )
        showFolderButton.frame = NSRect(
            x: changeFolderButton.frame.maxX + Layout.buttonGap,
            y: centeredY(height: Layout.fieldHeight, in: row),
            width: showWidth,
            height: Layout.fieldHeight
        )
        fileTypeLabel?.frame = NSRect(
            x: fileColumnX,
            y: centeredY(height: 18, in: row),
            width: Layout.accountLabelWidth,
            height: 18
        )
        let checkboxSize = min(22, Layout.fieldHeight)
        let checkboxGap: CGFloat = 4
        let checkboxY = centeredY(height: checkboxSize, in: row)
        let checkboxStartX = fileColumnX + Layout.accountLabelWidth
        for (index, button) in fileTypeButtons.enumerated() {
            button.frame = NSRect(
                x: checkboxStartX + CGFloat(index) * (checkboxSize + checkboxGap),
                y: checkboxY,
                width: checkboxSize,
                height: checkboxSize
            )
        }
    }

    func layoutOneDriveStatusRow() {
        guard let row = oneDriveStatusRow else { return }
        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        let badgeSize = oneDriveStatusBadge.intrinsicContentSize
        let iconGroupWidth = Layout.infoButtonSize * 2 + Layout.infoButtonGap * 2
        let preferredBadgeX = min(Layout.accountLabelWidth, row.bounds.width)
        let minimumBadgeX = min(preferredBadgeX, max(0, Layout.accountLabelWidth - 20))
        let badgeX = min(
            preferredBadgeX,
            max(minimumBadgeX, row.bounds.width - badgeSize.width - iconGroupWidth)
        )
        let maxBadgeWidth = max(1, row.bounds.width - badgeX - iconGroupWidth)
        let badgeWidth = min(maxBadgeWidth, badgeSize.width)
        label?.frame = NSRect(x: 0, y: centeredY(height: 18, in: row), width: badgeX, height: 18)
        oneDriveStatusBadge.frame = NSRect(
            x: badgeX,
            y: centeredY(height: badgeSize.height, in: row),
            width: badgeWidth,
            height: badgeSize.height
        )
        redetectOneDriveButton.frame = NSRect(
            x: oneDriveStatusBadge.frame.maxX + Layout.infoButtonGap,
            y: centeredY(height: Layout.infoButtonSize, in: row),
            width: Layout.infoButtonSize,
            height: Layout.infoButtonSize
        )
        syncInfoButton.frame = NSRect(
            x: redetectOneDriveButton.frame.maxX + Layout.infoButtonGap,
            y: centeredY(height: Layout.infoButtonSize, in: row),
            width: Layout.infoButtonSize,
            height: Layout.infoButtonSize
        )
    }

    func layoutSyncNowRow() {
        guard let row = syncNowRow else { return }
        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        let buttonWidth = min(Layout.buttonWidth, row.bounds.width - Layout.accountLabelWidth)
        label?.frame = NSRect(
            x: 0,
            y: centeredY(height: 18, in: row),
            width: Layout.accountLabelWidth,
            height: 18
        )
        syncNowButton.frame = NSRect(
            x: Layout.accountLabelWidth,
            y: centeredY(height: Layout.fieldHeight, in: row),
            width: max(1, buttonWidth),
            height: Layout.fieldHeight
        )
    }

    func layoutSwitchRows(in section: NSView?) {
        guard let section else { return }
        let rows = switchRows.filter { $0.row.superview === section }
        let availableWidth = max(1, section.bounds.width - Layout.sectionInset * 2)
        let columnWidth = floor(max(1, (availableWidth - Layout.switchColumnGap) / 2))
        for (index, switchRow) in rows.enumerated() {
            let columnIndex = index % 2
            let rowIndex = index / 2
            let rowX = Layout.sectionInset
                + CGFloat(columnIndex) * (columnWidth + Layout.switchColumnGap)
            let rowY = section.bounds.height
                - Layout.sectionInset
                - Layout.rowHeight
                - CGFloat(rowIndex) * (Layout.rowHeight + Layout.rowSpacing)
            let row = switchRow.row
            row.frame = NSRect(
                x: rowX,
                y: rowY,
                width: columnWidth,
                height: Layout.rowHeight
            )
            let stateX = row.bounds.width - Layout.switchStateWidth
            let controlX = max(0, stateX - Layout.switchStateGap - Layout.switchWidth)
            switchRow.label.frame = NSRect(
                x: 0,
                y: 7,
                width: max(1, controlX - Layout.buttonGap),
                height: 18
            )
            switchRow.control.frame = NSRect(
                x: controlX,
                y: 4,
                width: Layout.switchWidth,
                height: Layout.switchHeight
            )
            switchRow.stateLabel.frame = NSRect(
                x: stateX,
                y: 7,
                width: Layout.switchStateWidth,
                height: 18
            )
        }
    }

    func centeredY(height: CGFloat, in row: NSView) -> CGFloat {
        floor((row.bounds.height - height) / 2)
    }
}
