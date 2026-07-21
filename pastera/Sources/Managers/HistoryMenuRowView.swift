//
//  HistoryMenuRowView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/04.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

struct HistoryScriptAction {
    let id: UUID
    let title: String
    let copy: () -> Void
    let paste: () -> Void
}

enum HistoryScriptFeedback {
    case copied(scriptName: String)
    case pasted(scriptName: String)
    case failed(scriptName: String, error: ScriptExecutionError)

    var message: String {
        switch self {
        case let .copied(scriptName):
            return pasteraScriptString("\(scriptName) finished — copied to clipboard", "\(scriptName) 转换完成，已复制到剪贴板")
        case let .pasted(scriptName):
            return pasteraScriptString("\(scriptName) finished — pasted", "\(scriptName) 转换完成，已粘贴")
        case let .failed(scriptName, error):
            return pasteraScriptString(
                "\(scriptName) failed: \(error.shortDescription)",
                "\(scriptName) 执行失败：\(error.shortDescription)"
            )
        }
    }
}

private extension ScriptExecutionError {
    var shortDescription: String {
        switch self {
        case .inputTooLarge: return pasteraScriptString("input is too large", "输入内容过大")
        case .sourceTooLarge: return pasteraScriptString("script is too large", "脚本内容过大")
        case .missingTransform: return pasteraScriptString("transform(clip) is missing", "缺少 transform(clip)")
        case .javaScriptException: return pasteraScriptString("JavaScript error", "JavaScript 运行错误")
        case .invalidResult: return pasteraScriptString("invalid result type", "返回值类型无效")
        case .timeout: return pasteraScriptString("execution timed out", "执行超时")
        case .capacityExhausted: return pasteraScriptString("script runner is busy", "脚本执行器繁忙")
        }
    }
}

final class HistoryScriptFeedbackPresenter {
    static let shared = HistoryScriptFeedbackPresenter()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(_ feedback: HistoryScriptFeedback) {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)

        let isFailure: Bool
        if case .failed = feedback { isFailure = true } else { isFailure = false }
        let symbol = isFailure ? "xmark.circle.fill" : "checkmark.circle.fill"
        let color: NSColor = isFailure ? .systemRed : .systemGreen
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = color
        image.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: feedback.message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [image, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        let content = NSVisualEffectView()
        content.material = .hudWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        content.layer?.masksToBounds = true
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])

        let size = content.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = content
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 14))
        panel.orderFrontRegardless()
        NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [
            .announcement: feedback.message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        self.panel = panel

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }
}

private final class HistoryScriptMenuController: NSObject {
    private let actions: [HistoryScriptAction]

    init(actions: [HistoryScriptAction]) {
        self.actions = actions
    }

    var hasActions: Bool { !actions.isEmpty }

