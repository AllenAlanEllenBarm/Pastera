# Contextual Shortcut Tooltips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the main-menu shortcut help entry and show each shortcut only in the native tooltip of its corresponding component.

**Architecture:** Keep shortcut presentation local to the existing AppKit controls. Remove the toolbar callback and popover view, then extend existing button and row tooltip configuration without introducing a custom overlay or new persistent UI.

**Tech Stack:** Swift, AppKit, Swift Testing, Xcode/xcodebuild

## Global Constraints

- Default UI must not gain persistent text, badges, or decoration.
- Use native macOS tooltips and existing shortcut formatting.
- Preserve all keyboard behaviors and unrelated worktree changes.
- Do not change panel sizing, colors, information architecture, or preferences behavior.

---

### Task 1: Remove the centralized shortcut entry

**Files:**
- Modify: `pasteraTests/MainMenuVisualPolishTests.swift`
- Modify: `pastera/Sources/Managers/MainMenuFooterButtons.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`

**Interfaces:**
- Consumes: `MainMenuToolbarView`, `MainMenuToolbarActions`
- Produces: a toolbar with no `mainMenuShortcutsButton` and no shortcut popover path

- [ ] **Step 1: Write the failing regression assertion**

Update `footerToolbarUsesUnifiedHitAreas` so the unified IDs omit `mainMenuShortcutsButton`, and add:

```swift
#expect(frames["mainMenuShortcutsButton"] == nil)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run `xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' -only-testing:pasteraTests/MainMenuVisualPolishTests/footerToolbarUsesUnifiedHitAreas`.

Expected: FAIL because `mainMenuShortcutsButton` still exists.

- [ ] **Step 3: Remove the shortcut button and popover path**

Remove `onShortcuts`, `shortcutsButtonX`, `shortcutsButtonClicked`, `MainMenuShortcutsPopoverView`, `shortcutsPopover`, `showShortcuts(relativeTo:)`, and the corresponding action wiring. Keep OneDrive and Preferences trailing positions unchanged so they close the space naturally.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2. Expected: PASS.

### Task 2: Attach shortcuts to their corresponding controls

**Files:**
- Modify: `pasteraTests/MainMenuVisualPolishTests.swift`
- Modify: `pastera/Sources/Managers/MainMenuFooterButtons.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify if required by current control ownership: `pastera/Sources/Managers/HistoryMenuPaginationState.swift`

**Interfaces:**
- Consumes: existing `toolTip` properties and `PasteraShortcutFormatter`
- Produces: native tooltip strings in the format `localized action · shortcut`

- [ ] **Step 1: Write failing tooltip assertions**

Expose existing toolbar/control/row tooltip strings through read-only testing accessors, then assert representative values:

```swift
#expect(controller.mainMenuToolbarToolTipForTesting(identifier: "mainMenuSearchButton")?.contains("⌘F") == true)
#expect(controller.mainMenuHeaderToolTipsForTesting["previous"]?.contains("←") == true)
#expect(controller.mainMenuHeaderToolTipsForTesting["typeFilter"]?.contains("Tab") == true)
#expect(controller.mainMenuRowToolTipForTesting(title: "First copied value")?.contains("↩") == true)
```

- [ ] **Step 2: Run the focused tooltip tests and verify RED**

Run `xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' -only-testing:pasteraTests/MainMenuVisualPolishTests`.

Expected: FAIL because the contextual tooltip contract is incomplete.

- [ ] **Step 3: Implement the minimal native tooltip text**

Set each tooltip at its owning component. Use concise localized action text followed by ` · ` and the applicable shortcut. For a row, combine only its paste actions and numeric direct-selection key; do not recreate the full shortcut list.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

### Task 3: Regression and visual acceptance

**Files:**
- Test: `pasteraTests/MainMenuVisualPolishTests.swift`
- Test: `pasteraTests/MainMenuPinFooterTests.swift`

**Interfaces:**
- Consumes: completed toolbar and tooltip behavior
- Produces: build, regression, and screenshot evidence

- [ ] **Step 1: Run relevant tests**

Run `xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' -only-testing:pasteraTests/MainMenuVisualPolishTests -only-testing:pasteraTests/MainMenuPinFooterTests`.

Expected: PASS with zero failures.

- [ ] **Step 2: Build the application**

Run `xcodebuild build -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS'`.

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Launch and capture evidence**

Launch the built app, open the main panel, and capture the default footer plus one hovered component. Confirm the question-mark button and large shortcut panel are absent, the footer has no visual hole, and the native tooltip does not cover the target control.

- [ ] **Step 4: Review the scoped diff**

Run `git diff --check`, then inspect the diff for the source and test files named above.

Expected: no whitespace errors and no unrelated changes introduced by this task.
