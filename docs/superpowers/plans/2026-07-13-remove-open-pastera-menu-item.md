# Remove Open Pastera Menu Item Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant “Open Pastera” item from the status-item context menu while preserving left-click main-panel behavior.

**Architecture:** Change the existing menu builder and its focused tests only. Remove the now-unreferenced selector instead of retaining dead routing code.

**Tech Stack:** Swift, AppKit, Swift Testing, Xcode/xcodebuild

## Global Constraints

- History becomes the first context-menu item.
- Keep all remaining menu groups and order unchanged.
- Preserve left-click main-panel routing and right-click context-menu routing.
- Preserve unrelated worktree changes.

---

### Task 1: Remove the redundant context-menu entry

**Files:**
- Modify: `pasteraTests/MenuManagerStatusItemTests.swift`
- Modify: `pastera/Sources/Managers/MenuManagerStatusItem.swift`

**Interfaces:**
- Consumes: `MenuManager.makeStatusItemContextMenu()` and `statusItemClickAction(for:)`
- Produces: a context menu whose first actionable item is History

- [ ] **Step 1: Update tests first**

Remove `Open Pastera` from the expected ordered titles, assert lookup by that title returns `nil`, and retain the assertion that `.leftMouseUp` maps to `mainPanel`.

- [ ] **Step 2: Run focused tests and verify RED**

Run `xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' -skipPackagePluginValidation -skipMacroValidation -only-testing:pasteraTests/MenuManagerStatusItemTests`.

Expected: the title/absence assertions fail because the item still exists.

- [ ] **Step 3: Implement the minimal removal**

Delete the `Open Pastera` item construction and remove `openMainPanelFromContextMenu()`. Do not change `statusItemButtonClicked(_:)`.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2. Expected: the affected menu-order, absence, routing, and icon tests pass.

- [ ] **Step 5: Build and inspect the scoped diff**

Run `xcodebuild build -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' -skipPackagePluginValidation -skipMacroValidation`, `git diff --check`, and verify no `Open Pastera` production reference remains.

Expected: `** BUILD SUCCEEDED **`, no whitespace errors, and no production reference to the removed item or selector.
