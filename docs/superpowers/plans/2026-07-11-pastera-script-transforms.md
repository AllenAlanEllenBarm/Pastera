# Pastera Script Transforms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local JavaScript script center that transforms plain-text clipboard content on copy, Pastera-initiated paste, or one configurable global shortcut.

**Architecture:** Store ordered script definitions in SQLiteData, evaluate immutable script snapshots through a JavaScriptCore service, and route copy/paste/manual events through one coordinator. Extend the existing AppKit settings catalog and HotKeyService rather than creating parallel settings or shortcut systems.

**Tech Stack:** macOS 13+, Swift, AppKit, JavaScriptCore, SQLiteData, Tagged, Magnet/KeyHolder, Swift Testing, Xcode 26.5.

## Global Constraints

- JavaScript is local-only: no network, file system, Shell, process launch, native-object bridge, or arbitrary system API.
- Only plain text is transformed; images, files, rich text, audio, and video retain current behavior.
- `transform(clip)` receives `text` and optional `sourceAppBundleIdentifier` and must return a string; empty string is valid.
- Matching enabled scripts run in stable order as one atomic pipeline; any failure restores the original input.
- Copy writeback must suppress recursive execution and produce one final history item.
- Paste transforms only Pastera-initiated paste and does not intercept system `⌘V`.
- One global manual shortcut updates the clipboard and never auto-pastes.
- Scripts remain local in v1 and do not enter OneDrive sync.
- Preserve all unrelated dirty and untracked files in the current worktree.

---

### Task 1: Script model, migration, and repository

**Files:**
- Modify: `pastera/Sources/Database/SQLiteDataSchema.swift`
- Modify: `pastera/Sources/Database/SQLiteDataMigrator.swift`
- Create: `pastera/Sources/Models/ScriptTransform.swift`
- Create: `pastera/Sources/Repositories/ScriptRepository.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Test: `pasteraTests/Database/SQLiteDataMigratorTests.swift`
- Create: `pasteraTests/Repositories/ScriptRepositoryTests.swift`

**Interfaces:**
- Produces: `ScriptTransform`, `ScriptTrigger`, `ScriptRepositoryProtocol`, and `ScriptRepository`.
- `ScriptRepositoryProtocol.fetchAll() throws -> [ScriptTransform]` returns `sortIndex`, then `createdAt`, then ID order.
- `ScriptRepositoryProtocol.fetchEnabled(for trigger: ScriptTrigger) throws -> [ScriptTransform]` filters enabled rows by the selected trigger flag.
- `insert(_:)`, `update(_:)`, `delete(id:)`, and `replaceOrder(ids:)` are the only persistence mutations exposed to UI and runtime services.

- [ ] **Step 1: Write migration and repository tests that fail before the table and types exist**

```swift
@Test func scriptMigrationCreatesLocalScriptTableWithoutChangingExistingRows() throws {
    let database = try makeMigratedDatabase(through: 5)
    let columns = try database.columns(in: "scriptTransforms").map(\.name)
    #expect(columns == ["id", "name", "code", "isEnabled", "runOnCopy", "runOnPaste", "runManually", "sortIndex", "createdAt", "updatedAt"])
}

@Test func enabledScriptsUseStableOrderAndTriggerFilter() throws {
    let repository = try makeRepository()
    try repository.insert(.fixture(name: "second", runOnCopy: true, sortIndex: 20))
    try repository.insert(.fixture(name: "first", runOnCopy: true, sortIndex: 10))
    try repository.insert(.fixture(name: "paste", runOnPaste: true, sortIndex: 0))
    #expect(try repository.fetchEnabled(for: .copy).map(\.name) == ["first", "second"])
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/SQLiteDataMigratorTests \
  -only-testing:pasteraTests/ScriptRepositoryTests test
```

Expected: compilation fails because `ScriptTransform` and migration v5 do not exist.

- [ ] **Step 3: Add the schema model and migration**

```swift
@Table
struct ScriptTransformRecord: Identifiable, Equatable {
    typealias ID = Tagged<Self, UUID>
    @Column(primaryKey: true) let id: ID
    let name: String
    let code: String
    let isEnabled: Bool
    let runOnCopy: Bool
    let runOnPaste: Bool
    let runManually: Bool
    let sortIndex: Int
    let createdAt: Int
    let updatedAt: Int
}
```

Register migration v5 and create the strict `scriptTransforms` table plus an index on `(sortIndex, createdAt)`; do not modify migrations v1-v4.

- [ ] **Step 4: Add the domain model and repository implementation**

```swift
enum ScriptTrigger: Sendable { case copy, paste, manual }

struct ScriptTransform: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var code: String
    var isEnabled: Bool
    var runOnCopy: Bool
    var runOnPaste: Bool
    var runManually: Bool
    var sortIndex: Int
    let createdAt: Int
    var updatedAt: Int
}
```

Map between the domain UUID and tagged record ID inside `ScriptRepository`; keep SQLiteData query details out of callers.

- [ ] **Step 5: Run focused tests and commit the independently working persistence slice**

Expected: both focused suites pass and `git diff --check` reports no errors.

```bash
git add pastera/Sources/Database pastera/Sources/Models/ScriptTransform.swift \
  pastera/Sources/Repositories/ScriptRepository.swift pasteraTests/Database/SQLiteDataMigratorTests.swift \
  pasteraTests/Repositories/ScriptRepositoryTests.swift pastera.xcodeproj/project.pbxproj
