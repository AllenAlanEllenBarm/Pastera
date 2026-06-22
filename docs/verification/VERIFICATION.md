# Verification

## Default Automated Check

Run from the repository root:

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

Expected result: `** TEST SUCCEEDED **`.

## OneDrive Focused Automated Checks

Run focused sync checks while iterating on OneDrive behavior:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:pasteraTests/SyncCoordinatorTests \
  -only-testing:pasteraTests/PreferencePaneAlignmentTests \
  -only-testing:pasteraTests/SyncPreferenceOneDriveLocationTests \
  -only-testing:pasteraTests/PasteboardContentTests \
  test
```

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:pasteraTests/PasteboardHistoryRepositoryTests \
  -only-testing:pasteraTests/SnippetRepositorySyncTests \
  test
```

Expected result: both commands end with `** TEST SUCCEEDED **`. With Swift
Testing, verify the console lists the intended suite names; a build-only pass is
not enough.

## Feature Checks

- History retention: create more histories than the menu display limit and
  confirm search still finds older stored items.
- Plain search: verify case-sensitive and case-insensitive text matching.
- Regex search: verify valid patterns match and invalid patterns return a
  typed error without blocking the UI.
- Pagination: verify limit/offset does not duplicate or skip sorted results.
- Image pasteboard: copy an image from Preview or a screenshot, select it from
  Pastera, and paste it into Notes and Preview.
- File pasteboard: copy one or more files in Finder, select the history item,
  and paste into Finder or a text target that accepts file URLs.
- OneDrive sync simulation: use two local Pastera profiles or two macOS user
  accounts that point at the same OneDrive-backed root containing
  `manifest.json`, `histories/`, and `snippets/` directly under the selected
  `Pastera/sync` folder. No sync passphrase is required.
- OneDrive default location: with one macOS OneDrive account signed in, open the
  Sync pane and confirm Pastera selects `OneDrive > Pastera > sync` while Finder
  reveals the actual folder under
  `~/Library/CloudStorage/<OneDrive>/Pastera/sync`.
- OneDrive multiple accounts: when both personal and work OneDrive folders are
  present, open the Sync pane and confirm Pastera automatically uses the
  personal `OneDrive` root when present; otherwise it uses the first usable
  OneDrive root by name. There is no account chooser in v1 beta.
- OneDrive missing install/login: temporarily make
  `~/Library/CloudStorage/OneDrive*` unavailable, open the Sync pane, and click
  `自动同步`, `立即同步`, and each detailed scope switch. Each sync entry point
  should report that OneDrive must be installed and logged in, and no sync
  directory should be created under `Documents`.
- OneDrive Finder reveal: with a valid default sync root, click `显示` and
  confirm Finder opens the default `Pastera/sync` folder. Move or delete the
  folder and confirm `显示` reports that the selected sync folder is
  unavailable.
- OneDrive automatic switch: confirm `自动同步` is off by default. Turn it on
  when all four detailed switches are off and confirm Pastera enables history
  upload/import and snippet upload/import automatically.
- OneDrive plaintext protocol: trigger an upload and inspect a generated record.
  Confirm the JSON has a direct `payload` object and does not contain `crypto`,
  `nonce`, `ciphertext`, or `tag`.
- OneDrive legacy encrypted records: place an old encrypted beta record with
  `nonce`, `ciphertext`, and `tag` in the sync folder, trigger import, and
  confirm it is skipped without requiring a key or passphrase.
- OneDrive first-enable behavior: create old history and snippet data before
  enabling upload, then enable history upload and snippet upload. Confirm only
  new local changes created after enabling upload produce cloud records.
- OneDrive convergence: with history import/export and snippet import/export
  enabled on both profiles, create new history and snippets on profile A,
  trigger Sync Now, then trigger Sync Now on profile B and confirm records
  appear without changing their source device identity. Repeat from B to A.
- OneDrive LWW import: create or inject an older same-ID history/snippet record
  in the selected sync folder, sync the other profile, and confirm it does not
  overwrite newer local data or increment the imported count. Then inject a
  newer same-ID record and confirm it overwrites and increments the imported
  count.
- OneDrive snippet parent context: after enabling snippet upload, change only a
  snippet inside an older folder, trigger Sync Now, and confirm the exported
  `snippets/folders/<folder-id>.json` accompanies the changed snippet without
  bumping the folder payload `updatedAt`.
