# Script Settings Compact Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vertically oversized Scripts settings page with the confirmed compact scripts section and shared test/shortcut tools card.

**Architecture:** Keep all behavior in `CPYScriptsPreferenceViewController` and reorganize only its AppKit view composition. Add layout-focused test hooks to the existing preference tests, preserve the repository/executor/hotkey chains, then validate with tests, installation, and real screenshots.

**Tech Stack:** Swift, AppKit, Swift Testing, xcodebuild, macOS Computer Use

## Global Constraints

- Preserve script persistence, JavaScript execution, template, editing, deletion, enablement, and shortcut behavior.
- Use 16pt page module spacing and approximately 16pt card padding.
- The empty scripts state must not reserve 220pt of vertical space.
- Test and shortcut controls share one outer card with a divider.
- Do not introduce dependencies or new window types.

---

### Task 1: Lock compact layout behavior with tests

**Files:**
- Modify: `pasteraTests/ScriptPreferenceTests.swift`
- Test: `pasteraTests/ScriptPreferenceTests.swift`

**Interfaces:**
- Consumes: `CPYScriptsPreferenceViewController` test repository injection.
- Produces: `usesCompactEmptyStateForTesting`, `usesSharedToolsCardForTesting`, `emptyStateMinimumHeightForTesting`, and `toolsSectionCountForTesting` assertions.

- [ ] Add a test that constructs an empty scripts page and asserts the empty state is below 180pt and test/shortcut sections share one card.
- [ ] Run the focused test and confirm it fails because the compact layout hooks do not exist.
- [ ] Keep existing real JavaScript success/error tests unchanged.

### Task 2: Implement the compact scripts and shared tools layout

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/CPYScriptsPreferenceViewController.swift`

**Interfaces:**
- Consumes: existing `makeScriptsCard`, test controls, shortcut record view, repository reload, and script execution actions.
- Produces: compact empty state, horizontal tools composition, responsive stacked fallback, and test hooks from Task 1.

- [ ] Reduce card padding/spacing and remove the 220pt empty-state minimum.
- [ ] Replace separate test and shortcut cards with one shared card containing two sections and a divider.
- [ ] Arrange picker, input, and run button in one aligned operation row; keep result content below it.
- [ ] Disable the run button when no script is available and reset result height/color consistently.
- [ ] Run `ScriptPreferenceTests` and confirm all focused tests pass.

### Task 3: Runtime and visual acceptance

**Files:**
- Modify only if screenshot evidence exposes a P1/P2 issue: `pastera/Sources/Preferences/Panels/CPYScriptsPreferenceViewController.swift`

**Interfaces:**
- Consumes: installed Debug application and `--open-preferences` debug launch argument.
- Produces: real screenshots for empty page, template-created script state, and test result state.

- [ ] Run the focused script and preference-window interaction tests.
- [ ] Build and install with `./script/install_local.sh`.
- [ ] Open `/Applications/Pastera.app --args --open-preferences`, navigate to Scripts, and capture the real window.
- [ ] Verify no oversized blank area, shared-card appearance, control center-line alignment, clipping, or horizontal overflow.
- [ ] Create or select a saved script, run a real test, and verify the output state visually.
- [ ] Re-run tests after any visual correction and inspect the final diff.
