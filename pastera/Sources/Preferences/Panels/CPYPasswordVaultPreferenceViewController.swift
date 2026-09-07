// Copyright 2026 Feeyo

import AppKit

// The page keeps its three stateful security groups and their test-only frame access together.
// swiftlint:disable type_body_length file_length
final class CPYPasswordVaultPreferenceViewController: PasteraPreferencePageViewController {
    private enum Layout {
        static let groupSpacing: CGFloat = 12
        static let actionInset: CGFloat = 14
    }

    private let passwordVaultController: PasswordVaultUIController
    private let openPasswordVault: () -> Void
    private let localizedString: (String) -> String
    private let resetPasswordOverride: PasswordVaultMasterPasswordSheetController.ResetPassword?
    private let forceResetPasswordOverride: PasswordVaultForceResetSheetController.ForceReset?
    private var stateObserverToken: UUID?
    private var masterPasswordSheetController: PasswordVaultMasterPasswordSheetController?
    private var forceResetSheetController: PasswordVaultForceResetSheetController?
    private var latestState: PasswordVaultSecuritySettingsState?

    private let statusBadge = PasteraVaultStatusBadge()
    private let autoLockPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let systemUnlockSwitch = NSSwitch()
    private let stateDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let statusFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let statusFeedbackIcon = NSImageView()
    private let masterFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let masterFeedbackIcon = NSImageView()
    private let forceFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let forceFeedbackIcon = NSImageView()
    private let retryFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let retryFeedbackIcon = NSImageView()
    private let localRecoveryFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let localRecoveryFeedbackIcon = NSImageView()
    private let pendingDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let setupButton = NSButton()
    private let resetMasterPasswordButton = NSButton()
    private let forceResetButton = PasteraDestructiveSecondaryButton()
    private let retryButton = NSButton()
    private let localRecoveryButton = NSButton()
    private let groupStack = NSStackView()
    private var vaultGroups = [PasteraPreferenceGroupView]()
    private var anchorViews = [String: NSView]()
    private var actionRows = [NSStackView]()
    private var statusFeedback: NSStackView?
    private var masterFeedback: NSStackView?
    private var forceFeedback: NSStackView?
    private var retryFeedback: NSStackView?
    private var pendingContent: NSStackView?
    private var localRecoveryContent: NSStackView?
    private var localRecoveryStatus: NSView?
    private var localRecoveryActionRow: NSStackView?
    private var localRecoveryFeedback: NSStackView?
    private var isRetryingForcedReset = false
    private var isRetryingLocalRecovery = false

    init(
        controller: PasswordVaultUIController = AppEnvironment.current.passwordVaultUIController,
        openPasswordVault: @escaping () -> Void = {
            AppEnvironment.current.menuManager.popUpMenu(.passwordVault)
        },
        localizedString: @escaping (String) -> String = { pasteraPreferenceString($0) },
        resetPassword: PasswordVaultMasterPasswordSheetController.ResetPassword? = nil,
        forceResetPassword: PasswordVaultForceResetSheetController.ForceReset? = nil
    ) {
        passwordVaultController = controller
        self.openPasswordVault = openPasswordVault
        self.localizedString = localizedString
        resetPasswordOverride = resetPassword
        forceResetPasswordOverride = forceResetPassword
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
            (localizedString("1 Minute"), 60),
            (localizedString("5 Minutes"), 300),
            (localizedString("15 Minutes"), 900),
            (localizedString("30 Minutes"), 1_800)
        ] {
            autoLockPopup.addItem(withTitle: title)
            autoLockPopup.lastItem?.tag = interval
        }
        autoLockPopup.target = self
        autoLockPopup.action = #selector(autoLockIntervalChanged(_:))
        autoLockPopup.setAccessibilityLabel(localizedString("Automatic Lock"))
        autoLockPopup.setAccessibilityIdentifier("vault.autoLock.control")

        systemUnlockSwitch.target = self
        systemUnlockSwitch.action = #selector(systemUnlockChanged(_:))
        systemUnlockSwitch.setAccessibilityLabel(localizedString("System Unlock"))
        systemUnlockSwitch.setAccessibilityIdentifier("vault.systemUnlock.control")

