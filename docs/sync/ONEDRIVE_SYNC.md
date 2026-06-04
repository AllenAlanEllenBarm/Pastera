# OneDrive Folder Sync

## V1 Model

Pastera v1 sync uses a user-selected local OneDrive folder. Pastera writes and
reads files under `PasteraSync/`; the OneDrive desktop client handles cloud
transport. The app does not call Microsoft Graph and does not store OAuth
tokens.

## Directory Layout

```text
PasteraSync/
  manifest.json
  histories/
    <history-id>.json
  snippets/
    folders/
      <folder-id>.json
    items/
      <snippet-id>.json
```

Files are written atomically by writing a temporary file in the same directory
and then replacing the destination.

## Record Shape

Each record includes:

- `id`
- `kind`
- `deviceID`
- `updatedAt`
- `deletedAt`
- encrypted payload bytes
- payload nonce
- payload authentication tag
- schema version

History payloads include title, pasteboard types, assets within
`maxSyncedAssetBytes`, and thumbnail metadata when available. Snippet payloads
include folder and snippet content needed to rebuild the SQLiteData tables.

## Encryption Boundary

V1 uses a user-provided sync passphrase to derive an AES-GCM key. Only derived
key material or wrapped local key references may be stored in Keychain. Do not
write plaintext passphrases, tokens, or recovered payloads into repository
files, logs, docs, or chat.

## Conflict Policy

Conflict resolution is last-write-wins using `updatedAt`; delete tombstones win
when their timestamp is newer than the local record. Tombstones are retained for
30 days by default so other devices can observe deletes.

## Limits

Default `maxSyncedAssetBytes` is 10 MB per history record. Records larger than
the limit are skipped for sync and remain local-only.
