// Copyright 2026 Feeyo

import AppKit

private final class PasswordVaultMasterPasswordSheetWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class PasswordVaultPasswordInputView: NSView, NSTextFieldDelegate {
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

    var activeField: NSTextField {
        isPasswordVisible ? visibleField : secureField
    }

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
        visibilityButton.setAccessibilityLabel(pasteraPreferenceString(
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
        visibilityButton.setAccessibilityLabel(pasteraPreferenceString("Show Password"))

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
    typealias ChangePassword = (
        String,
        String,
        @escaping (Result<PasswordVaultMasterPasswordChangeResult, PasswordVaultError>) -> Void
    ) -> Void

    private let changePasswordOperation: ChangePassword
    private let onSuccess: (PasswordVaultMasterPasswordChangeResult) -> Void
    private let currentInput = PasswordVaultPasswordInputView(
        labelText: pasteraPreferenceString("Current Master Password"),
        accessibilityIdentifier: "masterPassword.current"
    )
    private let newInput = PasswordVaultPasswordInputView(
        labelText: pasteraPreferenceString("New Master Password"),
        accessibilityIdentifier: "masterPassword.new"
    )
    private let confirmationInput = PasswordVaultPasswordInputView(
        labelText: pasteraPreferenceString("Confirm New Master Password"),
        accessibilityIdentifier: "masterPassword.confirmation"
    )
    private let recoveryWarningLabel = NSTextField(wrappingLabelWithString: pasteraPreferenceString(
        "The new master password encrypts your password vault. If forgotten, it cannot be recovered by any other means."
    ))
    private let generalErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = NSButton(
        title: pasteraPreferenceString("Cancel"),
        target: nil,
        action: nil
    )
    private let submitButton = NSButton(
        title: pasteraPreferenceString("Change Master Password"),
        target: nil,
        action: nil
    )
    private weak var parentWindow: NSWindow?
    private(set) var isBusy = false
    private(set) var didCancel = false

    init(
        changePassword: @escaping ChangePassword,
        onSuccess: @escaping (PasswordVaultMasterPasswordChangeResult) -> Void = { _ in }
    ) {
        changePasswordOperation = changePassword
        self.onSuccess = onSuccess
        let window = PasswordVaultMasterPasswordSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 438),
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
        onSuccess: @escaping (PasswordVaultMasterPasswordChangeResult) -> Void
    ) {
        self.init(
            changePassword: { currentPassword, newPassword, completion in
                controller.changeMasterPassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword,
                    completion: completion
                )
            },
            onSuccess: onSuccess
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        clearSecrets()
    }

    func beginSheet(for parentWindow: NSWindow) {
        self.parentWindow = parentWindow
        didCancel = false
        parentWindow.beginSheet(window!) { [weak self] _ in
            self?.clearSecrets()
        }
        focusCurrentPassword()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isBusy else { return false }
        cancel()
        return parentWindow == nil
    }

    func windowWillClose(_ notification: Notification) {
        clearSecrets()
    }
}

private extension PasswordVaultMasterPasswordSheetController {
    var inputs: [PasswordVaultPasswordInputView] {
        [currentInput, newInput, confirmationInput]
    }

    func configureWindow(_ window: PasswordVaultMasterPasswordSheetWindow) {
        window.title = pasteraPreferenceString("Change Master Password")
        window.contentMinSize = NSSize(width: 360, height: 438)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onEscape = { [weak self] in self?.cancel() }
    }

