# Password Vault Contextual Quick Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the permanent password-vault guidance card with contextual username, password, and more actions on the selected password row.

**Architecture:** Extend the existing `MainMenuPanelRowView` accessory chain with a small reusable quick-action model and button stack. Password-vault row construction supplies actions in normal mode and keeps delete-only presentation in edit mode. A controller-owned overlay presents the one-time coachmark without participating in scroll layout.

**Tech Stack:** Swift 6, AppKit, SF Symbols, Swift Testing, UserDefaults.

## Global Constraints

- Preserve the current dark compact main-menu design and fixed panel size.
- Do not add a new window, popover, dependency, custom SVG, or password-history write.
- Reuse the existing password-vault paste, context-menu, keyboard, and authentication paths.
- Keep all unrelated dirty-worktree changes intact.

---

### Task 1: Contextual password-row actions

**Files:**
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: existing `pastePasswordVaultUsername`, `pastePasswordVaultPassword`, and `MainMenuPanelRowView.makeContextMenu()`.
- Produces: `MainMenuPanelRowView.QuickAction` and row-visible quick-action buttons.

- [ ] **Step 1: Write failing interaction tests**

Add a Swift Testing case that opens an unlocked vault with two entries, verifies the permanent guidance title is absent, selects one entry, and expects these visible identifiers only on that row:

```swift
[
    "mainMenuPasswordPasteUsernameButton",
    "mainMenuPasswordPastePasswordButton",
    "mainMenuPasswordMoreButton"
]
```

Click the first two buttons and assert the existing paste callbacks each run once. Click More and assert its menu contains Paste Username, Paste Password, Edit, and Delete Password.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -project pastera.xcodeproj -scheme pastera -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-derived-data \
  -clonedSourcePackagesDirPath .spm-cache/SourcePackages \
  -skipPackagePluginValidation -skipMacroValidation test \
  -only-testing:pasteraTests/PasswordVaultMenuTests
```

Expected: the guidance-removal and quick-action identifier expectations fail.

- [ ] **Step 3: Implement minimal row actions**

Add a `QuickAction` model containing identifier, symbol name, title, optional shortcut text, and action. Build 20-point borderless buttons in `MainMenuPanelRowView`, show them only when the row is hovered or keyboard-selected, and route a menu action to the row's existing context menu.

In `makePasswordVaultContent()`, remove `PasswordVaultGuidanceView` and provide the three actions only when `isWorkspaceEditing == false`.

- [ ] **Step 4: Verify GREEN**

Run the focused suite again. Expected: all `PasswordVaultMenuTests` pass.

### Task 2: Edit-mode priority and first-use coachmark

**Files:**
- Modify: `pastera/Sources/Constants.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: `AppEnvironment.current.defaults`, keyboard-entry roles, and the existing content surface.
- Produces: `Constants.UserDefaults.passwordVaultQuickActionsCoachmarkShown` and a transient controller-owned coachmark overlay.

- [ ] **Step 1: Write failing state tests**

Verify that normal mode hides the inline delete button while retaining Delete Password in the context menu, edit mode hides all quick-action identifiers and exposes the inline delete button, and the coachmark appears once without changing content-row frames.

- [ ] **Step 2: Run the focused suite and verify RED**

Use the Task 1 command. Expected: edit-mode priority and coachmark expectations fail.

- [ ] **Step 3: Implement minimal state behavior**

Add a separate `showsDeleteButton` input so context-menu deletion can remain available while the inline delete icon is hidden in normal mode. When selection moves to a password-entry role, show a noninteractive bottom overlay only if the local preference is false, persist true immediately, then fade and remove it after two seconds.

- [ ] **Step 4: Verify GREEN and screenshots**

Run the focused suite, write normal and edit-mode snapshots, and visually inspect both at the existing panel size.

### Task 3: Regression verification and local installation

**Files:**
- Verify only.

**Interfaces:**
- Consumes: completed Tasks 1 and 2.
- Produces: build, test, installation, and signature evidence.

- [ ] **Step 1: Run password-vault and embedded-menu suites**

Expected: password-vault and embedded-content suites pass. Report any pre-existing visual-token expectation mismatch separately.

- [ ] **Step 2: Run repository checks**

Run `git diff --check` and the Debug build. Expected: exit code 0.

- [ ] **Step 3: Install and verify**

Run `./script/install_local.sh --verify`, then `codesign --verify --deep --strict --verbose=2 /Applications/Pastera.app`. Expected: the installed process runs from `/Applications/Pastera.app` and signature verification succeeds.
