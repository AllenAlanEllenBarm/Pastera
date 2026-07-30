# Main Menu Shortcut Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the main shortcut always open history, fix history paging to bare arrow keys, change the default snippet shortcut to `⇧⌘M`, and add two-stage numeric folder/snippet navigation.

**Architecture:** Keep global shortcut registration in `HotKeyService`, entry routing in `MenuManager`, and transient keyboard state in `MainMenuPanelController`. Treat history search as the only configurable history-panel shortcut, derive snippet numeric stage from `expandedSnippetFolderID`, and reuse `HistoryMenuNumberShortcutMapper` for both badges and event routing.

**Tech Stack:** Swift 6, AppKit responder chain, Carbon/Magnet `KeyCombo`, Swift Testing, Xcode 26.5, macOS 13+.

## Global Constraints

- `⇧⌘V` always opens the unified panel in history mode, even after snippets or password vault.
- History previous/next page are fixed bare `←` and `→`; search remains configurable.
- Search or IME editing owns horizontal arrows and numeric text while its field editor is active.
- The snippet default changes to `⇧⌘M`; only the old default `⌥⌘F` migrates, while custom values remain untouched.
- Numeric navigation uses the existing `menuItemsTitleStartWithZero` contract and supports at most ten direct choices.
- Existing per-folder global shortcuts remain registered and editable.
- No new window, global key-sequence monitor, timer, persistence model, dependency, or password-vault behavior.

## File Responsibility Map

- `pastera/Sources/Managers/MenuManager.swift`: translate `.main` popup requests into a deterministic history entry.
- `pastera/Sources/Services/HotKeyService.swift`: own snippet default/migration and distinguish configurable search from fixed paging keys.
- `pastera/Sources/Constants.swift`: define the one-time snippet-default migration marker.
- `pastera/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift`: render only editable shortcuts.
- `pastera/Sources/Managers/HistoryBrowserPanelController.swift`: route fixed history keys without stealing text-editing events.
- `pastera/Sources/Managers/HistoryMenuPaginationState.swift`: preserve the search field’s responder-chain ownership of horizontal arrows.
- `pastera/Sources/Managers/MainMenuPanelController.swift`: render both folder number and folder global-shortcut badges and execute two-stage numeric navigation.
- `pasteraTests/MenuManagerStatusItemTests.swift`: protect main-entry mode reset.
- `pasteraTests/HotKeyServiceTests.swift`: protect fixed arrows and snippet default migration.
- `pasteraTests/ShortcutPreferenceResetTests.swift`: protect the simplified preferences surface.
- `pasteraTests/SnippetHotkeyPanelEntrypointTests.swift`: protect standalone history responder routing.
- `pasteraTests/MainMenuEmbeddedContentTests.swift`: protect two-stage snippet navigation and visible number badges.

## Scope / Out of Scope

In scope are the four shortcut/navigation behaviors, compatibility migration, focused tests, the repository regression command, and local reinstall. Out of scope are removing per-folder shortcuts, password-vault numeric navigation, changing item ordering, adding a timeout/HUD, pushing commits, and publishing a release.

## Acceptance

- Main popup after snippet or password-vault mode renders history.
- Fixed history paging accepts bare arrows, rejects business-modified arrows, and yields to search editing.
- Preferences contain five recorders: four menu shortcuts plus history search.
- Existing old-default snippet installs migrate to `⇧⌘M`; custom snippet shortcuts stay unchanged.
- First digit expands a folder; the next digit selects a snippet only from that folder.
- Folder and snippet number badges agree with one-based, zero-based, and tenth-item mapping.
- Focused tests, full tests, `git diff --check`, local install, and process verification complete successfully.

---

### Task 1: Make the main shortcut enter history deterministically

**Files:**
- Modify: `pastera/Sources/Managers/MenuManager.swift:195-208`
- Test: `pasteraTests/MenuManagerStatusItemTests.swift:159-175`

**Interfaces:**
- Consumes: `MainMenuPanelController.openHistoryFromMainMenu()`
- Produces: `.main`, `.history`, and `⇧⌘V` all enter `DisplayMode.history`; `.snippet` and `.passwordVault` remain unchanged.