    func makeItem(title: String, performsPaste: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for action in actions {
            let selector = performsPaste ? #selector(paste(_:)) : #selector(copy(_:))
            let child = NSMenuItem(title: action.title, action: selector, keyEquivalent: "")
            child.target = self
            child.representedObject = action.id.uuidString
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    @objc private func copy(_ sender: NSMenuItem) {
        action(for: sender)?.copy()
    }

    @objc private func paste(_ sender: NSMenuItem) {
        action(for: sender)?.paste()
    }

    private func action(for sender: NSMenuItem) -> HistoryScriptAction? {
        guard let id = UUID(uuidString: sender.representedObject as? String ?? "") else { return nil }
        return actions.first { $0.id == id }
    }
}

// swiftlint:disable:next type_body_length
final class HistoryMenuRowView: NSControl {
    enum LayoutStyle {
        case regular
        case compactMainMenu
    }

    private struct Metrics {
        let width: CGFloat
        let textRowHeight: CGFloat
        let imageRowHeight: CGFloat
        let horizontalInset: CGFloat
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        let textSpacing: CGFloat
        let shortcutSpacing: CGFloat
        let deleteButtonSize: CGFloat
        let titleFontSize: CGFloat

        static let textPreviewDelay: TimeInterval = 0.32
        static let maxPreviewTextLength = 1200

        static let regular = Metrics(
            width: HistoryBrowserLayout.width,
            textRowHeight: 36,
            imageRowHeight: 52,
            horizontalInset: 18,
            imageWidth: 56,
            imageHeight: 36,
            textSpacing: 12,
            shortcutSpacing: 8,
            deleteButtonSize: 28,
            titleFontSize: 15
        )

        static let compactMainMenu = Metrics(
            width: MainMenuPanelLayout.width,
            textRowHeight: MainMenuPanelLayout.rowHeight,
            imageRowHeight: MainMenuPanelLayout.compactImageRowHeight,
            horizontalInset: 7,
            imageWidth: 34,
            imageHeight: 20,
            textSpacing: 7,
            shortcutSpacing: 5,
            deleteButtonSize: 20,
            titleFontSize: 12
        )
    }

    private static let imagePreviewController = HistoryMenuImagePreviewController()
    private static let textPreviewController = HistoryMenuTextPreviewController()

    #if DEBUG
    private static var textPreviewRequestObserverForTesting: ((String) -> Void)?
    private static var textPreviewSchedulerForTesting: ((DispatchWorkItem) -> Void)?
    #endif

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let editButton = NSButton()
    private let deleteButton = NSButton()
    private let onConfirm: () -> Void
    private let onEdit: (() -> Void)?
    private let onQuickEdit: (() -> Void)?
    private let onDelete: (() -> Void)?
    private let scriptMenuController: HistoryScriptMenuController
    private let previewImage: NSImage?
    private let previewText: String?
    private let fullTitle: String
    private let layoutStyle: LayoutStyle
    private let metrics: Metrics
    private var trackingArea: NSTrackingArea?
    private var textPreviewWorkItem: DispatchWorkItem?
    private var isMouseInside = false
    private var isFocused = false
    private let editButtonSymbolName = "wand.and.stars"
    private let editButtonAccessibilityLabel = pasteraScriptString("Improve Prompt", "美化提示词")
    var onLogicalFocusChange: (() -> Void)?
    var onKeyboardEvent: ((NSEvent) -> Bool)?

    init(
        title: String,
        image: NSImage?,
        shortcutText: String? = nil,
        previewText: String? = nil,
        layoutStyle: LayoutStyle = .regular,
        onEdit: (() -> Void)? = nil,
        onQuickEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        scriptActions: [HistoryScriptAction] = [],
        onConfirm: @escaping () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onEdit = onEdit
        self.onQuickEdit = onQuickEdit
        self.onDelete = onDelete
        self.scriptMenuController = HistoryScriptMenuController(actions: scriptActions)
        self.previewImage = image
        self.previewText = Self.boundedPreviewText(previewText)
        self.fullTitle = title
        self.layoutStyle = layoutStyle
        self.metrics = layoutStyle == .compactMainMenu ? .compactMainMenu : .regular
        let height = image == nil ? metrics.textRowHeight : metrics.imageRowHeight
        super.init(frame: NSRect(x: 0, y: 0, width: metrics.width, height: height))
        setup(title: title, image: image, shortcutText: shortcutText)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCommandDeleteShortcut(event) {
            return deleteFromKeyboard()
        }
        return moveHistoryMenuFocus(with: event) || super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        onLogicalFocusChange?()
        isFocused = true
        updateAppearance()
        scheduleTextPreview()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        if isMouseInside {
            scheduleTextPreview()
        } else {
            cancelTextPreview()
        }
        updateAppearance()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onLogicalFocusChange?()
        isMouseInside = true
        updateAppearance()
        scheduleTextPreview()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        cancelTextPreview()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onLogicalFocusChange?()
        window?.makeFirstResponder(self)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        guard editButton.isHidden || !editButton.frame.contains(location) else { return }
        guard deleteButton.isHidden || !deleteButton.frame.contains(location) else { return }
        confirm()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard onEdit != nil || onDelete != nil || scriptMenuController.hasActions else { return nil }
        let menu = NSMenu()
        if scriptMenuController.hasActions {
            menu.addItem(scriptMenuController.makeItem(
                title: pasteraScriptString("Copy As", "复制为"),
                performsPaste: false
            ))
            menu.addItem(scriptMenuController.makeItem(
                title: pasteraScriptString("Paste As", "粘贴为"),
                performsPaste: true
            ))
        }
        if onEdit != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let editItem = NSMenuItem(title: String(localized: "Edit"), action: #selector(editButtonClicked(_:)), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)
        }
        if onQuickEdit != nil {
            let quickEditItem = NSMenuItem(
                title: String(localized: "Quick Edit"),
                action: #selector(quickEdit(_:)),
                keyEquivalent: ""
            )
            quickEditItem.target = self
            menu.addItem(quickEditItem)
        }
        if onDelete != nil {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let deleteItem = NSMenuItem(title: String(localized: "Delete History"), action: #selector(deleteButtonClicked(_:)), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }
        return menu
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isFocused = false
            isMouseInside = false
            cancelTextPreview()
            updateAppearance()
            Self.hidePreviews()
        }
    }

    override func keyDown(with event: NSEvent) {
        if isCommandDeleteShortcut(event), deleteFromKeyboard() {
            return
        }
        if onKeyboardEvent?(event) == true {
            return
        }
        switch event.keyCode {
        case 36, 76:
            confirm()
        case 48:
            if moveHistoryMenuFocus(with: event) {
                return
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    func confirmFromKeyboard() {
        confirm()
    }

    @discardableResult
    func deleteFromKeyboard() -> Bool {
        guard onDelete != nil else { return false }
        delete()
        return true
    }

    private func setup(title: String, image: NSImage?, shortcutText: String?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        let hasImage = image != nil

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = !hasImage
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 5
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = PasteraDesignTokens.colors().surface.cgColor
        imageView.layer?.borderColor = PasteraDesignTokens.colors().separator.cgColor
        imageView.layer?.borderWidth = hasImage ? 0.5 : 0

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: metrics.titleFontSize, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .labelColor

        configureHistoryRowShortcut(self, badge: shortcutBadge, title: title, shortcut: shortcutText)

        editButton.identifier = NSUserInterfaceItemIdentifier("historyRowEditButton")
        editButton.setButtonType(.momentaryPushIn)
        editButton.bezelStyle = .inline
        editButton.isBordered = false
        editButton.image = NSImage(systemSymbolName: editButtonSymbolName, accessibilityDescription: nil)
        editButton.imagePosition = .imageOnly
        editButton.contentTintColor = .tertiaryLabelColor
        editButton.toolTip = editButtonAccessibilityLabel
        editButton.setAccessibilityLabel(editButtonAccessibilityLabel)
        editButton.target = self
        editButton.action = #selector(editButtonClicked(_:))
        editButton.isHidden = true

        deleteButton.identifier = NSUserInterfaceItemIdentifier("historyRowDeleteButton")
        deleteButton.setButtonType(.momentaryPushIn)
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .tertiaryLabelColor
        let deleteShortcutTitle = "\(String(localized: "Delete History")) (⌘D)"
        deleteButton.toolTip = deleteShortcutTitle
        deleteButton.setAccessibilityLabel(deleteShortcutTitle)
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked(_:))
        deleteButton.isHidden = true

        [shortcutBadge, imageView, titleLabel, editButton, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let hasShortcut = shortcutText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let shortcutSpacing: CGFloat = hasShortcut ? metrics.shortcutSpacing : 0
        let editButtonWidth: CGFloat = onEdit == nil ? 0 : metrics.deleteButtonSize
        let editButtonSpacing: CGFloat = onEdit == nil ? 0 : -4
        let deleteButtonWidth: CGFloat = onDelete == nil ? 0 : metrics.deleteButtonSize
        let deleteButtonSpacing: CGFloat = onDelete == nil ? 0 : -4

        NSLayoutConstraint.activate([
            shortcutBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.horizontalInset),
            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.leadingAnchor.constraint(equalTo: shortcutBadge.trailingAnchor, constant: shortcutSpacing),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: hasImage ? metrics.imageWidth : 0),
            imageView.heightAnchor.constraint(equalToConstant: hasImage ? metrics.imageHeight : 0),

            titleLabel.leadingAnchor.constraint(
                equalTo: hasImage ? imageView.trailingAnchor : shortcutBadge.trailingAnchor,
                constant: hasImage ? metrics.textSpacing : shortcutSpacing
            ),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: editButtonSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            editButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: deleteButtonSpacing),
            editButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: editButtonWidth),
            editButton.heightAnchor.constraint(equalToConstant: metrics.deleteButtonSize),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -metrics.horizontalInset),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: deleteButtonWidth),
            deleteButton.heightAnchor.constraint(equalToConstant: metrics.deleteButtonSize)
        ])
        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundColor: NSColor = isFocused
            ? selectedBackgroundColor
            : isMouseInside ? hoveredBackgroundColor : .clear
        layer?.backgroundColor = backgroundColor.cgColor
        titleLabel.textColor = isFocused ? .selectedMenuItemTextColor : .labelColor
        shortcutBadge.setState(isEmphasized: isFocused || isMouseInside)
        editButton.contentTintColor = isFocused || isMouseInside ? .secondaryLabelColor : .tertiaryLabelColor
        editButton.isHidden = onEdit == nil || !showsEditButton
        deleteButton.contentTintColor = isFocused || isMouseInside ? .secondaryLabelColor : .tertiaryLabelColor
        deleteButton.isHidden = onDelete == nil || !showsDeleteButton
        updatePreviewVisibility(isFocused: isFocused)
    }

