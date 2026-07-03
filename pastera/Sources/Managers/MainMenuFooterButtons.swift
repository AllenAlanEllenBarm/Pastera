//
//  MainMenuFooterButtons.swift
//
//  Pastera
//

import AppKit

final class MainMenuOneDriveStatusButton: NSButton {
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(status: OneDriveProcessStatus) {
        switch status {
        case .running:
            image = Self.oneDriveStatusIcon
            contentTintColor = .labelColor
            alphaValue = 1
            toolTip = "OneDrive 正在运行。点击打开 OneDrive。"
        case .notRunning:
            image = Self.oneDriveStatusIcon
            contentTintColor = .secondaryLabelColor
            alphaValue = 0.78
            toolTip = "OneDrive 未运行。点击打开 OneDrive。"
        case .notInstalled:
            image = Self.oneDriveStatusIcon
            contentTintColor = .secondaryLabelColor
            alphaValue = 0.72
            toolTip = "未安装 OneDrive。"
        }
        setAccessibilityLabel(toolTip)
    }

    private func setup() {
        identifier = NSUserInterfaceItemIdentifier("mainMenuOneDriveStatusButton")
        setButtonType(.momentaryPushIn)
        bezelStyle = .inline
        isBordered = false
        imagePosition = .imageOnly
    }

    private static let oneDriveStatusIcon: NSImage = {
        let image = NSImage(named: "onedrive_status_template")
            ?? NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(
                width: MainMenuPanelLayout.oneDriveStatusButtonSize,
                height: MainMenuPanelLayout.oneDriveStatusButtonSize
            ))
        image.size = NSSize(
            width: MainMenuPanelLayout.oneDriveStatusButtonSize,
            height: MainMenuPanelLayout.oneDriveStatusButtonSize
        )
        image.isTemplate = true
        return image
    }()
}

final class MainMenuQuitButton: NSButton {
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        identifier = NSUserInterfaceItemIdentifier("mainMenuQuitButton")
        title = ""
        setButtonType(.momentaryPushIn)
        bezelStyle = .inline
        isBordered = false
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        image?.isTemplate = true
        contentTintColor = .secondaryLabelColor
        alphaValue = 0.82
        toolTip = String(localized: "Quit Pastera")
        setAccessibilityLabel(toolTip)
    }
}