- [ ] **Step 1: Write the failing regression test**

Add a test that first moves the reused controller through snippets and password vault, then calls `.main` and checks history each time:

```swift
@Test
func mainShortcutReturnsReusedUnifiedPanelToHistory() throws {
    try withRegisteredDefaultEnvironment { _, _ in
        let manager = MenuManager()

        manager.popUpMenu(.snippet)
        #expect(manager.mainMenuSelectedModeForTesting == "snippets")
        manager.popUpMenu(.main)
        #expect(manager.mainMenuSelectedModeForTesting == "history")

        manager.popUpMenu(.passwordVault)
        #expect(manager.mainMenuSelectedModeForTesting == "passwordVault")
        manager.popUpMenu(.main)
        #expect(manager.mainMenuSelectedModeForTesting == "history")
        manager.closeMainMenuPanelForTesting()
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/MenuManagerStatusItemTests
```

Expected: the assertion after `.main` fails because `MenuManager.popUpMenu(.main)` currently preserves `selectedMode`.

- [ ] **Step 3: Implement the smallest routing change**

Change only the `.main` branch:

```swift
switch type {
case .main, .history:
    panelController.openHistoryFromMainMenu()
case .snippet:
    panelController.openSnippetsFromMainMenu()
case .passwordVault:
    panelController.openPasswordVaultFromMainMenu()
}
```

- [ ] **Step 4: Re-run the focused test and verify GREEN**

Run the command from Step 2. Expected: `MenuManagerStatusItemTests` passes with zero failures.

- [ ] **Step 5: Commit the isolated increment**

```bash
git add pastera/Sources/Managers/MenuManager.swift pasteraTests/MenuManagerStatusItemTests.swift
git commit -m "fix(menu): make main shortcut open history"
```

### Task 2: Replace configurable history paging with fixed bare arrows

**Files:**
- Modify: `pastera/Sources/Services/HotKeyService.swift:37-129,256-485`
- Modify: `pastera/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift:20-231`
- Modify: `pastera/Sources/Managers/HistoryBrowserPanelController.swift:394-413`
- Modify: `pastera/Sources/Managers/HistoryMenuPaginationState.swift:721-750`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift:3568-3623`
- Test: `pasteraTests/HotKeyServiceTests.swift:54-195,249-301`
- Test: `pasteraTests/ShortcutPreferenceResetTests.swift:13-176`
- Test: `pasteraTests/SnippetHotkeyPanelEntrypointTests.swift:144-184`
- Test: `pasteraTests/MainMenuEmbeddedContentTests.swift`

**Interfaces:**
- Consumes: `HistoryPanelShortcut.matches(_:keyCombo:)`, `HistoryMenuHeaderView` search-focus ownership.
- Produces: `HistoryPanelShortcut.isUserConfigurable`, fixed `defaultKeyCombo` for paging, and `HotKeyService.historyPanelKeyCombo(for:)` that returns stored search or fixed paging values.

- [ ] **Step 1: Write failing service and preference tests**

Change expectations to literal fixed behavior:

```swift
#expect(service.historyPanelKeyCombo(for: .previousPage) ==
    KeyCombo(QWERTYKeyCode: 123, carbonModifiers: 0))
#expect(service.historyPanelKeyCombo(for: .nextPage) ==
    KeyCombo(QWERTYKeyCode: 124, carbonModifiers: 0))
```

Add a legacy/custom-value test that writes modified arrow combos into `UserDefaults`, calls `setupDefaultHotKeys()`, and still expects bare arrows. Update the preference test to expect five record views and no identifiers named `shortcuts.historyPanel.previousPage` or `shortcuts.historyPanel.nextPage`.

- [ ] **Step 2: Write failing responder-chain tests**

In the standalone history panel test fixture:

```swift
let left = try makeArrowEvent(keyCode: 123, modifierFlags: [])
let commandLeft = try makeArrowEvent(keyCode: 123, modifierFlags: [.command])

