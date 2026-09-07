import AppKit

// Context-specific password-vault recovery views and their narrow data source.
// swiftlint:disable file_length

enum PasswordVaultCreateStorageMode: String, Equatable {
    case localOnly
    case oneDrive
}

struct MainMenuPasswordVaultSyncDataSource {
    let snapshot: () -> PasswordVaultSyncSnapshot
    let enableConfiguredOneDrive: (
        String?,
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void
    let retryWithRemotePassword: (
        String,
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void
    let startOneDrive: () -> Bool
}

enum PasswordVaultInlineActionStyle {
    case primary
    case secondary
    case danger
}

final class PasswordVaultInlineActionView: NSView {
    struct Action {
        let title: String
        let identifier: String
        let style: PasswordVaultInlineActionStyle
        let isEnabled: Bool
        let handler: () -> Void

        init(
            title: String,
            identifier: String,
            style: PasswordVaultInlineActionStyle,
            isEnabled: Bool = true,
            handler: @escaping () -> Void
        ) {
            self.title = title
            self.identifier = identifier
            self.style = style
            self.isEnabled = isEnabled
            self.handler = handler
        }
    }

    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let messageLabels: [NSTextField]
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var actionHandlers = [() -> Void]()
    private var actionButtons = [NSButton]()

    init(
        symbolName: String,
        symbolColor: NSColor,
        title: String,
        messages: [String],
        actions: [Action],
        showsTitle: Bool = true
    ) {
        messageLabels = messages.map { NSTextField(wrappingLabelWithString: $0) }
        let height: CGFloat = showsTitle ? 234 : 160
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: height))
        setup(
            symbolName: symbolName,
            symbolColor: symbolColor,
            title: title,
            actions: actions,
            showsTitle: showsTitle
        )
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        let width = max(0, bounds.width - inset * 2)
        if titleLabel.isHidden {
            var top = bounds.height - 12
            for label in messageLabels {
                top -= 34
                label.frame = NSRect(x: inset, y: top, width: width, height: 32)
            }
            if !errorLabel.isHidden {
                top -= 34
                errorLabel.frame = NSRect(x: inset, y: top, width: width, height: 28)
            }
            for button in actionButtons {
                top -= 36
                button.frame = NSRect(x: inset, y: top, width: width, height: 28)
            }
            return
        }
        symbolView.frame = NSRect(x: inset, y: bounds.height - 40, width: 24, height: 24)
        titleLabel.frame = NSRect(x: 46, y: bounds.height - 44, width: max(0, bounds.width - 60), height: 30)

        let messageHeight: CGFloat = messageLabels.count >= 3 ? 28 : 34
        var top = bounds.height - 52
        for label in messageLabels {
            top -= messageHeight
            label.frame = NSRect(x: inset, y: top, width: width, height: messageHeight - 2)
        }

        var buttonY: CGFloat = 8
        for button in actionButtons.reversed() {
            button.frame = NSRect(x: inset, y: buttonY, width: width, height: 28)
            buttonY += 32
        }
        errorLabel.frame = NSRect(x: inset, y: buttonY + 2, width: width, height: 28)
    }

    func setError(_ message: String?) {
        errorLabel.stringValue = message ?? ""
        errorLabel.isHidden = message == nil
        setAccessibilityHelp(message ?? "")
    }

    private func setup(
        symbolName: String,
        symbolColor: NSColor,
        title: String,
        actions: [Action],
        showsTitle: Bool
    ) {
        wantsLayer = true
        symbolView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.contentTintColor = symbolColor
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        symbolView.isHidden = !showsTitle
        titleLabel.isHidden = !showsTitle
        messageLabels.forEach {
            $0.font = .systemFont(ofSize: 10.5)
            $0.textColor = .secondaryLabelColor
            $0.maximumNumberOfLines = 3
            $0.lineBreakMode = .byWordWrapping
        }
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isHidden = true
        [symbolView, titleLabel].forEach(addSubview)
        messageLabels.forEach(addSubview)
        addSubview(errorLabel)

        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.title, target: self, action: #selector(actionClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action.identifier)
            button.tag = index
            button.isEnabled = action.isEnabled
            button.controlSize = .large
            button.setAccessibilityLabel(action.title)
            switch action.style {
            case .primary:
                button.bezelStyle = .rounded
                button.keyEquivalent = "\r"
            case .secondary:
                button.bezelStyle = .inline
                button.isBordered = false
                button.contentTintColor = .secondaryLabelColor
            case .danger:
                button.bezelStyle = .rounded
                button.contentTintColor = .systemRed
                button.attributedTitle = NSAttributedString(
                    string: action.title,
                    attributes: [
                        .foregroundColor: NSColor.systemRed,
                        .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                    ]
                )
            }
            actionButtons.append(button)
            actionHandlers.append(action.handler)
            addSubview(button)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }

    @objc private func actionClicked(_ sender: NSButton) {
        guard actionHandlers.indices.contains(sender.tag) else { return }
        actionHandlers[sender.tag]()
    }

#if DEBUG
    var textValuesForTesting: [String] {
        [titleLabel].filter { !$0.isHidden }.map(\.stringValue)
            + messageLabels.map(\.stringValue)
            + [errorLabel.stringValue].filter { !$0.isEmpty }
    }
#endif
}

final class PasswordVaultRemoteCredentialsView: NSView {
    private let titleLabel = NSTextField(wrappingLabelWithString: String(localized: "Unlock the OneDrive Copy"))
    private let messageLabel = NSTextField(wrappingLabelWithString: String(
        localized: "Your local vault is already unlocked. Enter the OneDrive copy's master password for this merge only."
    ))
    private let fieldLabel = NSTextField(labelWithString: String(localized: "OneDrive Vault Master Password"))
    private let secureField = NSSecureTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let submitButton = NSButton()
    private let onSubmit: (String) -> Void

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: 234))
        setup()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        let width = max(0, bounds.width - inset * 2)
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 38, width: width, height: 26)
        messageLabel.frame = NSRect(x: inset, y: bounds.height - 88, width: width, height: 42)
        fieldLabel.frame = NSRect(x: inset, y: bounds.height - 110, width: width, height: 16)
        secureField.frame = NSRect(x: inset, y: bounds.height - 142, width: width, height: 26)
        errorLabel.frame = NSRect(x: inset, y: 46, width: width, height: 30)
        submitButton.frame = NSRect(x: inset, y: 8, width: width, height: 30)
    }

    func clearSecret() {
        secureField.stringValue = ""
    }

    func setError(_ message: String?) {
        errorLabel.stringValue = message ?? ""
        errorLabel.isHidden = message == nil
        setAccessibilityHelp(message ?? "")
    }

    func submit() {
        let password = secureField.stringValue
        clearSecret()
        guard !password.isEmpty else {
            setError(String(localized: "Enter the OneDrive vault master password."))
            return
        }
        setError(nil)
        onSubmit(password)
    }

    private func setup() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        messageLabel.font = .systemFont(ofSize: 10.5)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 3
        fieldLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        secureField.identifier = NSUserInterfaceItemIdentifier("passwordVaultRemoteMasterPasswordField")
        secureField.setAccessibilityLabel(String(localized: "OneDrive Vault Master Password"))
        secureField.target = self
        secureField.action = #selector(submitClicked(_:))
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        submitButton.title = String(localized: "Unlock and Merge")
        submitButton.identifier = NSUserInterfaceItemIdentifier("passwordVaultRemoteCredentialSubmit")
        submitButton.bezelStyle = .rounded
        submitButton.controlSize = .large
        submitButton.target = self
        submitButton.action = #selector(submitClicked(_:))
        submitButton.keyEquivalent = "\r"
        submitButton.setAccessibilityLabel(String(localized: "Unlock the OneDrive copy and merge"))
        [titleLabel, messageLabel, fieldLabel, secureField, errorLabel, submitButton].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "OneDrive copy credentials"))
    }

    @objc private func submitClicked(_ sender: Any?) {
        submit()
    }

#if DEBUG
    var secretValueForTesting: String { secureField.stringValue }
    var textValuesForTesting: [String] {
        [titleLabel.stringValue, messageLabel.stringValue, fieldLabel.stringValue, errorLabel.stringValue]
            .filter { !$0.isEmpty }
    }

    func setSecretForTesting(_ value: String) {
        secureField.stringValue = value
    }
#endif
}

func passwordVaultSyncFailureMessage(_ failure: PasswordVaultSyncFailure) -> String {
    switch failure {
    case .oneDriveNotInstalled: String(localized: "OneDrive is not installed.")
    case .oneDriveNotRunning: String(localized: "OneDrive is not running.")
    case .folderUnavailable: String(localized: "The selected OneDrive folder is unavailable.")
    case .folderNotWritable: String(localized: "The selected OneDrive folder is read-only.")
    case .remoteUnavailable: String(localized: "The OneDrive replica is temporarily unavailable.")
    case .remoteCorrupted: String(localized: "The OneDrive replica cannot be read safely.")
    case .remoteCredentialsRequired: String(localized: "The OneDrive replica uses a different master password.")
    case .remoteWriteFailed: String(localized: "The encrypted replica could not be saved to OneDrive.")
    case .remoteVerificationFailed: String(localized: "The saved OneDrive replica could not be verified.")
    }
}

// swiftlint:enable file_length