git commit -m "feat: persist script transforms"
```

### Task 2: JavaScript execution service

**Files:**
- Create: `pastera/Sources/Services/ScriptExecutionService.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/ScriptExecutionServiceTests.swift`

**Interfaces:**
- Consumes: ordered `[ScriptTransform]` snapshots from Task 1.
- Produces: `ScriptExecuting.execute(scripts:input:) async -> Result<String, ScriptExecutionError>`.
- `ScriptExecutionInput` contains `text: String` and `sourceAppBundleIdentifier: String?`.
- `ScriptExecutionError` distinguishes source/input limit, missing transform, JavaScript exception, invalid result, timeout, and capacity exhaustion without embedding clipboard content.

- [ ] **Step 1: Verify the SDK termination primitive before choosing the worker implementation**

Run:

```bash
rg -n "shouldTerminate|JSContextGroupSetExecutionTimeLimit|ExecutionTimeLimit" \
  "$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/JavaScriptCore.framework/Headers"
```

Expected: either a supported public time-limit API is present, or no public termination API is found. Record the actual result in the implementation comments and choose the matching bounded worker described in Step 3.

- [ ] **Step 2: Write failing contract tests**

```swift
@Test func executesOrderedAtomicPipeline() async throws {
    let scripts = [
        .fixture(code: "function transform(clip) { return clip.text.trim(); }", sortIndex: 0),
        .fixture(code: "function transform(clip) { return clip.text.toUpperCase(); }", sortIndex: 1)
    ]
    let result = await service.execute(scripts: scripts, input: .init(text: " hi ", sourceAppBundleIdentifier: nil))
    #expect(try result.get() == "HI")
}

