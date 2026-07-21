// Copyright 2026 Feeyo

import Foundation

struct PasswordVaultSecuritySettingsState: Equatable {
    let vaultState: PasswordVaultState
    let isBusy: Bool
    let autoLockInterval: TimeInterval
    let quickUnlockEnabled: Bool
    let quickUnlockAvailable: Bool
}
