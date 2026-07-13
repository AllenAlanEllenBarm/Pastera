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
        let controller = CPYGeneralPreferenceViewController()

        _ = controller.view

        #expect(controller.opacityLabelStringForTesting == String(localized: "Transparency"))
        #expect(controller.opacityLabelStringForTesting != "Opacity:")
    }

    @Test
    func unauthorizedAutomaticPasteRemainsOffAndDoesNotPersistTrue() throws {
        let suiteName = "OpacityPreferenceTests.automaticPastePermission.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYGeneralPreferenceViewController()
        var permissionRequestCount = 0
        controller.automaticPastePermissionChecker = { false }
        controller.automaticPastePermissionRequester = {
            permissionRequestCount += 1
        }

        _ = controller.view
        let automaticPasteButton = try #require(buttons(in: controller.view).first {
            ["Automatic Paste", "自动粘贴"].contains($0.accessibilityLabel() ?? $0.title)
        })

        automaticPasteButton.state = .off
        automaticPasteButton.performClick(nil)

        #expect(!defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand))
        #expect(automaticPasteButton.state == .off)
        #expect(permissionRequestCount == 1)
        let openSettingsButton = try #require(buttons(in: controller.view).first {
            ["Open System Settings", "打开系统设置"].contains($0.title) && !$0.isHidden
        })
        #expect(textFields(in: controller.view).contains {
            !$0.isHidden && !$0.stringValue.isEmpty && $0.textColor == .systemOrange
        })
        openSettingsButton.performClick(nil)
        #expect(permissionRequestCount == 2)
    }

    @Test
    func generalSwitchesWriteImmediatelyWhenAutomaticPasteIsAuthorized() throws {
        let suiteName = "OpacityPreferenceTests.immediateGeneralSwitches.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let immediateKeys = [
            Constants.UserDefaults.loginItem,
            Constants.UserDefaults.showColorPreviewInTheMenu,
            Constants.HotKey.suspendDuringRemoteSession
        ]
        immediateKeys.forEach { defaults.set(false, forKey: $0) }
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYGeneralPreferenceViewController()
        controller.automaticPastePermissionChecker = { true }
        _ = controller.view

        for key in immediateKeys {
            let button = try #require(buttons(in: controller.view).first {
                $0.identifier?.rawValue == key
            })
            button.performClick(nil)
            #expect(defaults.bool(forKey: key))
        }

        let automaticPasteButton = try #require(buttons(in: controller.view).first {
            ["Automatic Paste", "自动粘贴"].contains($0.accessibilityLabel() ?? $0.title)
        })
        automaticPasteButton.performClick(nil)
        #expect(defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand))
        #expect(automaticPasteButton.state == .on)
    }

    @Test
    func titleLengthInvalidDraftDoesNotWriteEscapeRestoresAndParseableLowValueClamps() throws {
        let suiteName = "OpacityPreferenceTests.titleLengthDraft.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(20, forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYGeneralPreferenceViewController()
        _ = controller.view
        let field = try #require(textFields(in: controller.view).first {
            $0.accessibilityLabel() == pasteraPreferenceString("Menu Title Length")
        })

        field.stringValue = "invalid"
        #expect(try sendOpacityControlAction(field))
        #expect(field.stringValue == "invalid")
        #expect(defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength) == 20)

        #expect(controller.control(
            field,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))
        #expect(field.stringValue == "20")

        field.stringValue = "-4"
        #expect(try sendOpacityControlAction(field))
        #expect(field.stringValue == "1")
        #expect(defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength) == 1)

        field.stringValue = "24"
        controller.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(field.stringValue == "24")
        #expect(defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength) == 24)
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
    func preferenceWindowKeepsStableOpaqueBackgroundWhenMenuOpacityChanges() throws {
        let suiteName = "OpacityPreferenceTests.preferenceOpacityChange.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.94, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYPreferencesWindowController()
        defer { controller.close() }
        controller.showWindow(nil)

        #expect(abs(controller.rootBackgroundAlphaForTesting - 1) < 0.001)

        CPYWindowAppearance.setOpacity(0.82, defaults: defaults)

        #expect(abs(controller.rootBackgroundAlphaForTesting - 1) < 0.001)
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
        #expect(slider.isContinuous)
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
        #expect(!defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting))
    }

    @Test
    func simplifiedGeneralDefaultsKeepAutomaticPasteOffAndNoCrashReports() throws {
        let suiteName = "OpacityPreferenceTests.simplifiedDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        CPYUtilities.registerUserDefaultKeys()

        #expect(!defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand))
        #expect(defaults.object(forKey: Constants.UserDefaults.showAlertBeforeClearHistory) == nil)
        #expect(!defaults.bool(forKey: Constants.UserDefaults.collectCrashReport))
        let removedDefaultsPrefix = "kCPY" + "Beta"
        #expect(!defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix(removedDefaultsPrefix) })
    }
}

