//
//  MenuType.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/06/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

enum MenuType: String {
    case main       = "ClipMenu"
    case history    = "HistoryMenu"
    case snippet    = "SnippetMenu"
    case passwordVault = "PasswordVaultMenu"

    var userDefaultsKey: String {
        switch self {
        case .main:
            return Constants.HotKey.mainKeyCombo
        case .history:
            return Constants.HotKey.historyKeyCombo
        case .snippet:
            return Constants.HotKey.snippetKeyCombo
        case .passwordVault:
            return Constants.HotKey.passwordVaultKeyCombo
        }
    }

    var hotKeySelector: Selector {
        switch self {
        case .main:
            return #selector(HotKeyService.popupMainMenu)
        case .history:
            return #selector(HotKeyService.popupHistoryMenu(_:))
        case .snippet:
            return #selector(HotKeyService.popUpSnippetMenu(_:))
        case .passwordVault:
            return #selector(HotKeyService.popupPasswordVaultMenu)
        }
    }

}