    private var showsDeleteButton: Bool {
        switch layoutStyle {
        case .regular:
            return isFocused || isMouseInside
        case .compactMainMenu:
            return isMouseInside
        }
    }

    private var showsEditButton: Bool {
        true
    }

    private var selectedBackgroundColor: NSColor {
        switch layoutStyle {
        case .regular:
            return NSColor(calibratedRed: 0.04, green: 0.45, blue: 1.0, alpha: 0.90)
        case .compactMainMenu:
            return MainMenuVisualColors.selectedRow
        }
    }

    private var hoveredBackgroundColor: NSColor {
        switch layoutStyle {
        case .regular:
            return NSColor(calibratedWhite: 1.0, alpha: 0.085)
        case .compactMainMenu:
            return MainMenuVisualColors.hoveredRow
        }
    }

    private func updatePreviewVisibility(isFocused: Bool) {
        guard let previewImage else {
            Self.hideImagePreview()
            return
        }

        guard window?.isVisible == true else {
            Self.hideImagePreview()
            return
        }

        if isFocused || isMouseInside {
            Self.imagePreviewController.show(image: previewImage, relativeTo: bounds, in: self)
        } else {
            Self.hideImagePreview()
        }
    }

    private func scheduleTextPreview() {
        cancelTextPreview()
        guard previewImage == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.showTextPreviewIfNeeded()
        }
        textPreviewWorkItem = workItem
        #if DEBUG
        if let textPreviewSchedulerForTesting = Self.textPreviewSchedulerForTesting {
            textPreviewSchedulerForTesting(workItem)
            return
        }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.textPreviewDelay, execute: workItem)
    }

    private func showTextPreviewIfNeeded() {
        guard isMouseInside || isFocused,
              window?.isVisible == true,
              let previewText = textPreviewCandidate() else {
            Self.hideTextPreview()
            return
        }
        #if DEBUG
        Self.textPreviewRequestObserverForTesting?(previewText)
        #endif
        Self.textPreviewController.show(text: previewText, relativeTo: bounds, in: self)
    }

    private func cancelTextPreview() {
        textPreviewWorkItem?.cancel()
        textPreviewWorkItem = nil
        Self.hideTextPreview()
    }

    private func confirm() {
        isFocused = false
        isMouseInside = false
        cancelTextPreview()
        Self.hideImagePreview()
        onConfirm()
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        delete()
    }

    @objc private func editButtonClicked(_ sender: Any) {
        cancelTextPreview()
        Self.hideImagePreview()
        onEdit?()
    }

    @objc private func quickEdit(_ sender: Any) {
        cancelTextPreview()
        onQuickEdit?()
    }

    private func delete() {
        cancelTextPreview()
        Self.hideImagePreview()
        onDelete?()
    }

    private func isCommandDeleteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)
        return flags == .command && event.charactersIgnoringModifiers?.lowercased() == "d"
    }

}

