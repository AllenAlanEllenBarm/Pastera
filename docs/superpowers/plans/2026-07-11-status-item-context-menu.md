# Pastera Status Item Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native right-click menu and route every history, snippet, and password-vault entry through the unified Pastera main interface.

**Architecture:** `MenuManagerStatusItem.swift` owns mouse-event routing, native menu construction, dynamic validation, and narrow action adapters. `MenuManager.popUpMenu(_:)` becomes the single mode-routing boundary: it creates the main controller, selects the requested embedded mode, and shows the same main interface for hotkeys and context-menu actions. Existing `AppDelegate`, preferences, repositories, and Sparkle updater remain the business owners.

**Tech Stack:** Swift 6, AppKit `NSStatusItem`/`NSMenu`, Sparkle, Swift Testing, Xcode.

## Global Constraints

- Left click continues to open the existing main panel attached to the status item.
- Right click opens an independent native `NSMenu`; do not permanently assign `statusItem.menu`.
- The exact visible item order is: Open Pastera, History, Snippet, Password Vault, separator, Manage Snippets, Clear History, separator, Preferences, Check for Updates…, About Pastera, separator, Quit Pastera.
- Clear History is disabled when the history repository is empty.
- Check for Updates… is disabled when Sparkle is unavailable or cannot check.
- About Pastera opens the existing About preference pane; do not create a second window.
- Main, History, Snippet, and Password Vault hotkeys all open the same `MainMenuPanelController`; mode-specific hotkeys select their matching embedded mode.
- Remove the secure-input legacy `NSMenu` fallback and all normal product routes to standalone history and snippet browser panels.
- Secure Keyboard Entry can block global hotkeys before Pastera receives them; the orange status icon and tooltip must direct users to click the status item instead of promising a keyboard bypass.
- After Secure Keyboard Entry ends, registered hotkeys resume without reconfiguration.
- Use SF Symbols without making icons the only accessible labels.
- Do not add Quick Reply, Clipboard Stack, Pause Monitoring, standalone OCR, standalone OneDrive, or a custom floating-menu UI.
- Preserve all unrelated dirty and untracked workspace changes.

---

### Task 1: Native menu model and dynamic availability

**Files:**
- Modify: `pastera/Sources/Managers/MenuManagerStatusItem.swift`
- Modify: `pastera/Sources/Managers/MenuManagerTestingSupport.swift`
- Test: `pasteraTests/MenuManagerStatusItemTests.swift`

**Interfaces:**
- Consumes: `pasteboardHistoryRepository.hasHistories()`, `NSApp.delegate as? AppDelegate`, `AppDelegate.updaterController?.updater.canCheckForUpdates`.
- Produces: `func makeStatusItemContextMenu() -> NSMenu`, `var statusItemContextMenuTitlesForTesting: [String]`, `func statusItemContextMenuItemForTesting(title: String) -> NSMenuItem?`.

- [ ] **Step 1: Write failing menu-structure and availability tests**

Add tests that build `MenuManager` inside the existing `withStatusItemTestEnvironment` helper and assert the exact non-separator titles:

```swift
@Test @MainActor
func contextMenuContainsOnlyExistingPasteraCapabilitiesInOrder() throws {
    try withStatusItemTestEnvironment { _, _ in
        let manager = MenuManager()
        #expect(manager.statusItemContextMenuTitlesForTesting == [
            "Open Pastera", "History", "Snippet", "Password Vault",
            "Manage Snippets", "Clear History", "Preferences",
            "Check for Updates…", "About Pastera", "Quit Pastera"
        ])
    }
}

@Test @MainActor
func contextMenuDisablesClearHistoryWhenRepositoryIsEmpty() throws {
    try withStatusItemTestEnvironment { _, _ in
        let manager = MenuManager()
        let item = try #require(manager.statusItemContextMenuItemForTesting(title: "Clear History"))
        #expect(item.isEnabled == false)
    }
}
```

