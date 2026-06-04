//
//  CPYGeneralPreferenceViewController.swift
//
//  Clipy
//

import Cocoa

final class CPYGeneralPreferenceViewController: NSViewController {
    private let opacityLabel = NSTextField(labelWithString: "Opacity:")
    private let opacitySlider = NSSlider()
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private var didInstallOpacityControls = false

    override func viewDidLoad() {
        super.viewDidLoad()
        installOpacityControls()
        updateOpacityControls()
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        let opacity = CPYWindowAppearance.normalizedOpacity(sender.doubleValue)
        AppEnvironment.current.defaults.set(opacity, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.current.defaults.synchronize()
        updateOpacityControls(opacity: opacity)
        CPYWindowAppearance.applyToVisibleWindows()
    }

    private func installOpacityControls() {
        guard !didInstallOpacityControls else { return }
        didInstallOpacityControls = true

        view.subviews.forEach { subview in
            CPYWindowAppearance.apply(to: subview)
        }
        CPYWindowAppearance.apply(to: view)

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

        [opacityLabel, opacitySlider, opacityValueLabel].forEach {
            $0.autoresizingMask = [.maxXMargin, .minYMargin]
            view.addSubview($0)
        }
    }

    private func updateOpacityControls(opacity: Double = CPYWindowAppearance.opacity()) {
        let normalizedOpacity = CPYWindowAppearance.normalizedOpacity(opacity)
        opacitySlider.doubleValue = normalizedOpacity
        opacityValueLabel.stringValue = "\(Int(round(normalizedOpacity * 100)))%"
    }
}
