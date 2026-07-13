//
//  CPYGeneralPreferenceViewController.swift
//
//  Pastera
//

import AppKit

final class CPYGeneralPreferenceViewController: PasteraPreferencePageViewController, NSTextFieldDelegate {
    private let defaults: UserDefaults
    private let remoteSessionHotKeyRefresher: () -> Void
    private var launchOnLoginButton = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )
    private var opacityLabel = NSTextField(labelWithString: String(localized: "Transparency"))
    private var opacitySlider = NSSlider()
    private var opacityValueLabel = NSTextField(labelWithString: "")
    private var menuTitleLengthField = NSTextField()
    private var menuTitleLengthErrorLabel = CPYGeneralPreferenceViewController.makeErrorLabel()
    private var showColorPreviewButton = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )
    private var automaticPasteButton = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )
    private var automaticPasteInfoButton = NSButton(title: "", target: nil, action: nil)
    private var openSystemSettingsButton = NSButton(
        title: localizedGeneralPreferenceString("Open System Settings", value: "Open System Settings"),
        target: nil,
        action: nil
    )
    private var permissionGuidanceStack = NSStackView()
    private var suspendRemoteHotKeysButton = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )

    var automaticPastePermissionChecker: () -> Bool = {
        AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false)
    }
    var automaticPastePermissionRequester: () -> Void = {
        let accessibilityService = AppEnvironment.current.accessibilityService
        guard !accessibilityService.isAccessibilityEnabled(isPrompt: false) else { return }
        _ = accessibilityService.isAccessibilityEnabled(isPrompt: true)
        _ = accessibilityService.openAccessibilitySettingWindow()
    }

    init(
        defaults: UserDefaults = AppEnvironment.current.defaults,
        remoteSessionHotKeyRefresher: @escaping () -> Void = {
            AppEnvironment.current.hotKeyService.refreshRemoteSessionHotKeyState()
        }
    ) {
        self.defaults = defaults
        self.remoteSessionHotKeyRefresher = remoteSessionHotKeyRefresher
        super.init(paneID: .general, title: pasteraPreferenceString("General"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        resetViewState()
        super.loadView()
        configureControls()
        buildStartupGroup()
        buildAppearanceGroup()
        buildAutomaticPasteGroup()
        buildRemoteControlGroup()
    }

    private func configureControls() {
        configureDefaultsButton(
            launchOnLoginButton,
            key: Constants.UserDefaults.loginItem,
            accessibilityLabel: localizedGeneralPreferenceString("Launch on Login")
        )
        configureDefaultsButton(
            showColorPreviewButton,
            key: Constants.UserDefaults.showColorPreviewInTheMenu,
            accessibilityLabel: localizedGeneralPreferenceString("Show color code preview")
        )
        configureDefaultsButton(
            suspendRemoteHotKeysButton,
            key: Constants.HotKey.suspendDuringRemoteSession,
            accessibilityLabel: localizedGeneralPreferenceString(
                "Pause shortcuts during remote control",
                value: "Pause shortcuts during remote control"
            )
        )

        opacitySlider.minValue = CPYWindowAppearance.minimumOpacity
        opacitySlider.maxValue = CPYWindowAppearance.maximumOpacity
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged(_:))
        opacitySlider.isContinuous = true
        opacitySlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        opacityValueLabel.alignment = .right
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        opacityValueLabel.textColor = .secondaryLabelColor
        updateOpacityControls()

        menuTitleLengthField.alignment = .right
        menuTitleLengthField.delegate = self
        menuTitleLengthField.target = self
        menuTitleLengthField.action = #selector(menuTitleLengthCommitted(_:))
        menuTitleLengthField.stringValue = String(currentMenuTitleLength())
        menuTitleLengthField.setAccessibilityLabel(pasteraPreferenceString("Menu Title Length"))
        menuTitleLengthField.widthAnchor.constraint(equalToConstant: 58).isActive = true

        automaticPasteButton.target = self
        automaticPasteButton.action = #selector(automaticPasteButtonChanged(_:))
        automaticPasteButton.setAccessibilityLabel(localizedGeneralPreferenceString("Automatic Paste"))
        automaticPasteInfoButton.bezelStyle = .helpButton
        automaticPasteInfoButton.target = self
        automaticPasteInfoButton.action = #selector(showAutomaticPasteInfo(_:))
        automaticPasteInfoButton.toolTip = automaticPastePermissionDescription()
        automaticPasteInfoButton.setAccessibilityLabel(
            localizedGeneralPreferenceString("Automatic Paste Permission Info")
        )
        openSystemSettingsButton.target = self
        openSystemSettingsButton.action = #selector(openAutomaticPasteSystemSettings(_:))
        openSystemSettingsButton.bezelStyle = .rounded
        configurePermissionGuidance()
        refreshAutomaticPasteState()
    }

    private func configureDefaultsButton(_ button: NSButton, key: String, accessibilityLabel: String) {
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.state = defaults.bool(forKey: key) ? .on : .off
        button.target = self
        button.action = #selector(defaultsButtonChanged(_:))
        button.setAccessibilityLabel(accessibilityLabel)
    }

    private func configurePermissionGuidance() {
        let status = PasteraPreferenceStatusView(
            text: automaticPastePermissionDescription(),
            style: .warning
        )
        permissionGuidanceStack.orientation = .vertical
        permissionGuidanceStack.alignment = .trailing
        permissionGuidanceStack.spacing = 8
        permissionGuidanceStack.addArrangedSubview(status)
        permissionGuidanceStack.addArrangedSubview(openSystemSettingsButton)
        permissionGuidanceStack.isHidden = true
    }

    private func buildStartupGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Startup"),
            symbolName: "power",
            accentColor: .systemGreen
        )
        let row = PasteraPreferenceSettingRowView(
            title: localizedGeneralPreferenceString("Launch on Login"),
            control: launchOnLoginButton
        )
        group.addRow(row)
        addGroup(group)
        registerAnchor("general.launchAtLogin", view: row)
    }

    private func buildAppearanceGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Menu Appearance"),
            symbolName: "slider.horizontal.3",
            accentColor: .systemBlue
        )
        let opacityControl = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityControl.orientation = .horizontal
        opacityControl.alignment = .centerY
        opacityControl.spacing = 10
        let opacityRow = PasteraPreferenceSettingRowView(
            title: opacityLabel.stringValue,
            control: opacityControl
        )
        let titleLengthRow = PasteraPreferenceSettingRowView(
            title: localizedGeneralPreferenceString("Number of characters in the menu:"),
            control: makeTitleLengthControl()
        )
        let colorPreviewRow = PasteraPreferenceSettingRowView(
            title: localizedGeneralPreferenceString("Show color code preview"),
            control: showColorPreviewButton
        )
        group.addRow(opacityRow)
        group.addRow(titleLengthRow)
        group.addRow(colorPreviewRow)
        addGroup(group)
        registerAnchor("general.windowOpacity", view: opacityRow)
        registerAnchor("general.titleLength", view: titleLengthRow)
        registerAnchor("general.colorPreview", view: colorPreviewRow)
    }

    private func makeTitleLengthControl() -> NSView {
        let unitLabel = NSTextField(labelWithString: localizedGeneralPreferenceString("chars"))
        unitLabel.textColor = .secondaryLabelColor
        let valueRow = NSStackView(views: [menuTitleLengthField, unitLabel])
        valueRow.orientation = .horizontal
        valueRow.alignment = .centerY
        valueRow.spacing = 6
        let stack = NSStackView(views: [valueRow, menuTitleLengthErrorLabel])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 3
        return stack
    }

    private func buildAutomaticPasteGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Automatic Paste"),
            symbolName: "clipboard",
            accentColor: .systemTeal
        )
        let buttonRow = NSStackView(views: [automaticPasteButton, automaticPasteInfoButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 6
        let control = NSStackView(views: [buttonRow, permissionGuidanceStack])
        control.orientation = .vertical
        control.alignment = .trailing
        control.spacing = 10
        let row = PasteraPreferenceSettingRowView(
            title: localizedGeneralPreferenceString("Automatic Paste"),
            subtitle: localizedGeneralPreferenceString(
                "Automatic Paste Permission Short Description",
                value: "Paste automatically after selecting a history item."
            ),
            control: control
        )
        group.addRow(row)
        addGroup(group)
        registerAnchor("general.autoPaste", view: row)
    }

    private func buildRemoteControlGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Remote Control"),
            symbolName: "command",
            accentColor: .systemPurple
        )
        let row = PasteraPreferenceSettingRowView(
            title: localizedGeneralPreferenceString(
                "Pause shortcuts during remote control",
                value: "Pause shortcuts during remote control"
            ),
            control: suspendRemoteHotKeysButton
        )
        group.addRow(row)
        addGroup(group)
        registerAnchor("general.pauseHotkeys", view: row)
    }

    @objc private func defaultsButtonChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        defaults.set(sender.state == .on, forKey: key)
        if key == Constants.HotKey.suspendDuringRemoteSession {
            remoteSessionHotKeyRefresher()
        }
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        CPYWindowAppearance.setOpacity(sender.doubleValue)
        updateOpacityControls()
    }

    private func updateOpacityControls(opacity: Double = CPYWindowAppearance.opacity()) {
        let normalizedOpacity = CPYWindowAppearance.normalizedOpacity(opacity)
        opacitySlider.doubleValue = normalizedOpacity
        opacityValueLabel.stringValue = "\(Int(round(normalizedOpacity * 100)))%"
    }

    @objc private func menuTitleLengthCommitted(_ sender: NSTextField) {
        commitMenuTitleLength(sender)
    }

    private func commitMenuTitleLength(_ field: NSTextField) {
        defer { invalidateContentSize() }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            menuTitleLengthErrorLabel.isHidden = false
            return
        }
        let normalizedValue = max(1, value)
        defaults.set(normalizedValue, forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        field.stringValue = String(normalizedValue)
        menuTitleLengthErrorLabel.isHidden = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === menuTitleLengthField else { return }
        commitMenuTitleLength(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
              let field = control as? NSTextField,
              field === menuTitleLengthField else { return false }
        field.stringValue = String(currentMenuTitleLength())
        menuTitleLengthErrorLabel.isHidden = true
        invalidateContentSize()
        return true
    }

    private func currentMenuTitleLength() -> Int {
        max(1, defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength))
    }

    @objc private func automaticPasteButtonChanged(_ sender: NSButton) {
        defer { invalidateContentSize() }
        guard sender.state == .on else {
            defaults.set(false, forKey: Constants.UserDefaults.inputPasteCommand)
            permissionGuidanceStack.isHidden = true
            return
        }
        guard automaticPastePermissionChecker() else {
            defaults.set(false, forKey: Constants.UserDefaults.inputPasteCommand)
            sender.state = .off
            permissionGuidanceStack.isHidden = false
            automaticPastePermissionRequester()
            return
        }
        defaults.set(true, forKey: Constants.UserDefaults.inputPasteCommand)
        permissionGuidanceStack.isHidden = true
    }

    private func refreshAutomaticPasteState() {
        defer { invalidateContentSize() }
        let isEnabled = defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand)
        guard !isEnabled || automaticPastePermissionChecker() else {
            defaults.set(false, forKey: Constants.UserDefaults.inputPasteCommand)
            automaticPasteButton.state = .off
            permissionGuidanceStack.isHidden = false
            return
        }
        automaticPasteButton.state = isEnabled ? .on : .off
    }

    @objc private func openAutomaticPasteSystemSettings(_ sender: NSButton) {
        automaticPastePermissionRequester()
    }

    @objc private func showAutomaticPasteInfo(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = localizedGeneralPreferenceString(
            "Why Accessibility is required",
            value: "Why Accessibility is required"
        )
        alert.informativeText = automaticPastePermissionDescription()
        alert.addButton(withTitle: localizedGeneralPreferenceString("OK", value: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func makeErrorLabel() -> NSTextField {
        let label = NSTextField(labelWithString: pasteraPreferenceString("Enter an integer."))
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.isHidden = true
        return label
    }
}

private extension CPYGeneralPreferenceViewController {
    func resetViewState() {
        removeExistingContent()
        launchOnLoginButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        opacityLabel = NSTextField(labelWithString: String(localized: "Transparency"))
        opacitySlider = NSSlider()
        opacityValueLabel = NSTextField(labelWithString: "")
        menuTitleLengthField = NSTextField()
        menuTitleLengthErrorLabel = Self.makeErrorLabel()
        showColorPreviewButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        automaticPasteButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        automaticPasteInfoButton = NSButton(title: "", target: nil, action: nil)
        openSystemSettingsButton = NSButton(
            title: localizedGeneralPreferenceString("Open System Settings", value: "Open System Settings"),
            target: nil,
            action: nil
        )
        permissionGuidanceStack = NSStackView()
        suspendRemoteHotKeysButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    }

    func removeExistingContent() {
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
}

private func automaticPastePermissionDescription() -> String {
    localizedGeneralPreferenceString(
        "Automatic Paste Permission Description",
        value: "When Automatic Paste is enabled, Pastera restores the target app and sends Command+V after you choose a history item or snippet. macOS requires Accessibility permission for that action. When this is off, Pastera only copies to the clipboard and you paste manually."
    )
}

private func localizedGeneralPreferenceString(_ key: String, value: String? = nil) -> String {
    pasteraPreferenceString(key, defaultValue: value)
}

#if DEBUG
extension CPYGeneralPreferenceViewController {
    var opacityLabelStringForTesting: String {
        opacityLabel.stringValue
    }
}
#endif
