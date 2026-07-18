# Sync Compatibility Fixtures

`contract.json` freezes the versions and invariants implemented by the macOS
baseline. The executable reference cases remain in:

- `pasteraTests/Models/PasteboardContentTests.swift`
- `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`
- `pasteraTests/Repositories/SnippetRepositoryTests.swift`
- `pasteraTests/SnippetRepositoryDeletionSyncTests.swift`
- `pasteraTests/SyncCoordinatorTests.swift`

Windows tests must first reproduce those cases with temporary SQLite snapshots,
then add checked-in synthetic macOS-to-Windows and Windows-to-macOS snapshots.
Snapshots are transport artifacts, never the live local database. Corrupt input
is skipped with a warning, and absence from a remote snapshot never deletes
local history or snippets.