Also assert that every non-separator item has a non-nil image and that `Check for Updates…` is disabled when there is no app delegate/updater in the unit-test host.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation test \
  -only-testing:pasteraTests/MenuManagerStatusItemTests
```

Expected: FAIL because the context-menu testing interfaces do not exist.

- [ ] **Step 3: Implement the minimal native menu builder**

In `MenuManagerStatusItem.swift`, add `makeStatusItemContextMenu()` with standard `NSMenuItem` instances and three separators. Use localized titles and these symbols: `macwindow`, `clock.arrow.circlepath`, `text.quote`, `key`, `square.and.pencil`, `trash`, `gearshape`, `arrow.triangle.2.circlepath`, `info.circle`, and `power`.

Each actionable item must set an explicit target (`self` for `MenuManager` adapters and `nil` for responder-chain `AppDelegate` actions). After construction, set:

```swift
clearHistoryItem.isEnabled = pasteboardHistoryRepository.hasHistories()
checkForUpdatesItem.isEnabled = (NSApp.delegate as? AppDelegate)?
    .updaterController?.updater.canCheckForUpdates == true
```

In `MenuManagerTestingSupport.swift`, expose titles and lookup by calling the real menu builder:

```swift
var statusItemContextMenuTitlesForTesting: [String] {
    makeStatusItemContextMenu().items.filter { !$0.isSeparatorItem }.map(\.title)
}

func statusItemContextMenuItemForTesting(title: String) -> NSMenuItem? {
    makeStatusItemContextMenu().items.first { $0.title == title }
}
```

- [ ] **Step 4: Run the test and verify GREEN**

Run the Task 1 command again. Expected: PASS with zero failures.

- [ ] **Step 5: Commit Task 1**

```bash
git add -p pastera/Sources/Managers/MenuManagerStatusItem.swift \
  pastera/Sources/Managers/MenuManagerTestingSupport.swift \
  pasteraTests/MenuManagerStatusItemTests.swift
git commit -m "feat(menu): define status item context menu"
```

### Task 2: Left/right click routing and feature actions

**Files:**
- Modify: `pastera/Sources/Managers/MenuManagerStatusItem.swift`
- Modify: `pastera/Sources/Managers/MenuManagerTestingSupport.swift`
- Test: `pasteraTests/MenuManagerStatusItemTests.swift`

**Interfaces:**
- Consumes: Task 1 `makeStatusItemContextMenu()`, unified `popUpMenu(_:)` routing from Task 3, `NSMenu.popUp(positioning:at:in:)`.
- Produces: `func handleStatusItemClick(eventType: NSEvent.EventType, button: NSStatusBarButton)`, action adapters `openMainPanelFromContextMenu`, `openHistoryFromContextMenu`, `openSnippetFromContextMenu`, `openPasswordVaultFromContextMenu`, and a test-injectable menu popup closure.

- [ ] **Step 1: Write failing event-routing and selector tests**

Add tests that inject counters through DEBUG testing hooks, call the event router directly, and assert:

```swift
manager.handleStatusItemClickForTesting(eventType: .leftMouseUp, button: button)
#expect(mainPanelOpenCount == 1)
#expect(contextMenuPopupCount == 0)

manager.handleStatusItemClickForTesting(eventType: .rightMouseUp, button: button)
#expect(mainPanelOpenCount == 1)
#expect(contextMenuPopupCount == 1)
```

Assert menu selectors map as follows:

```swift
#expect(item("Open Pastera").action == #selector(MenuManager.openMainPanelFromContextMenu))
#expect(item("History").action == #selector(MenuManager.openHistoryFromContextMenu))
#expect(item("Snippet").action == #selector(MenuManager.openSnippetFromContextMenu))
#expect(item("Password Vault").action == #selector(MenuManager.openPasswordVaultFromContextMenu))
#expect(item("Manage Snippets").action == #selector(AppDelegate.showSnippetEditorWindow))
#expect(item("Clear History").action == #selector(AppDelegate.clearAllHistory))
#expect(item("Preferences").action == #selector(AppDelegate.showPreferenceWindow))
#expect(item("Quit Pastera").action == #selector(AppDelegate.terminate))
```

- [ ] **Step 2: Run the test and verify RED**

Run the Task 1 test command. Expected: FAIL because event routing and action adapters do not exist.

- [ ] **Step 3: Implement event routing and adapters**

Change the existing button action to route using the current event:

```swift
@objc func statusItemButtonClicked(_ sender: NSStatusBarButton) {
    handleStatusItemClick(eventType: NSApp.currentEvent?.type ?? .leftMouseUp, button: sender)
}