@Test func rejectsNativeBridgeAndNonStringResults() async {
    let result = await service.execute(
        scripts: [.fixture(code: "function transform(clip) { return 42; }")],
        input: .init(text: "safe", sourceAppBundleIdentifier: nil)
    )
    #expect(result == .failure(.invalidResult(scriptID: scripts[0].id)))
}
```

Also cover empty output, missing function, thrown exception, atomic rollback, source/input limits, infinite loop timeout, and bounded capacity after repeated timeouts.

- [ ] **Step 3: Implement the minimal isolated executor**

Create a fresh `JSContext` per script and call the function without evaluating interpolated user data:

```swift
let clip = JSValue(newObjectIn: context)!
clip.setValue(input.text, forProperty: "text")
clip.setValue(input.sourceAppBundleIdentifier, forProperty: "sourceAppBundleIdentifier")
guard let function = context.objectForKeyedSubscript("transform"), !function.isUndefined else {
    throw ScriptExecutionError.missingTransform(scriptID: script.id)
}
let result = function.call(withArguments: [clip])
```

If the SDK exposes a supported execution limit, use it directly. Otherwise execute each context on a dedicated bounded worker, race it against a deadline, discard late output, and reject new tasks once the fixed worker budget is occupied; never run script code on the main thread or the shared serial coordinator queue.

- [ ] **Step 4: Run the execution tests and commit**

Expected: all `ScriptExecutionServiceTests` pass, including the real infinite-loop test within its outer test deadline.

```bash
git add pastera/Sources/Services/ScriptExecutionService.swift pasteraTests/ScriptExecutionServiceTests.swift pastera.xcodeproj/project.pbxproj
git commit -m "feat: execute local JavaScript transforms"
```

### Task 3: Clipboard coordinator and copy/paste/manual integration

**Files:**
- Create: `pastera/Sources/Services/ClipboardScriptCoordinator.swift`
- Modify: `pastera/Sources/Services/ClipService.swift`
- Modify: `pastera/Sources/Services/PasteService.swift`
- Modify: `pastera/Sources/Services/HotKeyService.swift`
- Modify: `pastera/Sources/Constants.swift`
- Modify: `pastera/Sources/Environments/Environment.swift`
- Modify: `pastera/Sources/Environments/AppEnvironment.swift`
- Modify: `pastera/Sources/AppDelegate.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/ClipboardScriptCoordinatorTests.swift`
- Modify: `pasteraTests/HotKeyServiceTests.swift`
- Modify: `pasteraTests/MenuPanelSelectionDismissalTests.swift`

**Interfaces:**
- Consumes: `ScriptRepositoryProtocol` and `ScriptExecuting`.
- Produces: `transform(text:sourceAppBundleIdentifier:trigger:) async -> ScriptTransformOutcome` and `runManualTransform()`.
- `ScriptTransformOutcome` is `.unchanged`, `.transformed(String)`, or `.failed(ScriptExecutionError)`.
- Copy-loop suppression consumes the exact pasteboard `changeCount` produced by coordinator writeback once and never suppresses unrelated external changes.

- [ ] **Step 1: Write failing coordinator and integration tests**

```swift
@Test func copyWritebackIsCapturedOnceWithoutRetransforming() async throws {
    let pasteboard = TestPasteboard(text: "hello")
    let coordinator = makeCoordinator(output: "HELLO", pasteboard: pasteboard)
    await coordinator.handleCopiedText("hello", sourceAppBundleIdentifier: "test.app")
    #expect(pasteboard.string == "HELLO")
    #expect(coordinator.consumeSuppression(changeCount: pasteboard.changeCount))
    #expect(!coordinator.consumeSuppression(changeCount: pasteboard.changeCount))
}
```

Add tests proving non-text bypass, failure fallback, Pastera paste uses transformed payload, manual execution does not post a paste event, shortcut registration/change/clear, and remote-session restore.

- [ ] **Step 2: Implement coordinator and environment wiring**

```swift
protocol ClipboardScriptCoordinating: AnyObject {
    func transform(text: String, sourceAppBundleIdentifier: String?, trigger: ScriptTrigger) async -> ScriptTransformOutcome
    func handleCopiedText(_ text: String, sourceAppBundleIdentifier: String?)
    func runManualTransform()
    func consumeSuppression(changeCount: Int) -> Bool
}
```

Construct the concrete repository, executor, and coordinator once in `Environment.fromStorage`; inject them into services rather than reading global state inside execution tests.

- [ ] **Step 3: Extend the existing copy and paste paths**

In `ClipService`, check the suppression token before transforming; delay history persistence for eligible text until the transform resolves, then save only the final text. In `PasteService`, transform the prepared plain-text payload before calling the existing target-restore and paste event path; on failure use the original payload.

- [ ] **Step 4: Register one manual hotkey through existing HotKeyService state**

Add `Constants.HotKey.scriptTransformKeyCombo`, persist it using the same archived `KeyCombo` format, register identifier `ScriptTransform`, and route the selector to `clipboardScriptCoordinator.runManualTransform()`.

- [ ] **Step 5: Run integration tests and commit**

Expected: coordinator, hotkey, paste, and existing clipboard-focused suites pass.

```bash
git add pastera/Sources/Services pastera/Sources/Constants.swift pastera/Sources/Environments \
  pastera/Sources/AppDelegate.swift pasteraTests/ClipboardScriptCoordinatorTests.swift \
  pasteraTests/HotKeyServiceTests.swift pasteraTests/MenuPanelSelectionDismissalTests.swift pastera.xcodeproj/project.pbxproj
git commit -m "feat: apply scripts to clipboard workflows"
```

### Task 4: Script settings page and editor

**Files:**
- Modify: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift`
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- Create: `pastera/Sources/Preferences/Panels/CPYScriptsPreferenceViewController.swift`
- Create: `pastera/Sources/Preferences/Panels/ScriptEditorViewController.swift`
- Modify: `pastera/Sources/Preferences/PasteraPreferenceComponents.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/ScriptPreferenceTests.swift`
- Modify: `pasteraTests/PreferenceSearchTests.swift`
- Modify: `pasteraTests/PreferenceWindowShellTests.swift`

**Interfaces:**
- Consumes: repository, execution service, and `HotKeyService` from Tasks 1-3.
- Produces: `.scripts` preference pane, searchable anchors `scripts.list` and `scripts.shortcut`, and an editor that saves only validated drafts.

