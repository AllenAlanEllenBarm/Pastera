// Copyright 2026 Feeyo

import AppKit

final class PasswordVaultForceResetSheetController: NSWindowController, NSWindowDelegate {
    typealias ForceReset = (
        String,
        @escaping (Result<PasswordVaultForcedResetOutcome, PasswordVaultError>) -> Void
    ) -> Void

    private enum Text {
        static let titleKey = "Force Reset Password Vault"
        static let limitationKey = "No usable unlock key is available. Because the existing password vault is encrypted, Pastera cannot decrypt or recover it. Continuing will preserve one latest encrypted archive and create a new empty password vault. Only the original master password can open the archive."
        static let archiveReplacementKey = "The next forced reset will replace the currently saved encrypted archive."
        static let acknowledgementKey = "I understand that my old entries will not appear in the new password vault."

        static let title = String(localized: "Force Reset Password Vault")
        static let limitation = String(localized:
            "No usable unlock key is available. Because the existing password vault is encrypted, Pastera cannot decrypt or recover it. Continuing will preserve one latest encrypted archive and create a new empty password vault. Only the original master password can open the archive."
        )
        static let archiveReplacement = String(localized:
            "The next forced reset will replace the currently saved encrypted archive."
        )
        static let acknowledgement = String(localized:
            "I understand that my old entries will not appear in the new password vault."
        )
    }

    private let forceResetOperation: ForceReset
    private let onSuccess: (PasswordVaultForcedResetOutcome) -> Void
    private let warningStatusView = NSStackView()
    private let limitationLabel = NSTextField(wrappingLabelWithString: Text.limitation)
    private let archiveReplacementLabel = NSTextField(wrappingLabelWithString: Text.archiveReplacement)
    private let newInput = PasswordVaultPasswordInputView(
        labelText: String(localized: "New Master Password"),
        accessibilityIdentifier: "forceReset.new"
    )
    private let confirmationInput = PasswordVaultPasswordInputView(
        labelText: String(localized: "Confirm New Master Password"),
        accessibilityIdentifier: "forceReset.confirmation"
    )
    private let acknowledgementButton = PasswordVaultKeyViewButton(
        checkboxWithTitle: Text.acknowledgement,
        target: nil,
        action: nil
    )
    private let generalErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = PasswordVaultKeyViewButton(
        title: String(localized: "Cancel"), target: nil, action: nil
    )
    private let submitButton = PasswordVaultKeyViewButton(title: Text.title, target: nil, action: nil)
    private weak var parentWindow: NSWindow?
    private weak var priorFirstResponder: NSResponder?
    private(set) var isBusy = false
    private(set) var didCancel = false

