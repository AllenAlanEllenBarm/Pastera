import AppKit

// This file owns the complete footer control family and its shared visual behavior.
// swiftlint:disable file_length

func mainMenuShortcutToolTip(title: String, includesPlainText: Bool, itemShortcut: String?) -> String {
    var hints = ["\(title) · ↩"]
    if includesPlainText { hints.append("⇧↩") }
    if let itemShortcut, !itemShortcut.isEmpty { hints.append(itemShortcut) }
    return hints.joined(separator: "  ·  ")
}

func configureHistoryRowShortcut(_ view: NSView, badge: PasteraShortcutBadgeView, title: String, shortcut: String?) {
    badge.style = .itemNumber
    badge.shortcutText = shortcut
    view.toolTip = mainMenuShortcutToolTip(title: title, includesPlainText: true, itemShortcut: shortcut)
    view.setAccessibilityHelp(view.toolTip)
}

struct MainMenuPanelBehavior {
    let isPinned: Bool

    init(isPinned: Bool = true) {
        self.isPinned = isPinned
    }

    var hidesOnDeactivate: Bool { !isPinned }
    var level: NSWindow.Level { isPinned ? .floating : .popUpMenu }
    var collectionBehavior: NSWindow.CollectionBehavior {
        isPinned ? [.ignoresCycle] : [.transient, .ignoresCycle]
    }
    var isMovableByWindowBackground: Bool { isPinned }
}

struct MainMenuToolbarViewConfiguration {
    let selectedMode: MainMenuToolbarMode
    let oneDriveStatus: OneDriveProcessStatus
    let passwordVaultSyncSnapshot: PasswordVaultSyncSnapshot?

    init(
        selectedMode: MainMenuToolbarMode,
        oneDriveStatus: OneDriveProcessStatus,
        passwordVaultSyncSnapshot: PasswordVaultSyncSnapshot? = nil
    ) {
        self.selectedMode = selectedMode
        self.oneDriveStatus = oneDriveStatus
        self.passwordVaultSyncSnapshot = passwordVaultSyncSnapshot
    }
}

enum MainMenuToolbarMode {
    case history
    case snippets
    case passwordVault
}

struct MainMenuToolbarActions {
    let onSearch: () -> Void
    let onHistory: () -> Void
    let onSnippets: () -> Void
    let onPasswordVault: () -> Void
    let onOneDrive: () -> Void
    let onPreferences: () -> Void
}

#if DEBUG
struct MainMenuToolbarButtonVisualState {
    let backgroundAlpha: CGFloat
}
#endif

struct MainMenuHoverTipContent {
    let title: String
    let shortcut: String?

    var accessibilityLabel: String {
        guard let shortcut, !shortcut.isEmpty else { return title }
        return "\(title), \(shortcut)"
    }
}

private final class MainMenuHoverTipLabelCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        drawingRect.origin.y += max(0, (drawingRect.height - textHeight) / 2)
        drawingRect.size.height = min(drawingRect.height, textHeight)
        return drawingRect
    }
}