#expect(controller.handleHistoryPanelKeyDownForTesting(left))
#expect(!controller.handleHistoryPanelKeyDownForTesting(commandLeft))

controller.focusSearchFieldForTesting()
#expect(!controller.handleHistoryPanelKeyDownForTesting(left))
```

Add the equivalent unified-main-panel test: bare left/right changes page, while command-left/right does not.

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation test \
  -only-testing:pasteraTests/HotKeyServiceTests \
  -only-testing:pasteraTests/ShortcutPreferenceResetTests \
  -only-testing:pasteraTests/SnippetHotkeyPanelEntrypointTests \
  -only-testing:pasteraTests/MainMenuEmbeddedContentTests
```

Expected: defaults still produce `⌘←/⌘→`, preferences still expose seven recorders, and the search-focused bare arrow is consumed by paging.

- [ ] **Step 4: Make search the only user-configurable history-panel shortcut**

Add explicit configurability and fixed bare defaults:

```swift
var isUserConfigurable: Bool { self == .search }

var defaultKeyCombo: KeyCombo {
    switch self {
    case .search:
        KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey)!
    case .previousPage:
        KeyCombo(QWERTYKeyCode: 123, carbonModifiers: 0)!
    case .nextPage:
        KeyCombo(QWERTYKeyCode: 124, carbonModifiers: 0)!
    }
}
```

Make `setupHistoryPanelKeyCombos`, `changeHistoryPanelKeyCombo`, reset, and legacy migration loops operate only on `.search`. Make `historyPanelKeyCombo(for:)` return the fixed default for non-configurable cases. Leave old defaults keys untouched.

- [ ] **Step 5: Remove the two retired recorders**

Delete the previous/next `RecordView` properties and their setup, refresh, delegate, and row entries. Keep the History Panel group and its reset button because search remains configurable. Update tests to compare these five identifiers:

```swift
[
    "shortcuts.main",
    "shortcuts.history",
    "shortcuts.snippet",
    "shortcuts.passwordVault",
    "shortcuts.historyPanel.search"
]
```

- [ ] **Step 6: Preserve text editing and require bare modifiers**

Rename the header predicate to `shouldPreserveSearchFieldEditingEvent(_:)` and return `true` for left/right key codes whenever the search field owns focus, before checking Command editing shortcuts. In the unified main panel, normalize device-independent flags by subtracting `.numericPad` and `.function`, and enter the history left/right switch only when the result is empty.

- [ ] **Step 7: Re-run focused tests and verify GREEN**

Run the command from Step 3. Expected: all four selected suites pass with zero failures.

- [ ] **Step 8: Commit the isolated increment**

```bash
git add pastera/Sources/Services/HotKeyService.swift \
  pastera/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift \
  pastera/Sources/Managers/HistoryBrowserPanelController.swift \
  pastera/Sources/Managers/HistoryMenuPaginationState.swift \
  pastera/Sources/Managers/MainMenuPanelController.swift \
  pasteraTests/HotKeyServiceTests.swift \
  pasteraTests/ShortcutPreferenceResetTests.swift \
  pasteraTests/SnippetHotkeyPanelEntrypointTests.swift \
  pasteraTests/MainMenuEmbeddedContentTests.swift
git commit -m "refactor(shortcuts): fix history paging to arrow keys"
```

### Task 3: Change and safely migrate the default snippet shortcut

**Files:**
- Modify: `pastera/Sources/Constants.swift:131-151`
- Modify: `pastera/Sources/Services/HotKeyService.swift:134-159,256-427`
- Test: `pasteraTests/HotKeyServiceTests.swift:35-52,220-247,438-513,640-660`
- Test: `pasteraTests/ShortcutPreferenceResetTests.swift:13-45`

**Interfaces:**
- Consumes: `HotKeyService.setupDefaultHotKeys()` and existing one-time migration pattern.
- Produces: `Constants.HotKey.migrateSnippetDefaultKeyComboToShiftCommandM` and a default snippet `KeyCombo(QWERTYKeyCode: 46, carbonModifiers: cmdKey | shiftKey)`.

- [ ] **Step 1: Write failing default, reset, migration, and preservation tests**

