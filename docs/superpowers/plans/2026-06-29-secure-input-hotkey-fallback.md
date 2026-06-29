# Secure Input Hotkey Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Pastera hotkeys callable in SSH password and protected-input situations by avoiding unnecessary remote-session suspension and falling back to legacy menus when secure keyboard input blocks custom panels.

**Architecture:** Keep Carbon/Magnet hotkey registration as-is. Make remote-session hotkey suspension opt-in, defaulting off. When `IsSecureEventInputEnabled()` is true, route hotkey popups through existing `NSMenu.popUp` menus instead of the custom `NSPanel` path that activates the app and can be blocked by protected input.

**Tech Stack:** Swift, AppKit, Carbon, Magnet, Swift Testing, Xcode.

---

### Task 1: Remote Session Hotkey Policy

**Files:**
- Modify: `pastera/Sources/Constants.swift`
- Modify: `pastera/Sources/Utility/CPYUtilities.swift`
- Modify: `pastera/Sources/Services/HotKeyService.swift`
- Test: `pasteraTests/HotKeyServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Add coverage that remote-session suspension is disabled by default and only enabled when the new UserDefaults key is set:

```swift
@Test
func remoteSessionPolicyDoesNotSuspendByDefault() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: Constants.HotKey.suspendDuringRemoteSession)

    #expect(!RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
        frontmostApplicationBundleIdentifier: "com.apple.ScreenSharing"
    ))
}

@Test
func remoteSessionPolicySuspendsWhenPreferenceIsEnabled() {
    let defaults = UserDefaults.standard
    defaults.set(true, forKey: Constants.HotKey.suspendDuringRemoteSession)
    defer { defaults.removeObject(forKey: Constants.HotKey.suspendDuringRemoteSession) }

    #expect(RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
        frontmostApplicationBundleIdentifier: "com.apple.ScreenSharing"
    ))
    #expect(!RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
        frontmostApplicationBundleIdentifier: "com.apple.finder"
    ))
}
```

- [ ] **Step 2: Verify red**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -scheme pastera -project pastera.xcodeproj -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" -packageCachePath "$PWD/.spm-cache/PackageCache" -skipPackagePluginValidation -skipMacroValidation test -only-testing:pasteraTests/HotKeyServiceTests
```

Expected: FAIL because `Constants.HotKey.suspendDuringRemoteSession` does not exist, or because current policy suspends by default.

- [ ] **Step 3: Implement minimal policy change**

Add `Constants.HotKey.suspendDuringRemoteSession`, register its default as `false`, and make `RemoteSessionHotKeyPolicy` return `false` unless that preference is enabled.

- [ ] **Step 4: Verify green**

Run the same `HotKeyServiceTests` command.

Expected: PASS.

### Task 2: Secure Input Legacy Menu Fallback

**Files:**
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Test: `pasteraTests/MenuManagerStatusItemTests.swift`
- Optionally modify: `pastera/Sources/Managers/MenuManagerTestingSupport.swift`

- [ ] **Step 1: Write failing tests**

Add tests that assert `MenuManager` chooses legacy menu fallback when secure keyboard input is active:

```swift
@Test
func secureKeyboardEntryUsesLegacyMenuFallbackForHotkeyPopups() throws {
    try withRegisteredDefaultEnvironment { _, _ in
        let manager = MenuManager()
        manager.secureEventInputEnabledProvider = { true }

        #expect(manager.shouldUseLegacyMenuFallbackForTesting)
    }
}

@Test
func normalInputUsesPanelPresentationForHotkeyPopups() throws {
    try withRegisteredDefaultEnvironment { _, _ in
        let manager = MenuManager()
        manager.secureEventInputEnabledProvider = { false }

        #expect(!manager.shouldUseLegacyMenuFallbackForTesting)
    }
}
```

- [ ] **Step 2: Verify red**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -scheme pastera -project pastera.xcodeproj -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" -packageCachePath "$PWD/.spm-cache/PackageCache" -skipPackagePluginValidation -skipMacroValidation test -only-testing:pasteraTests/MenuManagerStatusItemTests
```

Expected: FAIL because the testing accessor and fallback branch do not exist.

- [ ] **Step 3: Implement fallback**

Add a private `shouldUseLegacyMenuFallback` predicate backed by `secureEventInputEnabledProvider()`. In `popUpMenu(_:triggerKeyCombo:)`, if the predicate is true, show the corresponding legacy `NSMenu`:

```swift
private var shouldUseLegacyMenuFallback: Bool {
    secureEventInputEnabledProvider()
}
```

For `.main`, use existing `clipMenu` or create it. For `.history`, use `makeHistoryBrowserMenu()`. For `.snippet`, use a menu populated with snippet items. Call `menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)`.

- [ ] **Step 4: Verify green**

Run the same `MenuManagerStatusItemTests` command.

Expected: PASS.

### Task 3: Final Verification And Local Install

**Files:**
- No new production files.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -scheme pastera -project pastera.xcodeproj -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" -packageCachePath "$PWD/.spm-cache/PackageCache" -skipPackagePluginValidation -skipMacroValidation test -only-testing:pasteraTests/HotKeyServiceTests -only-testing:pasteraTests/MenuManagerStatusItemTests
```

Expected: PASS.

- [ ] **Step 2: Run static diff check**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: Install locally**

Run:

```bash
./script/install_local.sh --verify
```

Expected: build succeeds, `/Applications/Pastera.app` is replaced, and the script verifies Pastera is running from `/Applications/Pastera.app/Contents/MacOS/Pastera`.
