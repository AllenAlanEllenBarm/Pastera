//
//  CPYHistoryPreferenceViewController.swift
//
//  Pastera
//

import AppKit
import Dependencies

final class CPYHistoryPreferenceViewController: PasteraPreferencePageViewController, NSTextFieldDelegate {
    private struct Option {
        let key: String
        let title: String
    }

    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository

    private var imageLimitField = NSTextField()
    private var fileLimitField = NSTextField()
    private var imageLimitErrorLabel = CPYHistoryPreferenceViewController.makeErrorLabel()
    private var fileLimitErrorLabel = CPYHistoryPreferenceViewController.makeErrorLabel()
    private var copySameHistoryButton = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )
    private var overwriteSameHistoryButton = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )
    private var clearHistoryButton = NSButton(
        title: String(localized: "Clear History"),
        target: nil,
        action: #selector(AppDelegate.clearAllHistory)
    )

    private var storeTypes = [String: Any]()
    private var filePreviewTypes = [String: Any]()
    private var storeTypeButtons = [NSButton]()
    private var filePreviewButtons = [NSButton]()

    private let typeOptions = [
        Option(key: PasteboardAvailableType.string.rawValue, title: pasteraPreferenceString("Plain Text")),
        Option(key: PasteboardAvailableType.rtf.rawValue, title: pasteraPreferenceString("Rich Text")),
        Option(key: PasteboardAvailableType.rtfd.rawValue, title: pasteraPreferenceString("Rich Text with Attachments")),
        Option(key: PasteboardAvailableType.pdf.rawValue, title: pasteraPreferenceString("Documents")),
        Option(key: PasteboardAvailableType.filenames.rawValue, title: pasteraPreferenceString("Files")),
        Option(key: PasteboardAvailableType.url.rawValue, title: pasteraPreferenceString("Links")),
        Option(key: PasteboardAvailableType.tiff.rawValue, title: pasteraPreferenceString("Image Content"))
    ]
    private let filePreviewOptions = [
        Option(key: PasteraFilePreviewKind.image.rawValue, title: pasteraPreferenceString("Images")),
        Option(key: PasteraFilePreviewKind.document.rawValue, title: pasteraPreferenceString("Documents")),
        Option(key: PasteraFilePreviewKind.archive.rawValue, title: pasteraPreferenceString("Archives")),
        Option(key: PasteraFilePreviewKind.code.rawValue, title: pasteraPreferenceString("Code")),
        Option(key: PasteraFilePreviewKind.other.rawValue, title: pasteraPreferenceString("Other"))
    ]

    init() {
        super.init(paneID: .history, title: pasteraPreferenceString("History & Preview"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        resetViewState()
        super.loadView()
        loadDictionaries()
        configureControls()
        buildCapacityGroup()
        buildDuplicateGroup()
        buildSavedTypesGroup()
        buildPreviewTypesGroup()
        buildDangerGroup()
    }

    private func resetViewState() {
        removeExistingContent()
        imageLimitField = NSTextField()
        fileLimitField = NSTextField()
        imageLimitErrorLabel = Self.makeErrorLabel()
        fileLimitErrorLabel = Self.makeErrorLabel()
        copySameHistoryButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        overwriteSameHistoryButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        clearHistoryButton = NSButton(
            title: String(localized: "Clear History"),
            target: nil,
            action: #selector(AppDelegate.clearAllHistory)
        )
        storeTypeButtons.removeAll()
        filePreviewButtons.removeAll()
    }

    private func removeExistingContent() {
        contentStack.arrangedSubviews.forEach { arrangedSubview in
            NSLayoutConstraint.deactivate(contentStack.constraints.filter {
                $0.firstItem === arrangedSubview || $0.secondItem === arrangedSubview
            })
            contentStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        if let container = contentStack.superview {
            NSLayoutConstraint.deactivate(container.constraints.filter {
                $0.firstItem === contentStack || $0.secondItem === contentStack
            })
        }
        contentStack.removeFromSuperview()
    }

    private func loadDictionaries() {
        let defaults = AppEnvironment.current.defaults
        storeTypes = defaults.dictionary(forKey: Constants.UserDefaults.storeTypes) ?? [:]
        filePreviewTypes = defaults.dictionary(forKey: Constants.UserDefaults.filePreviewTypes)
            ?? PasteraFilePreviewKind.defaultStates()
    }

    private func configureControls() {
        configureLimitField(
            imageLimitField,
            accessibilityLabel: pasteraPreferenceString("Image History Limit"),
            value: currentLimit(forKey: Constants.UserDefaults.maxImageHistorySize)
        )
        configureLimitField(
            fileLimitField,
            accessibilityLabel: pasteraPreferenceString("File History Limit"),
            value: currentLimit(forKey: Constants.UserDefaults.maxFileHistorySize)
        )

        let defaults = AppEnvironment.current.defaults
        copySameHistoryButton.state = defaults.bool(forKey: Constants.UserDefaults.copySameHistory) ? .on : .off
        copySameHistoryButton.target = self
        copySameHistoryButton.action = #selector(copySameHistoryChanged(_:))
        copySameHistoryButton.setAccessibilityIdentifier("history.copySameHistory")
        copySameHistoryButton.setAccessibilityLabel(pasteraPreferenceString("Place already copied history at the top"))

        overwriteSameHistoryButton.state = defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory) ? .on : .off
        overwriteSameHistoryButton.target = self
        overwriteSameHistoryButton.action = #selector(overwriteSameHistoryChanged(_:))
        overwriteSameHistoryButton.setAccessibilityIdentifier("history.overwriteSameHistory")
        overwriteSameHistoryButton.setAccessibilityLabel(
            pasteraPreferenceString("Move instead of copying (removes the older one from the list)")
        )
        overwriteSameHistoryButton.isEnabled = copySameHistoryButton.state == .on

        clearHistoryButton.bezelStyle = .rounded
        clearHistoryButton.setButtonType(.momentaryPushIn)
    }

    private func configureLimitField(_ field: NSTextField, accessibilityLabel: String, value: Int) {
        field.alignment = .right
        field.delegate = self
        field.target = self
        field.action = #selector(limitFieldCommitted(_:))
        field.stringValue = String(value)
        field.setAccessibilityLabel(accessibilityLabel)
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
    }

    private func buildCapacityGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Retention Limits"),
            symbolName: "archivebox",
            accentColor: .systemBlue
        )
        let imageRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Image History Limit"),
            subtitle: pasteraPreferenceString("Keep 1 to 50 image history items."),
            control: makeLimitControl(field: imageLimitField, errorLabel: imageLimitErrorLabel)
        )
        let fileRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("File History Limit"),
            subtitle: pasteraPreferenceString("Keep 1 to 50 file history items."),
            control: makeLimitControl(field: fileLimitField, errorLabel: fileLimitErrorLabel)
        )
        group.addRow(imageRow)
        group.addRow(fileRow)
        addGroup(group)
        registerAnchor("history.imageLimit", view: imageRow)
        registerAnchor("history.fileLimit", view: fileRow)
    }

    private func makeLimitControl(field: NSTextField, errorLabel: NSTextField) -> NSView {
        let unitLabel = NSTextField(labelWithString: pasteraPreferenceString("items"))
        unitLabel.textColor = .secondaryLabelColor
        let valueRow = NSStackView(views: [field, unitLabel])
        valueRow.orientation = .horizontal
        valueRow.alignment = .centerY
        valueRow.spacing = 6
        let stack = NSStackView(views: [valueRow, errorLabel])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 3
        return stack
    }

    private func buildDuplicateGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Duplicates"),
            symbolName: "arrow.triangle.2.circlepath",
            accentColor: .systemIndigo
        )
        let copyRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Repeated Copy"),
            subtitle: pasteraPreferenceString("Place already copied history at the top"),
            control: copySameHistoryButton
        )
        let overwriteRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Move to Top"),
            subtitle: pasteraPreferenceString("Move instead of copying (removes the older one from the list)"),
            control: overwriteSameHistoryButton
        )
        group.addRow(copyRow)
        group.addRow(overwriteRow)
        addGroup(group, anchorID: "history.duplicatePolicy")
    }

    private func buildSavedTypesGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Stored Types"),
            symbolName: "square.stack.3d.up",
            accentColor: .systemTeal
        )
        typeOptions.forEach { option in
            let button = makeTypeButton(option: option, action: #selector(storeTypeChanged(_:)))
            button.state = dictionaryValue(storeTypes, key: option.key) ? .on : .off
            storeTypeButtons.append(button)
            group.addRow(PasteraPreferenceSettingRowView(title: option.title, control: button))
        }
        addGroup(group, anchorID: "history.savedTypes")
    }

    private func buildPreviewTypesGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("File Preview Types"),
            symbolName: "doc.text.magnifyingglass",
            accentColor: .systemOrange
        )
        filePreviewOptions.forEach { option in
            let button = makeTypeButton(option: option, action: #selector(filePreviewTypeChanged(_:)))
            button.state = dictionaryValue(filePreviewTypes, key: option.key) ? .on : .off
            filePreviewButtons.append(button)
            group.addRow(PasteraPreferenceSettingRowView(title: option.title, control: button))
        }
        updateFilePreviewButtonStates()
        addGroup(group, anchorID: "history.previewTypes")
    }

    private func makeTypeButton(option: Option, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(option.key)
        button.setAccessibilityLabel(option.title)
        return button
    }

    private func buildDangerGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Danger Zone"),
            symbolName: "trash",
            accentColor: .systemRed
        )
        let row = PasteraPreferenceSettingRowView(
            title: String(localized: "Clear History"),
            subtitle: pasteraPreferenceString("Delete all history stored on this device."),
            control: clearHistoryButton
        )
        group.addRow(row)
        addGroup(group, anchorID: "history.clearAll")
    }

    @objc private func limitFieldCommitted(_ sender: NSTextField) {
        commitLimitField(sender)
    }

    private func commitLimitField(_ field: NSTextField) {
        defer { invalidateContentSize() }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            errorLabel(for: field).isHidden = false
            return
        }
        let key = defaultsKey(for: field)
        let previousValue = currentLimit(forKey: key)
        let normalizedValue = HistoryRetentionSettings.clampedMediaHistoryLimit(value)
        AppEnvironment.current.defaults.set(normalizedValue, forKey: key)
        field.stringValue = String(normalizedValue)
        errorLabel(for: field).isHidden = true
        guard normalizedValue != previousValue else { return }
        pasteboardHistoryRepository.pruneHistories(settings: HistoryRetentionSettings.current())
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === imageLimitField || field === fileLimitField else { return }
        commitLimitField(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
              let field = control as? NSTextField,
              field === imageLimitField || field === fileLimitField else { return false }
        field.stringValue = String(currentLimit(forKey: defaultsKey(for: field)))
        errorLabel(for: field).isHidden = true
        invalidateContentSize()
        return true
    }

    private func defaultsKey(for field: NSTextField) -> String {
        field === imageLimitField
            ? Constants.UserDefaults.maxImageHistorySize
            : Constants.UserDefaults.maxFileHistorySize
    }

    private func currentLimit(forKey key: String) -> Int {
        HistoryRetentionSettings.mediaHistoryLimit(forKey: key)
    }

    private func errorLabel(for field: NSTextField) -> NSTextField {
        field === imageLimitField ? imageLimitErrorLabel : fileLimitErrorLabel
    }

    @objc private func copySameHistoryChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.copySameHistory)
        overwriteSameHistoryButton.isEnabled = sender.state == .on
    }

    @objc private func overwriteSameHistoryChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.overwriteSameHistory)
    }

    @objc private func storeTypeChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        storeTypes[key] = NSNumber(value: sender.state == .on)
        AppEnvironment.current.defaults.set(storeTypes, forKey: Constants.UserDefaults.storeTypes)
        updateFilePreviewButtonStates()
    }

    @objc private func filePreviewTypeChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        filePreviewTypes[key] = NSNumber(value: sender.state == .on)
        AppEnvironment.current.defaults.set(filePreviewTypes, forKey: Constants.UserDefaults.filePreviewTypes)
    }

    private func updateFilePreviewButtonStates() {
        let filesEnabled = dictionaryValue(storeTypes, key: PasteboardAvailableType.filenames.rawValue)
        filePreviewButtons.forEach { $0.isEnabled = filesEnabled }
    }

    private static func makeErrorLabel() -> NSTextField {
        let label = NSTextField(labelWithString: pasteraPreferenceString("Enter an integer."))
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.isHidden = true
        return label
    }
}

private func dictionaryValue(_ dictionary: [String: Any], key: String) -> Bool {
    if let number = dictionary[key] as? NSNumber { return number.boolValue }
    if let value = dictionary[key] as? Bool { return value }
    return true
}
