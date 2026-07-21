//
//  Constants.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/04/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

struct Constants {

    struct Application {
        #if DEBUG
            static let name = "PasteraDEBUG"
        #else
            static let name = "Pastera"
        #endif
    }

    struct Menu {
        static let clip = "ClipMenu"
        static let history = "HistoryMenu"
        static let snippet = "SnippetsMenu"
    }

    struct Common {
        static let index = "index"
        static let title = "title"
        static let snippets = "snippets"
        static let content = "content"
        static let selector = "selector"
        static let draggedDataType = "public.data"
    }

    struct Thumbnail {
        static let hoverPreviewPixelWidth = 808
        static let hoverPreviewPixelHeight = 548
        static let maxEncodedBytes = 384 * 1024
    }

    struct UserDefaults {
        static let hotKeys = "kCPYPrefHotKeysKey"
        static let menuIconSize = "kCPYPrefMenuIconSizeKey"
        static let maxHistorySize = "kCPYPrefMaxHistorySizeKey"
        static let storedHistoryLimit = "kCPYPrefStoredHistoryLimitKey"
        static let maxImageHistorySize = "kPasteraMaxImageHistorySizeKey"
        static let maxFileHistorySize = "kPasteraMaxFileHistorySizeKey"
        static let maxSyncedHistoryTextBytes = "kCPYPrefMaxSyncedHistoryTextBytesKey"
        static let maxHistorySnapshotTextBudgetBytes = "kCPYPrefMaxHistorySnapshotTextBudgetBytesKey"
        static let maxSyncedFileBytes = "kCPYPrefMaxSyncedFileBytesKey"
        static let syncedFileLimitPerDevice = "kCPYPrefSyncedFileLimitPerDeviceKey"
        static let syncDeviceID = "kCPYSyncDeviceIDKey"
        static let windowBackgroundOpacity = "kCPYPrefWindowBackgroundOpacityKey"
        static let storeTypes = "kCPYPrefStoreTypesKey"
        static let filePreviewTypes = "kPasteraFilePreviewTypes"
        static let inputPasteCommand = "kCPYPrefInputPasteCommandKey"
        static let numberOfItemsPlaceInline = "kCPYPrefNumberOfItemsPlaceInlineKey"
        static let numberOfItemsPlaceInsideFolder = "kCPYPrefNumberOfItemsPlaceInsideFolderKey"
        static let maxMenuItemTitleLength = "kCPYPrefMaxMenuItemTitleLengthKey"
        static let menuItemsTitleStartWithZero = "kCPYPrefMenuItemsTitleStartWithZeroKey"
        static let reorderClipsAfterPasting = "kCPYPrefReorderClipsAfterPasting"
        static let addClearHistoryMenuItem = "kCPYPrefAddClearHistoryMenuItemKey"
        static let showAlertBeforeClearHistory = "kCPYPrefShowAlertBeforeClearHistoryKey"
        static let menuItemsAreMarkedWithNumbers = "menuItemsAreMarkedWithNumbers"
        static let showToolTipOnMenuItem = "showToolTipOnMenuItem"
        static let showImageInTheMenu = "showImageInTheMenu"
        static let addNumericKeyEquivalents = "addNumericKeyEquivalents"
        static let maxLengthOfToolTip = "maxLengthOfToolTipKey"
        static let loginItem = "loginItem"
        static let suppressAlertForLoginItem = "suppressAlertForLoginItem"
        static let showStatusItem = "kCPYPrefShowStatusItemKey"
        static let thumbnailWidth = "thumbnailWidth"
        static let thumbnailHeight = "thumbnailHeight"
        static let overwriteSameHistory = "kCPYPrefOverwriteSameHistroy"
        static let copySameHistory = "kCPYPrefCopySameHistroy"
        static let suppressAlertForDeleteSnippet = "kCPYSuppressAlertForDeleteSnippet"
        static let excludeApplications = "kCPYExcludeApplications"
        static let collectCrashReport = "kCPYCollectCrashReport"
        static let showColorPreviewInTheMenu = "kCPYPrefShowColorPreviewInTheMenu"
        static let setupGuideDismissed = "kPasteraSetupGuideDismissed"
        static let syncRootPath = "kCPYSyncRootPath"
        static let syncAutomaticUploadEnabled = "kCPYSyncAutomaticUploadEnabled"
        static let syncAutomaticEnabled = "kCPYSyncAutomaticEnabled"
        static let syncHistoryUploadEnabled = "kCPYSyncHistoryUploadEnabled"
        static let syncHistoryImportEnabled = "kCPYSyncHistoryImportEnabled"
        static let syncSnippetUploadEnabled = "kCPYSyncSnippetUploadEnabled"
        static let syncSnippetImportEnabled = "kCPYSyncSnippetImportEnabled"
        static let syncFileUploadEnabled = "kCPYSyncFileUploadEnabled"
        static let syncFileImportEnabled = "kCPYSyncFileImportEnabled"
        static let syncFileTypes = "kCPYSyncFileTypes"
        static let syncPollInterval = "kCPYSyncPollInterval"
        static let passwordVaultAutoLockInterval = "kPasteraPasswordVaultAutoLockInterval"
        static let passwordVaultQuickActionsCoachmarkShown = "kPasteraPasswordVaultQuickActionsCoachmarkShown"
        static let promptOptimizationProvider = "kPasteraPromptOptimizationProvider"
        static let promptOptimizationPreset = "kPasteraPromptOptimizationPreset"
        static let promptOptimizationBaseURL = "kPasteraPromptOptimizationBaseURL"
        static let promptOptimizationModel = "kPasteraPromptOptimizationModel"
        static let promptOptimizationAllowsInsecureHTTP = "kPasteraPromptOptimizationAllowsInsecureHTTP"
        static let promptOptimizationConfirmedOrigins = "kPasteraPromptOptimizationConfirmedOrigins"
        static let thumbnailCompactionVersion = "kCPYThumbnailCompactionVersion"
    }

