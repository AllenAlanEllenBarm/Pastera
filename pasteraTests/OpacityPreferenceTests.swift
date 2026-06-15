//
//  OpacityPreferenceTests.swift
//
//  Clipy
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct OpacityPreferenceTests {
    @Test
    func setOpacityWritesPreferenceNotifiesAndUpdatesManagedWindow() throws {
        let suiteName = "OpacityPreferenceTests.setOpacity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { OpacityTestRetainer.retain(window: window) }
        window.contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        defaults.set(0.94, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        CPYWindowAppearance.apply(to: window, defaults: defaults)

        var notifiedOpacity: Double?
        let observer = NotificationCenter.default.addObserver(
            forName: CPYWindowAppearance.opacityDidChangeNotification,
            object: defaults,
            queue: nil
        ) { notification in
            notifiedOpacity = notification.userInfo?["opacity"] as? Double
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        CPYWindowAppearance.setOpacity(0.82, defaults: defaults)

        #expect(abs(defaults.double(forKey: Constants.UserDefaults.windowBackgroundOpacity) - 0.82) < 0.001)
        #expect(abs((notifiedOpacity ?? 0) - 0.82) < 0.001)
        #expect(abs(window.backgroundColor.alphaComponent - 0.82) < 0.001)
        #expect(abs(Double(window.contentView?.layer?.backgroundColor?.alpha ?? 0) - 0.82) < 0.001)
    }

    @Test
    func generalPreferenceOpacityLabelUsesTransparencyLocalizationKey() {
        let controller = CPYGeneralPreferenceViewController(
            nibName: "CPYGeneralPreferenceViewController",
            bundle: nil
        )

        _ = controller.view

        #expect(controller.opacityLabelStringForTesting == String(localized: "Transparency"))
        #expect(controller.opacityLabelStringForTesting != "Opacity:")
    }

    @Test
    func simplifiedChineseTransparencyLocalizationIsConfigured() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("pastera/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let transparency = try #require(strings["Transparency"] as? [String: Any])
        let localizations = try #require(transparency["localizations"] as? [String: Any])
        let zhHans = try #require(localizations["zh-Hans"] as? [String: Any])
        let stringUnit = try #require(zhHans["stringUnit"] as? [String: Any])

        #expect(stringUnit["value"] as? String == "透明度")
    }

    @Test
    func preferenceWindowRefreshesInternalBackgroundWhenOpacityChanges() throws {
        let suiteName = "OpacityPreferenceTests.preferenceOpacityChange.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.94, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }
        controller.showWindow(nil)

        #expect(abs(controller.rootBackgroundAlphaForTesting - 0.94) < 0.001)

        CPYWindowAppearance.setOpacity(0.82, defaults: defaults)

        #expect(abs(controller.rootBackgroundAlphaForTesting - 0.82) < 0.001)
    }

    @Test
    func generalPreferenceOpacitySliderReceivesMouseHitTesting() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let slider = try #require(sliders(in: contentView).first)
        let sliderFrame = contentView.convert(slider.bounds, from: slider)
        let hitView = contentView.hitTest(NSPoint(x: sliderFrame.midX, y: sliderFrame.midY))
        let superPoint = slider.superview?.convert(
            NSPoint(x: slider.bounds.midX, y: slider.bounds.midY),
            from: slider
        ) ?? .zero
        let superHitView = slider.superview?.hitTest(superPoint)

        #expect(
            hitView === slider || hitView?.isDescendant(of: slider) == true,
            """
            Expected opacity slider hit, got \(String(describing: hitView.map { type(of: $0) })).
            Super hit: \(String(describing: superHitView.map { type(of: $0) })).
            Slider frame in content: \(sliderFrame).
            Slider frame in superview: \(slider.frame).
            Superview bounds: \(String(describing: slider.superview?.bounds)).
            """
        )
    }

    @Test
    func generalPreferenceOpacitySliderSupportsFullZeroToHundredRange() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let slider = try #require(sliders(in: contentView).first)

        #expect(slider.minValue == 0)
        #expect(slider.maxValue == 1)
    }

    @Test
    func generalPreferenceShowsClearHistoryButton() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let clearHistoryButton = try #require(buttons(in: contentView).first {
            $0.title == String(localized: "Clear History")
        })

        #expect(clearHistoryButton.action == #selector(AppDelegate.clearAllHistory))
        #expect(clearHistoryButton.target == nil)
    }

    @Test
    func generalPreferenceClearHistoryButtonAlignsWithClipboardHistorySection() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let clearHistoryButton = try #require(buttons(in: contentView).first {
            $0.title == String(localized: "Clear History")
        })
        let sectionTitle = try #require(textFields(in: contentView).first {
            ["Clipboard History", "剪贴板历史"].contains($0.stringValue)
        })
        let sortPopup = try #require(popUpButtons(in: contentView).first)
        let buttonFrame = contentView.convert(clearHistoryButton.frame, from: clearHistoryButton.superview)
        let titleFrame = contentView.convert(sectionTitle.frame, from: sectionTitle.superview)
        let popupFrame = contentView.convert(sortPopup.frame, from: sortPopup.superview)

        #expect(clearHistoryButton.frame.height >= 22)
        #expect(abs(buttonFrame.midY - titleFrame.midY) <= 1)
        #expect(abs(buttonFrame.maxX - popupFrame.maxX) <= 1)
    }
}

private enum OpacityTestRetainer {
    private static var windows = [NSWindow]()

    static func retain(window: NSWindow) {
        windows.append(window)
    }
}

private func sliders(in view: NSView) -> [NSSlider] {
    var values = view.subviews.compactMap { $0 as? NSSlider }
    view.subviews.forEach {
        values.append(contentsOf: sliders(in: $0))
    }
    return values
}

private func buttons(in view: NSView) -> [NSButton] {
    var values = view.subviews.compactMap { $0 as? NSButton }
    view.subviews.forEach {
        values.append(contentsOf: buttons(in: $0))
    }
    return values
}

private func textFields(in view: NSView) -> [NSTextField] {
    var values = view.subviews.compactMap { $0 as? NSTextField }
    view.subviews.forEach {
        values.append(contentsOf: textFields(in: $0))
    }
    return values
}

private func popUpButtons(in view: NSView) -> [NSPopUpButton] {
    var values = view.subviews.compactMap { $0 as? NSPopUpButton }
    view.subviews.forEach {
        values.append(contentsOf: popUpButtons(in: $0))
    }
    return values
}