private final class MainMenuHoverTipController {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 10
        static let titleShortcutSpacing: CGFloat = 8
        static let titleTextInset: CGFloat = 4
        static let shortcutHorizontalPadding: CGFloat = 9
        static let minimumShortcutWidth: CGFloat = 42
        static let height: CGFloat = 32
    }

    private static let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    private static let shortcutFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    private var panel: NSPanel?
    private var pendingShow: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?

    deinit {
        close()
    }

    func scheduleShow(content: MainMenuHoverTipContent, relativeTo anchor: NSButton) {
        close()
        let workItem = DispatchWorkItem { [weak self, weak anchor] in
            guard let anchor else { return }
            self?.show(content: content, relativeTo: anchor)
        }
        pendingShow = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: workItem)
    }

    func close() {
        pendingShow?.cancel()
        pendingShow = nil
        pendingClose?.cancel()
        pendingClose = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
    }

    private func show(content: MainMenuHoverTipContent, relativeTo anchor: NSButton) {
        guard let parentWindow = anchor.window else { return }
        let titleWidth = ceil((content.title as NSString).size(withAttributes: [
            .font: Self.titleFont
        ]).width) + Metrics.titleTextInset * 2
        let shortcutWidth = content.shortcut.map {
            max(
                Metrics.minimumShortcutWidth,
                ceil(($0 as NSString).size(withAttributes: [.font: Self.shortcutFont]).width)
                    + Metrics.shortcutHorizontalPadding * 2
            )
        } ?? 0
        let spacing = content.shortcut == nil ? 0 : Metrics.titleShortcutSpacing
        let size = NSSize(
            width: Metrics.horizontalPadding * 2 + titleWidth + spacing + shortcutWidth,
            height: Metrics.height
        )
        let tipPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tipPanel.isOpaque = false
        tipPanel.backgroundColor = .clear
        tipPanel.hasShadow = true
        tipPanel.ignoresMouseEvents = true
        tipPanel.level = .popUpMenu
        tipPanel.collectionBehavior = [.transient, .ignoresCycle]

        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 9
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 0.98).cgColor
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        contentView.layer?.borderWidth = 1

        let titleLabel = NSTextField(labelWithString: content.title)
        titleLabel.cell = MainMenuHoverTipLabelCell(textCell: content.title)
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.font = Self.titleFont
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(
            x: Metrics.horizontalPadding,
            y: 6,
            width: titleWidth,
            height: 20
        )
        contentView.addSubview(titleLabel)

        if let shortcut = content.shortcut {
            let keycap = NSTextField(labelWithString: shortcut)
            keycap.cell = MainMenuHoverTipLabelCell(textCell: shortcut)
            keycap.isBordered = false
            keycap.drawsBackground = false
            keycap.font = Self.shortcutFont
            keycap.alignment = .center
            keycap.textColor = .secondaryLabelColor
            keycap.wantsLayer = true
            keycap.layer?.cornerRadius = 5
            keycap.layer?.masksToBounds = true
            keycap.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            keycap.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
            keycap.layer?.borderWidth = 1
            keycap.frame = NSRect(
                x: titleLabel.frame.maxX + Metrics.titleShortcutSpacing,
                y: 5,
                width: shortcutWidth,
                height: 22
            )
            contentView.addSubview(keycap)
        }
        tipPanel.contentView = contentView

        let anchorOnScreen = parentWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var origin = NSPoint(
            x: anchorOnScreen.midX - size.width / 2,
            y: anchorOnScreen.maxY + 7
        )
        if let visibleFrame = parentWindow.screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + 6), visibleFrame.maxX - size.width - 6)
        }
        tipPanel.setFrameOrigin(origin)
        parentWindow.addChildWindow(tipPanel, ordered: .above)
        tipPanel.orderFront(nil)
        panel = tipPanel

        let workItem = DispatchWorkItem { [weak self] in
            self?.closeVisibleTip()
        }
        pendingClose = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func closeVisibleTip() {
        pendingClose = nil
        guard let panel else { return }
        guard !PasteraMotion.shouldReduceMotion else {
            close()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard self?.panel === panel else { return }
            self?.close()
        }
    }

    #if DEBUG
    func showNowForTesting(content: MainMenuHoverTipContent, relativeTo anchor: NSButton) {
        close()
        show(content: content, relativeTo: anchor)
    }
    #endif
}

class MainMenuToolbarButton: NSButton {
    var hoverTip: MainMenuHoverTipContent?
    var onHoverChanged: ((Bool) -> Void)?
    var isModeSelected = false {
        didSet { updateAppearance() }
    }

    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        onHoverChanged?(false)
    }

    func updateAppearance() {
        let backgroundColor: NSColor
        if isModeSelected {
            backgroundColor = MainMenuVisualColors.accentFill
        } else if isHighlighted {
            backgroundColor = MainMenuVisualColors.selectedRow
        } else if isHovered {
            backgroundColor = MainMenuVisualColors.hoveredRow
        } else {
            backgroundColor = .clear
        }
        layer?.backgroundColor = backgroundColor.cgColor
        contentTintColor = isModeSelected ? .controlAccentColor : (isHovered ? .labelColor : .secondaryLabelColor)
        let scale: CGFloat = isHighlighted && !PasteraMotion.shouldReduceMotion ? 0.96 : 1
        layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    #if DEBUG
    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered
        updateAppearance()
    }
    #endif
}

