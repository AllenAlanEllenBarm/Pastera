//
//  MenuManagerStatusItem.swift
//
//  Clipy
//

import AppKit

// MARK: - Status Item
extension MenuManager {
    func configureStatusItemFromDefaults() {
        changeStatusItem(.white)
    }

    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        let image = NSImage(resource: .statusbarMenuWhite)
        image.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        statusItem?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = nil
        statusItem?.button?.image = image
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemButtonClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        guard let frame = sender.window?.frame else {
            showMainMenuPanelFromStatusItemFrame(nil)
            return
        }
        showMainMenuPanelFromStatusItemFrame(frame)
    }
}
