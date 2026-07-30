# Pastera Windows Porting Guide

## Frozen V1 Baseline

Windows V1 uses the annotated tag `windows-v1-baseline-20260718` as its frozen
macOS behavior reference. Later macOS commits do not automatically expand the
Windows V1 scope. A scope change must update the single Windows V1 plan at
`docs/superpowers/plans/2026-07-18-pastera-windows-v1.md`.

The first approved post-baseline parity delta ends at
`origin/develop@7b57094ce32cf19ac737d24d10e91ebf121aaed5`. It adds only
features that were implemented and testable by that commit. Later local
shortcut/digit-navigation plans or implementations remain outside this delta
until the single Windows V1 plan is reviewed again. The detailed classification
is `docs/windows-reference/WINDOWS_PARITY_DELTA_20260726.md`.

The baseline verification command passed 673 tests in 75 suites on macOS. The
cross-platform contract manifests live under `windows/fixtures/`; they contain
only synthetic data and protocol invariants. Windows implementation must add
two-way generated SQLite and KDBX compatibility artifacts without exporting a
user's clipboard history, passwords, Keychain data, DPAPI blobs, or other local
credentials.

The macOS UI evidence, geometry inventory, Windows-native adaptation rules, and
screenshot acceptance matrix live under `docs/windows-reference/`. Screenshots
are the product content-area acceptance baseline. Windows may replace system
chrome and native rendering, but it must retain the referenced layout,
positions, dimensions, spacing, ordering, and information density.

## Scope

The Windows implementation baseline is the frozen tag
`windows-v1-baseline-20260718`; its historical standalone predecessor is
`pastera-pre-standalone`. The approved delta includes the macOS 3.0.1 update
surface and release semantics.
It is the implementation entrypoint for the native Windows version of Pastera.

Treat the macOS code as the behavior reference, not as a framework template.
Windows must reproduce all core product capabilities through native Windows
equivalents. It should reuse the product contracts, sync protocol, data model,
restricted JavaScript `transform(clip)` behavior, and user flows, while replacing
AppKit, NSPasteboard, Accessibility, Sparkle, and macOS packaging.

Windows V1 targets Windows 11 x64 with C#, WinUI 3, Windows App SDK, and SQLite.
KDBX remains the password-vault source of truth; Windows Hello and DPAPI may
protect a local convenience key but must not create a Windows-only vault format.

Do not write local credentials, signing secrets, sync passphrases, OAuth
material, or machine-specific credential-store values into repository docs,
issues, commits, or chat.

## Frozen Baseline Feature Summary

- History search is now a first-class workflow. Menu rendering stays bounded,
  while stored history can be searched beyond the visible menu limit.
- History records support text, URL-like text, images, files, PDF, RTF/RTFD,
  thumbnails, and asset-backed pasteback. All are Windows V1 parity targets;
  implementation may be staged internally, but release acceptance cannot omit
  these core types.
- Snippets use SQLiteData-backed folders and items, with shortcut-oriented
  browsing, duplicate cleanup, and sync deletion tombstones.
- OneDrive sync is file-folder based. Pastera writes ordinary files under
  `Pastera/sync`; the OneDrive desktop client handles cloud transport.
- Sync is split by direction and content kind: history upload/import, snippet
  upload/import, and file asset upload/import.
- Automatic paste is opt-in. macOS uses Accessibility permission and synthetic
  Command-V; Windows should use a separate pasteback permission and injection
  strategy instead of enabling it by default.
- Release work added DMG, PKG, Homebrew Cask, GitHub release workflows, Sparkle
  appcast support, install-location guidance, and a setup guide. Windows should
  replace those with an installer and updater chain native to Windows.

## Approved `7b57094` Parity Delta

- Main-panel feedback and OCR/background work are bounded; UI state remains
  visible while heavy work stays off the interaction path.
- Password-vault storage is local-first. The local KDBX is the working copy;
  OneDrive stores an encrypted replica with revision/digest metadata, merge,
  recovery, and explicit status.
- The vault supports master-password changes and atomic rekey rollback.
- The vault Agent integration adds a versioned wire contract, peer verification,
  grants, one-time tickets, rate limits, redacted audit, a bounded local broker,
  CLI/MCP adapters, and rollback-safe installation.
- History prompt optimization is explicit and reversible. Local formatting is
  available by default; an OpenAI-compatible endpoint is user-configured.
  Apple Foundation Models are a macOS-only optional provider.
- Software update has its own settings page. Windows must implement equivalent
  version, integrity, user-confirmation, and rollback semantics with a Windows
  updater rather than Sparkle.
