# Folder Sync

## V3 Snapshot Model

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

- Cloud imports may create or update local history and snippet records.
- Cloud imports do not delete local history or snippets.
- Local deletes stay local and are not emitted as cross-device tombstones.
- When a user deletes a synced local item, Pastera records a local suppression
  entry so the same cloud item is not imported back onto that device later.

## Directory Layout

`sync` is the protocol root. History and snippets are stored separately, and
each device writes one SQLite snapshot per kind.

```text
<OneDrive>/Pastera/sync/
  history/
    devices/
      <device-id>.sqlite
  snippets/
    devices/
      <device-id>.sqlite
```

The old development protocol is not read. Pastera no longer reads
`manifest.json`, `histories/*.json`, or `snippets/items|folders/*.json`.
The first v3 write removes those known old paths from the selected sync root.

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

History metadata includes `schemaVersion=3`, `deviceID`, `platform`,
`generatedAt`, `historyLimit`, `maxTextBytes`, and
`snapshotTextBudgetBytes`.

History sync is text-only. `sourceKind` is one of:

- `plainText`: UTF-8 text copied as plain text.
- `url`: a non-`file://` URL serialized as its absolute string.

Images, files, PDFs, RTF, HTML, thumbnails, and raw pasteboard assets are not
stored in history sync snapshots. The history protocol does not expose macOS
`NSPasteboard` type names.

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
```

Snippet metadata includes `schemaVersion=2`, `deviceID`, and `generatedAt`.

Snippet snapshots remain full snapshots and may keep all snippet text. They are
independent from the text-only history protocol.

## Upload And Import

History upload writes only records whose `deviceID` matches the current device.
The exported history snapshot is ordered by `updatedAt DESC`, capped at 2000
rows, skips single text values larger than 256 KiB, and stops when the snapshot
reaches the 8 MiB text budget. The effective count is also limited by the local
stored-history retention setting. New installs default that local retention to
2000; explicit existing user settings are not force-reset.

Snippet upload writes the current complete snippet library. Folder and snippet
rows keep their `lastModifiedDeviceID`, so imported remote snippets do not
become current-device changes.

Import reads SQLite snapshots from other devices only. Same-ID conflicts use
last-write-wins by business timestamp:

- Remote history uses `histories.updatedAt`.
- Remote snippet folders and snippets use their `updatedAt`.
- A remote row is imported only when the local row does not exist, or the
  remote timestamp is strictly greater than the local timestamp.
- Equal or older remote rows are skipped.

Imported history rows are written locally as plain text clipboard history. URL
history also imports as plain text so it works the same across macOS and future
Windows clients.

Remote absence never deletes local data. Import counts report actual local
writes; corrupt snapshots, locally suppressed IDs, and older/equal records are
not counted as imported.

## Sync Switches

The Sync pane separates automatic work into two main switches:

- `自动上传`: startup, timer, and local-change passes may write this device's
  history/snippet snapshots to OneDrive.
- `自动同步`: startup and timer passes may import snapshots written by other
  devices.

Four detailed scope switches still control the exact work:

- `上传历史`
- `同步历史`
- `上传片段`
- `同步片段`

When `自动上传` is turned on and both upload scopes are off, Pastera enables
history and snippet upload so the switch has meaningful work. When `自动同步`
is turned on and both import scopes are off, Pastera enables history and
snippet import.

Manual `立即同步` bypasses the two automatic main switches, but still respects
the four detailed scope switches.

## Limits

History snapshots are capped at 2000 rows per device. A single history text
value larger than 256 KiB is skipped rather than truncated. Each device snapshot
also has an 8 MiB cumulative text budget. Items skipped by these sync limits
remain in the local clipboard history when local retention allows them.