    init(
        forceReset: @escaping ForceReset,
        onSuccess: @escaping (PasswordVaultForcedResetOutcome) -> Void = { _ in }
    ) {
        forceResetOperation = forceReset
        self.onSuccess = onSuccess
        let window = PasswordVaultResetSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
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
        onSuccess: @escaping (PasswordVaultForcedResetOutcome) -> Void
    ) {
        self.init(
            forceReset: { newPassword, completion in
                controller.forceResetPasswordVault(newPassword: newPassword, completion: completion)
            },
            onSuccess: onSuccess
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

private extension PasswordVaultForceResetSheetController {
    var inputs: [PasswordVaultPasswordInputView] { [newInput, confirmationInput] }

    func configureWindow(_ window: PasswordVaultResetSheetWindow) {
        window.title = Text.title
        window.contentMinSize = NSSize(width: 360, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onEscape = { [weak self] in self?.cancel() }
    }

    func buildContent(in window: NSWindow) {
        let contentView = PasteraPreferenceFlippedView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: Text.title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleLabel = NSTextField(wrappingLabelWithString: String(localized:
            "Review the encrypted-data limitation, then choose a password for the new empty vault. This attempt uses this Mac's authentication."
        ))
        subtitleLabel.font = .systemFont(ofSize: 12.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 3

        configureWarningStatusView()
        archiveReplacementLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        archiveReplacementLabel.textColor = .systemOrange
        archiveReplacementLabel.maximumNumberOfLines = 2
        archiveReplacementLabel.setAccessibilityIdentifier("forceReset.archiveReplacementWarning")

        acknowledgementButton.allowsMixedState = false
        acknowledgementButton.lineBreakMode = .byWordWrapping
        acknowledgementButton.setAccessibilityIdentifier("forceReset.acknowledgement")
        acknowledgementButton.setAccessibilityLabel(Text.acknowledgement)

        generalErrorLabel.font = .systemFont(ofSize: 11.5)
        generalErrorLabel.textColor = .systemRed
        generalErrorLabel.maximumNumberOfLines = 3
        generalErrorLabel.isHidden = true
        generalErrorLabel.setAccessibilityIdentifier("forceReset.generalError")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [spacer, cancelButton, submitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let stack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            warningStatusView,
            archiveReplacementLabel,
            newInput,
            confirmationInput,
            acknowledgementButton,
            generalErrorLabel,
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.setCustomSpacing(6, after: titleLabel)
        stack.setCustomSpacing(8, after: warningStatusView)
        stack.setCustomSpacing(15, after: archiveReplacementLabel)
        stack.setCustomSpacing(14, after: confirmationInput)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
            subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            warningStatusView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            archiveReplacementLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            newInput.widthAnchor.constraint(equalTo: stack.widthAnchor),
            confirmationInput.widthAnchor.constraint(equalTo: stack.widthAnchor),
            acknowledgementButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            generalErrorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func configureWarningStatusView() {
        let icon = NSImageView(image: NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = .systemRed
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        limitationLabel.font = .systemFont(ofSize: 11.5)
        limitationLabel.textColor = .labelColor
        limitationLabel.maximumNumberOfLines = 7
        warningStatusView.setViews([icon, limitationLabel], in: .top)
        warningStatusView.orientation = .horizontal
        warningStatusView.alignment = .top
        warningStatusView.spacing = 9
        warningStatusView.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        warningStatusView.wantsLayer = true
        warningStatusView.layer?.cornerRadius = 8
        warningStatusView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.09).cgColor
        warningStatusView.setAccessibilityRole(.group)
        warningStatusView.setAccessibilityIdentifier("forceReset.warning")
        warningStatusView.setAccessibilityLabel(Text.limitation)
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
        acknowledgementButton.target = self
        acknowledgementButton.action = #selector(acknowledgementChanged(_:))
        acknowledgementButton.refusesFirstResponder = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked(_:))
        cancelButton.refusesFirstResponder = false
        cancelButton.setAccessibilityIdentifier("forceReset.cancel")
        submitButton.target = self
        submitButton.action = #selector(submit(_:))
        submitButton.refusesFirstResponder = false
        submitButton.bezelStyle = .rounded
        submitButton.contentTintColor = .systemRed
        submitButton.setAccessibilityRole(.button)
        submitButton.setAccessibilityIdentifier("forceReset.submit")
        submitButton.setAccessibilityLabel(Text.title)
        installKeyViewLoop()
    }

    func installKeyViewLoop() {
        let confirmationField = confirmationInput.activeField
        newInput.secureField.nextKeyView = confirmationField
        newInput.visibleField.nextKeyView = confirmationField
        confirmationInput.secureField.nextKeyView = acknowledgementButton
        confirmationInput.visibleField.nextKeyView = acknowledgementButton
        acknowledgementButton.nextKeyView = cancelButton
        cancelButton.nextKeyView = submitButton
        submitButton.nextKeyView = newInput.activeField
    }

    func inputDidChange() {
        inputs.forEach { $0.setError(nil) }
        setGeneralError(nil)
        updateValidationState()
    }

    @objc func acknowledgementChanged(_ sender: Any?) {
        setGeneralError(nil)
        updateValidationState()
    }

    func updateValidationState() {
        let canSubmit = !isBusy
            && !newInput.value.isEmpty
            && newInput.value == confirmationInput.value
            && acknowledgementButton.state == .on
        submitButton.isEnabled = canSubmit
        submitButton.keyEquivalent = canSubmit ? "\r" : ""
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        inputs.forEach { $0.setEnabled(!busy) }
        acknowledgementButton.isEnabled = !busy
        cancelButton.isEnabled = !busy
        updateValidationState()
        submitButton.title = busy ? String(localized: "Resetting…") : Text.title
        window?.standardWindowButton(.closeButton)?.isEnabled = !busy
        window?.setAccessibilityValue(busy ? String(localized: "Processing") : nil)
    }

    func validateForSubmission() -> Bool {
        inputs.forEach { $0.setError(nil) }
        setGeneralError(nil)
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
        guard acknowledgementButton.state == .on else {
            setGeneralError(String(localized: "Confirm that the old entries will not appear in the new password vault."))
            window?.makeFirstResponder(acknowledgementButton)
            return false
        }
        return true
    }

    @objc func submit(_ sender: Any?) {
        guard !isBusy, validateForSubmission() else { return }
        let newPassword = newInput.value
        setBusy(true)
        forceResetOperation(newPassword) { [weak self] result in self?.finish(result) }
    }

    func finish(_ result: Result<PasswordVaultForcedResetOutcome, PasswordVaultError>) {
        setBusy(false)
        switch result {
        case let .success(outcome):
            closeSheetAndClearSecrets()
            onSuccess(outcome)
        case let .failure(error):
            handle(error)
        }
    }

    func handle(_ error: PasswordVaultError) {
        switch error {
        case .invalidPassword:
            newInput.setError(String(localized: "Enter a new master password."))
            focusNewPassword()
        case .userCancelled:
            setGeneralError(String(localized:
                "Authentication was canceled. The existing password vault was not changed."
            ))
        case .authenticationFailed:
            setGeneralError(String(localized:
                "This Mac could not authenticate the forced reset. The existing password vault was not changed."
            ))
        case .cloudUnavailable:
            setGeneralError(String(localized:
                "Pastera could not prepare the OneDrive replacement. The existing password vault was not changed."
            ))
        case .recoveryRequired:
            setGeneralError(String(localized:
                "Open Password Vault settings, choose Retry Local Recovery, then try the forced reset again."
            ))
        case .saveFailed:
            setGeneralError(String(localized:
                "The local encrypted archive could not be created, so no reset occurred."
            ))
        default:
            setGeneralError(String(localized:
                "The password vault could not be force reset. The existing password vault was not changed."
            ))
        }
        updateValidationState()
    }

    func setGeneralError(_ message: String?) {
        generalErrorLabel.stringValue = message ?? ""
        generalErrorLabel.isHidden = message?.isEmpty != false
        generalErrorLabel.setAccessibilityLabel(message)
    }

    func focusNewPassword() { window?.makeFirstResponder(newInput.activeField) }

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

    func clearSecrets() {
        inputs.forEach { $0.clear() }
        acknowledgementButton.state = .off
        updateValidationState()
    }

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
extension PasswordVaultForceResetSheetController {
    var secureFieldCountForTesting: Int { inputs.filter { !$0.isPasswordVisible }.count }
    var visiblePasswordFieldCountForTesting: Int { inputs.filter(\.isPasswordVisible).count }
    var fieldLabelsForTesting: [String] { inputs.map { $0.label.stringValue } }
    var limitationTextForTesting: String { limitationLabel.stringValue }
    var limitationLocalizationKeyForTesting: String { Text.limitationKey }
    var archiveReplacementWarningForTesting: String { archiveReplacementLabel.stringValue }
    var archiveReplacementLocalizationKeyForTesting: String { Text.archiveReplacementKey }
    var warningAccessibilityIdentifierForTesting: String? { warningStatusView.accessibilityIdentifier() }
    var inputAccessibilityIdentifiersForTesting: [String] { inputs.map(\.accessibilityIdentifier) }
    var primaryButtonEnabledForTesting: Bool { submitButton.isEnabled }
    var primaryButtonIsDefaultForTesting: Bool { submitButton.keyEquivalent == "\r" }
    var submitAccessibilityLabelForTesting: String? { submitButton.accessibilityLabel() }
    var submitAccessibilityRoleForTesting: NSAccessibility.Role? { submitButton.accessibilityRole() }
    var isBusyForTesting: Bool { isBusy }
    var didCancelForTesting: Bool { didCancel }
    var valuesForTesting: (new: String, confirmation: String) {
        (newInput.value, confirmationInput.value)
    }
    var keyViewOrderForTesting: [String] {
        var currentView: NSView? = newInput.activeField
        return (0..<5).map { _ in
            defer { currentView = currentView?.nextValidKeyView }
            return currentView?.accessibilityIdentifier() ?? "<missing>"
        }
    }
    var allInteractiveControlsDisabledForTesting: Bool {
        inputs.allSatisfy {
            !$0.secureField.isEnabled && !$0.visibleField.isEnabled && !$0.visibilityButton.isEnabled
        } && !acknowledgementButton.isEnabled && !cancelButton.isEnabled && !submitButton.isEnabled
    }
    var controlsFitBoundsForTesting: Bool {
        guard let contentView = window?.contentView else { return false }
        contentView.layoutSubtreeIfNeeded()
        let controls: [NSView] = [
            warningStatusView,
            archiveReplacementLabel,
            newInput,
            confirmationInput,
            acknowledgementButton,
            generalErrorLabel,
            cancelButton,
            submitButton
        ]
        return controls.allSatisfy {
            let frame = contentView.convert($0.bounds, from: $0)
            return frame.minX >= -0.5 && frame.maxX <= contentView.bounds.maxX + 0.5
                && frame.minY >= -0.5 && frame.maxY <= contentView.bounds.maxY + 0.5
        }
    }

    func setValuesForTesting(new: String, confirmation: String) {
        newInput.value = new
        confirmationInput.value = confirmation
        inputDidChange()
    }

    func setAcknowledgementForTesting(_ acknowledged: Bool) {
        acknowledgementButton.state = acknowledged ? .on : .off
        acknowledgementChanged(nil)
    }

    func submitForTesting() { submit(nil) }
    func cancelForTesting() { cancel() }
}
#endif