    func buildContent(in window: NSWindow) {
        let contentView = PasteraPreferenceFlippedView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: pasteraPreferenceString("Change Master Password"))
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleLabel = NSTextField(wrappingLabelWithString: pasteraPreferenceString(
            "Verify your current master password, then choose a new one. Your folders and entries will be preserved."
        ))
        subtitleLabel.font = .systemFont(ofSize: 12.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

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
            currentInput,
            newInput,
            confirmationInput,
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
            currentInput.widthAnchor.constraint(equalTo: stack.widthAnchor),
            newInput.widthAnchor.constraint(equalTo: stack.widthAnchor),
            confirmationInput.widthAnchor.constraint(equalTo: stack.widthAnchor),
            generalErrorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func bindActions() {
        inputs.forEach { input in
            input.onChange = { [weak self] in self?.inputDidChange() }
            input.visibilityButton.target = self
        }
        currentInput.visibilityButton.action = #selector(toggleCurrentVisibility(_:))
        newInput.visibilityButton.action = #selector(toggleNewVisibility(_:))
        confirmationInput.visibilityButton.action = #selector(toggleConfirmationVisibility(_:))
        inputs.flatMap { [$0.secureField, $0.visibleField] }.forEach { field in
            field.target = self
            field.action = #selector(submit(_:))
        }
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked(_:))
        cancelButton.setAccessibilityIdentifier("masterPassword.cancel")
        submitButton.target = self
        submitButton.action = #selector(submit(_:))
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded
        submitButton.setAccessibilityIdentifier("masterPassword.submit")
        installKeyViewLoop()
    }

    func installKeyViewLoop() {
        currentInput.secureField.nextKeyView = newInput.secureField
        currentInput.visibleField.nextKeyView = newInput.secureField
        newInput.secureField.nextKeyView = confirmationInput.secureField
        newInput.visibleField.nextKeyView = confirmationInput.secureField
        confirmationInput.secureField.nextKeyView = cancelButton
        confirmationInput.visibleField.nextKeyView = cancelButton
        cancelButton.nextKeyView = submitButton
        submitButton.nextKeyView = currentInput.secureField
    }

    func inputDidChange() {
        inputs.forEach { $0.setError(nil) }
        setGeneralError(nil)
        updateValidationState()
    }

    func updateValidationState() {
        let allPresent = inputs.allSatisfy { !$0.value.isEmpty }
        submitButton.isEnabled = !isBusy && allPresent && newInput.value == confirmationInput.value
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        inputs.forEach { $0.setEnabled(!busy) }
        cancelButton.isEnabled = !busy
        submitButton.isEnabled = !busy && inputs.allSatisfy { !$0.value.isEmpty }
            && newInput.value == confirmationInput.value
        submitButton.title = busy
            ? pasteraPreferenceString("Changing…")
            : pasteraPreferenceString("Change Master Password")
        window?.standardWindowButton(.closeButton)?.isEnabled = !busy
        window?.setAccessibilityValue(busy ? pasteraPreferenceString("Processing") : nil)
    }

    func validateForSubmission() -> Bool {
        inputs.forEach { $0.setError(nil) }
        setGeneralError(nil)
        if currentInput.value.isEmpty {
            currentInput.setError(pasteraPreferenceString("Enter the current master password."))
            focusCurrentPassword()
            return false
        }
        if newInput.value.isEmpty {
            newInput.setError(pasteraPreferenceString("Enter a new master password."))
            window?.makeFirstResponder(newInput.activeField)
            return false
        }
        if confirmationInput.value.isEmpty || confirmationInput.value != newInput.value {
            confirmationInput.setError(pasteraPreferenceString("The new master passwords do not match."))
            window?.makeFirstResponder(confirmationInput.activeField)
            return false
        }
        return true
    }

    @objc func submit(_ sender: Any?) {
        guard !isBusy, validateForSubmission() else { return }
        let currentPassword = currentInput.value
        let newPassword = newInput.value
        setBusy(true)
        changePasswordOperation(currentPassword, newPassword) { [weak self] result in
            self?.finish(result)
        }
    }

    func finish(_ result: Result<PasswordVaultMasterPasswordChangeResult, PasswordVaultError>) {
        switch result {
        case let .success(changeResult):
            clearSecrets()
            setBusy(false)
            closeSheet()
            onSuccess(changeResult)
        case let .failure(error):
            setBusy(false)
            handle(error)
        }
    }

