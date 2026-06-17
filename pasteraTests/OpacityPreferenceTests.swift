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
    func generalPreferenceUsesSingleColumnLayoutWithoutSectionHeadings() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let clearHistoryButton = try #require(buttons(in: contentView).first {
            $0.title == String(localized: "Clear History")
        })
        let launchButton = try #require(buttons(in: contentView).first {
            ["Launch on Login", "登录时打开"].contains($0.title)
        })
        let warningButton = try #require(buttons(in: contentView).first {
            ["Show alert panel before clear history", "清空历史前显示警告面板"].contains($0.title)
        })
        let opacityLabel = try #require(textFields(in: contentView).first {
            [$0.stringValue].contains(String(localized: "Transparency")) || ["透明度"].contains($0.stringValue)
        })
        let opacitySlider = try #require(sliders(in: contentView).first)
        let opacityValueLabel = try #require(textFields(in: contentView).first {
            $0.stringValue.hasSuffix("%")
        })
        let launchFrame = contentView.convert(launchButton.frame, from: launchButton.superview)
        let clearHistoryFrame = contentView.convert(clearHistoryButton.frame, from: clearHistoryButton.superview)
        let warningFrame = contentView.convert(warningButton.frame, from: warningButton.superview)
        let opacityLabelFrame = contentView.convert(opacityLabel.frame, from: opacityLabel.superview)
        let sliderFrame = contentView.convert(opacitySlider.frame, from: opacitySlider.superview)
        let opacityValueFrame = contentView.convert(opacityValueLabel.frame, from: opacityValueLabel.superview)

        #expect(clearHistoryButton.frame.height >= 22)
        #expect(abs(clearHistoryFrame.minX - launchFrame.minX) <= 2)
        #expect(abs(warningFrame.minX - launchFrame.minX) <= 2)
        #expect(abs(opacityLabelFrame.minX - launchFrame.minX) <= 2)
        #expect(launchFrame.minY > clearHistoryFrame.minY)
        #expect(clearHistoryFrame.minY > warningFrame.minY)
        #expect(warningFrame.minY > opacityLabelFrame.minY)
        #expect(sliderFrame.minX > opacityLabelFrame.maxX)
        #expect(opacityValueFrame.minX > sliderFrame.maxX)
    }

    @Test
    func generalPreferenceRemovesHistoryLimitAndSortControls() throws {
        let defaults = AppEnvironment.current.defaults
        let previousReorderPreference = defaults.object(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        defer {
            if let previousReorderPreference {
                defaults.set(previousReorderPreference, forKey: Constants.UserDefaults.reorderClipsAfterPasting)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
            }
            defaults.synchronize()
        }
        defaults.set(false, forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        defaults.synchronize()

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let visibleTexts = Set(textFields(in: contentView).map(\.stringValue).filter { !$0.isEmpty })
        let visibleButtons = Set(buttons(in: contentView).map(\.title).filter { !$0.isEmpty })

        #expect(popUpButtons(in: contentView).isEmpty)
        #expect(!visibleTexts.contains("Max clipboard history size:"))
        #expect(!visibleTexts.contains("最大剪贴板历史："))
        #expect(!visibleTexts.contains("Sort history order by:"))
        #expect(!visibleTexts.contains("历史排序按照："))
        #expect(!visibleTexts.contains("items"))
        #expect(!visibleTexts.contains("项"))
        #expect(!visibleTexts.contains("Behavior"))
        #expect(!visibleTexts.contains("行为"))
        #expect(!visibleTexts.contains("Clipboard History"))
        #expect(!visibleTexts.contains("剪贴板历史"))
        #expect(!visibleTexts.contains("Appearance"))
        #expect(!visibleTexts.contains("外观"))
        #expect(!visibleButtons.contains("Input \"⌘ + V\" after menu item selection"))
        #expect(!visibleButtons.contains("选中菜单项后输入”⌘ + V“"))
        #expect(!visibleButtons.contains("Send crash report and error log (reflected at the next launch)"))
        #expect(!visibleButtons.contains("发送崩溃报告和错误日志（下次启动时生效）"))
        #expect(defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting))
    }

    @Test
    func simplifiedGeneralDefaultsKeepDirectPasteAndNoCrashReports() throws {
        let suiteName = "OpacityPreferenceTests.simplifiedDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        CPYUtilities.registerUserDefaultKeys()

        #expect(defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand))
        #expect(!defaults.bool(forKey: Constants.UserDefaults.collectCrashReport))
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
