# Hierarchy-Scoped Create Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Place the single create button inside its actual folder hierarchy and make its action unambiguous.

**Architecture:** Build the root-folder create row only after all collapsed folder groups. Build the password/snippet create row inside the expanded folder group immediately after its entries. Replace the menu-backed generic create view with a direct icon action whose indentation is explicitly root-level or child-level.

**Tech Stack:** Swift, AppKit, Swift Testing, Xcodebuild.

## Global Constraints

- Password vault and snippets use identical hierarchy rules.
- Exactly one create button is visible in edit mode and none is visible outside edit mode or during search.
- Folders remain root-level only and cannot be nested.
- Preserve unrelated dirty workspace changes.

---

### Task 1: Specify hierarchy placement with failing tests

**Files:**
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: existing main-menu testing accessors for button identifiers, visible row order, frames, and context menus.
- Produces: regression coverage for root placement, child placement, direct action, switching, and snippets.

- [ ] Add assertions that a collapsed password-vault tree has one folder-create button after the final folder, aligned with folder icons, and no password-create button.
- [ ] Add assertions that expanding an empty or populated folder removes the root create button and inserts one password-create button immediately after that folder's last entry, before the next folder, aligned with entry icons.
- [ ] Add the equivalent snippet assertions and assert neither create button exposes an `NSMenu`.
- [ ] Run `PasswordVaultMenuTests` and confirm failures identify the current global trailing row, wrong indentation, and menu-backed action.

### Task 2: Move create rows into their owning hierarchy

**Files:**
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: `expandedPasswordVaultFolderID`, `expandedSnippetFolderID`, `isWorkspaceEditing`, and current folder/entry row builders.
- Produces: root `MainMenuCreateActionView` rows and child create rows embedded in the expanded folder group.

- [ ] Replace `MainMenuCreateActionsView` menu behavior with one direct action and an explicit indentation level.
- [ ] Append the password-create row to `folderRows + entryRows` for the expanded folder; append the folder-create row only when no password folder is expanded.
- [ ] Apply the same structure to snippets, including empty folders and switching the expanded folder.
- [ ] Preserve the existing edit-mode, search-mode, and guarded creation preconditions.
- [ ] Run both focused menu suites and confirm all hierarchy assertions pass.

### Task 3: Visual and installed-app verification

**Files:**
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: same-size AppKit snapshot helper and local install script.
- Produces: collapsed, empty-expanded, populated-expanded, and snippet screenshots plus an installed app.

- [ ] Capture and inspect the four required states, checking that root “+” aligns with folder icons and child “+” aligns with entry icons.
- [ ] Run `git diff --check` and the focused Xcode test suites.
- [ ] Run `./script/install_local.sh --verify`, then validate `/Applications/Pastera.app` signing and running process.