Use literal expectations:

```swift
let expected = try #require(KeyCombo(QWERTYKeyCode: 46, carbonModifiers: cmdKey | shiftKey))
#expect(service.snippetKeyCombo == expected)
#expect(PasteraShortcutFormatter.string(for: expected) == "⇧⌘M")
```

Add one test with saved old-default `⌥⌘F` and a false new migration marker that expects `⇧⌘M`. Add a second test with a custom snippet combo that expects the custom value to survive while the marker becomes true.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation test \
  -only-testing:pasteraTests/HotKeyServiceTests \
  -only-testing:pasteraTests/ShortcutPreferenceResetTests
```

Expected: the service and reset still return `⌥⌘F`, and the new migration marker/API does not exist.

- [ ] **Step 3: Implement the one-time migration**

Define both values so equality uses the old literal rather than the changed default:

```swift
private static let previousDefaultSnippetKeyCombo =
    KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | optionKey)!
private static let defaultSnippetKeyCombo =
    KeyCombo(QWERTYKeyCode: 46, carbonModifiers: cmdKey | shiftKey)!
```

Call the new migration after the older migrations:

```swift
private func migrateSnippetDefaultKeyComboToShiftCommandMIfNeeded() {
    guard !defaults.bool(forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToShiftCommandM) else { return }
    migrateDefaultKeyComboIfNeeded(
        forKey: Constants.HotKey.snippetKeyCombo,
        legacyDefault: Self.previousDefaultSnippetKeyCombo,
        newDefault: Self.defaultSnippetKeyCombo
    )
    defaults.set(true, forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToShiftCommandM)
    defaults.synchronize()
}
```

Update the default dictionary, reset path, formatter expectations, and migration sentinel list.

- [ ] **Step 4: Re-run focused tests and verify GREEN**

Run the command from Step 2. Expected: both selected suites pass with zero failures.

- [ ] **Step 5: Commit the isolated increment**

```bash
git add pastera/Sources/Constants.swift pastera/Sources/Services/HotKeyService.swift \
  pasteraTests/HotKeyServiceTests.swift pasteraTests/ShortcutPreferenceResetTests.swift
git commit -m "feat(shortcuts): default snippets to shift command m"
```

### Task 4: Add two-stage numeric folder and snippet navigation

**Files:**
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift:408-445,1603-1754,3532-3560,5070-5600,5900-5960`
- Test: `pasteraTests/MainMenuEmbeddedContentTests.swift:522-840`

**Interfaces:**
- Consumes: `expandedSnippetFolderID`, `enabledSnippetFolderDetails()`, `visibleSnippetIDs`, and `HistoryMenuNumberShortcutMapper`.
- Produces: `visibleSnippetFolderIDs: [SnippetFolder.ID]`, `MainMenuPanelRowView` support for a leading item-number badge plus its existing trailing command badge, and two-stage `confirmNumberShortcut(_:)`.

- [ ] **Step 1: Write failing first-stage and second-stage behavior tests**

Build two enabled folders with two snippets each, open snippets, then verify:

```swift
let firstDigit = try makeTextEvent("1", keyCode: 18)
let secondDigit = try makeTextEvent("2", keyCode: 19)

#expect(controller.handleMainMenuNavigationForTesting(firstDigit))
#expect(controller.mainMenuExpandedSnippetFolderIDForTesting == firstFolderID)
#expect(selectedSnippetID == nil)

#expect(controller.handleMainMenuNavigationForTesting(secondDigit))
#expect(selectedSnippetID == firstFolderSnippets[1].id)
```

Add separate cases for zero-based first folder, `0` selecting the tenth folder/item, an empty expanded folder returning `false`, and an active search/editor leaving digit input unconsumed by numeric selection.

- [ ] **Step 2: Write failing badge tests**

Assert every folder has a leading number and a configured folder still retains its command badge:

```swift
#expect(controller.mainMenuRowItemNumberTextForTesting(title: "AI Prompt") == "1")
#expect(controller.mainMenuRowShortcutTextForTesting(title: "AI Prompt") == "⌥⌘Q")
```

