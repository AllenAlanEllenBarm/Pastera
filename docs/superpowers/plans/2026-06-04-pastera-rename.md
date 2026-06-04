# Pastera Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the fork's user-facing product from Clipy to Pastera and prepare GitHub repository rename.

**Architecture:** Keep the Xcode project, target, scheme, source directory, and Swift module named `Clipy` for upstream merge compatibility. Rename the produced app bundle, executable, user-facing strings, documentation, sync folder naming, and GitHub repository metadata to `Pastera`.

**Tech Stack:** Xcode project settings, AppKit/macOS bundle metadata, Swift string catalogs, Markdown documentation, GitHub CLI.

---

### Task 1: Local Product Branding

**Files:**
- Modify: `Clipy.xcodeproj/project.pbxproj`
- Modify: `Clipy.xcodeproj/xcshareddata/xcschemes/Clipy.xcscheme`
- Modify: `Clipy/Supporting Files/Info.plist`
- Modify: `Clipy/Sources/Constants.swift`
- Modify: `Clipy/Resources/Localizable.xcstrings`
- Modify: `Clipy/Sources/Snippets/*/CPYSnippetsEditorWindowController.strings`

- [x] Set app product output to `Pastera.app` while keeping `PRODUCT_MODULE_NAME = Clipy`.
- [x] Point test host at `Pastera.app/Contents/MacOS/Pastera`.
- [x] Change app bundle identifiers to `com.pastera-app.Pastera` and `com.pastera-app.Pastera.debug`.
- [x] Change `Constants.Application.name` to `Pastera` / `PasteraDEBUG`.
- [x] Replace user-facing localized `Clipy` strings with `Pastera`.
- [x] Remove the upstream Clipy appcast URL from the fork's Info.plist.

### Task 2: Documentation Branding

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Move: `docs/development/CLIPY_FORK_PLAN.md` to `docs/development/PASTERA_FORK_PLAN.md`
- Modify: `docs/verification/VERIFICATION.md`
- Modify: `docs/sync/ONEDRIVE_SYNC.md`

- [x] Replace product branding with `Pastera`.
- [x] Keep factual project paths and build commands as `Clipy.xcodeproj` / `-scheme Clipy`.
- [x] Replace OneDrive sync directory naming and code paths with `PasteraSync/`.
- [x] Preserve upstream attribution and MIT license notice.

### Task 3: Verification And Install

**Files:**
- No source files.

- [x] Run the focused branding/build verification:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme Clipy \
  -project Clipy.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

- [ ] Install the built `Pastera.app` into `/Applications`.

### Task 4: GitHub Remote Rename

**Files:**
- Remote repository settings.
- Local git remote URL.

- [x] Install GitHub CLI under `~/.local/bin/gh`.
- [ ] Authenticate GitHub CLI with `gh auth login`.
- [ ] Rename repository from `Clipy` to `Pastera`:

```bash
gh repo rename Pastera --repo AllenAlanEllenBarm/Clipy --yes
git remote set-url origin https://github.com/AllenAlanEllenBarm/Pastera.git
```

- [ ] If a GitHub organization named `pastera` is intended as the group/owner, transfer the repository after the organization exists and the authenticated user has owner permissions.
- [ ] Push the current branch to the renamed origin.