- [ ] **Step 1: Write failing catalog, page, and editor tests**

```swift
@Test func scriptsPaneIsRegisteredAndSearchable() throws {
    let page = try #require(PasteraPreferenceCatalog.default.pages.first { $0.paneID == .scripts })
    #expect(page.title == pasteraPreferenceString("Scripts"))
    #expect(page.searchItems.map(\.anchorID) == ["scripts.list", "scripts.shortcut"])
}

@Test func invalidDraftCannotSaveButEmptyStringOutputIsVisible() async throws {
    let controller = makeEditor(code: "function transform(clip) { return ''; }")
    #expect(controller.canSaveForTesting)
    await controller.runTestForTesting(input: "Hello")
    #expect(controller.testOutputForTesting == "")
    #expect(controller.testErrorForTesting == nil)
}
```

Cover empty state, enabled toggle, edit cancel, deletion confirmation, name/trigger/function validation, manual shortcut row, and dark/light layout invariants.

- [ ] **Step 2: Extend the pane enum, catalog, controller factory, and search metadata**

Add `.scripts` between history/shortcuts and service pages using symbol `curlybraces.square`; update exhaustive switches and existing expected pane arrays.

- [ ] **Step 3: Build the AppKit list page with existing design components**

Reuse `PasteraPreferencePage`, section cards, switches, buttons, colors, and spacing. Empty state contains one primary “New Script” button; populated rows show name, trigger summary, enabled switch, edit, and delete. The shortcut row uses the existing KeyHolder recorder and `HotKeyService` mutation API.

- [ ] **Step 4: Build the editor and test runner**

Use an AppKit sheet with name, master switch, three trigger checkboxes, `NSTextView` in a scroll view using `NSFont.monospacedSystemFont`, test input, result/error, Cancel, and Save. Run test evaluation asynchronously and marshal UI updates to the main actor.

- [ ] **Step 5: Add localized strings and run focused UI tests**

Run `jq empty pastera/Resources/Localizable.xcstrings` and the three focused UI/search test suites. Expected: JSON is valid and all suites pass.

- [ ] **Step 6: Commit the complete user-facing settings slice**

```bash
git add pastera/Sources/Preferences pastera/Resources/Localizable.xcstrings \
  pasteraTests/ScriptPreferenceTests.swift pasteraTests/PreferenceSearchTests.swift \
  pasteraTests/PreferenceWindowShellTests.swift pastera.xcodeproj/project.pbxproj
git commit -m "feat: add script settings center"
```

### Task 5: Regression, installation, and real behavior verification

**Files:**
- Modify only if verification exposes a script-feature defect: files introduced or touched in Tasks 1-4.
- Update: `docs/superpowers/plans/2026-07-11-pastera-script-transforms.md` checkboxes and evidence notes.

**Interfaces:**
- Consumes the complete feature.
- Produces passing automated evidence and an installed `/Applications/Pastera.app` ready for user acceptance.

- [ ] **Step 1: Run focused script and affected regression suites**

Run the script repository, execution, coordinator, hotkey, paste, preference, search, database migration, and clipboard history suites. Expected: all selected tests pass without hanging on the infinite-loop case.

- [ ] **Step 2: Run static and data-format checks**

```bash
git diff --check
jq empty pastera/Resources/Localizable.xcstrings
```

Expected: both commands exit 0.

- [ ] **Step 3: Run the repository regression command**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation clean test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Install and verify the real application**

```bash
./script/install_local.sh
codesign --verify --deep --strict /Applications/Pastera.app
ps -axo pid,command | rg '/Applications/Pastera\.app/Contents/MacOS/Pastera$'
```

Expected: installation exits 0, codesign verification exits 0, and exactly one installed-app process is shown.

- [ ] **Step 5: Verify the visible and clipboard behavior**

Create `Uppercase` with `return clip.text.toUpperCase();`; confirm editor test returns `HELLO WORLD`, copy trigger yields one `HELLO WORLD` history item, Pastera paste transforms and returns focus to the prior app, manual shortcut changes the clipboard without sending paste, and disabling the script restores current behavior. Capture screenshots or accessibility-tree evidence for the scripts list and editor.

- [ ] **Step 6: Review the final diff against every specification requirement**

Confirm the diff contains no network/native bridge, sync integration, non-text mutation, four-shortcut expansion, or unrelated cleanup. Record any manual-only user acceptance item separately; do not claim it from unit tests.
