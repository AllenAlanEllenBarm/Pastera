# Script Settings and Offline Market Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unclear temporary scripts preference UI with a OneClip-inspired card home, a dedicated editor sheet, and a separate offline template-market sheet.

**Architecture:** Keep `ScriptRepositoryProtocol`, `ScriptExecutionService`, and `HotKeyService` as the existing behavior boundaries. Add a pure `ScriptTemplateCatalog`, then make the preference page coordinate two focused AppKit controllers: one editor and one read-only template browser; choosing a template creates only an unsaved draft until the editor validates and saves it.

**Tech Stack:** macOS 13+, Swift, AppKit, JavaScriptCore, KeyHolder, Swift Testing, Xcode 26.5.

## Global Constraints

- Template data is bundled and offline; no network, upload, account, rating, remote update, or OneDrive sync.
- The page uses Pastera semantic colors and existing preference spacing while following OneClip's information hierarchy.
- Template selection opens a prefilled editor and does not write to SQLite until Save.
- Save requires a non-empty name, at least one trigger, a `transform(clip)` function, and a successful validation execution.
- Preserve unrelated dirty and untracked worktree files.

---

### Task 1: Offline template catalog

**Files:**
- Create: `pastera/Sources/Models/ScriptTemplate.swift`
- Create: `pastera/Sources/Services/ScriptTemplateCatalog.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/ScriptTemplateCatalogTests.swift`

**Interfaces:**
- Produces `ScriptTemplate`, `ScriptTemplateCategory`, and `ScriptTemplateCatalog.search(query:category:) -> [ScriptTemplate]`.
- `ScriptTemplate.makeDraft(now:) -> ScriptTransform` produces a new UUID and never persists.

- [ ] **Step 1: Write failing catalog tests**

```swift
@Test func catalogContainsRequiredOfflineTemplates() {
    #expect(Set(ScriptTemplateCatalog.default.templates.map(\.id)) == [
        "plain-text", "uppercase", "lowercase", "format-json", "minify-json",
        "remove-blank-lines", "date-to-timestamp", "extract-email", "extract-url",
        "extract-phone", "extract-ip", "base64-encode", "base64-decode"
    ])
}

@Test func templateSearchMatchesNameSummaryAndCategory() {
    let catalog = ScriptTemplateCatalog.default
    #expect(catalog.search(query: "JSON", category: .all).map(\.id) == ["format-json", "minify-json"])
    #expect(catalog.search(query: "", category: .extract).allSatisfy { $0.category == .extract })
}

@Test func templateDraftGetsFreshIdentityWithoutPersistence() {
    let template = ScriptTemplateCatalog.default.templates[0]
    #expect(template.makeDraft(now: 100).id != template.makeDraft(now: 100).id)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' \
  -derivedDataPath /tmp/pastera-script-derived -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/ScriptTemplateCatalogTests
```

Expected: compile failure because catalog types do not exist.

- [ ] **Step 3: Implement immutable templates, categories, search, and draft conversion**

Define category cases `all`, `text`, `json`, and `extract`. Search uses localized case-insensitive matching over name, summary, and keywords while preserving catalog order. Every bundled program defines `function transform(clip)` and returns a string.

- [ ] **Step 4: Run focused tests and verify GREEN**

Expected: required IDs, filtering, search ordering, and fresh draft identity pass.

### Task 2: Validating script editor sheet

**Files:**
- Replace: `pastera/Sources/Preferences/Panels/ScriptEditorViewController.swift`
- Create: `pasteraTests/ScriptPreferenceTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes `ScriptTransform?`, `ScriptExecuting`, and `(ScriptTransform) -> Void`.
- Produces a four-card sheet and testing hooks for draft validation and test output.

- [ ] **Step 1: Write failing editor-state tests**

```swift
@Test @MainActor func editorRequiresNameTriggerFunctionAndSuccessfulValidation() async {
    let editor = makeEditor(code: "function transform(clip) { return clip.text; }")
    editor.setNameForTesting("Identity")
    editor.setTriggerForTesting(.manual, enabled: true)
    #expect(!editor.canSaveForTesting)
    await editor.validateForTesting(input: "Hello")
    #expect(editor.canSaveForTesting)
}