- OneDrive manual status: after Sync Now, confirm status distinguishes local
  writes to the local sync folder, actual imports, no new data, and waiting for
  the OneDrive desktop client. Pastera must not claim the cloud upload itself
  has completed.
- OneDrive non-destructive import: delete an imported history item and an
  imported snippet on profile A, sync both profiles, and confirm profile B keeps
  its local data. Re-sync profile A and confirm the deleted items are not
  re-imported there.
- OneDrive conflict copies: if OneDrive creates conflict-copy JSON files, record
  them as a v1 known limitation. Pastera does not auto-merge conflict copies;
  inspect or resolve them manually before considering the shared folder
  converged.
- OneDrive missing folder: point sync at a folder that is later moved or
  unavailable, trigger Sync Now, and confirm the status reports the problem
  while local data remains unchanged.
- OneDrive file asset sync: choose at least one `文件类型`, enable the matching
  history direction (`上传历史`/`同步历史`), copy supported non-text assets
  (image, PDF, RTF/RTFD), sync two local profiles, and confirm the remote
  profile imports usable history entries.
- OneDrive file limits: copy more than 10 file assets or one file asset larger
  than 25 MiB, trigger upload, and confirm Pastera reports a file skip warning
  while smaller text history records still sync.
- OneDrive Finder file exclusion: copy a Finder file or folder, trigger upload,
  and confirm it stays out of file sync without failing text history or snippet
  sync.

## Release DMG Checks

Before publishing a public release, build the signed and notarized DMG and
update Sparkle appcast with:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
NOTARY_KEYCHAIN_PROFILE="PasteraNotary" \
SPARKLE_PRIVATE_KEY="<private key from secrets>" \
script/package_release.sh \
  --version "2.0.1-beta" \
  --tag "v2.0.1-beta" \
  --update-appcast
```

For a local packaging dry run without Apple notarization credentials or a
Developer ID certificate, use:

```bash
script/package_release.sh --version "2.0.1-beta" --skip-notarization
```

This dry run ad-hoc signs the app locally and creates a DMG, but the output is
not suitable for public distribution.

The packaging script validates the app and DMG with:

```bash
codesign --verify --deep --strict --verbose=4 Pastera.app
spctl -a -vv Pastera.app
xcrun stapler validate Pastera.app
spctl -a -vv Pastera.dmg
xcrun stapler validate Pastera.dmg
```

If the appcast must be updated separately after the DMG is created, use:

```bash
SPARKLE_PRIVATE_KEY="<private key from secrets>" \
script/update_appcast_for_dmg.sh \
  --version "2.0.1-beta" \
  --tag "v2.0.1-beta" \
  --dmg ".build/release-artifacts/Pastera-2.0.1-beta-macOS.dmg"
```

Do not write certificate passwords, notary credentials, or Sparkle private keys
into the repository or release notes.

## DMG Accessibility Checks

- Clean install: download the DMG on a macOS 13+ machine, mount it, drag
  `Pastera.app` to `/Applications`, launch it from `/Applications`, trigger a
  snippet hotkey, grant Accessibility when prompted, restart Pastera, and
  confirm the hotkey no longer repeats the Accessibility alert.
- Direct-from-DMG guard: launch `Pastera.app` from the mounted DMG and confirm
  Pastera prompts the user to move the app to Applications before enabling
  Accessibility.
- Downloads guard: copy `Pastera.app` to `~/Downloads`, launch it, and confirm
  the same move-to-Applications prompt appears.
- Upgrade path: if an older zip/ad-hoc build was previously authorized, remove
  the old Accessibility entry or run
  `tccutil reset Accessibility com.pastera-app.Pastera`, then authorize the
  signed `/Applications/Pastera.app` once and verify subsequent signed updates
  keep the permission stable.

## Performance Checks

- Seed 1000 and 5000 text histories, then confirm menu creation only fetches
  the configured display limit.
- Search must run off the main thread or through a cancellable debounced path
  before wiring into UI.
- Large image assets should be skipped or bounded by `maxSyncedAssetBytes`
  during sync export.

## Manual Evidence

Record manual checks in task summaries, not in `AGENTS.md`. Include app/source,
target app, data type, expected result, and observed result.
