// Copyright 2026 Feeyo

import AppKit

final class PasswordVaultResetSheetWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

final class PasswordVaultKeyViewButton: NSButton {
    override var canBecomeKeyView: Bool { true }
}

final class PasswordVaultPasswordInputView: NSView, NSTextFieldDelegate {
    let secureField = NSSecureTextField()
    let visibleField = NSTextField()
    let visibilityButton = NSButton()
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    let label: NSTextField
    let accessibilityIdentifier: String
    var onChange: (() -> Void)?

    private(set) var isPasswordVisible = false

    init(labelText: String, accessibilityIdentifier: String) {
        label = NSTextField(labelWithString: labelText)
        self.accessibilityIdentifier = accessibilityIdentifier
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var value: String {
        get { isPasswordVisible ? visibleField.stringValue : secureField.stringValue }
        set {
            secureField.stringValue = newValue
            visibleField.stringValue = newValue
        }
    }

    var activeField: NSTextField { isPasswordVisible ? visibleField : secureField }

    func setEnabled(_ enabled: Bool) {
        secureField.isEnabled = enabled
        visibleField.isEnabled = enabled
        visibilityButton.isEnabled = enabled
    }

    func setError(_ message: String?) {
        errorLabel.stringValue = message ?? ""
        errorLabel.isHidden = message?.isEmpty != false
        errorLabel.setAccessibilityLabel(message)
    }

    func clear() {
        value = ""
        setError(nil)
    }

    func toggleVisibility() {
        guard let window else { return }
        let priorField = activeField
        let editor = priorField.currentEditor()
        let wasFocused = window.firstResponder === priorField || window.firstResponder === editor
        let selectedRange = (editor as? NSTextView)?.selectedRange()
        let currentValue = value

        isPasswordVisible.toggle()
        secureField.stringValue = currentValue
        visibleField.stringValue = currentValue
        secureField.isHidden = isPasswordVisible
        visibleField.isHidden = !isPasswordVisible
        visibilityButton.image = NSImage(
            systemSymbolName: isPasswordVisible ? "eye.slash" : "eye",
            accessibilityDescription: nil
        )
        visibilityButton.setAccessibilityLabel(String(localized:
            isPasswordVisible ? "Hide Password" : "Show Password"
        ))

        window.makeFirstResponder(activeField)
        if wasFocused,
           let selectedRange,
           let newEditor = window.fieldEditor(false, for: activeField) as? NSTextView {
            newEditor.setSelectedRange(selectedRange)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        let currentValue = value
        secureField.stringValue = currentValue
        visibleField.stringValue = currentValue
        onChange?()
    }

    private func configure() {
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor

        [secureField, visibleField].forEach { field in
            field.font = .systemFont(ofSize: 13)
            field.bezelStyle = .roundedBezel
            field.delegate = self
            field.setAccessibilityLabel(label.stringValue)
        }
        secureField.setAccessibilityIdentifier(accessibilityIdentifier)
        visibleField.setAccessibilityIdentifier(accessibilityIdentifier)
        visibleField.isHidden = true

        visibilityButton.isBordered = false
        visibilityButton.bezelStyle = .inline
        visibilityButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        visibilityButton.setAccessibilityLabel(String(localized: "Show Password"))

        errorLabel.font = .systemFont(ofSize: 11.5)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true

        let fieldContainer = NSView()
        secureField.translatesAutoresizingMaskIntoConstraints = false
        visibleField.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.addSubview(secureField)
        fieldContainer.addSubview(visibleField)
        NSLayoutConstraint.activate([
            secureField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor),
            secureField.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            secureField.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            visibleField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor),
            visibleField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor),
            visibleField.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            visibleField.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            fieldContainer.heightAnchor.constraint(equalToConstant: 28)
        ])

        let fieldRow = NSStackView(views: [fieldContainer, visibilityButton])
        fieldRow.orientation = .horizontal
        fieldRow.alignment = .centerY
        fieldRow.spacing = 8
        visibilityButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        visibilityButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let stack = NSStackView(views: [label, fieldRow, errorLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            fieldRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }
}

final class PasswordVaultMasterPasswordSheetController: NSWindowController, NSWindowDelegate {
    typealias ResetPassword = (
        String,
        @escaping (Result<PasswordVaultMasterPasswordResetResult, PasswordVaultError>) -> Void
    ) -> Void

