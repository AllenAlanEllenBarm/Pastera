//
//  MainMenuModeIconTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MainMenuModeIconTests {
    @Test
    func modeIconsUseReadyMadeSystemSymbolsWithMatchingSize() {
        #expect(MainMenuModeIcons.historySymbolName == "clock.arrow.circlepath")
        #expect(MainMenuModeIcons.snippetsSymbolName == "text.quote")
        #expect(MainMenuModeIcons.passwordVaultSymbolName == "lock.fill")
        #expect(MainMenuModeIcons.history().size == NSSize(width: 18, height: 18))
        #expect(MainMenuModeIcons.snippets().size == NSSize(width: 18, height: 18))
        #expect(MainMenuModeIcons.passwordVault().size == NSSize(width: 18, height: 18))
    }
}