final class MainMenuToolbarView: NSView {
    private struct ButtonSpec {
        let identifier: String
        let image: NSImage?
        let hoverTip: MainMenuHoverTipContent
        let frame: NSRect
        let style: ButtonStyle
        let isSelected: Bool
        let action: Selector
    }

    private enum ButtonStyle {
        case utility
        case mode
    }

    private let configuration: MainMenuToolbarViewConfiguration
    private let actions: MainMenuToolbarActions
    private let hoverTipController = MainMenuHoverTipController()
    private(set) var oneDriveStatusButton: MainMenuOneDriveStatusButton?

    init(
        frame frameRect: NSRect,
        configuration: MainMenuToolbarViewConfiguration,
        actions: MainMenuToolbarActions
    ) {
        self.configuration = configuration
        self.actions = actions
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hoverTipController.close()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func setup() {
        identifier = NSUserInterfaceItemIdentifier("mainMenuFooterDock")
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0

        let centerY = bounds.midY
        addModeGroupBackground()
        addButton(ButtonSpec(
            identifier: "mainMenuSearchButton",
            image: systemImage("magnifyingglass", description: String(localized: "Search")),
            hoverTip: MainMenuHoverTipContent(title: String(localized: "Search"), shortcut: "⌘F"),
            frame: toolbarButtonFrame(originX: MainMenuPanelLayout.contentInnerPadding, centerY: centerY),
            style: .utility,
            isSelected: false,
            action: #selector(searchButtonClicked(_:))
        ))
        addButton(ButtonSpec(
            identifier: "mainMenuHistoryModeButton",
            image: MainMenuModeIcons.history(),
            hoverTip: MainMenuHoverTipContent(
                title: String(localized: "History"),
                shortcut: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.historyKeyCombo)
            ),
            frame: modeButtonFrame(originX: modeGroupX, centerY: centerY),
            style: .mode,
            isSelected: configuration.selectedMode == .history,
            action: #selector(historyButtonClicked(_:))
        ))
        addButton(ButtonSpec(
            identifier: "mainMenuSnippetModeButton",
            image: MainMenuModeIcons.snippets(),
            hoverTip: MainMenuHoverTipContent(
                title: String(localized: "Snippet"),
                shortcut: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.snippetKeyCombo)
            ),
            frame: modeButtonFrame(originX: modeGroupX + MainMenuPanelLayout.modeButtonWidth + Metrics.modeButtonSpacing,
                                   centerY: centerY),
            style: .mode,
            isSelected: configuration.selectedMode == .snippets,
            action: #selector(snippetButtonClicked(_:))
        ))
        addButton(ButtonSpec(
            identifier: "mainMenuPasswordVaultModeButton",
            image: MainMenuModeIcons.passwordVault(),
            hoverTip: MainMenuHoverTipContent(
                title: String(localized: "Password Vault"),
                shortcut: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.passwordVaultKeyCombo)
            ),
            frame: modeButtonFrame(originX: modeGroupX + (MainMenuPanelLayout.modeButtonWidth + Metrics.modeButtonSpacing) * 2,
                                   centerY: centerY),
            style: .mode,
            isSelected: configuration.selectedMode == .passwordVault,
            action: #selector(passwordVaultButtonClicked(_:))
        ))
        addOneDriveButton(centerY: centerY)
        addButton(ButtonSpec(
            identifier: "mainMenuPreferencesButton",
            image: systemImage("gearshape", description: String(localized: "Preferences")),
            hoverTip: MainMenuHoverTipContent(title: String(localized: "Preferences"), shortcut: "⌘,"),
            frame: toolbarButtonFrame(originX: preferencesButtonX, centerY: centerY),
            style: .utility,
            isSelected: false,
            action: #selector(preferencesButtonClicked(_:))
        ))
    }

    private enum Metrics {
        static let modeButtonSpacing: CGFloat = 2
        static let modeGroupPadding: CGFloat = 1
        static let modeGroupWidth: CGFloat = 99
        static let toolbarButtonSpacing: CGFloat = 3
    }

    private var preferencesButtonX: CGFloat {
        bounds.width
            - MainMenuPanelLayout.contentInnerPadding
            - MainMenuPanelLayout.toolbarButtonSize
    }

    private var oneDriveButtonX: CGFloat {
        preferencesButtonX
            - Metrics.toolbarButtonSpacing
            - MainMenuPanelLayout.oneDriveStatusButtonSize
    }

    private var modeGroupX: CGFloat {
        modeGroupFrame.minX + Metrics.modeGroupPadding
    }

    private var modeGroupFrame: NSRect {
        NSRect(
            x: (bounds.width - Metrics.modeGroupWidth) / 2,
            y: bounds.midY - MainMenuPanelLayout.modeControlHeight / 2,
            width: Metrics.modeGroupWidth,
            height: MainMenuPanelLayout.modeControlHeight
        )
    }

    private func toolbarButtonFrame(originX: CGFloat, centerY: CGFloat) -> NSRect {
        NSRect(
            x: originX,
            y: centerY - MainMenuPanelLayout.toolbarButtonSize / 2,
            width: MainMenuPanelLayout.toolbarButtonSize,
            height: MainMenuPanelLayout.toolbarButtonSize
        )
    }

    private func modeButtonFrame(originX: CGFloat, centerY: CGFloat) -> NSRect {
        NSRect(
            x: originX,
            y: centerY - MainMenuPanelLayout.modeControlHeight / 2,
            width: MainMenuPanelLayout.modeButtonWidth,
            height: MainMenuPanelLayout.modeControlHeight
        )
    }

    private func addModeGroupBackground() {
        let backgroundView = NSView(frame: modeGroupFrame)
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = MainMenuPanelLayout.modeControlHeight / 2
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.backgroundColor = MainMenuVisualColors.toolbarSurface.cgColor
        backgroundView.layer?.borderColor = MainMenuVisualColors.controlBorder.cgColor
        backgroundView.layer?.borderWidth = 1
        addSubview(backgroundView)
    }

    private func addButton(_ spec: ButtonSpec) {
        let button = MainMenuToolbarButton(frame: spec.frame)
        button.identifier = NSUserInterfaceItemIdentifier(spec.identifier)
        button.target = self
        button.action = spec.action
        button.title = ""
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = spec.image
        button.image?.isTemplate = true
        button.hoverTip = spec.hoverTip
        button.setAccessibilityLabel(spec.hoverTip.accessibilityLabel)
        button.onHoverChanged = { [weak self, weak button] isHovered in
            guard let self, let button else { return }
            if isHovered {
                self.hoverTipController.scheduleShow(content: spec.hoverTip, relativeTo: button)
            } else {
                self.hoverTipController.close()
            }
        }
        style(button, style: spec.style, isSelected: spec.isSelected)
        addSubview(button)
    }

    private func style(_ button: MainMenuToolbarButton, style: ButtonStyle, isSelected: Bool) {
        button.wantsLayer = true
        button.layer?.cornerRadius = style == .mode
            ? MainMenuPanelLayout.modeControlHeight / 2
            : MainMenuPanelLayout.toolbarButtonSize / 2
        button.layer?.masksToBounds = true
        button.isModeSelected = isSelected
        button.layer?.borderColor = style == .utility
            ? NSColor.clear.cgColor
            : NSColor.clear.cgColor
        button.layer?.borderWidth = 0
        button.updateAppearance()
    }

    private func addOneDriveButton(centerY: CGFloat) {
        let button = MainMenuOneDriveStatusButton(frame: NSRect(
            x: oneDriveButtonX,
            y: centerY - MainMenuPanelLayout.toolbarButtonSize / 2,
            width: MainMenuPanelLayout.toolbarButtonSize,
            height: MainMenuPanelLayout.toolbarButtonSize
        ))
        button.target = self
        button.action = #selector(oneDriveButtonClicked(_:))
        if let snapshot = configuration.passwordVaultSyncSnapshot {
            button.configure(snapshot: snapshot, processStatus: configuration.oneDriveStatus)
        } else {
            button.configure(status: configuration.oneDriveStatus)
        }
        button.onHoverChanged = { [weak self, weak button] isHovered in
            guard let self, let button, let hoverTip = button.hoverTip else { return }
            if isHovered {
                self.hoverTipController.scheduleShow(content: hoverTip, relativeTo: button)
            } else {
                self.hoverTipController.close()
            }
        }
        addSubview(button)
        oneDriveStatusButton = button
    }

    private func systemImage(_ symbolName: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    @objc private func searchButtonClicked(_ sender: NSButton) {
        actions.onSearch()
    }

    @objc private func historyButtonClicked(_ sender: NSButton) {
        actions.onHistory()
    }

    @objc private func snippetButtonClicked(_ sender: NSButton) {
        actions.onSnippets()
    }

    @objc private func passwordVaultButtonClicked(_ sender: NSButton) {
        actions.onPasswordVault()
    }

    @objc private func oneDriveButtonClicked(_ sender: NSButton) {
        actions.onOneDrive()
    }

    @objc private func preferencesButtonClicked(_ sender: NSButton) {
        actions.onPreferences()
    }

    #if DEBUG
    func showHoverTipForTesting(identifier: String) {
        guard let button = subviews.compactMap({ $0 as? MainMenuToolbarButton }).first(where: {
            $0.identifier?.rawValue == identifier
        }), let hoverTip = button.hoverTip else { return }
        hoverTipController.showNowForTesting(content: hoverTip, relativeTo: button)
    }

    func buttonVisualStateForTesting(identifier: String) -> MainMenuToolbarButtonVisualState? {
        guard let button = subviews.compactMap({ $0 as? MainMenuToolbarButton }).first(where: {
            $0.identifier?.rawValue == identifier
        }) else { return nil }
        let alpha = button.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.alphaComponent } ?? 0
        return MainMenuToolbarButtonVisualState(backgroundAlpha: alpha)
    }

    func setHoveredForTesting(_ hovered: Bool, identifier: String) {
        subviews.compactMap { $0 as? MainMenuToolbarButton }.first(where: {
            $0.identifier?.rawValue == identifier
        })?.setHoveredForTesting(hovered)
    }

    func hoverTipForTesting(identifier: String) -> MainMenuHoverTipContent? {
        subviews.compactMap { $0 as? MainMenuToolbarButton }.first {
            $0.identifier?.rawValue == identifier
        }?.hoverTip
    }

    func nativeToolTipForTesting(identifier: String) -> String? {
        subviews.compactMap { $0 as? MainMenuToolbarButton }.first {
            $0.identifier?.rawValue == identifier
        }?.toolTip
    }
    #endif
}