func handleStatusItemClick(eventType: NSEvent.EventType, button: NSStatusBarButton) {
    if eventType == .rightMouseUp {
        let menu = makeStatusItemContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        return
    }
    showMainMenuPanelFromStatusItemFrame(button.window?.frame)
}
```

Implement the four `@objc` adapters by using the status-item frame for the main interface and the `.history`, `.snippet`, and `.passwordVault` unified routes from Task 3 for the other entries. Ensure context-menu tracking has ended before opening the main interface by dispatching the action to the next main-queue turn.

Add DEBUG hooks that replace only the popup and main-panel calls, so tests verify real branching without displaying UI.

- [ ] **Step 4: Run the test and verify GREEN**

Run the Task 1 command again. Expected: PASS with zero failures.

- [ ] **Step 5: Commit Task 2**

```bash
git add -p pastera/Sources/Managers/MenuManagerStatusItem.swift \
  pastera/Sources/Managers/MenuManagerTestingSupport.swift \
  pasteraTests/MenuManagerStatusItemTests.swift
git commit -m "feat(menu): route status item right clicks"
```

### Task 3: Unify hotkeys and feature entries in the main interface

**Files:**
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pastera/Sources/Managers/MenuManagerTestingSupport.swift`
- Test: `pasteraTests/MenuManagerStatusItemTests.swift`
- Test: `pasteraTests/MainMenuEmbeddedContentTests.swift`
- Test: `pasteraTests/SnippetHotkeyPanelEntrypointTests.swift`

**Interfaces:**
- Consumes: `MainMenuPanelController.openHistoryFromMainMenu()`, `openSnippetsFromMainMenu()`, `openPasswordVaultFromMainMenu()`, and `show(at:pinned:)`.
- Produces: one `MenuManager.popUpMenu(_:)` path that displays `MainMenuPanelController` for `.main`, `.history`, `.snippet`, and `.passwordVault`; DEBUG `mainMenuSelectedModeForTesting` evidence.

- [ ] **Step 1: Write failing unified-entry tests**

Replace the secure-input fallback expectations with assertions that both secure and normal states choose the main interface. Add entry tests that call `popUpMenu(.history)`, `popUpMenu(.snippet)`, and `popUpMenu(.passwordVault)` and assert the main controller mode is respectively `history`, `snippets`, and `passwordVault`, while `historyBrowserPanelFrameForTesting` and `snippetBrowserPanelFrameForTesting` remain nil.

```swift
manager.secureEventInputEnabledProvider = { true }
manager.popUpMenu(.history)
#expect(manager.mainMenuSelectedModeForTesting == "history")
#expect(manager.historyBrowserPanelFrameForTesting == nil)

manager.popUpMenu(.snippet)
#expect(manager.mainMenuSelectedModeForTesting == "snippets")
#expect(manager.snippetBrowserPanelFrameForTesting == nil)
```

- [ ] **Step 2: Run targeted suites and verify RED**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation test \
  -only-testing:pasteraTests/MenuManagerStatusItemTests \
  -only-testing:pasteraTests/MainMenuEmbeddedContentTests \
  -only-testing:pasteraTests/SnippetHotkeyPanelEntrypointTests
