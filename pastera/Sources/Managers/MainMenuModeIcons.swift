//
//  MainMenuModeIcons.swift
//
//  Pastera
//

import AppKit

enum MainMenuModeIcons {
    static let historyImageName: NSImage.Name = "pastera.mode.history"
    static let snippetsImageName: NSImage.Name = "pastera.mode.snippets"
    static let passwordVaultImageName: NSImage.Name = "pastera.mode.password-vault"
    static let historySymbolName = "clock.arrow.circlepath"
    static let snippetsSymbolName = "text.quote"
    static let passwordVaultSymbolName = "lock.fill"

    static func history() -> NSImage {
        historyImage
    }

    static func snippets() -> NSImage {
        snippetsImage
    }

    static func passwordVault() -> NSImage {
        passwordVaultImage
    }

    private static let iconSize = NSSize(width: 18, height: 18)

    private static let historyImage = makeSymbolImage(
        named: historyImageName,
        symbolName: historySymbolName,
        fallbackSymbolName: "clock",
        description: "History"
    )

    private static let snippetsImage = makeSymbolImage(
        named: snippetsImageName,
        symbolName: snippetsSymbolName,
        fallbackSymbolName: "doc.text",
        description: "Snippets"
    )

    private static let passwordVaultImage = makeSymbolImage(
        named: passwordVaultImageName,
        symbolName: passwordVaultSymbolName,
        fallbackSymbolName: "lock",
        description: "Password Vault"
    )

    private static func makeSymbolImage(
        named name: NSImage.Name,
        symbolName: String,
        fallbackSymbolName: String,
        description: String
    ) -> NSImage {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: description)
            ?? NSImage(size: iconSize)
        image.size = iconSize
        image.isTemplate = true
        _ = image.setName(name)
        return image
    }
}
