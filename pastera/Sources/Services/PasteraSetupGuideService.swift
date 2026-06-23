import Cocoa
import Foundation

struct PasteraSetupGuidePolicy {
    static let launchArgument = "--pastera-open-setup-guide"

    let arguments: [String]
    let isAccessibilityTrusted: Bool
    let didDismissSetupGuide: Bool

    var shouldShowSetupGuide: Bool {
        if arguments.contains(Self.launchArgument) {
            return true
        }
        if isAccessibilityTrusted {
            return false
        }
        return !didDismissSetupGuide
    }
}

enum PasteraSetupGuideAction: Equatable {
    case openAccessibilitySettings, recheckAccessibility, finish, dismiss
}

enum PasteraSetupGuideStep: Equatable {
    case installLocation, accessibility
}

enum PasteraSetupGuideStepStatus: Equatable {
    case completed, current
}

struct PasteraSetupGuideStepState: Equatable {
    let step: PasteraSetupGuideStep
    let status: PasteraSetupGuideStepStatus
}

struct PasteraSetupGuideViewState: Equatable {
    let isAccessibilityTrusted: Bool
    let didOpenAccessibilitySettings: Bool

    var progressTitle: String {
        isAccessibilityTrusted ? "已完成 2 / 2 步" : "第 2 步 / 共 2 步"
    }

    var stepStates: [PasteraSetupGuideStepState] {
        [
            PasteraSetupGuideStepState(step: .installLocation, status: .completed),
            PasteraSetupGuideStepState(
                step: .accessibility,
                status: isAccessibilityTrusted ? .completed : .current
            )
        ]
    }

    var primaryAction: PasteraSetupGuideAction {
        if isAccessibilityTrusted {
            return .finish
        }
        if didOpenAccessibilitySettings {
            return .recheckAccessibility
        }
        return .openAccessibilitySettings
    }

    var secondaryAction: PasteraSetupGuideAction? {
        if isAccessibilityTrusted {
            return nil
        }
        if didOpenAccessibilitySettings {
            return .openAccessibilitySettings
        }
        return .dismiss
    }

    var availableActions: [PasteraSetupGuideAction] {
        [primaryAction]
    }
}

enum PasteraSetupGuideLayout {
    static let windowSize = CGSize(width: 680, height: 430)
    static let contentWidth: CGFloat = 616
    static let headerHeight: CGFloat = 58
    static let stepRowHeight: CGFloat = 74
    static let noticeHeight: CGFloat = 64
    static let stepMarkerWidth: CGFloat = 30
    static let stepTextLeading: CGFloat = 16
    static let stepStatusWidth: CGFloat = 74
}

final class PasteraSetupGuideWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let accessibilityService: AccessibilityService
    private let defaults: UserDefaults
    private let progressLabel = NSTextField(labelWithString: "")
    private let headlineLabel = NSTextField(labelWithString: "")
    private let statusTitleLabel = NSTextField(labelWithString: "")
    private let statusBodyLabel = NSTextField(wrappingLabelWithString: "")
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)
    private let statusCard = NSView()
    private let statusIconView = NSImageView()
    private var stepRows = [PasteraSetupGuideStepRowView]()
    private var didOpenAccessibilitySettings = false

    init(accessibilityService: AccessibilityService, defaults: UserDefaults) {
        self.accessibilityService = accessibilityService
        self.defaults = defaults

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PasteraSetupGuideLayout.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Text.windowTitle
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
        updateStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if !accessibilityService.isAccessibilityEnabled(isPrompt: false) {
            defaults.set(true, forKey: Constants.UserDefaults.setupGuideDismissed)
        }
        onClose?()
    }
}