    private enum Text {
        static let title = String(localized: "Reset Master Password")
        static let subtitle = String(localized:
            "Pastera will use this Mac's authentication, then preserve your folders and entries while resetting the master password."
        )
        static let recoveryWarning = String(localized:
            "The new master password encrypts your password vault. If forgotten, it cannot be recovered by any other means."
        )
        static let forcedResetExplanation = String(localized:
            "No usable unlock key is available, so Pastera cannot preserve the existing password vault. Review forced reset to create a new empty vault."
        )
    }

    private let resetPasswordOperation: ResetPassword
    private let onSuccess: (PasswordVaultMasterPasswordResetResult) -> Void
    private let onReviewForceReset: () -> Void
    private let newInput = PasswordVaultPasswordInputView(
        labelText: String(localized: "New Master Password"),
        accessibilityIdentifier: "masterPassword.new"
    )
    private let confirmationInput = PasswordVaultPasswordInputView(
        labelText: String(localized: "Confirm New Master Password"),
        accessibilityIdentifier: "masterPassword.confirmation"
    )
    private let recoveryWarningLabel = NSTextField(wrappingLabelWithString: Text.recoveryWarning)
    private let generalErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let forceResetExplanationLabel = NSTextField(wrappingLabelWithString: Text.forcedResetExplanation)
    private let reviewForceResetButton = NSButton(
        title: String(localized: "Review Force Reset..."),
        target: nil,
        action: nil
    )
    private let cancelButton = PasswordVaultKeyViewButton(
        title: String(localized: "Cancel"), target: nil, action: nil
    )
    private let submitButton = PasswordVaultKeyViewButton(
        title: String(localized: "Authenticate & Reset"),
        target: nil,
        action: nil
    )
    private let forceResetRecoveryPanel = NSStackView()
    private weak var parentWindow: NSWindow?
    private weak var priorFirstResponder: NSResponder?
    private(set) var isBusy = false
    private(set) var didCancel = false

    init(
        resetPassword: @escaping ResetPassword,
        onSuccess: @escaping (PasswordVaultMasterPasswordResetResult) -> Void = { _ in },
        onReviewForceReset: @escaping () -> Void = {}
    ) {
        resetPasswordOperation = resetPassword
        self.onSuccess = onSuccess
        self.onReviewForceReset = onReviewForceReset
        let window = PasswordVaultResetSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow(window)
        buildContent(in: window)
        bindActions()
        updateValidationState()
    }

