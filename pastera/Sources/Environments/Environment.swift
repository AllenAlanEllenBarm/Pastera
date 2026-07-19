//
//  Environment.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2017/08/10.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

struct Environment {

    // MARK: - Properties
    let clipService: ClipService
    let hotKeyService: HotKeyService
    let pasteService: PasteService
    let excludeAppService: ExcludeAppService
    let accessibilityService: AccessibilityService
    let oneDriveProcessStatusService: OneDriveProcessStatusServicing
    let passwordVaultStore: PasswordVaultStore
    let secureClipboard: SecureClipboardWriting
    let passwordVaultUIController: PasswordVaultUIController
    let clipboardScriptCoordinator: ClipboardScriptCoordinating
    let menuManager: MenuManager

    let defaults: UserDefaults

    // MARK: - Initialize
    init(clipService: ClipService? = nil,
         hotKeyService: HotKeyService = HotKeyService(),
         pasteService: PasteService? = nil,
         excludeAppService: ExcludeAppService = ExcludeAppService(applications: []),
         accessibilityService: AccessibilityService = AccessibilityService(),
         oneDriveProcessStatusService: OneDriveProcessStatusServicing = OneDriveProcessStatusService(),
         passwordVaultStore: PasswordVaultStore = KDBXPasswordVaultStore(),
         secureClipboard: SecureClipboardWriting = SecureClipboardService(),
         passwordVaultUIController: PasswordVaultUIController? = nil,
         clipboardScriptCoordinator: ClipboardScriptCoordinating = ClipboardScriptCoordinator(
             repository: ScriptRepository(),
             executor: ScriptExecutionService()
         ),
         menuManager: MenuManager = MenuManager(),
         defaults: UserDefaults = .standard) {

        self.clipService = clipService ?? ClipService(
            clipboardScriptCoordinatorProvider: { clipboardScriptCoordinator }
        )
        self.hotKeyService = hotKeyService
        let resolvedPasteService = pasteService ?? PasteService(
            clipboardScriptCoordinatorProvider: { clipboardScriptCoordinator }
        )
        self.pasteService = resolvedPasteService
        self.excludeAppService = excludeAppService
        self.accessibilityService = accessibilityService
        self.oneDriveProcessStatusService = oneDriveProcessStatusService
        self.passwordVaultStore = passwordVaultStore
        self.secureClipboard = secureClipboard
        self.passwordVaultUIController = passwordVaultUIController ?? PasswordVaultUIController(
            store: passwordVaultStore,
            clipboard: secureClipboard,
            pasteService: resolvedPasteService
        )
        self.clipboardScriptCoordinator = clipboardScriptCoordinator
        self.menuManager = menuManager
        self.defaults = defaults
    }

}
