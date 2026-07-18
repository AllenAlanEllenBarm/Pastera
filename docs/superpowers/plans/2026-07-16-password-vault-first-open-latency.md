# Password Vault First-Open Latency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the password-vault panel appear immediately even when the first Keychain query is slow.

**Architecture:** The panel owns a cached quick-unlock availability state and never queries Security Framework while rendering. `PasswordVaultUIController` performs the Keychain capability check on its existing serial store queue and publishes the result on the main thread; automatic quick unlock starts only after the panel is already visible.

**Tech Stack:** Swift 6, AppKit, Security Framework, Swift Testing, KDBXKit.

## Global Constraints

- Preserve the embedded password-vault UI and existing master-password fallback.
- Do not weaken `ThisDeviceOnly + userPresence` protection.
- Do not put KDBX or Keychain work on the main thread.
- Preserve existing dirty workspace changes.

---

### Task 1: Prove the first-open blocking regression

**Files:**
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: `MainMenuPasswordVaultDataSource`
- Produces: regression coverage proving a pending quick-unlock check does not delay the locked form.

- [x] Add a test data source whose quick-unlock check captures its completion without completing.
- [x] Open and show the password vault, then assert the secure master-password field is already visible.
- [x] Run `PasswordVaultMenuTests` and verify the new test fails because rendering still invokes the synchronous Keychain capability closure.

### Task 2: Move Keychain capability checks off the main thread

**Files:**
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Produces: `checkQuickUnlockAvailability(completion: @escaping (Bool) -> Void)`.
- Produces: asynchronous `MainMenuPasswordVaultDataSource.checkQuickUnlockAvailability`.

- [x] Replace synchronous `canQuickUnlock` reads in menu rendering with the asynchronous data-source operation.
- [x] Execute `store.canQuickUnlock` on `PasswordVaultUIController.storeQueue` and complete on the main thread.
- [x] Cache availability in the panel as unknown/checking/available/unavailable.
- [x] Render the locked form immediately with quick unlock hidden while availability is unknown or checking.
- [x] After the first render cycle, check availability; automatically unlock when available and retain the manual quick-unlock button after cancellation.
- [x] Run the regression test and the full password-vault menu suite.

### Task 3: Verify and install

**Files:**
- Test: `pasteraTests/PasswordVaultMenuTests.swift`
- Test: `pasteraTests/PasswordVaultStoreTests.swift`

**Interfaces:**
- Consumes: the asynchronous quick-unlock boundary from Task 2.
- Produces: build, UI-flow, signing, and installed-process evidence.

- [x] Run focused menu and store tests, including real temporary KDBX creation/unlock.
- [x] Run `git diff --check` and a clean Debug build.
- [x] Install the built app at `/Applications/Pastera.app` without overlaying stale bundle resources.
- [x] Run strict `codesign` verification and confirm the installed process starts.
