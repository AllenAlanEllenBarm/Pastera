//
//  GeneralPreferenceHelpButtonLayoutTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct GeneralPreferenceHelpButtonLayoutTests {
    @Test
    func remoteControlHotkeyPausePreferenceIsVisible() throws {
        let controller = CPYGeneralPreferenceViewController()
        let paneView = controller.view
        paneView.frame.size = paneView.fittingSize
        paneView.layoutSubtreeIfNeeded()
        let buttons = generalPreferenceButtons(in: paneView)

        #expect(buttons.contains {
            $0.accessibilityLabel() == pasteraPreferenceString("Pause shortcuts during remote control")
        })
    }

    @Test
    func remoteControlHotkeyPausePreferenceRefreshesRegisteredHotkeysImmediately() throws {
        let suiteName = "GeneralPreferenceHelpButtonLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var refreshCount = 0
        let controller = CPYGeneralPreferenceViewController(
            defaults: defaults,
            remoteSessionHotKeyRefresher: { refreshCount += 1 }
        )
        let button = try #require(generalPreferenceButtons(in: controller.view).first {
            $0.accessibilityLabel() == pasteraPreferenceString("Pause shortcuts during remote control")
        })

        button.performClick(nil)

        #expect(defaults.bool(forKey: Constants.HotKey.suspendDuringRemoteSession))
        #expect(refreshCount == 1)
    }

    @Test
    func automaticPasteHelpButtonStaysCloseToLabel() throws {
        let controller = CPYGeneralPreferenceViewController()
        let paneView = controller.view
        paneView.frame.size = paneView.fittingSize
        paneView.layoutSubtreeIfNeeded()
        let buttons = generalPreferenceButtons(in: paneView)
        let automaticPasteButton = try #require(buttons.first {
            ["Automatic Paste", "自动粘贴"].contains($0.accessibilityLabel() ?? $0.title)
        })
        let automaticPasteHelpButton = try #require(buttons.first {
            ["Automatic Paste Permission Info", "自动粘贴权限说明"].contains($0.accessibilityLabel() ?? $0.title)
        })

        let automaticPasteFrame = paneView.convert(automaticPasteButton.bounds, from: automaticPasteButton)
        let helpButtonFrame = paneView.convert(automaticPasteHelpButton.bounds, from: automaticPasteHelpButton)
        let automaticPasteVisualWidth = ceil(automaticPasteButton.intrinsicContentSize.width)
        let helpVisualGap = helpButtonFrame.minX
            - automaticPasteFrame.minX
            - automaticPasteVisualWidth

        #expect(automaticPasteFrame.width <= automaticPasteVisualWidth + 6)
        #expect(helpVisualGap >= 4)
        #expect(helpVisualGap <= 10)
        #expect(abs(helpButtonFrame.midY - automaticPasteFrame.midY) <= 2)
    }

    @Test
    func compoundAutomaticPasteControlAlignsToTheSharedTrailingColumn() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }
        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(paneID: .general)
        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let buttons = generalPreferenceButtons(in: contentView)
        let helpButton = try #require(buttons.first {
            ["Automatic Paste Permission Info", "自动粘贴权限说明"].contains($0.accessibilityLabel() ?? $0.title)
        })
        let remoteButton = try #require(buttons.first {
            ["Pause shortcuts during remote control", "远程控制时暂停快捷键"].contains(
                $0.accessibilityLabel() ?? $0.title
            )
        })

        let helpFrame = contentView.convert(helpButton.bounds, from: helpButton)
        let remoteFrame = contentView.convert(remoteButton.bounds, from: remoteButton)
        #expect(abs(helpFrame.maxX - remoteFrame.maxX) <= 2)
    }
}

private func generalPreferenceButtons(in view: NSView) -> [NSButton] {
    var values = view.subviews.compactMap { $0 as? NSButton }
    view.subviews.forEach { values.append(contentsOf: generalPreferenceButtons(in: $0)) }
    return values
}