After expanding the folder, assert its snippets expose `1`, `2`, and the tenth item exposes `0`.

- [ ] **Step 3: Run the focused suite and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/MainMenuEmbeddedContentTests
```

Expected: the first digit returns `false` because `visibleSnippetIDs` is empty, and the folder row has no numeric badge API.

- [ ] **Step 4: Render folder and snippet number badges from the shared mapper**

Reset `visibleSnippetFolderIDs` during content reload. In `makeSnippetContent()`, enumerate enabled details, append each folder ID, and pass `numericShortcutText(forRowIndex:)` as a leading item number while keeping `folderShortcutText` as the existing trailing command shortcut.

Extend `MainMenuPanelRowView` with:

```swift
private let itemNumberBadge = PasteraShortcutBadgeView(style: .itemNumber)

init(
    title: String,
    image: NSImage?,
    shortcutText: String? = nil,
    itemNumberText: String? = nil,
    // existing arguments remain unchanged
)
```

Place `itemNumberBadge` at the row’s leading inset, then place the image/title after it. Keep `shortcutBadge` at the trailing edge for folder global shortcuts. Migrate snippet rows to `itemNumberText` so one path owns number styling and test exposure.

- [ ] **Step 5: Implement two-stage event routing**

Branch only inside `.snippets`:

```swift
case .snippets:
    if expandedSnippetFolderID == nil {
        guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
            for: event,
            startsAtZero: startsAtZero,
            rowCount: visibleSnippetFolderIDs.count
        ) else { return false }
        expandSnippetFolder(visibleSnippetFolderIDs[rowIndex])
        return true
    }

    guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
        for: event,
        startsAtZero: startsAtZero,
        rowCount: visibleSnippetIDs.count
    ) else { return false }
    confirmSnippetSelection(visibleSnippetIDs[rowIndex])
    return true
```

Keep this call after IME, search-field, inline-editor, and folder-shortcut-editor guards so digit input remains text in those states.

- [ ] **Step 6: Re-run the focused suite and verify GREEN**

Run the command from Step 3. Expected: `MainMenuEmbeddedContentTests` passes with zero failures.

- [ ] **Step 7: Commit the isolated increment**

```bash
git add pastera/Sources/Managers/MainMenuPanelController.swift \
  pasteraTests/MainMenuEmbeddedContentTests.swift
git commit -m "feat(snippets): add two-stage numeric navigation"
```

### Task 5: Run regression and install verification

**Files:**
- Verify only: all files changed by Tasks 1-4

**Interfaces:**
- Consumes: all behavior produced by Tasks 1-4.
- Produces: fresh build, test, diff, install, and running-process evidence.

- [ ] **Step 1: Run whitespace validation**

```bash
git diff --check origin/develop...HEAD
```

Expected: no output and exit code `0`.

- [ ] **Step 2: Run the repository regression command**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  clean test
```

Expected: `** TEST SUCCEEDED **` with zero failed tests.

- [ ] **Step 3: Reinstall and launch the built application**

```bash
./script/install_local.sh
```

Expected: the script replaces `/Applications/Pastera.app`, ad-hoc signs it, and launches Pastera successfully.

- [ ] **Step 4: Verify the installed process**

```bash
pgrep -x Pastera
```

Expected: at least one numeric PID and exit code `0`.

- [ ] **Step 5: Review the final scoped diff**

```bash
git status --short --branch
git diff origin/develop...HEAD --stat
git log --oneline --decorate origin/develop..HEAD
```

Expected: only the approved design, plan, source, and test files appear; the implementation branch is ahead of `origin/develop` and has not been pushed.

## Risks / Rollback

- Bare arrows can conflict with text caret movement; responder-focus tests and exact modifier matching are the rollback gate.
- Adding a second badge can compress long folder titles; existing compact-width layout tests and real app inspection are required.
- Migration can overwrite custom shortcuts if equality uses the new default; the test must seed both old-default and custom values.
- If any regression or install check fails, stop before claiming completion. The feature can be rolled back by reverting the implementation commits while retaining the approved specification and plan.
