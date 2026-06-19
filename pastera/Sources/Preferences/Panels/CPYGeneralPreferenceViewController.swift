//
//  CPYGeneralPreferenceViewController.swift
//
//  Clipy
//

import Cocoa

final class CPYGeneralPreferenceViewController: NSViewController {
    private let clearHistoryButton = NSButton(title: String(localized: "Clear History"), target: nil, action: #selector(AppDelegate.clearAllHistory))
    private let opacityLabel = NSTextField(labelWithString: String(localized: "Transparency"))
    private let opacitySlider = NSSlider()
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private let menuTitleLengthLabel = NSTextField(labelWithString: localizedPreferenceString("Number of characters in the menu:"))
    private let menuTitleLengthField = NSTextField()
    private let menuTitleLengthUnitLabel = NSTextField(labelWithString: localizedPreferenceString("chars"))
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
    private var didInstallAdditionalControls = false
    private weak var launchOnLoginButton: NSButton?

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

        [menuTitleLengthLabel].forEach {
            $0.textColor = .labelColor
            $0.font = .systemFont(ofSize: NSFont.systemFontSize)
        }

        [menuTitleLengthUnitLabel].forEach {
            $0.textColor = .secondaryLabelColor
            $0.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }

        copySameHistoryButton.bindValue(to: Constants.UserDefaults.copySameHistory)
        overwriteSameHistoryButton.bindValue(to: Constants.UserDefaults.overwriteSameHistory)
        overwriteSameHistoryButton.bindEnabled(to: Constants.UserDefaults.copySameHistory)
        menuTitleLengthField.bindValue(to: Constants.UserDefaults.maxMenuItemTitleLength)
        showColorPreviewButton.bindValue(to: Constants.UserDefaults.showColorPreviewInTheMenu)

        [
            clearHistoryButton,
            opacityLabel,
            opacitySlider,
            opacityValueLabel,
            menuTitleLengthLabel,
            menuTitleLengthField,
            menuTitleLengthUnitLabel,
            copySameHistoryButton,
            overwriteSameHistoryButton,
            showColorPreviewButton
        ].forEach {
            $0.autoresizingMask = [.maxXMargin, .maxYMargin]
            CPYWindowAppearance.apply(to: $0)
            view.addSubview($0)
        }
        layoutAdditionalControls()
    }

    private func configureNumberField(_ textField: NSTextField, minimum: Int) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.minimum = NSNumber(value: minimum)
        textField.formatter = formatter
        textField.alignment = .right
        textField.isEditable = true
        textField.isSelectable = true
    }

    private func layoutAdditionalControls() {
        let contentLeftX: CGFloat = 59
        let topY: CGFloat = 230
        let controlMaxX = min(view.bounds.width - 18, 438)
        let checkboxHeight: CGFloat = 18
        let checkboxWidth = max(180, controlMaxX - contentLeftX)
        let clearHistoryButtonSize = NSSize(width: 118, height: 24)
        let numberFieldSize = NSSize(width: 58, height: 22)
        let unitLabelSize = NSSize(width: 58, height: 14)
        let inputX = min(controlMaxX - unitLabelSize.width - numberFieldSize.width - 8, contentLeftX + 273)
        let inputLabelWidth = max(160, inputX - contentLeftX - 8)

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

        copySameHistoryButton.frame = NSRect(x: contentLeftX, y: topY - 136, width: checkboxWidth, height: checkboxHeight)
        overwriteSameHistoryButton.frame = NSRect(x: contentLeftX + 15, y: topY - 166, width: checkboxWidth - 15, height: checkboxHeight)
        showColorPreviewButton.frame = NSRect(x: contentLeftX, y: topY - 196, width: checkboxWidth, height: checkboxHeight)
    }

    private func updateOpacityControls(opacity: Double = CPYWindowAppearance.opacity()) {
        let normalizedOpacity = CPYWindowAppearance.normalizedOpacity(opacity)
        opacitySlider.doubleValue = normalizedOpacity
        opacityValueLabel.stringValue = "\(Int(round(normalizedOpacity * 100)))%"
    }
}

private func localizedPreferenceString(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "CPYGeneralPreferenceViewController")
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