    convenience init(
        controller: PasswordVaultUIController,
        onSuccess: @escaping (PasswordVaultMasterPasswordResetResult) -> Void,
        onReviewForceReset: @escaping () -> Void = {}
    ) {
        self.init(
            resetPassword: { newPassword, completion in
                controller.resetMasterPassword(newPassword: newPassword, completion: completion)
            },
            onSuccess: onSuccess,
            onReviewForceReset: onReviewForceReset
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { clearSecrets() }

    func beginSheet(for parentWindow: NSWindow) {
        self.parentWindow = parentWindow
        priorFirstResponder = parentWindow.firstResponder
        didCancel = false
        parentWindow.beginSheet(window!)
        focusNewPassword()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isBusy else { return false }
        cancel()
        return false
    }

    func windowWillClose(_ notification: Notification) { clearSecrets() }
}

private extension PasswordVaultMasterPasswordSheetController {
    var inputs: [PasswordVaultPasswordInputView] { [newInput, confirmationInput] }

    func configureWindow(_ window: PasswordVaultResetSheetWindow) {
        window.title = Text.title
        window.contentMinSize = NSSize(width: 360, height: 390)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onEscape = { [weak self] in self?.cancel() }
    }

    func buildContent(in window: NSWindow) {
        let contentView = PasteraPreferenceFlippedView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: Text.title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleLabel = NSTextField(wrappingLabelWithString: Text.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 3

        let warningIcon = NSImageView(image: NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        warningIcon.contentTintColor = .systemOrange
        warningIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        recoveryWarningLabel.font = .systemFont(ofSize: 11.5)
        recoveryWarningLabel.textColor = .secondaryLabelColor
        recoveryWarningLabel.maximumNumberOfLines = 3
        let warningRow = NSStackView(views: [warningIcon, recoveryWarningLabel])
        warningRow.orientation = .horizontal
        warningRow.alignment = .top
        warningRow.spacing = 7
        warningRow.setAccessibilityLabel(recoveryWarningLabel.stringValue)
        warningRow.setAccessibilityIdentifier("masterPassword.recoveryWarning")

        configureForceResetRecoveryPanel()

        generalErrorLabel.font = .systemFont(ofSize: 11.5)
        generalErrorLabel.textColor = .systemRed
        generalErrorLabel.maximumNumberOfLines = 3
        generalErrorLabel.isHidden = true
        generalErrorLabel.setAccessibilityIdentifier("masterPassword.generalError")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [spacer, cancelButton, submitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let stack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            warningRow,
            newInput,
            confirmationInput,
            forceResetRecoveryPanel,
            generalErrorLabel,
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.setCustomSpacing(6, after: titleLabel)
        stack.setCustomSpacing(16, after: warningRow)
        stack.setCustomSpacing(16, after: confirmationInput)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
            subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            warningRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recoveryWarningLabel.widthAnchor.constraint(lessThanOrEqualTo: warningRow.widthAnchor, constant: -24),
            newInput.widthAnchor.constraint(equalTo: stack.widthAnchor),
            confirmationInput.widthAnchor.constraint(equalTo: stack.widthAnchor),
            forceResetRecoveryPanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            generalErrorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func configureForceResetRecoveryPanel() {
        forceResetExplanationLabel.font = .systemFont(ofSize: 11.5)
        forceResetExplanationLabel.textColor = .secondaryLabelColor
        forceResetExplanationLabel.maximumNumberOfLines = 3
        reviewForceResetButton.bezelStyle = .rounded
        reviewForceResetButton.contentTintColor = .systemRed
        reviewForceResetButton.setAccessibilityIdentifier("masterPassword.reviewForceReset")
        forceResetRecoveryPanel.setViews([forceResetExplanationLabel, reviewForceResetButton], in: .top)
        forceResetRecoveryPanel.orientation = .horizontal
        forceResetRecoveryPanel.alignment = .top
        forceResetRecoveryPanel.spacing = 10
        forceResetRecoveryPanel.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        forceResetRecoveryPanel.wantsLayer = true
        forceResetRecoveryPanel.layer?.cornerRadius = 8
        forceResetRecoveryPanel.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.10).cgColor
        forceResetRecoveryPanel.setAccessibilityIdentifier("masterPassword.forceResetRecovery")
        forceResetRecoveryPanel.isHidden = true
        reviewForceResetButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    func bindActions() {
        inputs.forEach { input in
            input.onChange = { [weak self] in self?.inputDidChange() }
            input.visibilityButton.target = self
        }
        newInput.visibilityButton.action = #selector(toggleNewVisibility(_:))
        confirmationInput.visibilityButton.action = #selector(toggleConfirmationVisibility(_:))
        inputs.flatMap { [$0.secureField, $0.visibleField] }.forEach { field in
            field.target = self
            field.action = #selector(submit(_:))
        }
        reviewForceResetButton.target = self
        reviewForceResetButton.action = #selector(reviewForceReset(_:))
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked(_:))
        cancelButton.refusesFirstResponder = false
        cancelButton.setAccessibilityIdentifier("masterPassword.cancel")
        submitButton.target = self
        submitButton.action = #selector(submit(_:))
        submitButton.refusesFirstResponder = false
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded
        submitButton.setAccessibilityIdentifier("masterPassword.submit")
        installKeyViewLoop()
    }

    func installKeyViewLoop() {
        let confirmationField = confirmationInput.activeField
        newInput.secureField.nextKeyView = confirmationField
        newInput.visibleField.nextKeyView = confirmationField
        confirmationInput.secureField.nextKeyView = cancelButton
        confirmationInput.visibleField.nextKeyView = cancelButton
        cancelButton.nextKeyView = submitButton
        submitButton.nextKeyView = newInput.activeField
    }

    func inputDidChange() {
        inputs.forEach { $0.setError(nil) }
        setGeneralError(nil)
        forceResetRecoveryPanel.isHidden = true
        updateValidationState()
    }

    func updateValidationState() {
        submitButton.isEnabled = !isBusy && !newInput.value.isEmpty
            && newInput.value == confirmationInput.value
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        inputs.forEach { $0.setEnabled(!busy) }
        reviewForceResetButton.isEnabled = !busy
        cancelButton.isEnabled = !busy
        updateValidationState()
        submitButton.title = busy ? String(localized: "Resetting…") : String(localized: "Authenticate & Reset")
        window?.standardWindowButton(.closeButton)?.isEnabled = !busy
        window?.setAccessibilityValue(busy ? String(localized: "Processing") : nil)
    }

    func validateForSubmission() -> Bool {
        inputs.forEach { $0.setError(nil) }
        setGeneralError(nil)
        forceResetRecoveryPanel.isHidden = true
        if newInput.value.isEmpty {
            newInput.setError(String(localized: "Enter a new master password."))
            focusNewPassword()
            return false
        }
        if confirmationInput.value.isEmpty || confirmationInput.value != newInput.value {
            confirmationInput.setError(String(localized: "The new master passwords do not match."))
            window?.makeFirstResponder(confirmationInput.activeField)
            return false
        }
        return true
    }

    @objc func submit(_ sender: Any?) {
        guard !isBusy, validateForSubmission() else { return }
        let newPassword = newInput.value
        setBusy(true)
        resetPasswordOperation(newPassword) { [weak self] result in self?.finish(result) }
    }

    func finish(_ result: Result<PasswordVaultMasterPasswordResetResult, PasswordVaultError>) {
        setBusy(false)
        switch result {
        case let .success(resetResult):
            closeSheetAndClearSecrets()
            onSuccess(resetResult)
        case let .failure(error):
            handle(error)
        }
    }

    func handle(_ error: PasswordVaultError) {
        switch error {
        case .resetRequiresForcedReset:
            setGeneralError(nil)
            forceResetRecoveryPanel.isHidden = false
        case .invalidPassword:
            newInput.setError(String(localized: "Enter a new master password."))
            focusNewPassword()
        case .userCancelled:
            setGeneralError(String(localized:
                "Authentication was canceled. No password-vault data was changed."
            ))
        case .authenticationFailed:
            setGeneralError(String(localized:
                "This Mac could not authenticate the reset. No password-vault data was changed."
            ))
        case .externalConflict, .cloudUnavailable:
            setGeneralError(String(localized:
                "Resolve the sync conflict, then try again without closing this sheet."
            ))
        case .saveFailed:
            setGeneralError(String(localized:
                "Check access to the password vault file, then try again."
            ))
        case .recoveryRequired:
            setGeneralError(String(localized:
                "Close this window, open Password Vault settings, choose Retry Local Recovery, then try again."
            ))
        default:
            setGeneralError(String(localized: "The master password could not be reset. Please try again."))
        }
        updateValidationState()
    }

    func setGeneralError(_ message: String?) {
        generalErrorLabel.stringValue = message ?? ""
        generalErrorLabel.isHidden = message?.isEmpty != false
        generalErrorLabel.setAccessibilityLabel(message)
    }

    func focusNewPassword() { window?.makeFirstResponder(newInput.activeField) }

    @objc func reviewForceReset(_ sender: Any?) {
        guard !isBusy, !forceResetRecoveryPanel.isHidden else { return }
        closeSheetAndClearSecrets()
        onReviewForceReset()
    }

    @objc func cancelClicked(_ sender: Any?) { cancel() }

    func cancel() {
        guard !isBusy else { return }
        didCancel = true
        closeSheetAndClearSecrets()
    }

    func closeSheetAndClearSecrets() {
        guard let window else { return }
        if let parentWindow, window.sheetParent === parentWindow {
            parentWindow.endSheet(window)
            if let priorFirstResponder { parentWindow.makeFirstResponder(priorFirstResponder) }
        } else {
            window.orderOut(nil)
        }
        self.parentWindow = nil
        priorFirstResponder = nil
        clearSecrets()
    }

    func clearSecrets() { inputs.forEach { $0.clear() } }

    @objc func toggleNewVisibility(_ sender: Any?) {
        newInput.toggleVisibility()
        installKeyViewLoop()
    }

    @objc func toggleConfirmationVisibility(_ sender: Any?) {
        confirmationInput.toggleVisibility()
        installKeyViewLoop()
    }
}

#if DEBUG
extension PasswordVaultMasterPasswordSheetController {
    var secureFieldCountForTesting: Int { inputs.filter { !$0.isPasswordVisible }.count }
    var visiblePasswordFieldCountForTesting: Int { inputs.filter(\.isPasswordVisible).count }
    var fieldLabelsForTesting: [String] { inputs.map { $0.label.stringValue } }
    var inputAccessibilityIdentifiersForTesting: [String] { inputs.map(\.accessibilityIdentifier) }
    var recoveryWarningForTesting: String { recoveryWarningLabel.stringValue }
    var primaryButtonEnabledForTesting: Bool { submitButton.isEnabled }
    var confirmationErrorForTesting: String { confirmationInput.errorLabel.stringValue }
    var generalErrorForTesting: String { generalErrorLabel.stringValue }
    var forceResetExplanationVisibleForTesting: Bool { !forceResetRecoveryPanel.isHidden }
    var reviewForceResetTitleForTesting: String { reviewForceResetButton.title }
    var isBusyForTesting: Bool { isBusy }
    var didCancelForTesting: Bool { didCancel }
    var valuesForTesting: (new: String, confirmation: String) {
        (newInput.value, confirmationInput.value)
    }
    var keyViewOrderForTesting: [String] {
        var currentView: NSView? = newInput.activeField
        return (0..<4).map { _ in
            defer { currentView = currentView?.nextValidKeyView }
            return currentView?.accessibilityIdentifier() ?? "<missing>"
        }
    }
    var allInteractiveControlsDisabledForTesting: Bool {
        inputs.allSatisfy {
            !$0.secureField.isEnabled && !$0.visibleField.isEnabled && !$0.visibilityButton.isEnabled
        } && !cancelButton.isEnabled && !submitButton.isEnabled
    }
    var controlsFitBoundsForTesting: Bool {
        guard let contentView = window?.contentView else { return false }
        contentView.layoutSubtreeIfNeeded()
        let controls: [NSView] = inputs + [
            recoveryWarningLabel,
            forceResetRecoveryPanel,
            cancelButton,
            submitButton
        ]
        return controls.allSatisfy {
            let frame = contentView.convert($0.bounds, from: $0)
            return frame.minX >= -0.5 && frame.maxX <= contentView.bounds.maxX + 0.5
                && frame.minY >= -0.5 && frame.maxY <= contentView.bounds.maxY + 0.5
        }
    }
    var focusedFieldIdentifierForTesting: String? {
        guard let window else { return nil }
        for input in inputs {
            let field = input.activeField
            if window.firstResponder === field || window.firstResponder === field.currentEditor() {
                return input.accessibilityIdentifier
            }
        }
        return nil
    }

    func setValuesForTesting(new: String, confirmation: String) {
        newInput.value = new
        confirmationInput.value = confirmation
        inputDidChange()
    }

    func passwordIsVisibleForTesting(index: Int) -> Bool { inputs[index].isPasswordVisible }

    func focusFieldForTesting(index: Int) {
        window?.makeFirstResponder(nil)
        window?.makeFirstResponder(inputs[index].activeField)
    }

    func toggleVisibilityForTesting(index: Int) {
        if index == 0 {
            toggleNewVisibility(nil)
        } else {
            toggleConfirmationVisibility(nil)
        }
    }
    func submitForTesting() { submit(nil) }
    func cancelForTesting() { cancel() }
    func reviewForceResetForTesting() { reviewForceReset(nil) }
}
#endif