extension HistoryMenuRowView {
    static func hideImagePreview() {
        imagePreviewController.hide()
    }

    static func hideTextPreview() {
        textPreviewController.hide()
    }

    static func hidePreviews() {
        hideImagePreview()
        hideTextPreview()
    }
}

private extension HistoryMenuRowView {
    static func boundedPreviewText(_ text: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedText, !trimmedText.isEmpty else { return nil }
        guard trimmedText.utf16.count > Metrics.maxPreviewTextLength else { return trimmedText }
        return (trimmedText as NSString).substring(to: Metrics.maxPreviewTextLength - 1) + "…"
    }

    func textPreviewCandidate() -> String? {
        if let previewText, !previewText.isEmpty { return previewText }
        guard isTitleVisuallyTruncated else {
            return nil
        }
        return Self.boundedPreviewText(fullTitle)
    }

    var isTitleVisuallyTruncated: Bool {
        layoutSubtreeIfNeeded()
        let visibleWidth = min(
            titleLabel.bounds.width,
            max(0, bounds.maxX - titleLabel.frame.minX - metrics.horizontalInset)
        )
        guard visibleWidth > 0 else {
            return false
        }
        let requiredWidth = (titleLabel.stringValue as NSString).size(
            withAttributes: [.font: titleLabel.font as Any]
        ).width
        return ceil(requiredWidth) > floor(visibleWidth) + 1
    }
}

