//
//  CPYGeneralPreferenceViewController.swift
//
//  Clipy
//

import Cocoa
import Dependencies

final class CPYGeneralPreferenceViewController: NSViewController, NSTextFieldDelegate {
    private let clearHistoryButton = NSButton(title: String(localized: "Clear History"), target: nil, action: #selector(AppDelegate.clearAllHistory))
    private let opacityLabel = NSTextField(labelWithString: String(localized: "Transparency"))
    private let opacitySlider = NSSlider()
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private let menuTitleLengthLabel = NSTextField(labelWithString: localizedPreferenceString("Number of characters in the menu:"))
    private let menuTitleLengthField = NSTextField()
    private let menuTitleLengthUnitLabel = NSTextField(labelWithString: localizedPreferenceString("chars"))
    private let mediaHistoryLimitLabel = NSTextField(labelWithString: localizedPreferenceString("Image/file limit:"))
    private let mediaImageLimitLabel = NSTextField(labelWithString: localizedPreferenceString("Images"))
    private let mediaImageLimitField = NSTextField()
    private let mediaImageLimitUnitLabel = NSTextField(labelWithString: localizedPreferenceString("items"))
    private let mediaFileLimitLabel = NSTextField(labelWithString: localizedPreferenceString("Files"))
    private let mediaFileLimitField = NSTextField()
    private let mediaFileLimitUnitLabel = NSTextField(labelWithString: localizedPreferenceString("items"))
    private let copySameHistoryButton = NSButton(
        checkboxWithTitle: localizedPreferenceString("Place already copied history at the top"),
        target: nil,
        action: nil
    )
    private let overwriteSameHistoryButton = NSButton(
        checkboxWithTitle: localizedPreferenceString("Move instead of copying (removes the older one from the list)"),
        target: nil,
        action: nil
    )
    private let showColorPreviewButton = NSButton(
        checkboxWithTitle: localizedPreferenceString("Show color code preview"),
        target: nil,
        action: nil
    )
    private let automaticPasteButton = NSButton(
        checkboxWithTitle: localizedPreferenceString("Automatic Paste"),
        target: nil,
        action: nil
    )
    private let automaticPasteInfoButton = NSButton(title: "", target: nil, action: nil)
    private let suspendRemoteHotKeysButton = NSButton(
        checkboxWithTitle: localizedPreferenceString(
            "Pause shortcuts during remote control",
            value: "Pause shortcuts during remote control"
        ),
        target: nil,
        action: nil
    )
    private var didInstallAdditionalControls = false
    private weak var launchOnLoginButton: NSButton?
    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository
    var automaticPastePermissionRequester: () -> Void = {
        let accessibilityService = AppEnvironment.current.accessibilityService
        guard !accessibilityService.isAccessibilityEnabled(isPrompt: false) else { return }

        _ = accessibilityService.isAccessibilityEnabled(isPrompt: true)
        _ = accessibilityService.openAccessibilitySettingWindow()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installAdditionalControls()
        updateOpacityControls()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutAdditionalControls()
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        CPYWindowAppearance.setOpacity(sender.doubleValue)
        updateOpacityControls()
    }

    @objc private func automaticPasteButtonChanged(_ sender: NSButton) {
        guard sender.state == .on else { return }
        automaticPastePermissionRequester()
    }

    @objc private func showAutomaticPasteInfo(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = localizedPreferenceString(
            "Why Accessibility is required",
            value: "Why Accessibility is required"
        )
        alert.informativeText = automaticPastePermissionDescription()
        alert.addButton(withTitle: localizedPreferenceString("OK", value: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func installAdditionalControls() {
        guard !didInstallAdditionalControls else { return }
        didInstallAdditionalControls = true
        launchOnLoginButton = view.subviews.compactMap { $0 as? NSButton }.first

        view.subviews.forEach { subview in
            CPYWindowAppearance.apply(to: subview)
        }
        CPYWindowAppearance.apply(to: view)

        clearHistoryButton.bezelStyle = .rounded
        clearHistoryButton.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        clearHistoryButton.setButtonType(.momentaryPushIn)

        opacityLabel.textColor = .labelColor
        opacityLabel.font = .systemFont(ofSize: NSFont.systemFontSize)

        opacitySlider.minValue = CPYWindowAppearance.minimumOpacity
        opacitySlider.maxValue = CPYWindowAppearance.maximumOpacity
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged(_:))
        opacitySlider.isContinuous = true

        opacityValueLabel.alignment = .right
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        configureNumberField(menuTitleLengthField, minimum: 1)
        configureNumberField(
            mediaImageLimitField,
            minimum: HistoryRetentionSettings.minimumMediaHistoryLimit,
            maximum: HistoryRetentionSettings.maximumMediaHistoryLimit
        )
        configureNumberField(
            mediaFileLimitField,
            minimum: HistoryRetentionSettings.minimumMediaHistoryLimit,
            maximum: HistoryRetentionSettings.maximumMediaHistoryLimit
        )
        mediaImageLimitField.delegate = self
        mediaFileLimitField.delegate = self

        [menuTitleLengthLabel, mediaHistoryLimitLabel, mediaImageLimitLabel, mediaFileLimitLabel].forEach {
            $0.textColor = .labelColor
            $0.font = .systemFont(ofSize: NSFont.systemFontSize)
        }

        [menuTitleLengthUnitLabel, mediaImageLimitUnitLabel, mediaFileLimitUnitLabel].forEach {
            $0.textColor = .secondaryLabelColor
            $0.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }

        copySameHistoryButton.bindValue(to: Constants.UserDefaults.copySameHistory)
        overwriteSameHistoryButton.bindValue(to: Constants.UserDefaults.overwriteSameHistory)
        overwriteSameHistoryButton.bindEnabled(to: Constants.UserDefaults.copySameHistory)
        menuTitleLengthField.bindValue(to: Constants.UserDefaults.maxMenuItemTitleLength)
        mediaImageLimitField.bindValue(to: Constants.UserDefaults.maxImageHistorySize)
        mediaFileLimitField.bindValue(to: Constants.UserDefaults.maxFileHistorySize)
        showColorPreviewButton.bindValue(to: Constants.UserDefaults.showColorPreviewInTheMenu)
        automaticPasteButton.bindValue(to: Constants.UserDefaults.inputPasteCommand)
        automaticPasteButton.target = self
        automaticPasteButton.action = #selector(automaticPasteButtonChanged(_:))
        automaticPasteButton.setAccessibilityLabel(localizedPreferenceString("Automatic Paste"))
        suspendRemoteHotKeysButton.bindValue(to: Constants.HotKey.suspendDuringRemoteSession)
        suspendRemoteHotKeysButton.setAccessibilityLabel(localizedPreferenceString(
            "Pause shortcuts during remote control",
            value: "Pause shortcuts during remote control"
        ))

        automaticPasteInfoButton.bezelStyle = .helpButton
        automaticPasteInfoButton.target = self
        automaticPasteInfoButton.action = #selector(showAutomaticPasteInfo(_:))
        automaticPasteInfoButton.toolTip = automaticPastePermissionDescription()
        automaticPasteInfoButton.setAccessibilityLabel(localizedPreferenceString("Automatic Paste Permission Info"))

        [
            clearHistoryButton,
            opacityLabel,
            opacitySlider,
            opacityValueLabel,
            menuTitleLengthLabel,
            menuTitleLengthField,
            menuTitleLengthUnitLabel,
            mediaHistoryLimitLabel,
            mediaImageLimitLabel,
            mediaImageLimitField,
            mediaImageLimitUnitLabel,
            mediaFileLimitLabel,
            mediaFileLimitField,
            mediaFileLimitUnitLabel,
            copySameHistoryButton,
            overwriteSameHistoryButton,
            showColorPreviewButton,
            automaticPasteButton,
            automaticPasteInfoButton,
            suspendRemoteHotKeysButton
        ].forEach {
            $0.autoresizingMask = [.maxXMargin, .maxYMargin]
            CPYWindowAppearance.apply(to: $0)
            view.addSubview($0)
        }
        layoutAdditionalControls()
    }

    private func configureNumberField(_ textField: NSTextField, minimum: Int, maximum: Int? = nil) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.minimum = NSNumber(value: minimum)
        if let maximum {
            formatter.maximum = NSNumber(value: maximum)
        }
        textField.formatter = formatter
        textField.alignment = .right
        textField.isEditable = true
        textField.isSelectable = true
    }

    private func layoutAdditionalControls() {
        let contentLeftX: CGFloat = 59
        let topY: CGFloat = 308
        let controlMaxX = min(view.bounds.width - 18, 438)
        let checkboxHeight: CGFloat = 18
        let checkboxWidth = max(180, controlMaxX - contentLeftX)
        let automaticPasteWidth = max(1, ceil(automaticPasteButton.intrinsicContentSize.width))
        let helpButtonSize = NSSize(width: 18, height: 18)
        let clearHistoryButtonSize = NSSize(width: 118, height: 24)
        let numberFieldSize = NSSize(width: 58, height: 22)
        let unitLabelSize = NSSize(width: 58, height: 14)
        let inputX = min(controlMaxX - unitLabelSize.width - numberFieldSize.width - 8, contentLeftX + 273)
        let inputLabelWidth = max(160, inputX - contentLeftX - 8)
        let mediaNumberFieldSize = NSSize(width: 44, height: 22)
        let mediaKindLabelWidth: CGFloat = 42
        let mediaUnitLabelWidth: CGFloat = 32
        let mediaElementGap: CGFloat = 4
        let mediaGroupGap: CGFloat = 10
        let mediaGroupWidth = mediaKindLabelWidth + mediaElementGap
            + mediaNumberFieldSize.width + mediaElementGap
            + mediaUnitLabelWidth
        let mediaFirstKindX = max(contentLeftX + 110, controlMaxX - mediaGroupWidth * 2 - mediaGroupGap)
        let mediaLabelWidth = mediaFirstKindX - contentLeftX - 8
        let mediaFirstFieldX = mediaFirstKindX + mediaKindLabelWidth + mediaElementGap
        let mediaFirstUnitX = mediaFirstFieldX + mediaNumberFieldSize.width + mediaElementGap
        let mediaSecondKindX = mediaFirstKindX + mediaGroupWidth + mediaGroupGap
        let mediaSecondFieldX = mediaSecondKindX + mediaKindLabelWidth + mediaElementGap
        let mediaSecondUnitX = mediaSecondFieldX + mediaNumberFieldSize.width + mediaElementGap

        launchOnLoginButton?.frame = NSRect(
            x: contentLeftX,
            y: topY,
            width: checkboxWidth,
            height: checkboxHeight
        )

        clearHistoryButton.frame = NSRect(
            x: contentLeftX,
            y: topY - 36,
            width: clearHistoryButtonSize.width,
            height: clearHistoryButtonSize.height
        )

        let opacityY = topY - 68
        opacityLabel.frame = NSRect(x: contentLeftX, y: opacityY, width: 80, height: checkboxHeight)
        opacitySlider.frame = NSRect(x: contentLeftX + 98, y: opacityY - 4, width: 176, height: 24)
        opacityValueLabel.frame = NSRect(x: contentLeftX + 292, y: opacityY, width: 42, height: checkboxHeight)

        let menuTitleLengthY = topY - 106
        menuTitleLengthLabel.frame = NSRect(x: contentLeftX, y: menuTitleLengthY + 2, width: inputLabelWidth, height: checkboxHeight)
        menuTitleLengthField.frame = NSRect(x: inputX, y: menuTitleLengthY, width: numberFieldSize.width, height: numberFieldSize.height)
        menuTitleLengthUnitLabel.frame = NSRect(
            x: inputX + numberFieldSize.width + 8,
            y: menuTitleLengthY + 4,
            width: unitLabelSize.width,
            height: unitLabelSize.height
        )

        let mediaHistoryLimitY = topY - 140
        mediaHistoryLimitLabel.frame = NSRect(x: contentLeftX, y: mediaHistoryLimitY + 2, width: mediaLabelWidth, height: checkboxHeight)
        mediaImageLimitLabel.frame = NSRect(x: mediaFirstKindX, y: mediaHistoryLimitY + 2, width: mediaKindLabelWidth, height: checkboxHeight)
        mediaImageLimitField.frame = NSRect(x: mediaFirstFieldX, y: mediaHistoryLimitY, width: mediaNumberFieldSize.width, height: mediaNumberFieldSize.height)
        mediaImageLimitUnitLabel.frame = NSRect(x: mediaFirstUnitX, y: mediaHistoryLimitY + 4, width: mediaUnitLabelWidth, height: unitLabelSize.height)
        mediaFileLimitLabel.frame = NSRect(x: mediaSecondKindX, y: mediaHistoryLimitY + 2, width: mediaKindLabelWidth, height: checkboxHeight)
        mediaFileLimitField.frame = NSRect(x: mediaSecondFieldX, y: mediaHistoryLimitY, width: mediaNumberFieldSize.width, height: mediaNumberFieldSize.height)
        mediaFileLimitUnitLabel.frame = NSRect(x: mediaSecondUnitX, y: mediaHistoryLimitY + 4, width: mediaUnitLabelWidth, height: unitLabelSize.height)

        copySameHistoryButton.frame = NSRect(x: contentLeftX, y: topY - 170, width: checkboxWidth, height: checkboxHeight)
        overwriteSameHistoryButton.frame = NSRect(x: contentLeftX + 15, y: topY - 200, width: checkboxWidth - 15, height: checkboxHeight)
        showColorPreviewButton.frame = NSRect(x: contentLeftX, y: topY - 230, width: checkboxWidth, height: checkboxHeight)
        automaticPasteButton.frame = NSRect(x: contentLeftX, y: topY - 260, width: automaticPasteWidth, height: checkboxHeight)
        automaticPasteInfoButton.frame = NSRect(
            x: contentLeftX + automaticPasteWidth + 4,
            y: topY - 260,
            width: helpButtonSize.width,
            height: helpButtonSize.height
        )
        suspendRemoteHotKeysButton.frame = NSRect(
            x: contentLeftX,
            y: topY - 290,
            width: checkboxWidth,
            height: checkboxHeight
        )
    }

    private func updateOpacityControls(opacity: Double = CPYWindowAppearance.opacity()) {
        let normalizedOpacity = CPYWindowAppearance.normalizedOpacity(opacity)
        opacitySlider.doubleValue = normalizedOpacity
        opacityValueLabel.stringValue = "\(Int(round(normalizedOpacity * 100)))%"
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField,
              textField === mediaImageLimitField || textField === mediaFileLimitField else {
            return
        }
        let settings = normalizeMediaHistoryLimitFields()
        pasteboardHistoryRepository.pruneHistories(settings: settings)
    }

    private func normalizeMediaHistoryLimitFields() -> HistoryRetentionSettings {
        let defaults = AppEnvironment.current.defaults
        let imageLimit = HistoryRetentionSettings.clampedMediaHistoryLimit(
            mediaImageLimitField.integerValue
        )
        let fileLimit = HistoryRetentionSettings.clampedMediaHistoryLimit(
            mediaFileLimitField.integerValue
        )
        defaults.set(imageLimit, forKey: Constants.UserDefaults.maxImageHistorySize)
        defaults.set(fileLimit, forKey: Constants.UserDefaults.maxFileHistorySize)
        mediaImageLimitField.integerValue = imageLimit
        mediaFileLimitField.integerValue = fileLimit
        return HistoryRetentionSettings.current(defaults: defaults)
    }
}

private func automaticPastePermissionDescription() -> String {
    localizedPreferenceString(
        "Automatic Paste Permission Description",
        value: "When Automatic Paste is enabled, Pastera restores the target app and sends Command+V after you choose a history item or snippet. macOS requires Accessibility permission for that action. When this is off, Pastera only copies to the clipboard and you paste manually."
    )
}

private func localizedPreferenceString(_ key: String, value: String? = nil) -> String {
    Bundle.main.localizedString(forKey: key, value: value ?? key, table: "CPYGeneralPreferenceViewController")
}

private extension NSControl {
    func bindValue(to defaultKey: String) {
        bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values.\(defaultKey)", options: nil)
    }

    func bindEnabled(to defaultKey: String) {
        bind(.enabled, to: NSUserDefaultsController.shared, withKeyPath: "values.\(defaultKey)", options: nil)
    }
}

#if DEBUG
extension CPYGeneralPreferenceViewController {
    var opacityLabelStringForTesting: String {
        opacityLabel.stringValue
    }
}
#endif