- Script template, editor, test, and settings flows include the fixes delivered
  by `178af2c`.

These items are part of Windows V1 even though they were added after the frozen
baseline. CodeGraph and ignore-file changes in the same commit range are
repository tooling, not Windows product scope.

## Windows Implementation Order

1. Build the app shell and local storage first.
   - Use a persistent app data directory for database files, settings, logs, and
     the app-level device UUID.
   - Keep clipboard history and snippet storage in SQLite-compatible tables so
     sync payload generation can match the macOS repository behavior.

2. Implement clipboard capture and pasteback.
   - Start with Unicode text and URL-like text.
   - Preserve update timestamps, stable IDs, source device ID, and available
     type metadata.
   - Add images, PDF, RTF/RTFD, and file assets only after the text path and
     local history UI are stable.

3. Implement history and snippet workflows.
   - Keep menu display limits separate from stored-history retention.
   - Search stored history, not only currently visible rows.
   - Preserve snippet folders, item order, enabled state, and deletion
     tombstones.

4. Implement scripts, prompt optimization, and the local-first KDBX vault.
   - Preserve the restricted JavaScript `transform(clip)` contract without
     substituting PowerShell or allowing arbitrary process execution.
   - Preserve explicit prompt optimization, preview, undo, save, endpoint
     validation, credential protection, cancellation, and failure fallback.
   - Support KDBX folders, entries, reveal/copy/paste, editing, deletion, search,
     master-password rekey, and local quick unlock through Windows-native
     authentication.

5. Implement the vault Agent security boundary.
   - Preserve the versioned wire operations, peer verification, grants,
     one-time tickets, rate limits, redacted audit, cancellation, and bounded
     broker lifecycle.
   - Use Windows-native IPC, ACLs, process identity, DPAPI/Hello, and helper
     lifecycle without returning plaintext secrets to the Agent.

6. Implement the OneDrive folder sync protocol.
   - Locate the Windows OneDrive root, then write the same
     `<OneDrive>/Pastera/sync/` protocol tree as macOS.
   - Implement export/import with local test fixtures before connecting it to
     timers or UI switches.
   - Keep the KDBX working copy local and use the compatible
     `<configured-sync-root>/PasteraSync/vault/PasteraVault.kdbx` encrypted
     replica path.
   - Keep OneDrive cloud status wording conservative: local file writes are not
     proof that the cloud upload has finished.

7. Add global shortcuts and optional paste injection.
   - Register shortcuts independently from clipboard capture.
   - If Windows blocks injection or the target app rejects paste, report that
     state without losing the selected history or snippet.

8. Add installer, updater, and first-run guidance.
   - Windows should not copy DMG, PKG, Homebrew, or Sparkle mechanics.
   - The equivalent deliverable is an installer that places the app in a stable
     location, configures startup/update expectations, and opens a setup guide
     when needed.

## Platform Replacement Map

| macOS reference | Windows design entry |
| --- | --- |
| `NSPasteboard` and `NSPasteboard.PasteboardType` | Windows Clipboard APIs plus an internal protocol type map. Preserve Pastera sync type identifiers separately from native clipboard constants. |
| Accessibility permission and synthetic Command-V | Explicit paste-injection permission/state, likely based on Windows input injection APIs. Keep automatic paste off by default. |
| Global hot keys in `HotKeyService.swift` | Windows global hotkey registration with collision reporting and per-shortcut enablement. |
| AppKit menu panels and preferences XIBs | Native Windows tray/menu and settings surfaces. Replace system chrome and control rendering, but retain the screenshot-defined product content layout, dimensions, spacing, order, and density. |
| `UserDefaults` | A versioned settings store under the user profile or app data directory. Preserve key semantics, not macOS key names. |
| SQLiteData repositories | SQLite-backed repositories with equivalent history, asset, snippet, suppression, and deletion behavior. |
| Keychain and `LocalAuthentication` | DPAPI/Credential Manager and Windows Hello/user verification. Keep KDBX as the root credential and fail back to the master password. |
| Unix-domain local broker and macOS signing identity | Windows single-user IPC, ACLs, process token/signature verification, and bounded helper lifecycle. Preserve the Agent wire and authorization semantics. |
| Apple Foundation Models | Optional Windows-local provider only if it satisfies the same privacy/cancel/fallback contract; do not fake Apple Intelligence parity. |
| Sparkle appcast | Windows updater metadata and installer update flow. Keep release notes and integrity checks, but do not reuse Sparkle-specific fields. |
| DMG, PKG, Homebrew Cask | MSI/MSIX/EXE installer path plus a Windows package manager strategy if needed later. |
| `/Applications/Pastera.app` install guidance | Stable install directory and startup/permission guidance for Windows. |