final class MainMenuPanelNoticeView: NSView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 9
        static let verticalInset: CGFloat = 7
        static let iconSize: CGFloat = 15
        static let iconSpacing: CGFloat = 6
        static let titleMessageSpacing: CGFloat = 2
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")

    init(title: String, message: String, image: NSImage?) {
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.noticeHeight
        ))
        setup(title: title, message: message, image: image)
    }

    required init?(coder: NSCoder) { nil }

    private func setup(title: String, message: String, image: NSImage?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .systemOrange

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        messageLabel.stringValue = message
        messageLabel.font = .systemFont(ofSize: 10, weight: .regular)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byWordWrapping

        [imageView, titleLabel, messageLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalInset),
            imageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: Metrics.iconSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalInset),

            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.titleMessageSpacing),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Metrics.verticalInset)
        ])
    }
}

enum MainMenuOneDriveSyncBadge: Equatable {
    case none
    case progress
    case disconnected
    case conflicts(Int)
}

struct MainMenuOneDriveStatusPresentation {
    let badge: MainMenuOneDriveSyncBadge
    let tintColor: NSColor
    let badgeColor: NSColor
    let pendingChangeCount: Int
    let accessibilityLabel: String

    init(snapshot: PasswordVaultSyncSnapshot, processStatus: OneDriveProcessStatus) {
        pendingChangeCount = snapshot.pendingChangeCount

        guard snapshot.mode == .oneDrive else {
            badge = .none
            tintColor = .secondaryLabelColor
            badgeColor = .clear
            accessibilityLabel = String(localized: "OneDrive sync is not enabled")
            return
        }

        let conflictCount = Self.conflictCount(snapshot: snapshot)
        if conflictCount > 0 {
            badge = .conflicts(conflictCount)
            tintColor = .systemBlue
            badgeColor = .systemYellow
            accessibilityLabel = String(
                format: String(localized: "OneDrive has %lld conflict copies"),
                Int64(conflictCount)
            )
            return
        }

        if !processStatus.isRunning || snapshot.phase.isDisconnected {
            badge = .disconnected
            tintColor = .secondaryLabelColor
            badgeColor = .systemRed
            accessibilityLabel = Self.disconnectedLabel(pendingChangeCount: snapshot.pendingChangeCount)
            return
        }

        switch snapshot.phase {
        case let .syncing(step):
            badge = .progress
            tintColor = .systemBlue
            badgeColor = .systemBlue
            accessibilityLabel = String(
                format: String(localized: "OneDrive is syncing: %@"),
                step.localizedStatus
            )
        case .waitingForUnlock:
            badge = .none
            tintColor = .systemBlue
            badgeColor = .clear
            accessibilityLabel = String(localized: "OneDrive is waiting for the vault to unlock")
        case .failed:
            badge = .disconnected
            tintColor = .secondaryLabelColor
            badgeColor = .systemRed
            accessibilityLabel = String(localized: "OneDrive sync failed")
        case .disabled:
            badge = .none
            tintColor = .secondaryLabelColor
            badgeColor = .clear
            accessibilityLabel = String(localized: "OneDrive sync is not enabled")
        case .synced, .conflicts, .disconnected:
            badge = .none
            tintColor = .systemBlue
            badgeColor = .clear
            accessibilityLabel = String(localized: "OneDrive is synced")
        }
    }