```

Expected: FAIL because history/snippet still create standalone panels and secure input still routes to legacy menus.

- [ ] **Step 3: Implement the unified mode router**

Remove `shouldUseLegacyMenuFallback` and `popUpLegacyMenu(_:)`. In `popUpMenu(_:)`, always obtain `mainMenuPanelController ?? makeMainMenuPanelController()`, store it, select a mode when needed, then show it once:

```swift
func popUpMenu(_ type: MenuType, triggerKeyCombo: KeyCombo? = nil) {
    let controller = mainMenuPanelController ?? makeMainMenuPanelController()
    mainMenuPanelController = controller
    switch type {
    case .main:
        break
    case .history:
        controller.openHistoryFromMainMenu()
    case .snippet:
        controller.openSnippetsFromMainMenu()
    case .passwordVault:
        controller.openPasswordVaultFromMainMenu()
    }
    controller.show(at: NSEvent.mouseLocation, pinned: false)
    installPanelDismissMonitorsIfNeeded()
}
```

Keep `triggerKeyCombo` temporarily source-compatible until all call sites are migrated, but do not use it to create a standalone panel. Remove legacy-mode testing support and replace it with selected-main-mode evidence.

- [ ] **Step 4: Update the secure-input notice**

Change the notice copy to state that macOS has paused global shortcuts and that clicking the Pastera menu bar icon opens the app. Keep the orange status item tint and matching tooltip; do not suggest that Pastera can bypass Secure Keyboard Entry.

- [ ] **Step 5: Run targeted suites and verify GREEN**

Run the Task 3 command again. Expected: PASS with zero failures.

- [ ] **Step 6: Remove unreachable standalone panel product routes**

Delete normal calls from `makeMainMenuPanelController`, context menu actions, and hotkeys to `showHistoryBrowserPanel`/`showSnippetBrowserPanel`. Keep standalone controller source files only if still required by focused legacy tests; otherwise remove the source files and their project references after confirming `rg` finds no production callers.

- [ ] **Step 7: Commit Task 3**

```bash
git add -p pastera/Sources/Managers/MenuManager.swift \
  pastera/Sources/Managers/MenuManagerTestingSupport.swift \
  pastera/Resources/Localizable.xcstrings \
  pasteraTests/MenuManagerStatusItemTests.swift \
  pasteraTests/MainMenuEmbeddedContentTests.swift \
  pasteraTests/SnippetHotkeyPanelEntrypointTests.swift
git commit -m "refactor(menu): unify feature entries in main interface"
```

### Task 4: About-pane and Sparkle update routes

**Files:**
- Modify: `pastera/Sources/AppDelegate.swift`
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- Modify: `pastera/Sources/Managers/MenuManagerStatusItem.swift`
- Test: `pasteraTests/MenuManagerStatusItemTests.swift`
- Test: `pasteraTests/PreferenceWindowInteractionRegressionTests.swift`

**Interfaces:**
- Consumes: `PasteraPreferencePaneID.about`, `CPYPreferencesWindowController.sharedController`, `SPUUpdater.checkForUpdates()`.
- Produces: `CPYPreferencesWindowController.showPreferencePane(_:)`, `AppDelegate.showAboutPreferencePane()`, `AppDelegate.checkForUpdatesFromMenu()`.

- [ ] **Step 1: Write failing route tests**

In preference-window tests, create/show the controller, call the production pane API, and assert:

```swift
controller.showPreferencePane(.about)
#expect(controller.selectedPreferencePaneIDForTesting == .about)
```

In status-item tests, assert selectors:

```swift
#expect(item("Check for Updates…").action == #selector(AppDelegate.checkForUpdatesFromMenu))
#expect(item("About Pastera").action == #selector(AppDelegate.showAboutPreferencePane))
```

- [ ] **Step 2: Run both suites and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation test \
  -only-testing:pasteraTests/MenuManagerStatusItemTests \
  -only-testing:pasteraTests/PreferenceWindowInteractionRegressionTests
```

Expected: FAIL because the three production routes do not exist.

- [ ] **Step 3: Implement narrow routes**

Expose a production wrapper around the existing private switch logic:

