// Copyright 2026 Feeyo

import AppKit

final class CPYPasswordVaultPreferenceViewController: PasteraPreferencePageViewController {
    private enum Layout {
        static let lockingWeight: CGFloat = 1.18
        static let masterPasswordWeight: CGFloat = 0.82
    }

    private let passwordVaultController: PasswordVaultUIController
    private let openPasswordVault: () -> Void
    private var stateObserverToken: UUID?
    private var masterPasswordSheetController: PasswordVaultMasterPasswordSheetController?
    private var latestState: PasswordVaultSecuritySettingsState?

    private let statusBadge = PasteraVaultStatusBadge()
    private let autoLockPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let quickUnlockSwitch = NSSwitch()
    private let stateDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let feedbackIcon = NSImageView()
    private let setupButton = NSButton(
        title: pasteraPreferenceString("Open Password Vault Setup"),
        target: nil,
        action: nil
    )
    private let changeMasterPasswordButton = NSButton(
        title: pasteraPreferenceString("Change Master Password"),
        target: nil,
        action: nil
    )

    init(
        controller: PasswordVaultUIController = AppEnvironment.current.passwordVaultUIController,
        openPasswordVault: @escaping () -> Void = {
            AppEnvironment.current.menuManager.popUpMenu(.passwordVault)
        }
    ) {
        passwordVaultController = controller
        self.openPasswordVault = openPasswordVault
        super.init(paneID: .passwordVault, title: pasteraPreferenceString("Password Vault"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        removeStateObserver()
    }

    override func loadView() {
        removeStateObserver()
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        super.loadView()
        configureControls()
        buildHeader()
        buildGroups()
        installStateObserver()
        refreshSecuritySettings()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        installStateObserver()
        refreshSecuritySettings()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        removeStateObserver()
    }

    private func configureControls() {
        autoLockPopup.removeAllItems()
        for (title, interval) in [
            (pasteraPreferenceString("1 Minute"), 60),
            (pasteraPreferenceString("5 Minutes"), 300),
            (pasteraPreferenceString("15 Minutes"), 900),
            (pasteraPreferenceString("30 Minutes"), 1_800)
        ] {
            autoLockPopup.addItem(withTitle: title)
            autoLockPopup.lastItem?.tag = interval
        }
        autoLockPopup.target = self
        autoLockPopup.action = #selector(autoLockIntervalChanged(_:))
        autoLockPopup.setAccessibilityLabel(pasteraPreferenceString("Automatic Lock"))
        autoLockPopup.setAccessibilityIdentifier("vault.autoLock.control")

        quickUnlockSwitch.target = self
        quickUnlockSwitch.action = #selector(quickUnlockChanged(_:))
        quickUnlockSwitch.setAccessibilityLabel(pasteraPreferenceString("Quick Unlock"))
        quickUnlockSwitch.setAccessibilityIdentifier("vault.quickUnlock.control")

        stateDetailLabel.font = .systemFont(ofSize: 11.5)
        stateDetailLabel.textColor = .secondaryLabelColor
        stateDetailLabel.maximumNumberOfLines = 4
        stateDetailLabel.setAccessibilityIdentifier("vault.state.detail")

        feedbackIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        feedbackIcon.contentTintColor = .systemOrange
        feedbackLabel.font = .systemFont(ofSize: 11.5)
        feedbackLabel.textColor = .systemOrange
        feedbackLabel.maximumNumberOfLines = 4

        setupButton.target = self
        setupButton.action = #selector(openPasswordVaultSetup(_:))
        setupButton.bezelStyle = .rounded
        setupButton.setAccessibilityIdentifier("vault.setup.button")

        changeMasterPasswordButton.target = self
        changeMasterPasswordButton.action = #selector(changeMasterPassword(_:))
        changeMasterPasswordButton.bezelStyle = .rounded
        changeMasterPasswordButton.keyEquivalent = "\r"
        changeMasterPasswordButton.setAccessibilityIdentifier("vault.masterPassword.button")
    }

    private func buildHeader() {
        let subtitle = NSTextField(
            wrappingLabelWithString: pasteraPreferenceString("Manage password vault locking, unlocking, and master password.")
        )
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [subtitle, spacer, statusBadge])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        contentStack.insertArrangedSubview(header, at: 1)
        header.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(18, after: header)
    }

    private func buildGroups() {
        let lockingGroup = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Locking & Unlocking"),
            symbolName: "lock.rotation",
            accentColor: .systemBlue
        )
        let autoLockRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Automatic Lock"),
            subtitle: pasteraPreferenceString("Lock after the selected period of inactivity."),
            control: autoLockPopup,
            minimumHeight: 58
        )
        let quickUnlockRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Quick Unlock"),
            subtitle: pasteraPreferenceString("Use this Mac's authentication instead of entering the master password."),
            control: quickUnlockSwitch,
            minimumHeight: 58
        )
        lockingGroup.addRow(autoLockRow)
        lockingGroup.addRow(quickUnlockRow)
        lockingGroup.addContent(stateDetailLabel)
        stateDetailLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
        stateDetailLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true

        let feedback = NSStackView(views: [feedbackIcon, feedbackLabel])
        feedback.orientation = .horizontal
        feedback.alignment = .top
        feedback.spacing = 6
        feedback.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 10, right: 14)
        feedback.isHidden = true
        feedback.setAccessibilityIdentifier("vault.feedback")
        lockingGroup.addContent(feedback)

        addGroup(lockingGroup, weight: Layout.lockingWeight)
        registerAnchor("vault.autoLock", view: autoLockRow)
        registerAnchor("vault.quickUnlock", view: quickUnlockRow)

        let masterPasswordGroup = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Master Password"),
            symbolName: "key.fill",
            accentColor: .systemOrange
        )
        let warning = PasteraPreferenceStatusView(
            text: pasteraPreferenceString(
                "The master password encrypts your password vault. If forgotten, it cannot be recovered by any other means."
            ),
            style: .warning
        )
        warning.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        warning.setAccessibilityIdentifier("vault.masterPassword.warning")
        masterPasswordGroup.addContent(warning)

        let actions = NSStackView(views: [setupButton, changeMasterPasswordButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 11, right: 14)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.insertArrangedSubview(spacer, at: 0)
        masterPasswordGroup.addContent(actions)

        addGroup(masterPasswordGroup, weight: Layout.masterPasswordWeight)
        registerAnchor("vault.masterPassword", view: masterPasswordGroup)
    }

    private func installStateObserver() {
        guard stateObserverToken == nil else { return }
        stateObserverToken = passwordVaultController.addStateChangeObserver { [weak self] in
            self?.refreshSecuritySettings()
        }
    }

    private func removeStateObserver() {
        guard let stateObserverToken else { return }
        passwordVaultController.removeStateChangeObserver(stateObserverToken)
        self.stateObserverToken = nil
    }

    private func refreshSecuritySettings() {
        passwordVaultController.loadSecuritySettings { [weak self] state in
            self?.apply(state)
        }
    }

    private func apply(_ state: PasswordVaultSecuritySettingsState) {
        latestState = state
        if let item = autoLockPopup.itemArray.first(where: { TimeInterval($0.tag) == state.autoLockInterval }) {
            autoLockPopup.select(item)
        }
        quickUnlockSwitch.state = state.quickUnlockEnabled ? .on : .off

        let isConfigured: Bool
        let allowsGeneralSettings: Bool
        let allowsMasterPasswordChange: Bool
        let status: (String, String, NSColor)
        let detail: String

        if state.isBusy || state.vaultState == .unlocking {
            isConfigured = true
            allowsGeneralSettings = false
            allowsMasterPasswordChange = false
            status = (pasteraPreferenceString("Processing"), "hourglass", .secondaryLabelColor)
            detail = pasteraPreferenceString("A password vault security operation is in progress.")
        } else {
            switch state.vaultState {
            case .notConfigured:
                isConfigured = false
                allowsGeneralSettings = false
                allowsMasterPasswordChange = false
                status = (pasteraPreferenceString("Not Set Up"), "circle.dashed", .secondaryLabelColor)
                detail = pasteraPreferenceString("Set up the password vault from the main menu before configuring security options.")
            case .locked:
                isConfigured = true
                allowsGeneralSettings = true
                allowsMasterPasswordChange = true
                status = (pasteraPreferenceString("Locked"), "lock.fill", .secondaryLabelColor)
                detail = state.quickUnlockEnabled
                    ? pasteraPreferenceString("The vault is locked. Quick unlock remains available on this Mac.")
                    : pasteraPreferenceString("Unlock the vault from the main menu before enabling quick unlock.")
            case .unlocked:
                isConfigured = true
                allowsGeneralSettings = true
                allowsMasterPasswordChange = true
                status = (pasteraPreferenceString("Unlocked"), "lock.open.fill", .systemGreen)
                detail = state.quickUnlockAvailable
                    ? pasteraPreferenceString("Quick unlock is ready on this Mac.")
                    : pasteraPreferenceString("Enable quick unlock to use this Mac's authentication next time.")
            case let .readOnlyWarning(message):
                isConfigured = true
                allowsGeneralSettings = true
                allowsMasterPasswordChange = false
                status = (pasteraPreferenceString("Read Only"), "exclamationmark.triangle.fill", .systemOrange)
                detail = message.isEmpty
                    ? pasteraPreferenceString("Resolve the sync or file access issue before changing the master password.")
                    : message
            case let .failed(message):
                isConfigured = true
                allowsGeneralSettings = false
                allowsMasterPasswordChange = false
                status = (pasteraPreferenceString("Unavailable"), "xmark.octagon.fill", .systemRed)
                detail = message.isEmpty
                    ? pasteraPreferenceString("Restore access to the password vault file before changing security settings.")
                    : message
            case .unlocking:
                isConfigured = true
                allowsGeneralSettings = false
                allowsMasterPasswordChange = false
                status = (pasteraPreferenceString("Processing"), "hourglass", .secondaryLabelColor)
                detail = pasteraPreferenceString("A password vault security operation is in progress.")
            }
        }

        statusBadge.update(text: status.0, symbolName: status.1, color: status.2)
        stateDetailLabel.stringValue = detail
        autoLockPopup.isEnabled = allowsGeneralSettings
        quickUnlockSwitch.isEnabled = allowsGeneralSettings
        changeMasterPasswordButton.isEnabled = allowsMasterPasswordChange
        setupButton.isHidden = isConfigured
        changeMasterPasswordButton.isHidden = !isConfigured
        view.setAccessibilityValue(status.0)
        invalidateContentSize()
    }

    private func showFeedback(_ message: String, isError: Bool = true) {
        feedbackIcon.image = NSImage(
            systemSymbolName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            accessibilityDescription: nil
        )
        feedbackIcon.contentTintColor = isError ? .systemOrange : .systemGreen
        feedbackLabel.textColor = isError ? .systemOrange : .systemGreen
        feedbackLabel.stringValue = message
        feedbackLabel.superview?.isHidden = false
        feedbackLabel.superview?.setAccessibilityLabel(message)
        invalidateContentSize()
    }

    private func hideFeedback() {
        feedbackLabel.superview?.isHidden = true
        feedbackLabel.stringValue = ""
    }

    @objc private func autoLockIntervalChanged(_ sender: NSPopUpButton) {
        guard sender.selectedTag() > 0 else { return }
        hideFeedback()
        sender.isEnabled = false
        passwordVaultController.setAutoLockInterval(TimeInterval(sender.selectedTag())) { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                self.showFeedback(self.message(for: error))
            }
            self.refreshSecuritySettings()
        }
    }

    @objc private func quickUnlockChanged(_ sender: NSSwitch) {
        let requestedValue = sender.state == .on
        hideFeedback()
        sender.isEnabled = false
        passwordVaultController.setQuickUnlockEnabled(requestedValue) { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                if requestedValue, error == .vaultLocked {
                    self.showFeedback(
                        pasteraPreferenceString("Unlock the vault from the main menu before enabling quick unlock.")
                    )
                } else {
                    self.showFeedback(self.message(for: error))
                }
            }
            self.refreshSecuritySettings()
        }
    }

    @objc private func openPasswordVaultSetup(_ sender: Any?) {
        openPasswordVault()
    }

    @objc private func changeMasterPassword(_ sender: Any?) {
        guard let parentWindow = view.window else { return }
        let sheetController = PasswordVaultMasterPasswordSheetController(
            controller: passwordVaultController
        ) { [weak self] result in
            self?.handleMasterPasswordChangeSuccess(result)
        }
        masterPasswordSheetController = sheetController
        sheetController.beginSheet(for: parentWindow)
    }

    private func handleMasterPasswordChangeSuccess(_ result: PasswordVaultMasterPasswordChangeResult) {
        let warningMessages = result.warnings.compactMap { warning -> String? in
            switch warning {
            case .quickUnlockDisabled:
                return pasteraPreferenceString("Quick unlock was turned off. Unlock the vault and enable it again.")
            case .automationUnlockDisabled:
                return pasteraPreferenceString("Agent automatic unlock needs to be authorized again.")
            case .credentialCleanupFailed:
                return pasteraPreferenceString("An old unlock credential could not be removed. Review Keychain access.")
            case .conflictArchivePending:
                return pasteraPreferenceString("A resolved conflict archive still needs attention.")
            }
        }
        if warningMessages.isEmpty {
            showFeedback(pasteraPreferenceString("Master password changed."), isError: false)
        } else {
            showFeedback(
                ([pasteraPreferenceString("Master password changed.")] + warningMessages).joined(separator: " ")
            )
        }
        masterPasswordSheetController = nil
        refreshSecuritySettings()
    }

    private func message(for error: PasswordVaultError) -> String {
        switch error {
        case .vaultLocked:
            return pasteraPreferenceString("Unlock the password vault and try again.")
        case .keychainUnavailable:
            return pasteraPreferenceString("This Mac could not update quick unlock. Try again after unlocking the vault.")
        case .cloudUnavailable, .externalConflict:
            return pasteraPreferenceString("Resolve the sync conflict, then try again.")
        case .saveFailed:
            return pasteraPreferenceString("The password vault file could not be saved. Check file access and try again.")
        default:
            return pasteraPreferenceString("The security setting could not be updated. Please try again.")
        }
    }
}

private final class PasteraVaultStatusBadge: NSView {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.065).cgColor

        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 22)
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier("vault.status.badge")
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(text: String, symbolName: String, color: NSColor) {
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        imageView.contentTintColor = color
        label.stringValue = text
        label.textColor = color
        setAccessibilityLabel(text)
    }
}