        stateDetailLabel.font = .systemFont(ofSize: 11.5)
        stateDetailLabel.textColor = .secondaryLabelColor
        stateDetailLabel.maximumNumberOfLines = 0
        stateDetailLabel.setAccessibilityIdentifier("vault.state.detail")

        for label in [
            statusFeedbackLabel,
            masterFeedbackLabel,
            forceFeedbackLabel,
            retryFeedbackLabel,
            localRecoveryFeedbackLabel,
            pendingDetailLabel
        ] {
            label.font = .systemFont(ofSize: 11.5)
            label.maximumNumberOfLines = 0
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for icon in [
            statusFeedbackIcon,
            masterFeedbackIcon,
            forceFeedbackIcon,
            retryFeedbackIcon,
            localRecoveryFeedbackIcon
        ] {
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        }

        setupButton.title = localizedString("Open Password Vault Setup")
        setupButton.target = self
        setupButton.action = #selector(openPasswordVaultSetup(_:))
        setupButton.bezelStyle = .rounded
        setupButton.setAccessibilityIdentifier("vault.setup.button")

        resetMasterPasswordButton.title = localizedString("Reset Master Password")
        resetMasterPasswordButton.target = self
        resetMasterPasswordButton.action = #selector(resetMasterPassword(_:))
        resetMasterPasswordButton.bezelStyle = .rounded
        resetMasterPasswordButton.keyEquivalent = "\r"
        resetMasterPasswordButton.setAccessibilityIdentifier("vault.masterPassword.button")

        forceResetButton.setDestructiveTitle(localizedString("Force Reset Password Vault"))
        forceResetButton.target = self
        forceResetButton.action = #selector(forceResetPasswordVault(_:))
        forceResetButton.bezelStyle = .rounded
        forceResetButton.hasDestructiveAction = true
        forceResetButton.setAccessibilityLabel(localizedString("Force Reset Password Vault"))
        forceResetButton.setAccessibilityIdentifier("vault.forceReset.button")

        retryButton.title = localizedString("Retry")
        retryButton.target = self
        retryButton.action = #selector(retryForcedReset(_:))
        retryButton.bezelStyle = .rounded
        retryButton.setAccessibilityIdentifier("vault.forceReset.retry")

        localRecoveryButton.title = localizedString("Retry Local Recovery")
        localRecoveryButton.target = self
        localRecoveryButton.action = #selector(retryLocalRecovery(_:))
        localRecoveryButton.bezelStyle = .rounded
        localRecoveryButton.setAccessibilityIdentifier("vault.localRecovery.retry")
    }

