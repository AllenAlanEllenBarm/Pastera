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
    private var didInstallAdditionalControls = false

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

        view.subviews.forEach { subview in
            CPYWindowAppearance.apply(to: subview)
        }
        CPYWindowAppearance.apply(to: view)

        clearHistoryButton.bezelStyle = .rounded
        clearHistoryButton.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        clearHistoryButton.setButtonType(.momentaryPushIn)

        opacityLabel.frame = NSRect(x: 270, y: 47, width: 62, height: 18)
        opacityLabel.textColor = .labelColor
        opacityLabel.font = .systemFont(ofSize: NSFont.systemFontSize)

        opacitySlider.frame = NSRect(x: 330, y: 43, width: 92, height: 24)
        opacitySlider.minValue = CPYWindowAppearance.minimumOpacity
        opacitySlider.maxValue = CPYWindowAppearance.maximumOpacity
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged(_:))
        opacitySlider.isContinuous = true

        opacityValueLabel.frame = NSRect(x: 428, y: 47, width: 42, height: 18)
        opacityValueLabel.alignment = .right
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        [clearHistoryButton, opacityLabel, opacitySlider, opacityValueLabel].forEach {
            $0.autoresizingMask = [.maxXMargin, .maxYMargin]
            CPYWindowAppearance.apply(to: $0)
            view.addSubview($0)
        }
        layoutAdditionalControls()
    }

    private func layoutAdditionalControls() {
        let clearHistoryButtonSize = NSSize(width: 118, height: 24)
        let fallbackX: CGFloat = 290
        let fallbackY: CGFloat = 132
        let sectionTitle = view.subviews
            .compactMap { $0 as? NSTextField }
            .first { ["Clipboard History", "剪贴板历史"].contains($0.stringValue) }
        let sortPopup = view.subviews.compactMap { $0 as? NSPopUpButton }.first
        let buttonMaxX = sortPopup?.frame.maxX ?? fallbackX + clearHistoryButtonSize.width
        let buttonMidY = sectionTitle?.frame.midY ?? fallbackY + clearHistoryButtonSize.height / 2

        clearHistoryButton.frame = NSRect(
            x: buttonMaxX - clearHistoryButtonSize.width,
            y: buttonMidY - clearHistoryButtonSize.height / 2,
            width: clearHistoryButtonSize.width,
            height: clearHistoryButtonSize.height
        )
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
