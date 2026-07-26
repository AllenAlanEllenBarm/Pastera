# Pastera

## Project Context

Pastera is an independent clipboard productivity product. The macOS app is the
executable behavior baseline; native Windows work belongs under `windows/` and
must preserve shared contracts without copying AppKit UI. `origin` is the only
product remote; do not recreate a Clipy tracking remote.

The app targets macOS 13+ and Xcode 26.5. Dependencies use Xcode Swift Package
Manager; do not reintroduce CocoaPods, SwiftGen, or BartyCrouch without an
explicit product requirement.

## Architecture Boundaries

- Runtime entrypoint: `pastera/Sources/AppDelegate.swift`; menu behavior:
  `pastera/Sources/Managers/MenuManager.swift`.
- Clipboard capture, pasteback, history cleanup, and app filtering:
  `pastera/Sources/Services/`.
- SQLiteData schema, bootstrap, and migrations: `pastera/Sources/Database/`.
- Snippet persistence: `pastera/Sources/Repositories/SnippetRepository.swift`.
- SQLiteData is the fact store. Realm may remain only as a bounded, read-only
  legacy import path; do not add Realm-backed product behavior.

## Local Development

Local builds may enable `Configurations/CodeSigning-AdHoc.xcconfig` through
`Configurations/CodeSigning.xcconfig`. Preserve user changes unless asked to
change signing mode. Do not commit `.DS_Store` or SwiftPM cache contents;
`.spm-cache/` exists only for dependency download stability.

Run `script/codex/code-intelligence.sh bootstrap` once per clone to activate the
local `pastera_codegraph` MCP and watcher. CodeGraph returns candidates only;
confirm with `rg`, focused source reads, and real tests—especially for AppKit
selectors, notifications, target-action, and runtime dispatch. See
`docs/development/CODE_INTELLIGENCE.md`.

## Build And Verification

Default regression pass:

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

Manual clipboard verification for image, file, rich text, and app paste targets
is tracked in `docs/verification/VERIFICATION.md`.

After app behavior, UI, packaging, or tests change and requested verification
passes, reinstall for manual testing unless the user opts out:

```bash
./script/install_local.sh
```

The script ad-hoc signs `Pastera.app`, replaces `/Applications/Pastera.app`, and
launches it. Use `PASTERA_INSTALL_DIR` only when `/Applications` is not writable.
The `.codex/hooks.json` Stop hook runs
`script/codex_stop_install_if_changed.sh` only when build-relevant paths changed.

## Documentation Boundaries

- Product roadmap and migration history: `docs/development/PASTERA_FORK_PLAN.md`.
- Windows porting: `docs/development/WINDOWS_PORTING_GUIDE.md`.
- Verification matrix: `docs/verification/VERIFICATION.md`.
- OneDrive sync and credential boundaries: `docs/sync/ONEDRIVE_SYNC.md`.

For reusable local credentials, check `~/.codex/docs/local-credentials.md`,
`~/.codex/service-accounts.toml`, and the corresponding Keychain items. Never
write plaintext passwords, tokens, passphrases, or OAuth material into the repo,
agent rules, docs, or chat.

## Skill Routing

- Project agent rules: `$agents-authoring`.
- Only explicit plan/task creation, key Goal/Scope/Architecture/Acceptance
  changes, or requested plan/Story/Task synchronization triggers
  `$delivery-workflow`; direct implementation and an existing plan do not.
- Confirmed multi-step specs: `$superpowers:writing-plans`, then
  `$superpowers:executing-plans` or explicitly requested subagent execution;
  reuse the unique plan.
- Code changes/reviews: `$coding-guardrails` first; new behavior and bug fixes
  add `$superpowers:test-driven-development`.
- Bugs, build failures, regressions, performance issues, or failing tests:
  `$superpowers:systematic-debugging` before production edits.
- macOS build/run/debug or test triage: `$build-macos-apps:build-run-debug` or
  `$build-macos-apps:test-triage`; AppKit/SwiftUI bridging:
  `$build-macos-apps:appkit-interop`.
- Signing/entitlements or distribution:
  `$build-macos-apps:signing-entitlements` or
  `$build-macos-apps:packaging-notarization`.
- Ordinary Git/release work does not trigger `$change-sync`; use it only for an
  explicitly requested Delivery Record closeout against one confirmed plan.
