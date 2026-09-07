// Copyright 2026 Feeyo

import Foundation

struct PasswordVaultSecuritySettingsState: Equatable {
    let vaultState: PasswordVaultState
    let isBusy: Bool
    let autoLockInterval: TimeInterval
    let quickUnlockEnabled: Bool
    let quickUnlockAvailable: Bool
    // swiftlint:disable:next inclusive_language
    let masterPasswordResetCapability: PasswordVaultMasterPasswordResetCapability
    let forcedResetPending: Bool
    let forcedResetPendingFailure: PasswordVaultSyncFailure?
}

struct PasswordVaultForcedResetOutcome: Equatable {
    let localArchiveDigest: String
    let oneDriveReplacementPending: Bool
    let warnings: [PasswordVaultForcedResetWarning]
}