    private func buildHeader() {
        let subtitle = NSTextField(
            wrappingLabelWithString: localizedString("Manage password vault locking, unlocking, and master password.")
        )
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [subtitle])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        contentStack.insertArrangedSubview(header, at: 1)
        header.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(18, after: header)
    }

    private func buildGroups() {
        groupStack.arrangedSubviews.forEach {
            groupStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        vaultGroups.removeAll()
        anchorViews.removeAll()
        actionRows.removeAll()

        let statusGroup = PasteraPreferenceGroupView(
            title: localizedString("Vault Status"),
            symbolName: "lock.rotation",
            accentColor: .systemBlue
        )
        statusGroup.setHeaderAccessory(statusBadge)
        let autoLockRow = PasteraPreferenceSettingRowView(
            title: localizedString("Automatic Lock"),
            subtitle: localizedString("Lock after the selected period of inactivity."),
            control: autoLockPopup,
            minimumHeight: 58
        )
        let systemUnlockRow = PasteraPreferenceSettingRowView(
            title: localizedString("System Unlock"),
            subtitle: localizedString("Use Touch ID, Apple Watch, or the Mac login password to unlock on this Mac."),
            control: systemUnlockSwitch,
            minimumHeight: 58
        )
        statusGroup.addContent(insetContent(stateDetailLabel, top: 9, bottom: 10))
        statusGroup.addRow(autoLockRow)
        statusFeedback = makeFeedback(
            identifier: "vault.status.feedback",
            icon: statusFeedbackIcon,
            label: statusFeedbackLabel
        )
        statusGroup.addContent(makeFooter([systemUnlockRow, statusFeedback!]))

        let masterPasswordGroup = PasteraPreferenceGroupView(
            title: localizedString("Master Password"),
            symbolName: "key.fill",
            accentColor: .systemOrange
        )
        let warning = PasteraPreferenceStatusView(
            text: localizedString(
                "The master password encrypts your password vault. If forgotten, it cannot be recovered by any other means."
            ),
            style: .warning
        )
        warning.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        warning.setAccessibilityIdentifier("vault.masterPassword.warning")
        masterPasswordGroup.addContent(warning)

        masterFeedback = makeFeedback(identifier: "vault.masterPassword.feedback", icon: masterFeedbackIcon, label: masterFeedbackLabel)
        let masterActions = makeActionRow(buttons: [setupButton, resetMasterPasswordButton])
        masterPasswordGroup.addContent(makeFooter([masterActions, masterFeedback!]))

        let forceGroup = PasteraPreferenceGroupView(
            title: localizedString("Can't Unlock?"),
            symbolName: "exclamationmark.shield.fill",
            accentColor: .systemRed
        )
        let forceWarning = PasteraPreferenceStatusView(
            text: localizedString(
                "A forced reset creates a new empty password vault. Only the original master password can open the retained encrypted archive."
            ),
            style: .warning
        )
        forceWarning.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        forceWarning.setAccessibilityIdentifier("vault.forceReset.warning")
        forceGroup.addContent(forceWarning)

        localRecoveryContent = makeLocalRecoveryContent()
        pendingContent = makePendingContent()
        forceFeedback = makeFeedback(identifier: "vault.forceReset.feedback", icon: forceFeedbackIcon, label: forceFeedbackLabel)
        let forceActions = makeActionRow(buttons: [forceResetButton])
        forceGroup.addContent(makeFooter([
            localRecoveryContent!,
            pendingContent!,
            forceActions,
            forceFeedback!
        ]))

        vaultGroups = [statusGroup, masterPasswordGroup, forceGroup]
        groupStack.orientation = .vertical
        groupStack.alignment = .leading
        groupStack.spacing = Layout.groupSpacing
        vaultGroups.forEach {
            groupStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true
        }
        addAdaptiveContent(groupStack)

        for (anchor, view) in [
            ("vault.autoLock", autoLockRow),
            ("vault.systemUnlock", systemUnlockRow),
            ("vault.masterPassword", masterPasswordGroup),
            ("vault.forceReset", forceGroup)
        ] {
            registerAnchor(anchor, view: view)
            anchorViews[anchor] = view
        }
    }

    private func insetContent(_ view: NSView, top: CGFloat, bottom: CGFloat) -> NSStackView {
        let content = NSStackView(views: [view])
        content.orientation = .vertical
        content.edgeInsets = NSEdgeInsets(top: top, left: Layout.actionInset, bottom: bottom, right: Layout.actionInset)
        return content
    }

    private func makeFeedback(
        identifier: String,
        icon: NSImageView,
        label: NSTextField,
        edgeInsets: NSEdgeInsets = NSEdgeInsets(
            top: 9,
            left: Layout.actionInset,
            bottom: 10,
            right: Layout.actionInset
        )
    ) -> NSStackView {
        let feedback = NSStackView(views: [icon, label])
        feedback.orientation = .horizontal
        feedback.alignment = .top
        feedback.spacing = 6
        feedback.edgeInsets = edgeInsets
        feedback.isHidden = true
        feedback.setAccessibilityIdentifier(identifier)
        return feedback
    }

    private func makeActionRow(buttons: [NSButton]) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer] + buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(
            top: 10,
            left: Layout.actionInset,
            bottom: 11,
            right: Layout.actionInset
        )
        actionRows.append(row)
        return row
    }

    private func makeFooter(_ views: [NSView]) -> NSStackView {
        let footer = NSStackView(views: views)
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 0
        views.forEach { $0.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true }
        return footer
    }

    private func makePendingContent() -> NSStackView {
        let status = PasteraPreferenceStatusView(
            text: localizedString(
                "Password Vault sync is paused until Pastera archives and replaces the previous OneDrive vault."
            ),
            style: .warning
        )
        status.setAccessibilityIdentifier("vault.forceReset.pending")
        pendingDetailLabel.textColor = .systemOrange
        let retrySpacer = NSView()
        retrySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let retryRow = NSStackView(views: [retrySpacer, retryButton])
        retryRow.orientation = .horizontal
        retryRow.alignment = .centerY
        retryFeedback = makeFeedback(
            identifier: "vault.forceReset.retryFeedback",
            icon: retryFeedbackIcon,
            label: retryFeedbackLabel,
            edgeInsets: NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        )
        let content = NSStackView(views: [status, pendingDetailLabel, retryRow, retryFeedback!])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 7
        content.edgeInsets = NSEdgeInsets(top: 10, left: Layout.actionInset, bottom: 11, right: Layout.actionInset)
        content.isHidden = true
        return content
    }

    private func makeLocalRecoveryContent() -> NSStackView {
        let status = PasteraPreferenceStatusView(
            text: localizedString(
                "Finish local password vault recovery before changing security settings. OneDrive sync is paused, and the cloud vault will not be replaced."
            ),
            style: .warning
        )
        status.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        status.setAccessibilityIdentifier("vault.localRecovery.status")
        localRecoveryStatus = status

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actionRow = NSStackView(views: [spacer, localRecoveryButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.edgeInsets = NSEdgeInsets(
            top: 10,
            left: Layout.actionInset,
            bottom: 11,
            right: Layout.actionInset
        )
        localRecoveryActionRow = actionRow

        localRecoveryFeedback = makeFeedback(
            identifier: "vault.localRecovery.feedback",
            icon: localRecoveryFeedbackIcon,
            label: localRecoveryFeedbackLabel
        )
        let content = NSStackView(views: [status, actionRow, localRecoveryFeedback!])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        content.isHidden = true
        [status, actionRow, localRecoveryFeedback!].forEach {
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        return content
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
        systemUnlockSwitch.state = state.quickUnlockEnabled ? .on : .off

        let isConfigured: Bool
        let allowsGeneralSettings: Bool
        let allowsMasterPasswordChange: Bool
        let status: (String, String, NSColor)
        let detail: String

        let requiresLocalRecovery: Bool
        if case .recoveryRequired = state.vaultState {
            requiresLocalRecovery = true
        } else {
            requiresLocalRecovery = false
        }

        if !requiresLocalRecovery
            && (state.isBusy || state.vaultState == .unlocking || state.vaultState == .preparingLocalCopy) {
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
            case .preparingLocalCopy:
                isConfigured = true
                allowsGeneralSettings = false
                allowsMasterPasswordChange = false
                status = (pasteraPreferenceString("Processing"), "hourglass", .secondaryLabelColor)
                detail = pasteraPreferenceString("A password vault security operation is in progress.")
            case .localCopyUnavailable:
                isConfigured = true
                allowsGeneralSettings = false
                allowsMasterPasswordChange = false
                status = (pasteraPreferenceString("Unavailable"), "xmark.octagon.fill", .systemRed)
                detail = pasteraPreferenceString("Restore access to the password vault file before changing security settings.")
            case .locked:
                isConfigured = true
                allowsGeneralSettings = true
                allowsMasterPasswordChange = true
                status = (pasteraPreferenceString("Locked"), "lock.fill", .secondaryLabelColor)
                detail = state.quickUnlockEnabled
                    ? localizedString("The vault is locked. System Unlock remains available on this Mac.")
                    : localizedString("Unlock the vault from the main menu before enabling System Unlock.")
            case .unlocked:
                isConfigured = true
                allowsGeneralSettings = true
                allowsMasterPasswordChange = true
                status = (pasteraPreferenceString("Unlocked"), "lock.open.fill", .systemGreen)
                detail = state.quickUnlockAvailable
                    ? localizedString("System Unlock is ready on this Mac.")
                    : localizedString("Enable System Unlock to use this Mac's authentication next time.")
            case let .readOnlyWarning(message):
                isConfigured = true
                allowsGeneralSettings = true
                allowsMasterPasswordChange = false
                status = (pasteraPreferenceString("Read Only"), "exclamationmark.triangle.fill", .systemOrange)
                detail = message.isEmpty
                    ? pasteraPreferenceString("Resolve the sync or file access issue before changing the master password.")
                    : message
            case .recoveryRequired:
                isConfigured = true
                allowsGeneralSettings = false
                allowsMasterPasswordChange = false
                status = (localizedString("Recovery Needed"), "arrow.triangle.2.circlepath", .systemOrange)
                detail = localizedString(
                    "Finish local password vault recovery before changing security settings. OneDrive sync is paused, and the cloud vault will not be replaced."
                )
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
        systemUnlockSwitch.isEnabled = allowsGeneralSettings
        let resetActionsEnabled = allowsMasterPasswordChange
            && state.masterPasswordResetCapability != .unavailable
            && !state.forcedResetPending
            && !state.isBusy
        resetMasterPasswordButton.isEnabled = resetActionsEnabled
        forceResetButton.isEnabled = resetActionsEnabled
        setupButton.isHidden = isConfigured
        resetMasterPasswordButton.isHidden = !isConfigured
        localRecoveryStatus?.isHidden = !requiresLocalRecovery
        localRecoveryActionRow?.isHidden = !requiresLocalRecovery
        localRecoveryContent?.isHidden = !requiresLocalRecovery && localRecoveryFeedback?.isHidden != false
        localRecoveryButton.isEnabled = requiresLocalRecovery && !state.isBusy && !isRetryingLocalRecovery
        pendingContent?.isHidden = !state.forcedResetPending || requiresLocalRecovery
        retryButton.isEnabled = state.forcedResetPending
            && !requiresLocalRecovery
            && !state.isBusy
            && !isRetryingForcedReset
        if state.forcedResetPendingFailure == .remoteVerificationFailed {
            pendingDetailLabel.stringValue = localizedString(
                "OneDrive changed elsewhere. Retry will archive the latest remote encrypted vault before replacing the active vault."
            )
        } else {
            pendingDetailLabel.stringValue = ""
        }
        pendingDetailLabel.isHidden = pendingDetailLabel.stringValue.isEmpty
        if !state.forcedResetPending || requiresLocalRecovery {
            hideFeedback(retryFeedback, label: retryFeedbackLabel)
        }
        view.setAccessibilityValue(status.0)
        invalidateContentSize()
    }

    private func showFeedback(
        _ message: String,
        in feedback: NSStackView?,
        icon: NSImageView,
        label: NSTextField,
        isError: Bool = true
    ) {
        icon.image = NSImage(
            systemSymbolName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            accessibilityDescription: nil
        )
        icon.contentTintColor = isError ? .systemOrange : .systemGreen
        label.textColor = isError ? .systemOrange : .systemGreen
        label.stringValue = message
        feedback?.isHidden = false
        feedback?.setAccessibilityLabel(message)
        invalidateContentSize()
    }

    private func hideFeedback(_ feedback: NSStackView?, label: NSTextField) {
        feedback?.isHidden = true
        label.stringValue = ""
    }

    @objc private func autoLockIntervalChanged(_ sender: NSPopUpButton) {
        guard sender.selectedTag() > 0 else { return }
        hideFeedback(statusFeedback, label: statusFeedbackLabel)
        sender.isEnabled = false
        passwordVaultController.setAutoLockInterval(TimeInterval(sender.selectedTag())) { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                self.showStatusFeedback(self.message(for: error))
            }
            self.refreshSecuritySettings()
        }
    }

    @objc private func systemUnlockChanged(_ sender: NSSwitch) {
        let requestedValue = sender.state == .on
        hideFeedback(statusFeedback, label: statusFeedbackLabel)
        sender.isEnabled = false
        passwordVaultController.setQuickUnlockEnabled(requestedValue) { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                if requestedValue, error == .vaultLocked {
                    self.showStatusFeedback(
                        self.localizedString("Unlock the vault from the main menu before enabling System Unlock.")
                    )
                } else {
                    self.showStatusFeedback(self.message(for: error))
                }
            }
            self.refreshSecuritySettings()
        }
    }

    @objc private func openPasswordVaultSetup(_ sender: Any?) {
        openPasswordVault()
    }

    @objc private func resetMasterPassword(_ sender: Any?) {
        guard let parentWindow = view.window else { return }
        let onSuccess: (PasswordVaultMasterPasswordResetResult) -> Void = { [weak self] result in
            self?.handleMasterPasswordResetSuccess(result)
        }
        let onReview: () -> Void = { [weak self, weak parentWindow] in
            self?.masterPasswordSheetController = nil
            guard let parentWindow else { return }
            self?.presentForceResetSheet(for: parentWindow)
        }
        let sheetController = if let resetPasswordOverride {
            PasswordVaultMasterPasswordSheetController(
                resetPassword: resetPasswordOverride,
                onSuccess: onSuccess,
                onReviewForceReset: onReview
            )
        } else {
            PasswordVaultMasterPasswordSheetController(
                controller: passwordVaultController,
                onSuccess: onSuccess,
                onReviewForceReset: onReview
            )
        }
        masterPasswordSheetController = sheetController
        sheetController.beginSheet(for: parentWindow)
    }

    private func handleMasterPasswordResetSuccess(_ result: PasswordVaultMasterPasswordResetResult) {
        let warningMessages = result.warnings.compactMap { warning -> String? in
            switch warning {
            case .systemUnlockDisabled:
                return String(localized: "System unlock was turned off. Unlock the vault and enable it again.")
            case .automationUnlockDisabled:
                return pasteraPreferenceString("Agent automatic unlock needs to be authorized again.")
            case .credentialCleanupFailed:
                return pasteraPreferenceString("An old unlock credential could not be removed. Review Keychain access.")
            case .conflictArchivePending:
                return pasteraPreferenceString("A resolved conflict archive still needs attention.")
            case .rekeyArtifactCleanupPending:
                return pasteraPreferenceString("A secured password-change artifact is still pending cleanup.")
            }
        }
        if warningMessages.isEmpty {
            showMasterFeedback(
                String(localized: "Master password reset. Folders and entries were preserved."),
                isError: false
            )
        } else {
            showMasterFeedback(
                ([String(localized: "Master password reset. Folders and entries were preserved.")]
                    + warningMessages).joined(separator: " ")
            )
        }
        masterPasswordSheetController = nil
        refreshSecuritySettings()
    }

    @objc private func forceResetPasswordVault(_ sender: Any?) {
        guard let parentWindow = view.window else { return }
        presentForceResetSheet(for: parentWindow)
    }

    private func presentForceResetSheet(for parentWindow: NSWindow) {
        guard parentWindow.attachedSheet == nil else { return }
        let onSuccess: (PasswordVaultForcedResetOutcome) -> Void = { [weak self] outcome in
            self?.handleForcedResetSuccess(outcome)
        }
        let sheetController = if let forceResetPasswordOverride {
            PasswordVaultForceResetSheetController(
                forceReset: forceResetPasswordOverride,
                onSuccess: onSuccess
            )
        } else {
            PasswordVaultForceResetSheetController(
                controller: passwordVaultController,
                onSuccess: onSuccess
            )
        }
        forceResetSheetController = sheetController
        sheetController.beginSheet(for: parentWindow)
    }

    private func handleForcedResetSuccess(_ outcome: PasswordVaultForcedResetOutcome) {
        let baseMessage = outcome.oneDriveReplacementPending
            ? localizedString(
                "The new local password vault is empty and ready. One latest encrypted archive was retained. Password-vault sync is paused until Pastera can archive and replace the previous OneDrive vault. Agent access must be authorized again."
            )
            : localizedString(
                "The new empty password vault is ready. One latest encrypted archive was retained. Agent access must be authorized again."
            )
        let warningMessages = outcome.warnings.compactMap { warning -> String? in
            switch warning {
            case .systemUnlockDisabled:
                return localizedString("System unlock was turned off. Unlock the vault and enable it again.")
            case .credentialCleanupFailed:
                return localizedString("An old unlock credential could not be removed. Review Keychain access.")
            case .resetArtifactCleanupPending:
                return localizedString("A secured forced-reset artifact is still pending cleanup.")
            }
        }
        showForceFeedback(
            ([baseMessage] + warningMessages).joined(separator: " "),
            isError: !warningMessages.isEmpty
        )
        forceResetSheetController = nil
        refreshSecuritySettings()
    }

    @objc private func retryForcedReset(_ sender: Any?) {
        guard latestState?.forcedResetPending == true, !isRetryingForcedReset else { return }
        isRetryingForcedReset = true
        retryButton.isEnabled = false
        retryButton.title = localizedString("Retrying…")
        hideFeedback(retryFeedback, label: retryFeedbackLabel)
        passwordVaultController.retryForcedReset { [weak self] result in
            guard let self else { return }
            self.isRetryingForcedReset = false
            self.retryButton.title = self.localizedString("Retry")
            if case .failure = result {
                self.showRetryFeedback(
                    self.localizedString(
                        "Pastera could not retry the OneDrive replacement. Password Vault sync remains paused."
                    )
                )
            }
            self.refreshSecuritySettings()
        }
    }

    @objc private func retryLocalRecovery(_ sender: Any?) {
        guard let vaultState = latestState?.vaultState,
              case .recoveryRequired = vaultState,
              !isRetryingLocalRecovery else { return }
        isRetryingLocalRecovery = true
        localRecoveryButton.isEnabled = false
        localRecoveryButton.title = localizedString("Retrying…")
        hideFeedback(localRecoveryFeedback, label: localRecoveryFeedbackLabel)
        passwordVaultController.retryForcedResetRecovery { [weak self] result in
            guard let self else { return }
            self.isRetryingLocalRecovery = false
            self.localRecoveryButton.title = self.localizedString("Retry Local Recovery")
            switch result {
            case let .success(recovery):
                let message = switch recovery {
                case .rolledBack:
                    self.localizedString(
                        "Local recovery restored the previous password vault. Password Vault is ready to continue."
                    )
                case .committed:
                    self.localizedString(
                        "Local recovery kept the new password vault. Password Vault is ready to continue."
                    )
                }
                self.showLocalRecoveryFeedback(message, isError: false)
            case .failure:
                self.showLocalRecoveryFeedback(self.localizedString(
                    "Local recovery is not complete. OneDrive sync remains paused. You can safely try again."
                ))
            }
            self.refreshSecuritySettings()
        }
    }

    private func showMasterFeedback(_ message: String, isError: Bool = true) {
        showFeedback(message, in: masterFeedback, icon: masterFeedbackIcon, label: masterFeedbackLabel, isError: isError)
    }

    private func showStatusFeedback(_ message: String, isError: Bool = true) {
        showFeedback(message, in: statusFeedback, icon: statusFeedbackIcon, label: statusFeedbackLabel, isError: isError)
    }

    private func showForceFeedback(_ message: String, isError: Bool = true) {
        showFeedback(message, in: forceFeedback, icon: forceFeedbackIcon, label: forceFeedbackLabel, isError: isError)
    }

    private func showRetryFeedback(_ message: String, isError: Bool = true) {
        showFeedback(message, in: retryFeedback, icon: retryFeedbackIcon, label: retryFeedbackLabel, isError: isError)
    }

    private func showLocalRecoveryFeedback(_ message: String, isError: Bool = true) {
        showFeedback(
            message,
            in: localRecoveryFeedback,
            icon: localRecoveryFeedbackIcon,
            label: localRecoveryFeedbackLabel,
            isError: isError
        )
        localRecoveryContent?.isHidden = false
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
            return localizedString("The security setting could not be updated. Please try again.")
        default:
            return pasteraPreferenceString("The security setting could not be updated. Please try again.")
        }
    }
}

