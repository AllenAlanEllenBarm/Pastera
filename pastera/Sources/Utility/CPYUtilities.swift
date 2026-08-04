//
//  CPYUtilities.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import IOKit

final class CPYUtilities {
    // ref: https://gist.github.com/vadimpiven/3373bb2592d59560b5d698ba1e2ed7e4
    private static let hardwareDeviceID: String? = {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        return IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ).takeRetainedValue() as? String
    }()

    static var deviceID: String? {
        syncDeviceID()
    }

    static func syncDeviceID(defaults: UserDefaults = AppEnvironment.current.defaults) -> String {
        if let existingDeviceID = defaults.string(forKey: Constants.UserDefaults.syncDeviceID),
           !existingDeviceID.isEmpty {
            return existingDeviceID
        }
        let deviceID = hardwareDeviceID ?? UUID().uuidString
        defaults.set(deviceID, forKey: Constants.UserDefaults.syncDeviceID)
        return deviceID
    }

    static func initSDKs() {
        // Fabric
        AppEnvironment.current.defaults.register(defaults: ["NSApplicationCrashOnExceptions": true])
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.collectCrashReport) else { return }
        // TODO: - Migrate Firebase Crashlytics
        CPYUtilities.sendCustomLog(with: "applicationDidFinishLaunching")
    }

    static func registerUserDefaultKeys() {
        var defaultValues = [String: Any]()

        defaultValues.updateValue(HotKeyService.defaultKeyCombos, forKey: Constants.UserDefaults.hotKeys)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.HotKey.suspendDuringRemoteSession)
        /* General */
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.loginItem)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.suppressAlertForLoginItem)
        defaultValues.updateValue(NSNumber(value: 30), forKey: Constants.UserDefaults.maxHistorySize)
        defaultValues.updateValue(NSNumber(value: 2000), forKey: Constants.UserDefaults.storedHistoryLimit)
        defaultValues.updateValue(NSNumber(value: 15), forKey: Constants.UserDefaults.maxImageHistorySize)
        defaultValues.updateValue(NSNumber(value: 15), forKey: Constants.UserDefaults.maxFileHistorySize)
        defaultValues.updateValue(NSNumber(value: 256 * 1024), forKey: Constants.UserDefaults.maxSyncedHistoryTextBytes)
        defaultValues.updateValue(
            NSNumber(value: 8 * 1024 * 1024),
            forKey: Constants.UserDefaults.maxHistorySnapshotTextBudgetBytes
        )
        defaultValues.updateValue(NSNumber(value: 25 * 1024 * 1024), forKey: Constants.UserDefaults.maxSyncedFileBytes)
        defaultValues.updateValue(NSNumber(value: 10), forKey: Constants.UserDefaults.syncedFileLimitPerDevice)
        defaultValues.updateValue(NSNumber(value: CPYWindowAppearance.defaultOpacity), forKey: Constants.UserDefaults.windowBackgroundOpacity)
        defaultValues.updateValue(NSNumber(value: 2), forKey: Constants.UserDefaults.showStatusItem)
        let storeTypes = PasteboardAvailableType.allCases.reduce(into: [:]) { $0[$1.rawValue] = NSNumber(value: true) }
        defaultValues.updateValue(storeTypes, forKey: Constants.UserDefaults.storeTypes)
        defaultValues.updateValue(PasteraFilePreviewKind.defaultStates(), forKey: Constants.UserDefaults.filePreviewTypes)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.inputPasteCommand)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.collectCrashReport)

        /* Menu */
        defaultValues.updateValue(NSNumber(value: 16), forKey: Constants.UserDefaults.menuIconSize)
        defaultValues.updateValue(NSNumber(value: 20), forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        defaultValues.updateValue(NSNumber(value: 0), forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        defaultValues.updateValue(NSNumber(value: 10), forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.addClearHistoryMenuItem)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.addNumericKeyEquivalents)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showImageInTheMenu)
        defaultValues.updateValue(NSNumber(value: 200), forKey: Constants.UserDefaults.maxLengthOfToolTip)
        defaultValues.updateValue(NSNumber(value: 100), forKey: Constants.UserDefaults.thumbnailWidth)
        defaultValues.updateValue(NSNumber(value: 32), forKey: Constants.UserDefaults.thumbnailHeight)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.overwriteSameHistory)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.copySameHistory)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncAutomaticUploadEnabled)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncAutomaticEnabled)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncHistoryUploadEnabled)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncHistoryImportEnabled)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncSnippetUploadEnabled)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncSnippetImportEnabled)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncFileUploadEnabled)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.syncFileImportEnabled)
        let syncFileTypes = PasteboardAvailableType.syncFileTypes.reduce(into: [:]) {
            $0[$1.rawValue] = NSNumber(value: false)
        }
        defaultValues.updateValue(syncFileTypes, forKey: Constants.UserDefaults.syncFileTypes)
        defaultValues.updateValue(NSNumber(value: 300), forKey: Constants.UserDefaults.syncPollInterval)
        defaultValues.updateValue(NSNumber(value: 300), forKey: Constants.UserDefaults.passwordVaultAutoLockInterval)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled)
        // Retain the scalar defaults while Prompt Optimization settings migrate to V2.
        defaultValues.updateValue(
            PromptOptimizationProviderSelection.automaticFree.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationProvider
        )
        defaultValues.updateValue(
            OpenAICompatiblePreset.openAI.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationPreset
        )
        defaultValues.updateValue("", forKey: Constants.UserDefaults.promptOptimizationBaseURL)
        defaultValues.updateValue("", forKey: Constants.UserDefaults.promptOptimizationModel)
        defaultValues.updateValue(
            NSNumber(value: false),
            forKey: Constants.UserDefaults.promptOptimizationAllowsInsecureHTTP
        )
        defaultValues.updateValue(
            [String](),
            forKey: Constants.UserDefaults.promptOptimizationConfirmedOrigins
        )

        /* Updates */
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.Update.enableAutomaticCheck)
        defaultValues.updateValue(NSNumber(value: 86400), forKey: Constants.Update.checkInterval)

        AppEnvironment.current.defaults.register(defaults: defaultValues)
        AppEnvironment.current.defaults.synchronize()
    }

    static func applicationSupportFolder() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        let basePath: String = paths.first ?? NSTemporaryDirectory()
        return (basePath as NSString).appendingPathComponent(Constants.Application.name)
    }

    static func sendCustomLog(with name: String) {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.collectCrashReport) else { return }
        // TODO: - Migrate Firebase Crashlytics
    }
}