    func handle(_ error: PasswordVaultError) {
        switch error {
        case .wrongMasterPassword:
            currentInput.value = ""
            currentInput.setError(pasteraPreferenceString("The current master password is incorrect."))
            focusCurrentPassword()
        case .invalidPassword:
            newInput.setError(pasteraPreferenceString("Enter a new master password."))
            window?.makeFirstResponder(newInput.activeField)
        case .externalConflict, .cloudUnavailable:
            setGeneralError(pasteraPreferenceString("Resolve the sync conflict, then try again without closing this sheet."))
        case .saveFailed:
            setGeneralError(pasteraPreferenceString("Check access to the password vault file, then try again."))
        default:
            setGeneralError(pasteraPreferenceString("The master password could not be changed. Please try again."))
        }
        updateValidationState()
    }

    func setGeneralError(_ message: String?) {
        generalErrorLabel.stringValue = message ?? ""
        generalErrorLabel.isHidden = message?.isEmpty != false
        generalErrorLabel.setAccessibilityLabel(message)
    }

    func focusCurrentPassword() {
        window?.makeFirstResponder(currentInput.activeField)
    }

    @objc func cancelClicked(_ sender: Any?) {
        cancel()
    }

    func cancel() {
        guard !isBusy else { return }
        didCancel = true
        clearSecrets()
        closeSheet()
    }

    func closeSheet() {
        guard let window else { return }
        if let parentWindow, window.sheetParent === parentWindow {
            parentWindow.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }

    func clearSecrets() {
        inputs.forEach { $0.clear() }
    }

    @objc func toggleCurrentVisibility(_ sender: Any?) { currentInput.toggleVisibility() }
    @objc func toggleNewVisibility(_ sender: Any?) { newInput.toggleVisibility() }
    @objc func toggleConfirmationVisibility(_ sender: Any?) { confirmationInput.toggleVisibility() }
}

#if DEBUG
extension PasswordVaultMasterPasswordSheetController {
    var secureFieldCountForTesting: Int { inputs.filter { !$0.isPasswordVisible }.count }
    var visiblePasswordFieldCountForTesting: Int { inputs.filter(\.isPasswordVisible).count }
    var fieldLabelsForTesting: [String] { inputs.map { $0.label.stringValue } }
    var recoveryWarningForTesting: String { recoveryWarningLabel.stringValue }
    var primaryButtonEnabledForTesting: Bool { submitButton.isEnabled }
    var confirmationErrorForTesting: String { confirmationInput.errorLabel.stringValue }
    var currentPasswordErrorForTesting: String { currentInput.errorLabel.stringValue }
    var isBusyForTesting: Bool { isBusy }
    var didCancelForTesting: Bool { didCancel }
    var valuesForTesting: (current: String, new: String, confirmation: String) {
        (currentInput.value, newInput.value, confirmationInput.value)
    }
    var keyViewOrderForTesting: [String] {
        inputs.map(\.accessibilityIdentifier) + ["masterPassword.cancel", "masterPassword.submit"]
    }
    var allInteractiveControlsDisabledForTesting: Bool {
        inputs.allSatisfy {
            !$0.secureField.isEnabled && !$0.visibleField.isEnabled && !$0.visibilityButton.isEnabled
        } && !cancelButton.isEnabled && !submitButton.isEnabled
    }
    var controlsFitBoundsForTesting: Bool {
        guard let contentView = window?.contentView else { return false }
        contentView.layoutSubtreeIfNeeded()
        let controls: [NSView] = inputs + [recoveryWarningLabel, cancelButton, submitButton]
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

    func setValuesForTesting(current: String, new: String, confirmation: String) {
        currentInput.value = current
        newInput.value = new
        confirmationInput.value = confirmation
        inputDidChange()
    }

    func passwordIsVisibleForTesting(index: Int) -> Bool {
        inputs[index].isPasswordVisible
    }

    func focusFieldForTesting(index: Int) {
        window?.makeFirstResponder(nil)
        window?.makeFirstResponder(inputs[index].activeField)
    }

    func toggleVisibilityForTesting(index: Int) {
        inputs[index].toggleVisibility()
    }

    func submitForTesting() { submit(nil) }
    func cancelForTesting() { cancel() }
}
#endif
