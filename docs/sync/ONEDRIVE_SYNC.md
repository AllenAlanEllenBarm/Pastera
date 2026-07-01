# Folder Sync

## V4 Snapshot Model

Pastera sync uses ordinary files in a folder-sync provider. On macOS today that
folder is a local OneDrive directory; the OneDrive desktop client handles cloud
transport. Pastera does not call Microsoft Graph, CloudKit, or a hosted Pastera
service. A future Windows client can write the same `Pastera/sync` structure
under its own OneDrive/AppData-backed path.

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

The settings UI allows the user to choose a sync location. On macOS the chosen
location must be inside a usable OneDrive folder and writable; otherwise Pastera
does not save it. If no usable OneDrive folder is detected, sync controls report
that the user must install and log in to OneDrive. Pastera does not fall back to
`~/Documents`.

Sync is intentionally non-destructive:

- Cloud imports may create or update local history records.
- Cloud history imports do not delete local history.
- Cloud snippet imports may apply explicit folder/snippet deletion tombstones
  when the tombstone is newer than the matching local row.
- Remote absence never deletes local history or snippets.
- When a user deletes a synced local history item, Pastera records a local
  suppression entry so the same cloud item is not imported back onto that device
  later.
- When a user deletes a synced local snippet folder or item, Pastera exports a
  deletion tombstone so other devices can apply the newer snippet deletion.

## Directory Layout

`sync` is the protocol root. History and snippets are stored separately, and
each device writes one SQLite snapshot per kind. File assets are a separate
directory domain: metadata lives in a JSON manifest, while payloads remain as
ordinary files under the device's `assets` directory.

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

The old development protocol is not read. Pastera no longer reads
the root-level `manifest.json`, `histories/*.json`, or
`snippets/items|folders/*.json`. History sync is not backward-compatible during
development: if `history/protocol.json` is missing, corrupt, or not
`schemaVersion=4`, Pastera deletes and rebuilds only the `history` domain.
The `files` domain is left intact.

Each app installation uses a persistent app-level device UUID. macOS seeds that
value from the machine UUID on first use when available, then stores it in
preferences; Windows should store an equivalent UUID under the user's app data
directory. Device snapshot file names only use cross-platform-safe characters.

Snapshots are written by generating a temporary SQLite file in the target
directory, closing the SQLite connection, then atomically replacing the target
device snapshot. WAL is disabled so OneDrive does not need to sync `-wal` or
`-shm` sidecar files.

Corrupt SQLite snapshots are skipped during import. Sync success status
reflects local file work only; Pastera does not know whether the OneDrive
desktop client has uploaded the local snapshot to the cloud.

## SQLite Schemas

History snapshot:

```sql
metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)
histories(
  id TEXT PRIMARY KEY NOT NULL,
  updatedAt INTEGER NOT NULL,
  sourceKind TEXT NOT NULL,
  text TEXT NOT NULL
)
CREATE INDEX histories_updatedAt_index ON histories(updatedAt DESC);
```

History metadata includes `schemaVersion=4`, `deviceID`, `platform`,
`generatedAt`, `historyLimit`, `maxTextBytes`, `snapshotTextBudgetBytes`, and
`windowSignature`.

History sync is text-only. `sourceKind` is one of:

- `plainText`: UTF-8 text copied as plain text.
- `url`: a non-`file://` URL serialized as its absolute string.

Images, files, PDFs, RTF, HTML, thumbnails, and raw pasteboard assets are not
stored in history sync snapshots. The history protocol does not expose macOS
`NSPasteboard` type names.

File asset snapshot:

```json
{
  "manifestVersion": 1,
  "schemaVersion": 1,
  "deviceID": "<device-id>",
  "generatedAt": 1781970000,
  "assetCount": 2,
  "histories": [
    {
      "historyID": "<history-id>",
      "updatedAt": 1781970000,
      "assets": [
        {
          "assetIndex": 0,
          "pasteboardType": "com.adobe.pdf",
          "byteCount": 1234,
          "modifiedAtNanoseconds": 1781970000000000000,
          "relativePath": "assets/<history-id>/000-1234-1781970000000000000-document.pdf",
          "originalFilename": "document.pdf"
        }
      ]
    }
  ]
}
```

The file manifest stores only metadata and relative file paths. Binary payloads
are written directly as normal files under
`files/devices/<device-id>/assets/<history-id>/`. File assets are versioned by
asset index, byte count, source modification time when available, and the
original filename. Pastera does not keep a separate local file index or hash file
contents during file sync.

Snippet snapshot:

