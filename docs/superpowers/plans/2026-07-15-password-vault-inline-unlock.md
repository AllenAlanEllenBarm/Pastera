# Password Vault Inline Unlock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace modal KDBX password prompts with a stable embedded create/unlock form that transitions in place to password folders and entries.

**Architecture:** `PasswordVaultUIController` becomes a UI-independent lifecycle facade with explicit state, create, password-unlock, and quick-unlock operations. `MainMenuPanelController` owns the presentation state and embeds a dedicated `PasswordVaultAccessView`; successful operations reload the existing vault list in place.

**Tech Stack:** Swift 6, AppKit, Swift Testing, KDBXKit 1.3.x, LocalAuthentication, macOS 15.

## Global Constraints

- Do not call `NSAlert.runModal()` or open another window for database creation or unlock.
- Keep master passwords only in transient `NSSecureTextField` values and clear them after submission.
- Attempt automatic quick unlock at most once per password-vault presentation; cancellation or failure must fall back to the inline master-password form.
- Preserve existing KDBX persistence, folder/entry UI, system authorization for sensitive actions, and secure clipboard behavior.
- Preserve unrelated dirty-worktree changes.

---

### Task 1: Explicit password-vault lifecycle facade

**Files:**
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Produces: `state: PasswordVaultState`, `canQuickUnlock: Bool`, `createDatabase(masterPassword:completion:)`, `unlock(masterPassword:completion:)`, and `unlockWithQuickKey(completion:)`.
- Consumes: existing `PasswordVaultStore.createDatabase`, `unlock`, `unlockWithQuickKey`, and `state`.

- [ ] **Step 1: Write failing facade tests**

Add tests with a recording `PasswordVaultStore` proving explicit create/unlock methods forward the supplied password, quick unlock is separately invokable, and no preparation method asks AppKit for input.

- [ ] **Step 2: Run the focused tests and verify RED**

Run the `PasswordVaultMenuTests` suite and expect compilation failures for the new lifecycle members.

- [ ] **Step 3: Implement the minimal lifecycle facade**

Remove `ensureVaultReady()` and `requestDatabasePassword(confirm:)`. Forward each explicit operation through the existing result/error conversion path, call `onChange` after success, and expose quick-unlock availability without loading the protected key.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run `PasswordVaultMenuTests`; expect the new facade tests and existing real-KDBX UI flow to pass.

### Task 2: Embedded access form and one-shot quick unlock

**Files:**
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: Task 1 lifecycle callbacks and `PasswordVaultState`.
- Produces: embedded `PasswordVaultAccessView`, presentation-owned access error/progress state, and a one-shot automatic quick-unlock transition.

- [ ] **Step 1: Write failing embedded-flow tests**

Add tests that assert an unconfigured store exposes two secure fields and no modal preparation button; a locked store exposes one secure field; submitting a correct password replaces the form with folder rows; a wrong password leaves the form visible with inline error; and reopening after a cancelled automatic quick unlock does not loop.

- [ ] **Step 2: Run the focused tests and verify RED**

Run `PasswordVaultMenuTests`; expect failures because the current preparation row only invokes `prepare` and the controller still lacks embedded access fields.

- [ ] **Step 3: Extend `MainMenuPasswordVaultDataSource`**

Replace `prepare` with state and explicit lifecycle closures. Wire them in `MenuManager` from the `PasswordVaultUIController` instance without duplicating KDBX operations in the menu coordinator.

- [ ] **Step 4: Implement `PasswordVaultAccessView`**

Build an AppKit vertical form using `NSSecureTextField`, inline status text, and primary/secondary buttons. Keep submitted values local to the view, validate confirmation locally, disable controls during submission, clear secrets after submission, and use stable accessibility identifiers for tests.

- [ ] **Step 5: Implement state-driven embedded rendering**

Replace `passwordVaultPreparationContent` with access content selected from `PasswordVaultState`. Attempt quick unlock once when password-vault mode is entered, reload in place on success, and retain the inline form on cancellation or failure.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run `PasswordVaultMenuTests`; expect all embedded state-transition and existing folder/entry tests to pass.

### Task 3: Relock transition and installed-app verification

**Files:**
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: store state changes delivered through the existing `onChange` reload path.
- Produces: unlocked-list to locked-form transition without closing the main panel.

- [ ] **Step 1: Write a failing relock test**

Keep the password-vault mode visible, change the store state from `unlocked` to `locked`, trigger `onChange`, and assert that folder rows are replaced by the embedded unlock form.

- [ ] **Step 2: Run the focused test and verify RED**

Expect the current cached content to remain visible or the access view not to render.

- [ ] **Step 3: Implement the minimal relock refresh**

Reset transient access state when leaving password-vault mode and render current store state whenever `onChange` reloads visible content. Do not automatically quick-unlock after session relock within the same presentation.

- [ ] **Step 4: Verify tests, build, install, and runtime**

Run focused password-vault tests, `git diff --check`, the full macOS build, `/Applications/Pastera.app` installation, `codesign --verify --deep --strict`, and an exact installed-process lookup. Confirm that no `NSAlert` password prompt remains in `PasswordVaultUIController`.
