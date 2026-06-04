# Verification

## Default Automated Check

Run from the repository root:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme Clipy \
  -project Clipy.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  clean test
```

Expected result: `** TEST SUCCEEDED **`.

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
- OneDrive sync simulation: use two temporary folders or two local Pastera
  profiles that point at the same `PasteraSync/` directory, then verify history
  and snippet records converge after import/export.

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