extension OpacityPreferenceTests {
    @Test
    func generalSavedSettingRowsOwnVisibleLabelsWhileCheckboxesStayAccessible() throws {
        let controller = CPYGeneralPreferenceViewController()
        _ = controller.view

        let defaultsKeys = Set([
            Constants.UserDefaults.loginItem,
            Constants.UserDefaults.showColorPreviewInTheMenu,
            Constants.HotKey.suspendDuringRemoteSession
        ])
        let allButtons = buttons(in: controller.view)
        var savedSettingButtons = allButtons.filter { button in
            button.identifier.map { defaultsKeys.contains($0.rawValue) } ?? false
        }
        savedSettingButtons.append(try #require(allButtons.first {
            ["Automatic Paste", "自动粘贴"].contains($0.accessibilityLabel() ?? $0.title)
        }))
        let visibleRowLabels = Set(textFields(in: controller.view).map(\.stringValue).filter { !$0.isEmpty })

        #expect(savedSettingButtons.count == 4)
        for button in savedSettingButtons {
            let accessibilityLabel = try #require(button.accessibilityLabel())
            #expect(button.title.isEmpty)
            #expect(visibleRowLabels.contains(accessibilityLabel))
        }
    }

    @Test
    func generalPreferenceReloadKeepsStableHierarchyAndLiveDefaultsActions() throws {
        let suiteName = "OpacityPreferenceTests.reload.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: Constants.UserDefaults.loginItem)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYGeneralPreferenceViewController()
        controller.automaticPastePermissionChecker = { true }
        let initialView = controller.view
        let initialGroupCount = generalPreferenceGroups(in: initialView).count
        let initialButtonCount = buttons(in: initialView).count

        controller.loadView()
        let reloadedView = controller.view

        #expect(initialGroupCount == 4)
        #expect(generalPreferenceGroups(in: reloadedView).count == initialGroupCount)
        #expect(buttons(in: reloadedView).count == initialButtonCount)
        let launchOnLoginButton = try #require(buttons(in: reloadedView).first {
            $0.identifier?.rawValue == Constants.UserDefaults.loginItem
        })
        launchOnLoginButton.performClick(nil)
        #expect(defaults.bool(forKey: Constants.UserDefaults.loginItem))
    }

    @Test
    func titleLengthBlankDraftAndInvalidFocusLossDoNotWrite() throws {
        let suiteName = "OpacityPreferenceTests.titleLengthInvalidFocusLoss.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(20, forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYGeneralPreferenceViewController()
        _ = controller.view
        let field = try #require(textFields(in: controller.view).first {
            $0.accessibilityLabel() == pasteraPreferenceString("Menu Title Length")
        })

        field.stringValue = ""
        #expect(try sendOpacityControlAction(field))
        #expect(field.stringValue.isEmpty)
        #expect(defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength) == 20)

        field.stringValue = "invalid"
        controller.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field)
        )
        #expect(field.stringValue == "invalid")
        #expect(defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength) == 20)
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

private func generalPreferenceGroups(in view: NSView) -> [PasteraPreferenceGroupView] {
    var values = view.subviews.compactMap { $0 as? PasteraPreferenceGroupView }
    view.subviews.forEach {
        values.append(contentsOf: generalPreferenceGroups(in: $0))
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

private func sendOpacityControlAction(_ control: NSControl) throws -> Bool {
    NSApp.sendAction(try #require(control.action), to: control.target, from: control)
}