private extension PasteraSetupGuideWindowController {
    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        stack.addArrangedSubview(makeHeaderView())
        stack.addArrangedSubview(makeStepList())
        stack.addArrangedSubview(makeStatusCard())
        stack.addArrangedSubview(makeButtonRow())

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.contentWidth),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -2)
        ])
        return root
    }

    private func makeHeaderView() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        headlineLabel.font = .systemFont(ofSize: 12, weight: .medium)
        headlineLabel.textColor = .secondaryLabelColor
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: Text.title)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(wrappingLabelWithString: Text.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configurePill(progressLabel, textColor: .controlAccentColor)
        progressLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        [iconView, headlineLabel, titleLabel, subtitleLabel, progressLabel].forEach(header.addSubview)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.contentWidth),
            header.heightAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.headerHeight),
            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: header.topAnchor, constant: 2),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            headlineLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            headlineLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 1),
            titleLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: progressLabel.leadingAnchor, constant: -18),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            progressLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            progressLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 4),
            progressLabel.widthAnchor.constraint(equalToConstant: 116),
            progressLabel.heightAnchor.constraint(equalToConstant: 26)
        ])
        return header
    }

    private func makeStepList() -> NSView {
        let list = NSView()
        list.wantsLayer = true
        list.layer?.cornerRadius = 12
        list.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.46).cgColor
        list.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        list.layer?.borderWidth = 1
        list.translatesAutoresizingMaskIntoConstraints = false

        let installRow = PasteraSetupGuideStepRowView(
            step: .installLocation,
            number: "1",
            title: Text.stepInstallTitle,
            body: Text.stepInstallBody
        )
        let accessibilityRow = PasteraSetupGuideStepRowView(
            step: .accessibility,
            number: "2",
            title: Text.stepAccessibilityTitle,
            body: Text.stepAccessibilityBody
        )
        let divider = makeDivider()

        stepRows = [installRow, accessibilityRow]
        [installRow, divider, accessibilityRow].forEach(list.addSubview)

        NSLayoutConstraint.activate([
            list.widthAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.contentWidth),
            list.heightAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.stepRowHeight * 2 + 1),
            installRow.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            installRow.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            installRow.topAnchor.constraint(equalTo: list.topAnchor),
            installRow.heightAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.stepRowHeight),
            divider.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 58),
            divider.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            divider.topAnchor.constraint(equalTo: installRow.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            accessibilityRow.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            accessibilityRow.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            accessibilityRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            accessibilityRow.heightAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.stepRowHeight)
        ])
        return list
    }

    private func makeStatusCard() -> NSView {
        statusCard.wantsLayer = true
        statusCard.layer?.cornerRadius = 12
        statusCard.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.38).cgColor
        statusCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        statusCard.layer?.borderWidth = 1
        statusCard.translatesAutoresizingMaskIntoConstraints = false

        statusIconView.imageScaling = .scaleProportionallyUpOrDown
        statusIconView.translatesAutoresizingMaskIntoConstraints = false

        statusTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusTitleLabel.textColor = .labelColor
        statusTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBodyLabel.font = .systemFont(ofSize: 13)
        statusBodyLabel.textColor = .secondaryLabelColor
        statusBodyLabel.maximumNumberOfLines = 2
        statusBodyLabel.translatesAutoresizingMaskIntoConstraints = false

        [statusIconView, statusTitleLabel, statusBodyLabel].forEach(statusCard.addSubview)

        NSLayoutConstraint.activate([
            statusCard.widthAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.contentWidth),
            statusCard.heightAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.noticeHeight),
            statusIconView.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 18),
            statusIconView.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor),
            statusIconView.widthAnchor.constraint(equalToConstant: 22),
            statusIconView.heightAnchor.constraint(equalToConstant: 22),
            statusTitleLabel.leadingAnchor.constraint(equalTo: statusIconView.trailingAnchor, constant: 14),
            statusTitleLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -18),
            statusTitleLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 12),
            statusBodyLabel.leadingAnchor.constraint(equalTo: statusTitleLabel.leadingAnchor),
            statusBodyLabel.trailingAnchor.constraint(equalTo: statusTitleLabel.trailingAnchor),
            statusBodyLabel.topAnchor.constraint(equalTo: statusTitleLabel.bottomAnchor, constant: 4)
        ])
        return statusCard
    }

    private func makeButtonRow() -> NSView {
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10
        buttons.detachesHiddenViews = true
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .large
        primaryButton.keyEquivalent = "\r"
        secondaryButton.bezelStyle = .rounded
        secondaryButton.controlSize = .large

        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(secondaryButton)
        buttons.addArrangedSubview(primaryButton)

        NSLayoutConstraint.activate([
            buttons.widthAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.contentWidth),
            buttons.heightAnchor.constraint(equalToConstant: 34),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
            secondaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])
        return buttons
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        return divider
    }

    private func configurePill(_ label: NSTextField, textColor: NSColor) {
        label.alignment = .center
        label.textColor = textColor
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.backgroundColor = textColor.withAlphaComponent(0.12).cgColor
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    @discardableResult
    private func updateStatus() -> Bool {
        let isTrusted = accessibilityService.isAccessibilityEnabled(isPrompt: false)
        let viewState = PasteraSetupGuideViewState(
            isAccessibilityTrusted: isTrusted,
            didOpenAccessibilitySettings: didOpenAccessibilitySettings
        )

        progressLabel.stringValue = viewState.progressTitle
        for stepState in viewState.stepStates {
            stepRows.first { $0.step == stepState.step }?.update(with: stepState.status)
        }

        if isTrusted {
            applyStatus(
                headline: Text.readyHeadline,
                title: Text.authorizedStatusTitle,
                body: Text.authorizedStatusBody,
                symbolName: "checkmark.circle.fill",
                color: .systemGreen
            )
        } else if didOpenAccessibilitySettings {
            applyStatus(
                headline: Text.recheckHeadline,
                title: Text.recheckStatusTitle,
                body: Text.recheckStatusBody,
                symbolName: "arrow.clockwise.circle.fill",
                color: .controlAccentColor
            )
        } else {
            applyStatus(
                headline: Text.pendingHeadline,
                title: Text.pendingStatusTitle,
                body: Text.pendingStatusBody,
                symbolName: "lock.shield.fill",
                color: .controlAccentColor
            )
        }

        configure(primaryButton, for: viewState.primaryAction)
        if let secondaryAction = viewState.secondaryAction {
            configure(secondaryButton, for: secondaryAction)
            secondaryButton.isHidden = false
        } else {
            secondaryButton.isHidden = true
        }

        return isTrusted
    }

    private func applyStatus(headline: String, title: String, body: String, symbolName: String, color: NSColor) {
        headlineLabel.stringValue = headline
        statusTitleLabel.stringValue = title
        statusBodyLabel.stringValue = body
        statusIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        statusIconView.contentTintColor = color
        statusCard.layer?.borderColor = color.withAlphaComponent(0.38).cgColor
        statusCard.layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
    }

    private func configure(_ button: NSButton, for action: PasteraSetupGuideAction) {
        button.title = Text.buttonTitle(for: action)
        button.target = self

        switch action {
        case .openAccessibilitySettings:
            button.action = #selector(openAccessibilitySettings)
        case .recheckAccessibility:
            button.action = #selector(recheckAccessibility)
        case .finish:
            button.action = #selector(finishSetup)
        case .dismiss:
            button.action = #selector(dismissSetup)
        }
    }

    @objc private func openAccessibilitySettings() {
        didOpenAccessibilitySettings = true
        _ = accessibilityService.isAccessibilityEnabled(isPrompt: true)
        _ = accessibilityService.openAccessibilitySettingWindow()
        updateStatus()
    }

    @objc private func recheckAccessibility() {
        guard updateStatus() else { return }
        close()
    }

    @objc private func finishSetup() {
        close()
    }

    @objc private func dismissSetup() {
        close()
    }

    private enum Text {
        static let windowTitle = "Pastera Setup"
        static let title = "完成 Pastera 设置"
        static let subtitle = "安装已完成。授权辅助功能后，Pastera 才能响应热键并粘贴片段。"
        static let stepInstallTitle = "已安装到 Applications"
        static let stepInstallBody = "安装位置稳定，macOS 权限会绑定到同一个 Pastera.app。"
        static let stepAccessibilityTitle = "允许辅助功能"
        static let stepAccessibilityBody = "打开隐私与安全性 > 辅助功能，允许 Pastera。"
        static let pendingHeadline = "当前停在第 2 步"
        static let recheckHeadline = "等待授权确认"
        static let readyHeadline = "设置已完成"
        static let pendingStatusTitle = "需要打开辅助功能设置"
        static let pendingStatusBody = "下一步会打开 macOS 系统设置；找到 Pastera 并打开开关。"
        static let recheckStatusTitle = "授权后回到这里重新检测"
        static let recheckStatusBody = "如果还没有看到 Pastera，确认当前安装的是 /Applications/Pastera.app。"
        static let authorizedStatusTitle = "辅助功能已授权"
        static let authorizedStatusBody = "可以关闭此窗口，Pastera 会继续在菜单栏运行。"
        static let openSettingsButton = "打开辅助功能设置"
        static let recheckButton = "重新检测授权状态"
        static let finishButton = "完成"
        static let dismissButton = "稍后"

        static func buttonTitle(for action: PasteraSetupGuideAction) -> String {
            switch action {
            case .openAccessibilitySettings:
                return openSettingsButton
            case .recheckAccessibility:
                return recheckButton
            case .finish:
                return finishButton
            case .dismiss:
                return dismissButton
            }
        }
    }
}