## OneDrive Sync Contract

The sync root is the cross-platform contract:

```text
<OneDrive>/Pastera/sync/
  history/
    protocol.json
    devices/
      <device-id>.sqlite
  snippets/
    devices/
      <device-id>.sqlite
  files/
    devices/
      <device-id>/
        manifest.json
        assets/
          <history-id>/
            <asset-index>-<byte-count>-<version>-<filename>
```

Windows can choose its own OneDrive discovery logic, but once a root is chosen
it must use the same `Pastera/sync` directory shape. Do not introduce a
Windows-only protocol directory unless the protocol version is intentionally
changed for both platforms.

Each installation needs a persistent app-level device UUID. Store it under the
user's app data/settings area. Device snapshot file names must use
cross-platform-safe characters.

History sync:

- `history/protocol.json` uses `schemaVersion=4`.
- Each device writes one SQLite snapshot under `history/devices/`.
- The `histories` table contains `id`, `updatedAt`, `sourceKind`, and `text`.
- Text history exports are capped at 2000 rows, 256 KiB per text value, and an
  8 MiB cumulative text budget.
- History import is last-write-wins by `updatedAt`. Remote absence never deletes
  local history.

Snippet sync:

- Current writes use `schemaVersion=3` in each device SQLite snapshot.
- The snapshot includes `folders`, `snippets`, `deletedFolders`, and
  `deletedSnippets`.
- Folder and snippet conflicts use `updatedAt`.
- Deletion tombstones use `deletedAt`; apply them only when they are newer than
  the local row they target.
- Absence from a remote snapshot is not a delete signal.

File asset sync:

- The file domain uses `manifestVersion=1` and `schemaVersion=1`.
- Metadata lives in `files/devices/<device-id>/manifest.json`; payload bytes are
  ordinary files under that device's `assets/` directory.
- Current supported file asset classes are image/TIFF, PDF, RTF, and RTFD.
- Each device exports at most 10 file assets. A single file asset larger than
  25 MiB is skipped.
- Finder file URL history is intentionally excluded from file sync. Windows
  should similarly avoid syncing local filesystem references as portable file
  payloads.

Sync run semantics:

- Manual sync bypasses automatic master switches, but still respects the
  detailed content-scope switches.
- Local-change sync uploads only; it does not import remote snapshots during
  the local-change debounce path.
- Corrupt remote SQLite snapshots or unreadable file manifests are skipped and
  reported as warnings where possible.
- A successful sync status means Pastera finished local file work. OneDrive
  cloud upload/download state remains owned by the OneDrive client.

Password-vault sync is local-first and uses a separate compatible replica:

```text
<configured-sync-root>/PasteraSync/
  vault/
    PasteraVault.kdbx
```

- The working KDBX and sync metadata stay in the local Windows app-data area.
- The OneDrive file is an encrypted replica, not the live working file.
- Local revision, last-synced revision, local/remote digest, migration, merge,
  conflict, rebuild, and recovery states must remain distinct.
- DPAPI/Hello convenience material never enters the replica.
- UI wording distinguishes OneDrive client availability, local replica writes,
  and unknown cloud upload/download completion.

## Source Reading Map

Start with these files when porting behavior:

- `pastera/Sources/Models/PasteboardContent.swift`: sync payload models,
  OneDrive provider, SQLite snapshot writer/reader, file manifest logic, and
  safe path handling.
- `pastera/Sources/Services/SyncCoordinator.swift`: sync settings, automatic
  direction planning, startup/timer/manual/local-change orchestration, status
  messages, and warnings.
- `pastera/Sources/Repositories/PasteboardHistoryRepository.swift`: stored
  history queries, search, retention, sync payload export/import, file asset
  export/import, and local suppression behavior.
- `pastera/Sources/Repositories/SnippetRepository.swift` and
  `pastera/Sources/Repositories/SnippetRepositoryDeletionSync.swift`: snippet
  folders/items, duplicate cleanup, sync import, and tombstone handling.
- `pastera/Sources/Services/PasteService.swift`: pasteback behavior, automatic
  paste toggle, and blocked-input reporting.
- `pastera/Sources/Services/HotKeyService.swift`: shortcut registration,
  remote-session handling, and snippet/history shortcut wiring.
- `pastera/Sources/Services/ClipboardScriptCoordinator.swift` and script
  preference controllers: restricted JavaScript transforms, triggers, ordering,
  templates, testing, and manual shortcuts.
