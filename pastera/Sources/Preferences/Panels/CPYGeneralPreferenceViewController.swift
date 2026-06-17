//
//  CPYGeneralPreferenceViewController.swift
//
//  Clipy
//

import Cocoa

final class CPYGeneralPreferenceViewController: NSViewController {
    private let clearHistoryButton = NSButton(title: String(localized: "Clear History"), target: nil, action: #selector(AppDelegate.clearAllHistory))
    private let clearHistoryWarningButton = NSButton(
        checkboxWithTitle: String(localized: "Show alert panel before clear history"),
        target: nil,
        action: nil
    )
    private let opacityLabel = NSTextField(labelWithString: String(localized: "Transparency"))
    private let opacitySlider = NSSlider()
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private var didInstallAdditionalControls = false
    private weak var launchOnLoginButton: NSButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        enforceRecentUseHistorySort()
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

        clearHistoryWarningButton.font = .systemFont(ofSize: NSFont.systemFontSize)
        clearHistoryWarningButton.bind(
            .value,
            to: NSUserDefaultsController.shared,
            withKeyPath: "values.\(Constants.UserDefaults.showAlertBeforeClearHistory)",
            options: nil
        )

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

        [clearHistoryButton, clearHistoryWarningButton, opacityLabel, opacitySlider, opacityValueLabel].forEach {
            $0.autoresizingMask = [.maxXMargin, .maxYMargin]
            CPYWindowAppearance.apply(to: $0)
            view.addSubview($0)
        }
        layoutAdditionalControls()
    }

    private func enforceRecentUseHistorySort() {
        AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.reorderClipsAfterPasting)
    }

    private func layoutAdditionalControls() {
        let contentLeftX: CGFloat = 59
        let topY: CGFloat = 126
        let controlMaxX = min(view.bounds.width - 18, 408)
        let checkboxHeight: CGFloat = 18
        let checkboxWidth = max(180, controlMaxX - contentLeftX)
        let clearHistoryButtonSize = NSSize(width: 118, height: 24)

        launchOnLoginButton?.frame = NSRect(
            x: contentLeftX,
            y: topY,
            width: checkboxWidth,
            height: checkboxHeight
        )

        clearHistoryButton.frame = NSRect(
            x: contentLeftX,
            y: topY - 38,
            width: clearHistoryButtonSize.width,
            height: clearHistoryButtonSize.height
        )

        clearHistoryWarningButton.frame = NSRect(x: contentLeftX, y: topY - 68, width: checkboxWidth, height: checkboxHeight)

        let opacityY = topY - 112
        opacityLabel.frame = NSRect(x: contentLeftX, y: opacityY, width: 80, height: checkboxHeight)
        opacitySlider.frame = NSRect(x: contentLeftX + 98, y: opacityY - 4, width: 176, height: 24)
        opacityValueLabel.frame = NSRect(x: contentLeftX + 292, y: opacityY, width: 42, height: checkboxHeight)
    }

    private func updateOpacityControls(opacity: Double = CPYWindowAppearance.opacity()) {
        let normalizedOpacity = CPYWindowAppearance.normalizedOpacity(opacity)
        opacitySlider.doubleValue = normalizedOpacity
        opacityValueLabel.stringValue = "\(Int(round(normalizedOpacity * 100)))%"
    }
}

#if DEBUG
extension CPYGeneralPreferenceViewController {
    var opacityLabelStringForTesting: String {
        opacityLabel.stringValue
    }
}
#endif