#if DEBUG
extension CPYPasswordVaultPreferenceViewController {
    var passwordVaultGroupFramesForTesting: [NSRect] {
        vaultGroups.map { $0.convert($0.bounds, to: view) }
    }

    var passwordVaultActionInsetsForTesting: [NSEdgeInsets] { actionRows.map(\.edgeInsets) }

    var passwordVaultActionRowFramesForTesting: [NSRect] {
        actionRows.map { $0.convert($0.bounds, to: view) }
    }

    var passwordVaultActionButtonFramesForTesting: [NSRect] {
        [resetMasterPasswordButton, forceResetButton].map { $0.convert($0.bounds, to: view) }
    }

    func passwordVaultAnchorFrameForTesting(_ anchorID: String) -> NSRect? {
        anchorViews[anchorID].map { $0.convert($0.bounds, to: view) }
    }

    var passwordVaultVisibleContentFramesForTesting: [NSRect] {
        vaultGroups.flatMap { group in
            group.contentStack.arrangedSubviews.filter { !$0.isHidden }.map { $0.convert($0.bounds, to: view) }
        }
    }

    var passwordVaultPendingRowVisibleForTesting: Bool { pendingContent?.isHidden == false }
    var passwordVaultFeedbackIdentifiersForTesting: [String] {
        [statusFeedback, masterFeedback, forceFeedback, retryFeedback].compactMap { $0?.accessibilityIdentifier() }
    }
    var passwordVaultRetryVisibleForTesting: Bool { retryButton.isHidden == false && pendingContent?.isHidden == false }
    var passwordVaultResetActionsEnabledForTesting: Bool {
        resetMasterPasswordButton.isEnabled || forceResetButton.isEnabled
    }
    var passwordVaultPendingDetailForTesting: String { pendingDetailLabel.stringValue }
    var passwordVaultMasterFeedbackVisibleForTesting: Bool { masterFeedback?.isHidden == false }
    var passwordVaultForceFeedbackVisibleForTesting: Bool { forceFeedback?.isHidden == false }
    var passwordVaultHiddenOptionalRowsAreCollapsedForTesting: Bool {
        [statusFeedback, masterFeedback, forceFeedback, retryFeedback, localRecoveryFeedback]
            .compactMap { $0 }.allSatisfy {
            $0.isHidden
        }
    }