- `pastera/Sources/Services/KDBXPasswordVaultStore.swift` and
  `PasswordVaultUIController.swift`: KDBX persistence, folder/entry behavior,
  authentication boundaries, and secure clipboard actions.
- `pastera/Sources/Services/PasswordVaultLocalStorage.swift`,
  `PasswordVaultMigrationService.swift`, `PasswordVaultCloudReplica.swift`, and
  `PasswordVaultSyncService.swift`: local-first KDBX, migration, encrypted
  replica, revision/merge/recovery semantics, and status.
- `pastera-agent/Sources/` plus `pastera/Sources/Services/VaultAgent*.swift`:
  versioned Agent wire, peer verification, grants, tickets, bounded broker,
  audit, CLI/MCP adapters, and installation transactions.
- `pastera/Sources/Managers/HistoryEditorWindowController.swift` plus
  `pastera/Sources/Services/PromptOptimization*.swift`: explicit prompt
  optimization, local/remote providers, cancellation, preview, undo, and save.
- `pastera/Sources/Preferences/Panels/CPYSoftwareUpdatePreferenceViewController.swift`
  and `pastera/Sources/Preferences/PasteraUpdaterFacade.swift`: separate update
  settings and updater state semantics.
- `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`:
  current sync settings information architecture and OneDrive status wording.
- `pastera/Sources/Services/InstallationLocationService.swift` and
  `pastera/Sources/Services/PasteraSetupGuideService.swift`: install guidance
  and first-run setup concepts that need Windows equivalents.

Use the tests as executable behavior notes:

- `pasteraTests/Models/PasteboardContentTests.swift`
- `pasteraTests/SyncCoordinatorTests.swift`
- `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`
- `pasteraTests/Repositories/SnippetRepositoryTests.swift`
- `pasteraTests/SnippetRepositoryDeletionSyncTests.swift`
- `pasteraTests/SyncPreferenceTopSectionTests.swift`
- `pasteraTests/HotKeyServiceTests.swift`
- `pasteraTests/InstallationLocationServiceTests.swift`
- `pasteraTests/SparkleUpdateFeedTests.swift`
- `pasteraTests/ReleasePackagingConfigurationTests.swift`
- `pasteraTests/PasswordVaultLocalStorageTests.swift`
- `pasteraTests/PasswordVaultMigrationTests.swift`
- `pasteraTests/PasswordVaultMasterPasswordTests.swift`
- `pasteraTests/PasswordVaultCloudReplicaTests.swift`
- `pasteraTests/PasswordVaultSyncServiceTests.swift`
- `pasteraAgentTests/VaultAgentProtocolTests.swift`
- `pasteraTests/VaultAgentAuthorizationPolicyTests.swift`
- `pasteraTests/VaultAgentBrokerTests.swift`
- `pasteraTests/VaultAgentIntegrationInstallerTests.swift`
- `pasteraTests/PromptOptimizationServiceTests.swift`
- `pasteraTests/PromptOptimizationPreferenceTests.swift`
- `pasteraTests/SoftwareUpdatePreferenceTests.swift`

## Windows Acceptance Checklist

- A clean Windows install can capture text, search older stored history, and
  paste selected history without enabling automatic paste by default.
- Snippet folders and item shortcuts work locally before sync is enabled.
- Two Windows profiles pointing at the same OneDrive-backed `Pastera/sync`
  directory can exchange text history and snippets without deleting unrelated
  local data.
- A Windows profile can import a macOS `schemaVersion=4` history snapshot and a
  `schemaVersion=3` snippet snapshot.
- File asset sync skips unsupported or oversized assets without failing text
  history or snippet sync.
- Script transforms preserve the restricted `transform(clip)` contract and do
  not expose PowerShell or unrestricted OS execution.
- Prompt optimization preserves explicit trigger, preview, undo/save, endpoint
  validation, cancellation, and failure-does-not-overwrite behavior.
- KDBX databases created or updated by either platform remain readable by the
  other platform; master-password rekey is atomic and Windows Hello/DPAPI data
  is only a local unlock convenience.
- Vault Agent protocol/security tests cover peer identity, grants, one-time
  tickets, rate limits, redacted audit, cancel/close behavior, CLI/MCP adapters,
  and rollback-safe installation.
- The encrypted OneDrive vault replica supports revision comparison, merge,
  rebuild, recovery, and status semantics without becoming the working file.
- Sync status never claims cloud completion based only on local file writes.
- Every major UI state has a macOS reference, Windows screenshot, 50% overlay,
  P0-P3 difference report, and zero unapproved P0/P1 differences.
- Installer/update work is kept separate from clipboard correctness and sync
  correctness.
