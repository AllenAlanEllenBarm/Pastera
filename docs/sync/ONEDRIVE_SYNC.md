# OneDrive Folder Sync

## V1 Beta Model

Pastera v1 beta sync uses the local OneDrive folder on macOS. Pastera only
reads and writes protocol files under the OneDrive-backed local directory; the
OneDrive desktop client handles cloud transport. The app does not call
Microsoft Graph, CloudKit, or a hosted Pastera service.

The default macOS location is:

```text
~/Library/CloudStorage/<OneDrive>/Pastera/sync
```

The settings UI shows a friendly path such as `OneDrive > Pastera > sync`
instead of exposing the hidden `Library` path. Pastera detects usable
`~/Library/CloudStorage/OneDrive*` folders, filters shared-library/temp
locations, and creates `<OneDrive>/Pastera/sync` only for the selected default
candidate. If multiple OneDrive roots exist, Pastera prefers the personal
`OneDrive` folder; otherwise it uses the first usable OneDrive root by name.

There is no custom sync-folder picker in v1 beta. If no usable OneDrive folder
is detected, sync controls report that the user must install and log in to
OneDrive. Pastera does not fall back to `~/Documents`.

Sync is intentionally non-destructive:

- Cloud imports may create or update local history and snippet records.
- Cloud imports do not delete local history or snippets.
- Local deletes stay local and are not emitted as cross-device delete
  tombstones in v1.
- When a user deletes a synced local item, Pastera records a local suppression
  entry so the same cloud record is not imported back onto that device later.

## Directory Layout

`sync` is the protocol root. Pastera no longer creates an extra `PasteraSync`
folder inside it.

```text
<OneDrive>/Pastera/sync/
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
and then replacing the destination. Corrupt JSON and legacy encrypted beta
records are skipped during import.

Sync success status reflects local file work only. When Pastera reports that it
wrote records to the local sync folder, it means the local OneDrive-backed
folder was updated. Pastera does not know whether the OneDrive desktop client
has uploaded those files to the cloud yet.

## Manifest And Records

`manifest.json` stores the sync schema version, the creating device ID, the
manifest update time, and record summaries. It does not contain crypto metadata.

Each record includes:

- `id`
- `kind`
- `deviceID`
- `updatedAt`
- `deletedAt`
- plain JSON `payload`
- `schemaVersion`

The payload is a JSON object encoded directly in the record. History payloads
include title, pasteboard types, assets within `maxSyncedAssetBytes`, and
thumbnail metadata when available. Snippet payloads include folder and snippet
content needed to rebuild the SQLiteData tables. Binary assets inside payloads
use Swift `Codable` data encoding, but the record is not encrypted.

V1 keeps the `deletedAt` field for schema compatibility, but Pastera does not
emit or apply cross-device tombstones.

Legacy encrypted beta records with `nonce`, `ciphertext`, and `tag` payloads
are incompatible with the simplified protocol. New builds skip those records;
clean the sync folder or re-export from a current build if a beta profile still
contains old encrypted files.

## Sync Switches

The Sync pane has a top-level `自动同步` switch. It defaults to off and gates
startup sync, timer sync, and local-change sync. Manual `立即同步` remains
available even when automatic sync is off.

The app still exposes four detailed scope switches:

- History upload
- History import
- Snippet upload
- Snippet import

When `自动同步` is turned on for the first time and all four detailed switches
are off, Pastera enables all four scopes so the first sync has meaningful work.
All sync paths go through `SyncCoordinator`, which respects the same scope
switches for each pass.

When upload is enabled for the first time, Pastera records the enable time.
Upload candidates are limited to records from the current device with
`updatedAt` at or after that enable time. Existing local history and snippet
stock is not backfilled to the cloud.

Remote records preserve their source `deviceID` on import. Imported records are
therefore not treated as current-device changes and are not re-uploaded by the
importing device.

Import counts report actual local writes. A record that is skipped by legacy
payload incompatibility, local suppression, or last-write-wins checks is not
counted as imported.

Snippet upload includes enough folder context for changed snippets. When a
snippet changed after upload was enabled, the exported snapshot also includes
that snippet's parent folder record, even if the folder itself did not change
after the cutoff. The parent folder payload preserves its existing `updatedAt`;
export does not bump an old folder timestamp just to provide context.

## Conflict Policy

For same-ID active records, last write wins by business payload timestamp:

- Remote history uses payload `updateAt`.
- Remote snippet folders and snippets use payload `updatedAt`.
- A remote record is imported only when the local record does not exist, or the
  remote payload timestamp is strictly greater than the local `updatedAt` /
  `updateAt`.
- Equal or older remote records are skipped.

Sync record `updatedAt` is copied from the business payload timestamp. It is not
replaced with the export time when the payload timestamp is `0`.

Remote tombstones do not delete or replace local active data in v1. Local
suppression still blocks re-importing records that the user deleted on this
device, even when the remote payload timestamp is newer.

If the OneDrive desktop client creates conflict copies of JSON files, Pastera v1
does not automatically merge those copies. Resolve or inspect OneDrive conflict
files manually before treating the folder as converged.

## Limits

Default `maxSyncedAssetBytes` is 10 MB per history record. Records larger than
the limit are skipped for sync and remain local-only.