```sql
metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)
folders(id TEXT PRIMARY KEY, title TEXT NOT NULL, displayIndex INTEGER NOT NULL,
        isEnabled INTEGER NOT NULL, updatedAt INTEGER NOT NULL,
        lastModifiedDeviceID TEXT)
snippets(id TEXT PRIMARY KEY, folderID TEXT NOT NULL, title TEXT NOT NULL,
         content TEXT NOT NULL, displayIndex INTEGER NOT NULL,
         isEnabled INTEGER NOT NULL, updatedAt INTEGER NOT NULL,
         lastModifiedDeviceID TEXT)
deletedFolders(id TEXT PRIMARY KEY, title TEXT NOT NULL, deletedAt INTEGER NOT NULL,
               deviceID TEXT)
deletedSnippets(id TEXT PRIMARY KEY, folderID TEXT NOT NULL, folderTitle TEXT NOT NULL,
                content TEXT NOT NULL, deletedAt INTEGER NOT NULL,
                deviceID TEXT)
```

Snippet metadata includes `schemaVersion=3`, `deviceID`, and `generatedAt`.
Pastera still reads `schemaVersion=2` snippet snapshots for development
compatibility, but current writes use `schemaVersion=3` so explicit deletion
tombstones can travel between devices.

Snippet snapshots remain full snapshots and may keep all snippet text. They are
independent from the text-only history protocol.

## Upload And Import

History upload writes only records whose `deviceID` matches the current device.
The exported history snapshot is ordered by `updatedAt DESC`, capped at 2000
rows, skips single text values larger than 256 KiB, and stops when the snapshot
reaches the 8 MiB text budget. The effective count is also limited by the local
stored-history retention setting. New installs default that local retention to
2000; explicit existing user settings are not force-reset.

Pastera computes a lightweight window signature from exported row IDs,
timestamps, source kinds, text byte counts, and sync limits. If the signature is
unchanged and the current device snapshot still exists, Pastera skips rewriting
the SQLite file so OneDrive has nothing new to upload.

Snippet upload writes the current complete snippet library. Folder and snippet
rows keep their `lastModifiedDeviceID`, so imported remote snippets do not
become current-device changes.

File upload writes this device's newest supported non-text clipboard assets.
The file domain is independent from text history sync and snippet sync:

- Supported file assets are images, PDF, and RTF/RTFD.
- Plain text and non-file URL history stay in the text-only history protocol.
- Finder file URL history is not part of OneDrive file sync.
- Each device exports at most 10 file assets.
- A single file asset larger than 25 MiB is skipped.
- A multi-asset history is kept whole; if it would exceed the 10-asset budget
  or contains a skipped asset, the whole history is skipped for file sync.

Import reads SQLite snapshots from other devices only. Same-ID conflicts use
last-write-wins by business timestamp:

- Remote history uses `histories.updatedAt`.
- Remote snippet folders and snippets use their `updatedAt`.
- Remote snippet deletions use `deletedAt`.
- A remote row is imported only when the local row does not exist, or the
  remote timestamp is strictly greater than the local timestamp.
- A remote snippet deletion is applied only when its `deletedAt` is greater than
  or equal to the matched local snippet or folder `updatedAt`.
- Equal or older remote rows are skipped.

Imported history rows are written locally as plain text clipboard history. URL
history also imports as plain text so it works the same across macOS and future
Windows clients.

Remote absence never deletes local data. Import counts report actual local
writes; corrupt snapshots, locally suppressed IDs, older/equal records, and
older snippet tombstones are not counted as imported.

Before opening a remote history SQLite file, Pastera compares its file size and
modification time against the last successfully processed state for that app
run. Unchanged remote snapshots are skipped without opening SQLite or running
row-level import checks.

## Sync Switches

The Sync pane separates automatic work into two main switches:

- `自动上传`: startup, timer, and local-change passes may write this device's
  history/snippet snapshots to OneDrive.
- `自动同步`: startup and timer passes may import snapshots written by other
  devices.

Four detailed scope switches control text history and snippets:

- `上传历史`
- `同步历史`
- `上传片段`
- `同步片段`

When `自动上传` is turned on and both upload scopes are off, Pastera enables
history and snippet upload so the switch has meaningful work. When
`自动同步` is turned on and both import scopes are off, Pastera enables history
and snippet import.

File assets are controlled by compact icon checkboxes in the `文件类型` row of
the OneDrive account section. The default is no selected file type; choosing
image, PDF, or RTF/RTFD enables the separate `files` sync domain for the matching
history direction. This keeps text history snapshots small and fast while still
allowing selected binary assets to upload through the independent manifest/file
path.

Manual `立即同步` bypasses the two automatic main switches, but still respects
the four text/snippet scope switches and the selected file types.

## Limits

History snapshots are capped at 2000 rows per device. A single history text
value larger than 256 KiB is skipped rather than truncated. Each device snapshot
also has an 8 MiB cumulative text budget. Items skipped by these sync limits
remain in the local clipboard history when local retention allows them.

File snapshots are capped at 10 file assets per device. A single file asset
larger than 25 MiB is skipped. File skips and validation failures do not fail
text history or snippet sync; Pastera reports them as sync warnings.
