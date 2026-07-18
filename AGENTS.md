# Pastera

## Project Context

Pastera is an independent clipboard productivity product. The current macOS app
is the executable behavior baseline; native Windows work belongs under
`windows/` and must preserve the shared contracts without copying AppKit UI.
`origin` is the only product remote; do not recreate a Clipy tracking remote.

The app currently targets macOS 13+ and is built with Xcode 26.5. Dependencies
are resolved through Xcode Swift Package Manager; do not reintroduce CocoaPods,
SwiftGen, or BartyCrouch without an explicit product requirement.

## Architecture Boundaries

- Runtime entrypoint is `pastera/Sources/AppDelegate.swift`; menu behavior is in
  `pastera/Sources/Managers/MenuManager.swift`.
- Clipboard capture, pasteback, history cleanup, and app filtering live under
  `pastera/Sources/Services/`.
- SQLiteData schema, database bootstrap, and migrations live under
  `pastera/Sources/Database/`.
- Snippet persistence already uses SQLiteData via
  `pastera/Sources/Repositories/SnippetRepository.swift`.
- SQLiteData is the current fact store. Realm may only remain as a bounded,
  read-only legacy import path; do not add new Realm-backed product behavior.

## Local Development

Local builds may enable `Configurations/CodeSigning-AdHoc.xcconfig` through
`Configurations/CodeSigning.xcconfig`. Preserve existing user changes in this
file unless the user asks to change signing mode.

Do not commit `.DS_Store` or SwiftPM cache contents. The project-local
`.spm-cache/` directory is for dependency download stability only.

## Build And Verification

Use this command for the default regression pass:

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

After a development task changes app behavior, UI, packaging, or tests and the
requested verification has passed, reinstall the latest local build for manual
testing unless the user explicitly asks not to:

```bash
./script/install_local.sh
```

The script builds ad-hoc signed `Pastera.app`, replaces the local app under
`/Applications` by default, and launches it. Use `PASTERA_INSTALL_DIR` only when
`/Applications` is not writable.

The project also has a Codex Stop hook in `.codex/hooks.json` that runs
`script/codex_stop_install_if_changed.sh`. It only reinstalls when build-relevant
paths (`Configurations`, `pastera`, or `pastera.xcodeproj`) changed since the
last local install.

## Documentation Boundaries

- Independent product roadmap and historical migration boundary:
  `docs/development/PASTERA_FORK_PLAN.md`.
- Windows native porting entrypoint:
  `docs/development/WINDOWS_PORTING_GUIDE.md`.
- Verification matrix and known manual checks:
  `docs/verification/VERIFICATION.md`.
- OneDrive folder-sync protocol and credential boundaries:
  `docs/sync/ONEDRIVE_SYNC.md`.

Needed local credentials must be looked up through
`~/.codex/docs/local-credentials.md`, `~/.codex/service-accounts.toml`, and the
corresponding Keychain items. Never write plaintext passwords, tokens, sync
passphrases, or OAuth material into this repo, `AGENTS.md`, docs, or chat.

## Skill Routing

- Creating or updating `AGENTS.md` / project agent rules: use
  `$agents-authoring`.
- Requirements, implementation plans, data/interface changes, UI search flows,
  or delivery-record decisions: use `$delivery-workflow` first; do not let
  `$superpowers:writing-plans` replace the spec/confirmation gate.
- Multi-step implementation after the spec is stable: use
  `$superpowers:writing-plans`, then `$superpowers:executing-plans` or
  `$superpowers:subagent-driven-development`.
- New features or bug fixes: use `$superpowers:test-driven-development` and
  watch the relevant test fail before production edits.
- Any code modification, refactor, review, or test-impact assessment: use
  `$coding-guardrails` before the platform-specific implementation skill.
- Bugs, build failures, pasteboard regressions, performance issues, or failing
  tests: use `$superpowers:systematic-debugging` before proposing fixes.
- Implementation and verification closeout, Delivery Record updates, commit,
  push, tag, or branch integration: use `$change-sync`; it must reuse the
  already-confirmed unique plan.
