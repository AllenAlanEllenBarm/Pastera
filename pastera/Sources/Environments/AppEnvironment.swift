//
//  AppEnvironment.swift
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

struct AppEnvironment {

    // MARK: - Properties
    private static var stack = [Environment()]

    static var current: Environment {
        return stack.last ?? Environment()
    }

    // MARK: - Stacks
    static func push(environment: Environment) {
        stack.append(environment)
    }

    @discardableResult
    static func popLast() -> Environment? {
        return stack.popLast()
    }

    static func replaceCurrent(environment: Environment) {
        push(environment: environment)
        stack.remove(at: stack.count - 2)
    }

    static func push(clipService: ClipService = current.clipService,
                     hotKeyService: HotKeyService = current.hotKeyService,
                     pasteService: PasteService = current.pasteService,
                     excludeAppService: ExcludeAppService = current.excludeAppService,
                     accessibilityService: AccessibilityService = current.accessibilityService,
                     oneDriveProcessStatusService: OneDriveProcessStatusServicing = current.oneDriveProcessStatusService,
                     passwordVaultStore: PasswordVaultStore = current.passwordVaultStore,
                     passwordVaultSyncService: PasswordVaultSyncControlling = current.passwordVaultSyncService,
                     retryPasswordVaultLocalPreparation: @escaping () -> Void = current.retryPasswordVaultLocalPreparation,
                     secureClipboard: SecureClipboardWriting = current.secureClipboard,
                     passwordVaultUIController: PasswordVaultUIController = current.passwordVaultUIController,
                     vaultAgentApplicationRuntime: VaultAgentApplicationRuntimeServicing =
                         current.vaultAgentApplicationRuntime,
                     clipboardScriptCoordinator: ClipboardScriptCoordinating = current.clipboardScriptCoordinator,
                     promptOptimizationService: PromptOptimizationServicing = current.promptOptimizationService,
                     menuManager: MenuManager = current.menuManager,
                     defaults: UserDefaults = current.defaults) {
        push(environment: Environment(clipService: clipService,
                                      hotKeyService: hotKeyService,
                                      pasteService: pasteService,
                                      excludeAppService: excludeAppService,
                                      accessibilityService: accessibilityService,
                                      oneDriveProcessStatusService: oneDriveProcessStatusService,
                                      passwordVaultStore: passwordVaultStore,
                                      passwordVaultSyncService: passwordVaultSyncService,
                                      retryPasswordVaultLocalPreparation: retryPasswordVaultLocalPreparation,
                                      secureClipboard: secureClipboard,
                                      passwordVaultUIController: passwordVaultUIController,
                                      vaultAgentApplicationRuntime: vaultAgentApplicationRuntime,
                                      clipboardScriptCoordinator: clipboardScriptCoordinator,
                                      promptOptimizationService: promptOptimizationService,
                                      menuManager: menuManager,
                                      defaults: defaults))
    }

    static func replaceCurrent(clipService: ClipService = current.clipService,
                               hotKeyService: HotKeyService = current.hotKeyService,
                               pasteService: PasteService = current.pasteService,
                               excludeAppService: ExcludeAppService = current.excludeAppService,
                               accessibilityService: AccessibilityService = current.accessibilityService,
                               oneDriveProcessStatusService: OneDriveProcessStatusServicing = current.oneDriveProcessStatusService,
                               passwordVaultStore: PasswordVaultStore = current.passwordVaultStore,
                               passwordVaultSyncService: PasswordVaultSyncControlling = current.passwordVaultSyncService,
                               retryPasswordVaultLocalPreparation: @escaping () -> Void = current.retryPasswordVaultLocalPreparation,
                               secureClipboard: SecureClipboardWriting = current.secureClipboard,
                               passwordVaultUIController: PasswordVaultUIController = current.passwordVaultUIController,
                               vaultAgentApplicationRuntime: VaultAgentApplicationRuntimeServicing =
                                   current.vaultAgentApplicationRuntime,
                               clipboardScriptCoordinator: ClipboardScriptCoordinating = current.clipboardScriptCoordinator,
                               promptOptimizationService: PromptOptimizationServicing = current.promptOptimizationService,
                               menuManager: MenuManager = current.menuManager,
                               defaults: UserDefaults = current.defaults) {
        replaceCurrent(environment: Environment(clipService: clipService,
                                                hotKeyService: hotKeyService,
                                                pasteService: pasteService,
                                                excludeAppService: excludeAppService,
                                                accessibilityService: accessibilityService,
                                                oneDriveProcessStatusService: oneDriveProcessStatusService,
                                                passwordVaultStore: passwordVaultStore,
                                                passwordVaultSyncService: passwordVaultSyncService,
                                                retryPasswordVaultLocalPreparation: retryPasswordVaultLocalPreparation,
                                                secureClipboard: secureClipboard,
                                                passwordVaultUIController: passwordVaultUIController,
                                                vaultAgentApplicationRuntime: vaultAgentApplicationRuntime,
                                                clipboardScriptCoordinator: clipboardScriptCoordinator,
                                                promptOptimizationService: promptOptimizationService,
                                                menuManager: menuManager,
                                                defaults: defaults))
    }

    static func fromStorage(defaults: UserDefaults = .standard) -> Environment {
        var excludeApplications = [PasteraAppInfo]()
        PasteraAppInfo.registerLegacyArchiveClassName()
        if let data = defaults.object(forKey: Constants.UserDefaults.excludeApplications) as? Data, let applications = NSKeyedUnarchiver.unarchiveObject(with: data) as? [PasteraAppInfo] {
            excludeApplications = applications
        }
        let excludeAppService = ExcludeAppService(applications: excludeApplications)
        return Environment(hotKeyService: HotKeyService(defaults: defaults),
                           excludeAppService: excludeAppService,
                           accessibilityService: AccessibilityService(),
                           prepareProductionPasswordVault: true,
                           vaultAgentApplicationRuntimeFactory: { controller in
                               VaultAgentApplicationRuntime.production(
                                   vault: controller,
                                   defaults: defaults
                               )
                           },
                           menuManager: MenuManager(),
                           defaults: defaults)
    }

 }
