# Pastera DMG Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a repeatable signed/notarized DMG release path and reduce Accessibility permission churn by steering users away from temporary app locations.

**Architecture:** Keep local ad-hoc development intact for Debug and local scripts, while Release packaging uses Developer ID signing, notarization, and a DMG with an Applications alias. Add a small launch-time installation-location service that only warns when Pastera is launched from DMG, Downloads, App Translocation, or another non-Applications path.

**Tech Stack:** macOS AppKit, Xcode Swift tests, shell packaging scripts, GitHub Actions, Sparkle appcast.

---

### Task 1: Lock Expected Behavior With Tests

**Files:**
- Create: `pasteraTests/InstallationLocationServiceTests.swift`
- Create: `pasteraTests/ReleasePackagingConfigurationTests.swift`
- Modify: `pasteraTests/SparkleUpdateFeedTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

- [ ] Add tests for stable Applications installs, DMG/Downloads/AppTranslocation warnings, Release signing config, packaging scripts, and DMG appcast metadata.
- [ ] Run the focused tests and confirm they fail against the current zip/ad-hoc state.

### Task 2: Implement Install Location Guidance

**Files:**
- Create: `pastera/Sources/Services/InstallationLocationService.swift`
- Modify: `pastera/Sources/AppDelegate.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pastera.xcodeproj/project.pbxproj`

- [ ] Add a pure classifier for app bundle locations.
- [ ] Show an AppKit alert before Accessibility prompting when launched outside `/Applications`.
- [ ] Keep tests isolated from UI by testing the classifier only.

### Task 3: Add Release DMG Automation

**Files:**
- Modify: `Configurations/CodeSigning.xcconfig`
- Modify: `Configurations/CodeSigning-AdHoc.xcconfig`
- Create: `script/package_release_dmg.sh`
- Create: `script/update_appcast_for_dmg.sh`
- Create: `.github/workflows/release-dmg.yml`

- [ ] Stop the local ad-hoc include from overriding Release signing.
- [ ] Build Release with Developer ID identity, verify the app signature, notarize/staple app and DMG, and create a DMG containing `Pastera.app` plus an `/Applications` alias.
- [ ] Add a workflow that imports signing credentials from GitHub secrets, stores notary credentials in a temporary keychain profile, builds the DMG, updates appcast metadata, and uploads the DMG to the GitHub release.

### Task 4: Verify

**Files:**
- Modify: `docs/verification/VERIFICATION.md`

- [ ] Run focused Swift tests.
- [ ] Run default regression test command when feasible.
- [ ] Run shell syntax checks on new scripts.
- [ ] Document manual clean-machine DMG and Accessibility verification.