@Test @MainActor func emptyStringTestOutputIsShownAsSuccess() async {
    let editor = makeEditor(code: "function transform(clip) { return ''; }")
    await editor.validateForTesting(input: "Hello")
    #expect(editor.testOutputForTesting == "")
    #expect(editor.testErrorForTesting == nil)
}
```

- [ ] **Step 2: Run and verify RED**

Expected: missing validation API and test runner hooks.

- [ ] **Step 3: Build the OneClip-style sheet**

Use a fixed header with Cancel/Save and a scroll document containing Basic Information, Execution Configuration, Script Code, and Test Script cards. Execute a one-script immutable draft through `ScriptExecuting`; update result/error and save eligibility on the main actor. Editing any validated field invalidates the prior validation result.

- [ ] **Step 4: Verify editor tests GREEN**

Cover cancel without mutation, template-prefilled fields, new UUID preservation, existing ID preservation, empty output, JS error, and disabled Save.

### Task 3: Secondary offline template-market sheet

**Files:**
- Create: `pastera/Sources/Preferences/Panels/ScriptTemplateMarketViewController.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pasteraTests/ScriptPreferenceTests.swift`

**Interfaces:**
- Consumes `ScriptTemplateCatalog` and `(ScriptTemplate) -> Void`.
- Produces search, local category filters, template cards, Add actions, and Done dismissal.

- [ ] **Step 1: Write failing market interaction tests**

```swift
@Test @MainActor func marketFiltersAndSelectsTemplateWithoutSaving() {
    let probe = TemplateSelectionProbe()
    let controller = ScriptTemplateMarketViewController(onSelect: probe.select)
    controller.loadViewIfNeeded()
    controller.searchForTesting("URL")
    #expect(controller.visibleTemplateIDsForTesting == ["extract-url"])
    controller.selectTemplateForTesting(id: "extract-url")
    #expect(probe.selectedIDs == ["extract-url"])
}
```

- [ ] **Step 2: Run and verify RED**

Expected: market controller is undefined.

- [ ] **Step 3: Implement the secondary sheet**

Create a title/subtitle header with Done, a search field, category controls, and scrollable cards containing name, summary, code preview, and an accessible Add button. Selection calls the closure once; persistence remains outside this controller.

- [ ] **Step 4: Verify market tests GREEN**

Cover search, category, empty result, stable ordering, Add accessibility label, and Done.

### Task 4: Card-style scripts home and flow coordination

**Files:**
- Replace: `pastera/Sources/Preferences/Panels/CPYScriptsPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift`
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift` only if needed to reuse its recorder component
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pasteraTests/ScriptPreferenceTests.swift`
- Modify: `pasteraTests/PreferenceSearchTests.swift`
- Modify: `pasteraTests/PreferenceWindowShellTests.swift`

**Interfaces:**
- Coordinates repository CRUD, editor presentation, template-market presentation, delete confirmation, and the single manual shortcut.

- [ ] **Step 1: Write failing page-flow tests**

Test empty-state action titles, populated script summaries, whole-row edit, enabled toggle, delete confirmation, New Script sheet, Template Market sheet, template-to-editor handoff without early insert, save insert/update, and manual shortcut description.

- [ ] **Step 2: Run and verify RED**

Expected: the temporary page lacks cards, editor/market coordination, and test hooks.

- [ ] **Step 3: Replace the temporary page**

Build one My Scripts card with empty/populated states and New Script / Create from Template actions. Hide Import in v1 rather than show an inert control. Add a separate Manual Run card using the existing KeyHolder recording pattern and `changeScriptTransformKeyCombo`. Template selection dismisses the market then presents the editor with `makeDraft(now:)`; only editor Save calls repository insert.

- [ ] **Step 4: Add localization and accessibility**

Add Chinese and English strings for page, editor, categories, template summaries, actions, errors, and VoiceOver labels. Ensure every icon-only Add control includes the template name in its accessibility label.

- [ ] **Step 5: Run affected UI/search tests**

Expected: script page, catalog, preference shell, and search tests pass.

### Task 5: Verification and runtime acceptance

**Files:**
- Modify only script-setting files if verification exposes defects.

- [ ] **Step 1: Run script-focused suites**

Run template catalog, script preference, repository, execution, coordinator, paste, hotkey, preference search, and preference shell suites with isolated DerivedData.

- [ ] **Step 2: Run static checks**

Run `git diff --check` and `jq empty pastera/Resources/Localizable.xcstrings`; both must exit 0.

- [ ] **Step 3: Build the macOS app**

Run the existing macOS build with plugin/macro validation skipped. If unrelated dirty-worktree compilation failures remain, record their exact files and verify all script-setting source files compile before that failure.

- [ ] **Step 4: Install and visually inspect**

Install the local build only after a complete app build succeeds. Capture the script home, editor sheet, and template market in both appearance modes; verify focus order and template-to-editor-to-save behavior.
