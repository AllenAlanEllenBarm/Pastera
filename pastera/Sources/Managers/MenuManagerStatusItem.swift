//
//  MenuManagerStatusItem.swift
//
//  Clipy
//

import AppKit
import Carbon

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
        statusItem?.menu = nil
        statusItem?.button?.image = image
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemButtonClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshSecureEventInputStatus()
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

    func startSecureEventInputStatusMonitoring() {
        guard secureEventInputStatusTimer == nil else { return }
        refreshSecureEventInputStatus()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshSecureEventInputStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        secureEventInputStatusTimer = timer
    }

    func refreshSecureEventInputStatus() {
        let toolTip = statusItemToolTip(isSecureEventInputEnabled: IsSecureEventInputEnabled())
        statusItem?.toolTip = toolTip
        statusItem?.button?.toolTip = toolTip
    }

    func statusItemToolTip(isSecureEventInputEnabled: Bool) -> String {
        let baseToolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        guard isSecureEventInputEnabled else { return baseToolTip }

        return [
            baseToolTip,
            "Secure Keyboard Entry is active. macOS may block global shortcuts; click this menu bar icon to open Pastera."
        ].joined(separator: "\n")
    }
}