    func applySecurityStateForTesting(_ state: PasswordVaultSecuritySettingsState) {
        apply(state)
    }

    func openResetSheetForTesting() { resetMasterPassword(nil) }
    func openForceResetSheetForTesting() { forceResetPasswordVault(nil) }
    var resetSheetForTesting: PasswordVaultMasterPasswordSheetController? { masterPasswordSheetController }
    var forceSheetForTesting: PasswordVaultForceResetSheetController? { forceResetSheetController }
}
#endif

private final class PasteraDestructiveSecondaryButton: NSButton {
    private var destructiveTitle = ""

    override var isEnabled: Bool {
        didSet { updateDestructiveAppearance() }
    }

    func setDestructiveTitle(_ title: String) {
        destructiveTitle = title
        image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        imagePosition = .imageLeading
        imageHugsTitle = true
        wantsLayer = true
        layer?.cornerRadius = 6
        updateDestructiveAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDestructiveAppearance()
    }

    private func updateDestructiveAppearance() {
        guard !destructiveTitle.isEmpty else { return }
        let foregroundColor: NSColor = isEnabled ? .systemRed : .disabledControlTextColor
        attributedTitle = NSAttributedString(
            string: destructiveTitle,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: foregroundColor
            ]
        )
        contentTintColor = foregroundColor
        layer?.borderColor = foregroundColor.withAlphaComponent(isEnabled ? 0.55 : 0.22).cgColor
        layer?.borderWidth = 1
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
