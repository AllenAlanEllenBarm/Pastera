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
    let vaultAgentApplicationRuntime: VaultAgentApplicationRuntimeServicing
    let clipboardScriptCoordinator: ClipboardScriptCoordinating
    let promptOptimizationService: PromptOptimizationServicing
    let menuManager: MenuManager

    let defaults: UserDefaults

    // MARK: - Initialize
    init(clipService: ClipService? = nil,
         hotKeyService: HotKeyService = HotKeyService(),
         pasteService: PasteService? = nil,
         excludeAppService: ExcludeAppService = ExcludeAppService(applications: []),
         accessibilityService: AccessibilityService = AccessibilityService(),
         oneDriveProcessStatusService: OneDriveProcessStatusServicing = OneDriveProcessStatusService(),
         passwordVaultStore: PasswordVaultStore? = nil,
         passwordVaultMigrator: PasswordVaultMigrating? = nil,
         secureClipboard: SecureClipboardWriting = SecureClipboardService(),
         passwordVaultUIController: PasswordVaultUIController? = nil,
         vaultAgentApplicationRuntime: VaultAgentApplicationRuntimeServicing? = nil,
         vaultAgentApplicationRuntimeFactory: ((PasswordVaultUIController) ->
             VaultAgentApplicationRuntimeServicing)? = nil,
         clipboardScriptCoordinator: ClipboardScriptCoordinating = ClipboardScriptCoordinator(
             repository: ScriptRepository(),
             executor: ScriptExecutionService()
         ),
         promptOptimizationService: PromptOptimizationServicing? = nil,
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
        let resolvedPasswordVaultStore = passwordVaultStore ?? KDBXPasswordVaultStore(
            autoLockTimeoutProvider: { VaultSessionController.resolvedTimeout(defaults: defaults) }
        )
        self.passwordVaultStore = resolvedPasswordVaultStore
        self.secureClipboard = secureClipboard
        let resolvedPasswordVaultUIController = passwordVaultUIController ?? PasswordVaultUIController(
            store: resolvedPasswordVaultStore,
            clipboard: secureClipboard,
            pasteService: resolvedPasteService,
            defaults: defaults
        )
        self.passwordVaultUIController = resolvedPasswordVaultUIController
        if let passwordVaultMigrator {
            resolvedPasswordVaultUIController.vaultAgentExecutor.async {
                resolvedPasswordVaultStore.prepareLocalCopy(using: passwordVaultMigrator)
            }
        }
        self.vaultAgentApplicationRuntime = vaultAgentApplicationRuntime ??
            vaultAgentApplicationRuntimeFactory?(resolvedPasswordVaultUIController) ??
            UnavailableVaultAgentApplicationRuntime()
        self.clipboardScriptCoordinator = clipboardScriptCoordinator
        self.promptOptimizationService = promptOptimizationService ?? PromptOptimizationService(
            settingsStore: PromptOptimizationSettingsStore(defaults: defaults),
            apiKeyStore: PromptOptimizationAPIKeyStore()
        )
        self.menuManager = menuManager
        self.defaults = defaults
    }

}
