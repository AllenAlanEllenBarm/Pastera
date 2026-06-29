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
        let controller = CPYGeneralPreferenceViewController(
            nibName: "CPYGeneralPreferenceViewController",
            bundle: nil
        )
        let paneView = controller.view
        let buttons = paneView.subviews.compactMap { $0 as? NSButton }

        #expect(buttons.contains {
            ["Pause shortcuts during remote control", "远程控制时暂停本机快捷键"].contains($0.accessibilityLabel() ?? $0.title)
        })
    }

    @Test
    func automaticPasteHelpButtonStaysCloseToLabel() throws {
        let controller = CPYGeneralPreferenceViewController(
            nibName: "CPYGeneralPreferenceViewController",
            bundle: nil
        )
        let paneView = controller.view
        let buttons = paneView.subviews.compactMap { $0 as? NSButton }
        let automaticPasteButton = try #require(buttons.first {
            ["Automatic Paste", "自动粘贴"].contains($0.accessibilityLabel() ?? $0.title)
        })
        let automaticPasteHelpButton = try #require(buttons.first {
            ["Automatic Paste Permission Info", "自动粘贴权限说明"].contains($0.accessibilityLabel() ?? $0.title)
        })

        let automaticPasteVisualWidth = ceil(automaticPasteButton.intrinsicContentSize.width)
        let helpVisualGap = automaticPasteHelpButton.frame.minX
            - automaticPasteButton.frame.minX
            - automaticPasteVisualWidth

        #expect(automaticPasteButton.frame.width <= automaticPasteVisualWidth + 6)
        #expect(helpVisualGap >= 4)
        #expect(helpVisualGap <= 10)
        #expect(abs(automaticPasteHelpButton.frame.midY - automaticPasteButton.frame.midY) <= 2)
    }
}
