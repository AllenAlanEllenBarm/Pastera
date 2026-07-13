import AppKit

final class PasswordVaultReturnTextField: NSTextField {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onReturn?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}

final class PasswordVaultReturnSecureField: NSSecureTextField {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onReturn?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}

final class PasswordVaultNoteTextView: NSTextView {
    var onSave: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command) {
            onSave?()
        } else if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class PasswordVaultEditorView: NSView {
    private let folders: [PasswordVaultFolder]
    private let titleField = PasswordVaultReturnTextField()
    private let usernameField = PasswordVaultReturnTextField()
    private let passwordField = PasswordVaultReturnSecureField()
    private let websiteField = PasswordVaultReturnTextField()
    private let noteField = PasswordVaultNoteTextView()
    private let noteScrollView = NSScrollView()
    private let folderPopup = NSPopUpButton()
    private let moreButton = NSButton()
    private let errorLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private let moreStack = NSStackView()
    private let onSave: (PasswordVaultDraft) -> Void
    private let onCancel: () -> Void

    init(
        draft: PasswordVaultDraft,
        folders: [PasswordVaultFolder],
        errorMessage: String?,
        onSave: @escaping (PasswordVaultDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.folders = folders
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 226))
        titleField.stringValue = draft.title
        usernameField.stringValue = draft.username
        passwordField.stringValue = draft.password
        websiteField.stringValue = draft.website
        noteField.string = draft.note
        errorLabel.stringValue = errorMessage ?? ""
        setup(selectedFolderID: draft.folderID)
    }

    required init?(coder: NSCoder) { nil }

    func clearPassword() {
        passwordField.stringValue = ""
    }

    private func setup(selectedFolderID: UUID?) {
        stack.orientation = .vertical
        stack.spacing = 7
        stack.alignment = .leading
        stack.frame = bounds.insetBy(dx: 8, dy: 6)
        [titleField, usernameField, passwordField, folderPopup].forEach { $0.frame.size.width = stack.frame.width }
        titleField.placeholderString = String(localized: "Name")
        usernameField.placeholderString = String(localized: "Username")
        passwordField.placeholderString = String(localized: "Password")
        [titleField, usernameField, websiteField].forEach { field in
            field.onReturn = { [weak self] in self?.save(nil) }
            field.onEscape = { [weak self] in self?.cancel(nil) }
        }
        passwordField.onReturn = { [weak self] in self?.save(nil) }
        passwordField.onEscape = { [weak self] in self?.cancel(nil) }
        folders.forEach { folderPopup.addItem(withTitle: $0.name) }
        if let selectedFolderID, let index = folders.firstIndex(where: { $0.id == selectedFolderID }) {
            folderPopup.selectItem(at: index)
        }
        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(usernameField)
        stack.addArrangedSubview(passwordField)
        stack.addArrangedSubview(folderPopup)

        moreButton.title = String(localized: "More")
        moreButton.bezelStyle = .inline
        moreButton.target = self
        moreButton.action = #selector(toggleMore(_:))
        stack.addArrangedSubview(moreButton)

        moreStack.orientation = .vertical
        moreStack.spacing = 7
        websiteField.placeholderString = String(localized: "Website")
        noteField.isRichText = false
        noteField.font = .systemFont(ofSize: NSFont.systemFontSize)
        noteField.onSave = { [weak self] in self?.save(nil) }
        noteField.onEscape = { [weak self] in self?.cancel(nil) }
        noteScrollView.documentView = noteField
        noteScrollView.hasVerticalScroller = true
        noteScrollView.borderType = .bezelBorder
        noteScrollView.frame.size = NSSize(width: stack.frame.width, height: 54)
        moreStack.addArrangedSubview(websiteField)
        moreStack.addArrangedSubview(noteScrollView)
        moreStack.isHidden = true
        stack.addArrangedSubview(moreStack)

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.maximumNumberOfLines = 1
        errorLabel.isHidden = errorLabel.stringValue.isEmpty
        stack.addArrangedSubview(errorLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel(_:)))
        let save = NSButton(title: String(localized: "Save"), target: self, action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = [.command]
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(save)
        stack.addArrangedSubview(buttons)
        addSubview(stack)

        titleField.setAccessibilityLabel(String(localized: "Name"))
        usernameField.setAccessibilityLabel(String(localized: "Username"))
        passwordField.setAccessibilityLabel(String(localized: "Password"))
        websiteField.setAccessibilityLabel(String(localized: "Website"))
        noteField.setAccessibilityLabel(String(localized: "Note"))
        folderPopup.setAccessibilityLabel(String(localized: "Folder"))
    }

    @objc private func toggleMore(_ sender: NSButton) {
        moreStack.isHidden.toggle()
        sender.title = moreStack.isHidden ? String(localized: "More") : String(localized: "Less")
    }

    @objc private func save(_ sender: Any?) {
        let folderID = folders[safe: folderPopup.indexOfSelectedItem]?.id
        onSave(PasswordVaultDraft(
            folderID: folderID,
            title: titleField.stringValue,
            website: websiteField.stringValue,
            username: usernameField.stringValue,
            note: noteField.string,
            password: passwordField.stringValue
        ))
    }

    @objc private func cancel(_ sender: Any?) {
        clearPassword()
        onCancel()
    }
}

final class PasswordVaultFolderEditorView: NSView {
    private let iconView = NSImageView()
    private let field = PasswordVaultReturnTextField()
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    init(name: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.rowHeight
        ))
        field.stringValue = name
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        iconView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: String(localized: "Folder"))
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.frame = NSRect(x: 10, y: 8, width: 14, height: 14)
        addSubview(iconView)

        field.frame = NSRect(x: 34, y: 3, width: bounds.width - 44, height: 24)
        field.autoresizingMask = [.width]
        field.placeholderString = String(localized: "Folder Name")
        field.onReturn = { [weak self] in self?.save(nil) }
        field.onEscape = { [weak self] in self?.cancel(nil) }
        field.setAccessibilityLabel(String(localized: "Folder Name"))
        addSubview(field)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self.field)
        }
    }

    @objc private func save(_ sender: Any?) { onSave(field.stringValue) }
    @objc private func cancel(_ sender: Any?) { onCancel() }
}