    struct Update {
        static let enableAutomaticCheck = "kCPYEnableAutomaticCheckKey"
        static let checkInterval = "kCPYUpdateCheckIntervalKey"
    }

    struct Notification {
        static let closeSnippetEditor = "kCPYSnippetEditorWillCloseNotification"
    }

    struct Xml {
        static let fileType = "xml"
        static let type = "type"
        static let rootElement = "folders"
        static let folderElement = "folder"
        static let snippetElement = "snippet"
        static let titleElement = "title"
        static let snippetsElement = "snippets"
        static let contentElement = "content"
    }

    struct HotKey {
        static let mainKeyCombo = "kCPYHotKeyMainKeyCombo"
        static let historyKeyCombo = "kCPYHotKeyHistoryKeyCombo"
        static let snippetKeyCombo = "kCPYHotKeySnippetKeyCombo"
        static let passwordVaultKeyCombo = "kPasteraHotKeyPasswordVaultKeyCombo"
        static let migrateNewKeyCombo = "kCPYMigrateNewKeyCombo"
        static let migrateOptionCommandDefaultKeyCombos = "kCPYMigrateOptionCommandDefaultKeyCombos"
        static let migrateSnippetDefaultKeyComboToF = "kCPYMigrateSnippetDefaultKeyComboToF"
        static let migratePasswordVaultDefaultKeyCombo = "kPasteraMigratePasswordVaultDefaultKeyCombo"
        static let historyPanelShortcutDefaultsMigrated = "kCPYHistoryPanelShortcutDefaultsMigrated"
        static let migrateHistoryPanelOptionCommand = "kCPYMigrateHistoryPanelOptionCommand"
        static let migrateHistoryPanelCanonicalDefaults = "kCPYMigrateHistoryPanelCanonicalDefaults"
        static let migrateHistoryPanelCanonicalDefaultsV2 = "kCPYMigrateHistoryPanelCanonicalDefaultsV2"
        static let migrateHistoryPanelCommandDefaults = "kCPYMigrateHistoryPanelCommandDefaults"
        static let historySearchKeyCombo = "kCPYHistorySearchKeyCombo"
        static let historyNextPageKeyCombo = "kCPYHistoryNextPageKeyCombo"
        static let historyPreviousPageKeyCombo = "kCPYHistoryPreviousPageKeyCombo"
        static let folderKeyCombos = "kCPYFolderKeyCombos"
        static let clearHistoryKeyCombo = "kCPYClearHistoryKeyCombo"
        static let scriptTransformKeyCombo = "kPasteraScriptTransformKeyCombo"
        static let suspendDuringRemoteSession = "kPasteraSuspendHotKeysDuringRemoteSession"
    }

}