```swift
func showPreferencePane(_ paneID: PasteraPreferencePaneID) {
    switchView(paneID)
}
```

Add AppDelegate actions:

```swift
@objc func showAboutPreferencePane() {
    NSApp.activate(ignoringOtherApps: true)
    let controller = CPYPreferencesWindowController.sharedController
    controller.showWindow(self)
    controller.showPreferencePane(.about)
}

@objc func checkForUpdatesFromMenu() {
    guard updaterController?.updater.canCheckForUpdates == true else { return }
    updaterController?.updater.checkForUpdates()
}
```

Wire the two context-menu items to these selectors.

- [ ] **Step 4: Run both suites and verify GREEN**

Run the Task 4 command again. Expected: PASS with zero failures.

- [ ] **Step 5: Commit Task 3**

```bash
git add -p pastera/Sources/AppDelegate.swift \
  pastera/Sources/Preferences/CPYPreferencesWindowController.swift \
  pastera/Sources/Managers/MenuManagerStatusItem.swift \
  pasteraTests/MenuManagerStatusItemTests.swift \
  pasteraTests/PreferenceWindowInteractionRegressionTests.swift
git commit -m "feat(menu): connect app management actions"
```

### Task 5: Localization, regression verification, and live UI acceptance

**Files:**
- Modify: `pastera/Resources/Localizable.xcstrings`
- Test: `pasteraTests/MenuManagerStatusItemTests.swift`

**Interfaces:**
- Consumes: all Task 1-4 interfaces.
- Produces: localized English, German, Italian, Japanese, and Simplified Chinese titles for newly introduced strings.

- [ ] **Step 1: Add failing localization assertions**

Extend the existing localization-oriented status-item test to assert Simplified Chinese values for the new keys, including `Open Pastera` → `打开 Pastera`, `Manage Snippets` → `管理片段`, and `Check for Updates…` → `检查更新…`.

- [ ] **Step 2: Run status-item tests and verify RED**

Run the Task 1 command. Expected: FAIL because the new localized values are absent.

- [ ] **Step 3: Add catalog entries**

Add translations for every new key introduced by Tasks 1-3. Reuse existing catalog keys for History, Snippet, Password Vault, Clear History, Preferences, About Pastera, and Quit Pastera where available; do not create duplicates that differ only by punctuation.

- [ ] **Step 4: Run targeted suites**

Run the Task 4 command. Expected: PASS with zero failures.

- [ ] **Step 5: Run the full build**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Install and verify the real status-item interactions**

Use the repository's existing build/install workflow. Launch the freshly built Pastera, then verify with the real macOS UI:

1. Left-click the Pastera menu bar icon and confirm the existing main panel opens attached to the icon.
2. Close it, right-click the icon, and confirm the native menu opens without the main panel.
3. Confirm all titles, icons, separators, and enabled states match the specification.
4. Activate History, Snippet, and Password Vault one at a time; confirm each opens the same main interface in its matching mode and no standalone panel appears.
5. Activate Manage Snippets, Preferences, Check for Updates…, About Pastera, and Clear History (cancel the destructive confirmation) one at a time.
6. Confirm About Pastera selects the existing About preference pane.
7. Enable Secure Keyboard Entry in a password field, confirm the status icon becomes orange, confirm hotkeys are system-blocked, and confirm clicking the icon still opens the unified main interface.
8. End Secure Keyboard Entry and confirm the registered hotkeys resume without reconfiguration.
9. Do not activate Quit until all other checks have completed; then confirm it terminates the app.

- [ ] **Step 7: Review the scoped diff and commit**

```bash
git diff --check
git diff --stat
git status --short
git add -p pastera/Resources/Localizable.xcstrings pasteraTests/MenuManagerStatusItemTests.swift
git commit -m "feat(menu): localize status item shortcuts"
```

Only stage files and hunks attributable to this plan. If a listed file contains pre-existing user changes, stage the task hunks interactively or leave the commit to the user rather than including unrelated changes.
