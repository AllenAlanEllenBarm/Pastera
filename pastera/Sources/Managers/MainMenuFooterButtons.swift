import AppKit

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

final class MainMenuToolbarView: NSView {
    private struct ButtonSpec {
        let identifier: String
        let image: NSImage?
        let toolTip: String
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

    private func setup() {
        identifier = NSUserInterfaceItemIdentifier("mainMenuFooterDock")
        wantsLayer = true
        layer?.cornerRadius = MainMenuPanelLayout.sectionRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = MainMenuVisualColors.footerSurface.cgColor
        layer?.borderColor = MainMenuVisualColors.sectionBorder.cgColor
        layer?.borderWidth = 0.5

        let centerY = bounds.midY
        addModeGroupBackground()
        addButton(ButtonSpec(
            identifier: "mainMenuSearchButton",
            image: systemImage("magnifyingglass", description: String(localized: "Search")),
            toolTip: "\(String(localized: "Search")) · ⌘F",
            frame: toolbarButtonFrame(originX: MainMenuPanelLayout.contentInnerPadding, centerY: centerY),
            style: .utility,
            isSelected: false,
            action: #selector(searchButtonClicked(_:))
        ))
        addButton(ButtonSpec(
            identifier: "mainMenuHistoryModeButton",
            image: MainMenuModeIcons.history(),
            toolTip: String(localized: "History"),
            frame: modeButtonFrame(originX: modeGroupX, centerY: centerY),
            style: .mode,
            isSelected: configuration.selectedMode == .history,
            action: #selector(historyButtonClicked(_:))
        ))
        addButton(ButtonSpec(
            identifier: "mainMenuSnippetModeButton",
            image: MainMenuModeIcons.snippets(),
            toolTip: String(localized: "Snippet"),
            frame: modeButtonFrame(originX: modeGroupX + MainMenuPanelLayout.modeButtonWidth + Metrics.modeButtonSpacing,
                                   centerY: centerY),
            style: .mode,
            isSelected: configuration.selectedMode == .snippets,
            action: #selector(snippetButtonClicked(_:))
        ))
        addButton(ButtonSpec(
            identifier: "mainMenuPasswordVaultModeButton",
            image: MainMenuModeIcons.passwordVault(),
            toolTip: String(localized: "Password Vault"),
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
            toolTip: String(localized: "Preferences"),
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
        let button = NSButton(frame: spec.frame)
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
        button.toolTip = spec.toolTip
        button.setAccessibilityLabel(spec.toolTip)
        style(button, style: spec.style, isSelected: spec.isSelected)
        addSubview(button)
    }

    private func style(_ button: NSButton, style: ButtonStyle, isSelected: Bool) {
        button.wantsLayer = true
        button.layer?.cornerRadius = style == .mode
            ? MainMenuPanelLayout.modeControlHeight / 2
            : MainMenuPanelLayout.toolbarButtonSize / 2
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = buttonBackgroundColor(style: style, isSelected: isSelected).cgColor
        button.layer?.borderColor = style == .utility
            ? NSColor.clear.cgColor
            : NSColor.clear.cgColor
        button.layer?.borderWidth = 0
        button.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
    }

    private func buttonBackgroundColor(style: ButtonStyle, isSelected: Bool) -> NSColor {
        if isSelected {
            return MainMenuVisualColors.accentFill
        }
        switch style {
        case .utility:
            return .clear
        case .mode:
            return .clear
        }
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
        button.configure(status: configuration.oneDriveStatus)
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

final class MainMenuOneDriveStatusButton: NSButton {
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(status: OneDriveProcessStatus) {
        switch status {
        case .running:
            image = Self.oneDriveStatusIcon
            contentTintColor = .systemBlue
            alphaValue = 1
            toolTip = "OneDrive 正在运行。点击打开 OneDrive。"
        case .notRunning:
            image = Self.oneDriveStatusIcon
            contentTintColor = .secondaryLabelColor
            alphaValue = 0.90
            toolTip = "OneDrive 未运行。点击打开 OneDrive。"
        case .notInstalled:
            image = Self.oneDriveStatusIcon
            contentTintColor = .tertiaryLabelColor
            alphaValue = 0.82
            toolTip = "未安装 OneDrive。"
        }
        setAccessibilityLabel(toolTip)
    }

    private func setup() {
        identifier = NSUserInterfaceItemIdentifier("mainMenuOneDriveStatusButton")
        setButtonType(.momentaryPushIn)
        bezelStyle = .inline
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = MainMenuPanelLayout.toolbarButtonSize / 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
    }

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