#if DEBUG
extension HistoryMenuRowView {
    var isEditButtonVisibleForTesting: Bool {
        !editButton.isHidden
    }

    var editButtonSymbolNameForTesting: String {
        editButtonSymbolName
    }

    var editButtonAccessibilityLabelForTesting: String {
        editButtonAccessibilityLabel
    }

    func clickEditButtonForTesting() {
        editButton.performClick(nil)
    }

    static var isImagePreviewVisibleForTesting: Bool {
        imagePreviewController.isVisibleForTesting
    }

    static var isTextPreviewVisibleForTesting: Bool {
        textPreviewController.isVisibleForTesting
    }

    static var textPreviewValueForTesting: String {
        textPreviewController.textValueForTesting
    }

    static func observeTextPreviewRequestsForTesting(_ observer: ((String) -> Void)?) {
        textPreviewRequestObserverForTesting = observer
    }

    static func scheduleTextPreviewWorkItemsForTesting(_ scheduler: ((DispatchWorkItem) -> Void)?) {
        textPreviewSchedulerForTesting = scheduler
    }

    var textPreviewCandidateForTesting: String? {
        textPreviewCandidate()
    }

    var textValuesForTesting: [String] {
        collectTextValues(in: self)
    }

    func confirmForTesting() {
        confirm()
    }

    private func collectTextValues(in view: NSView) -> [String] {
        var values = [String]()
        for subview in view.subviews {
            if let label = subview as? NSTextField {
                values.append(label.stringValue)
            } else if let badge = subview as? PasteraShortcutBadgeView {
                values.append(badge.shortcutTextForTesting)
            }
            values.append(contentsOf: collectTextValues(in: subview))
        }
        return values
    }
}
#endif
