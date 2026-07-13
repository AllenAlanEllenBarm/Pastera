//
//  MenuManagerStatusItem.swift
//
//  Clipy
//

import AppKit
import Carbon

enum StatusItemClickAction {
    case mainPanel
    case contextMenu
}

// MARK: - Status Item
extension MenuManager {
    func makeStatusItemContextMenu() -> NSMenu {
        let menu = NSMenu(title: Constants.Application.name)
        menu.autoenablesItems = false

        menu.addItem(makeStatusItemContextMenuItem(
            title: String(localized: "History"),
            symbolName: "clock.arrow.circlepath",
            action: #selector(openHistoryFromContextMenu),
            target: self
        ))
        menu.addItem(makeStatusItemContextMenuItem(
            title: String(localized: "Snippet"),
            symbolName: "text.quote",
            action: #selector(openSnippetFromContextMenu),
            target: self
        ))
        menu.addItem(makeStatusItemContextMenuItem(
            title: String(localized: "Password Vault"),
            symbolName: "key",
            action: #selector(openPasswordVaultFromContextMenu),
            target: self
        ))
        menu.addItem(.separator())

        menu.addItem(makeStatusItemContextMenuItem(
            title: String(localized: "Manage Snippets"),
            symbolName: "square.and.pencil",
            action: #selector(AppDelegate.showSnippetEditorWindow)
        ))
        let clearHistoryItem = makeStatusItemContextMenuItem(
            title: String(localized: "Clear History"),
            symbolName: "trash",
            action: #selector(AppDelegate.clearAllHistory)
        )
        clearHistoryItem.isEnabled = hasHistoriesForStatusItemMenu
        menu.addItem(clearHistoryItem)
        menu.addItem(.separator())

        menu.addItem(makeStatusItemContextMenuItem(
            title: String(localized: "Preferences"),
            symbolName: "gearshape",
            action: #selector(AppDelegate.showPreferenceWindow)
        ))
        let checkForUpdatesItem = makeStatusItemContextMenuItem(
            title: String(localized: "Check for Updates…"),
            symbolName: "arrow.triangle.2.circlepath",
            action: #selector(AppDelegate.checkForUpdatesFromMenu)
        )
        checkForUpdatesItem.isEnabled = (NSApp.delegate as? AppDelegate)?
            .updaterController?.updater.canCheckForUpdates == true
        menu.addItem(checkForUpdatesItem)
        menu.addItem(makeStatusItemContextMenuItem(
            title: String(localized: "About Pastera"),
            symbolName: "info.circle",
            action: #selector(AppDelegate.showAboutPreferencePane)
        ))
        menu.addItem(.separator())

        menu.addItem(makeStatusItemContextMenuItem(
            title: String(localized: "Quit Pastera"),
            symbolName: "power",
            action: #selector(AppDelegate.terminate)
        ))
        return menu
    }

    private func makeStatusItemContextMenuItem(
        title: String,
        symbolName: String,
        action: Selector? = nil,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        item.isEnabled = true
        return item
    }

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
        switch statusItemClickAction(for: NSApp.currentEvent?.type) {
        case .mainPanel:
            showMainMenuPanelFromStatusItemFrame(sender.window?.frame)
        case .contextMenu:
            makeStatusItemContextMenu().popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY),
                in: sender
            )
        }
    }

    func statusItemClickAction(for eventType: NSEvent.EventType?) -> StatusItemClickAction {
        eventType == .rightMouseUp ? .contextMenu : .mainPanel
    }

    @objc func openHistoryFromContextMenu() {
        DispatchQueue.main.async { [weak self] in
            self?.popUpMenu(.history)
        }
    }

    @objc func openSnippetFromContextMenu() {
        DispatchQueue.main.async { [weak self] in
            self?.popUpMenu(.snippet)
        }
    }

    @objc func openPasswordVaultFromContextMenu() {
        DispatchQueue.main.async { [weak self] in
            self?.popUpMenu(.passwordVault)
        }
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

    func startOneDriveStatusMonitoring() {
        guard oneDriveStatusObservation == nil else { return }
        oneDriveStatusObservation = AppEnvironment.current.oneDriveProcessStatusService.startMonitoring { [weak self] in
            self?.mainMenuPanelController?.reloadOneDriveStatusIfVisible()
        }
    }

    func refreshSecureEventInputStatus() {
        let isSecureEventInputEnabled = secureEventInputEnabledProvider()
        let toolTip = statusItemToolTip(isSecureEventInputEnabled: isSecureEventInputEnabled)
        statusItem?.toolTip = toolTip
        statusItem?.button?.toolTip = toolTip
        statusItem?.button?.contentTintColor = isSecureEventInputEnabled ? .systemOrange : nil
        statusItem?.button?.setAccessibilityLabel(
            isSecureEventInputEnabled
            ? String(localized: "Pastera, Secure Keyboard Entry active")
            : Constants.Application.name
        )
    }

    func statusItemToolTip(isSecureEventInputEnabled: Bool) -> String {
        let baseToolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        guard isSecureEventInputEnabled else { return baseToolTip }

        return [
            baseToolTip,
            String(localized: "Secure Keyboard Entry is active. macOS may block global shortcuts; click this menu bar icon to open Pastera.")
        ].joined(separator: "\n")
    }
}