    private static func conflictCount(snapshot: PasswordVaultSyncSnapshot) -> Int {
        if case let .conflicts(phaseCount) = snapshot.phase {
            return max(phaseCount, snapshot.conflictCopyCount)
        }
        return snapshot.conflictCopyCount
    }

    private static func disconnectedLabel(pendingChangeCount: Int) -> String {
        guard pendingChangeCount > 0 else { return String(localized: "OneDrive is disconnected") }
        return String(
            format: String(localized: "OneDrive is disconnected; %lld changes are waiting"),
            Int64(pendingChangeCount)
        )
    }
}

private extension PasswordVaultSyncPhase {
    var isDisconnected: Bool {
        if case .disconnected = self {
            return true
        }
        return false
    }
}

private extension PasswordVaultSyncStep {
    var localizedStatus: String {
        switch self {
        case .checking: String(localized: "Checking OneDrive")
        case .downloading: String(localized: "Downloading encrypted replica")
        case .merging: String(localized: "Merging vault changes")
        case .savingLocal: String(localized: "Saving the local vault")
        case .uploading: String(localized: "Uploading encrypted replica")
        case .verifying: String(localized: "Verifying OneDrive copy")
        }
    }
}

private final class MainMenuOneDriveSyncBadgeView: NSView {
    private let imageView = NSImageView()
    private let countLabel = NSTextField(labelWithString: "")
    private(set) var symbolName: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(badge: MainMenuOneDriveSyncBadge, color: NSColor) {
        symbolName = nil
        imageView.image = nil
        countLabel.stringValue = ""
        isHidden = badge == .none
        guard badge != .none else { return }

        layer?.backgroundColor = color.cgColor
        switch badge {
        case .none:
            break
        case .progress:
            configureSymbol("arrow.triangle.2.circlepath")
        case .disconnected:
            configureSymbol("bolt.slash.fill")
        case let .conflicts(count):
            countLabel.stringValue = count > 99 ? "99+" : String(count)
            countLabel.textColor = .black
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = bounds.height / 2
        layer?.borderColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 1
        setAccessibilityElement(false)

        imageView.frame = bounds.insetBy(dx: 2.5, dy: 2.5)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .white
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        countLabel.frame = bounds
        countLabel.alignment = .center
        countLabel.font = .systemFont(ofSize: 8, weight: .bold)
        countLabel.autoresizingMask = [.width, .height]
        addSubview(countLabel)
    }

    private func configureSymbol(_ name: String) {
        symbolName = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        imageView.image = image
    }
}

final class MainMenuOneDriveStatusButton: MainMenuToolbarButton {
    override var acceptsFirstResponder: Bool { false }

    private let syncBadgeView = MainMenuOneDriveSyncBadgeView(frame: NSRect(x: 15, y: 15, width: 13, height: 13))
    private var syncBadge: MainMenuOneDriveSyncBadge = .none
    private var statusTintColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(status: OneDriveProcessStatus) {
        syncBadge = .none
        syncBadgeView.configure(badge: .none, color: .clear)
        switch status {
        case .running:
            image = Self.oneDriveStatusIcon
            statusTintColor = .systemBlue
            alphaValue = 1
            hoverTip = MainMenuHoverTipContent(title: "OneDrive 正在运行", shortcut: nil)
        case .notRunning:
            image = Self.oneDriveStatusIcon
            statusTintColor = .secondaryLabelColor
            alphaValue = 0.90
            hoverTip = MainMenuHoverTipContent(title: "OneDrive 未运行", shortcut: nil)
        case .notInstalled:
            image = Self.oneDriveStatusIcon
            statusTintColor = .tertiaryLabelColor
            alphaValue = 0.82
            hoverTip = MainMenuHoverTipContent(title: "未安装 OneDrive", shortcut: nil)
        }
        contentTintColor = statusTintColor
        setAccessibilityLabel(hoverTip?.accessibilityLabel)
    }

    func configure(snapshot: PasswordVaultSyncSnapshot, processStatus: OneDriveProcessStatus) {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: snapshot,
            processStatus: processStatus
        )
        image = Self.oneDriveStatusIcon
        statusTintColor = presentation.tintColor
        contentTintColor = presentation.tintColor
        alphaValue = 1
        syncBadge = presentation.badge
        syncBadgeView.configure(badge: presentation.badge, color: presentation.badgeColor)
        hoverTip = MainMenuHoverTipContent(title: presentation.accessibilityLabel, shortcut: nil)
        setAccessibilityLabel(presentation.accessibilityLabel)
    }

    override func updateAppearance() {
        super.updateAppearance()
        if let statusTintColor {
            contentTintColor = statusTintColor
        }
    }

    private func setup() {
        identifier = NSUserInterfaceItemIdentifier("mainMenuOneDriveStatusButton")
        setButtonType(.momentaryPushIn)
        bezelStyle = .inline
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = MainMenuPanelLayout.toolbarButtonSize / 2
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        syncBadgeView.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(syncBadgeView)
    }

    #if DEBUG
    var syncBadgeForTesting: MainMenuOneDriveSyncBadge { syncBadge }
    var syncBadgeSymbolForTesting: String? { syncBadgeView.symbolName }
    #endif

    private static let oneDriveStatusIcon: NSImage = {
        let image = NSImage(named: "onedrive_status_template")
            ?? NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(
                width: MainMenuPanelLayout.oneDriveStatusIconSize,
                height: MainMenuPanelLayout.oneDriveStatusIconSize
            ))
        image.size = NSSize(
            width: MainMenuPanelLayout.oneDriveStatusIconSize,
            height: MainMenuPanelLayout.oneDriveStatusIconSize
        )
        image.isTemplate = true
        return image
    }()
}

// swiftlint:enable file_length
