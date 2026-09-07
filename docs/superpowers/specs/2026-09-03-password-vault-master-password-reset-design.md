# Password Vault Master Password Reset Design

## Goal

Replace the current master-password change flow with a reset flow that solves the
forgotten-password case without claiming that encrypted data can be recovered when
no decryption material exists.

The feature has two paths:

1. **Secure reset** uses macOS device-owner authentication and an already available
   vault unlock key to set a new master password while preserving all vault data.
2. **Forced reset** is the fallback when no unlock key is available. It preserves
   one latest encrypted archive, creates a new empty vault, and explains that the
   original archive remains unreadable unless the original master password is
   remembered later.

The password-vault preference page is also reorganized into a stable full-width
vertical layout so status, controls, messages, and recovery actions share a clear
alignment and hierarchy.

## Current Problem

The preference page labels its action as changing the master password but requires
the current master password even when the user has already unlocked the vault through
this Mac. That only supports routine rotation; it does not support the primary reset
scenario in which the current password has been forgotten.

The page also places unequal locking and master-password cards side by side. Status
and feedback live in the left card while the password action sits in the shorter right
card, producing uneven vertical rhythm and misaligned content as text wraps or the
window width changes.

## Product Decisions

### macOS authentication, not Touch ID

Reset authorization uses `LAPolicy.deviceOwnerAuthentication`. Touch ID or Apple
Watch may satisfy the policy when available, but they are not required; macOS can
fall back to the current user's Mac login password.

Passing system authentication proves that the current Mac user authorized the
operation. It does not derive or replace the KDBX decryption key. Data-preserving
reset is therefore available only when Pastera already has valid decryption material
from one of these sources:

- the current readable vault session; or
- the user-presence-protected quick-unlock key in Keychain; or
- the existing Agent automation-unlock key, after the user has separately completed
  macOS device-owner authentication for this reset attempt.

If neither source is available, Pastera must not report that the old vault was
recovered or silently replace it. The UI moves to the forced-reset explanation.

### No recovery-code system

This change does not introduce a recovery code, escrowed key, security questions, or
network account recovery. Those mechanisms cannot recover an existing vault unless
they were provisioned before its master password was lost, and they would add a new
long-lived secret-management contract beyond this request.

### One latest archive slot

Local storage and OneDrive each keep at most one forced-reset archive. A later forced
reset atomically replaces the previous archive only after the new archive has been
written and verified. No timestamped archive history accumulates.

The archive is the encrypted active KDBX snapshot that existed immediately before
forced reset. It is not decrypted, merged, or re-encrypted. Its old master password
is still required to open it.

## User Experience

### Preference-page layout

Replace the weighted two-column layout with three full-width groups in this order:

1. **Vault Status**
   - status badge and state explanation;
   - automatic-lock setting;
   - a renamed **System Unlock** switch whose description says that this Mac's
     authentication can use Touch ID, Apple Watch, or the Mac login password.
2. **Master Password**
   - a short explanation that the master password encrypts the vault;
   - the primary **Reset Master Password...** button.
3. **Can't Unlock?**
   - a restrained warning explaining that forced reset creates an empty vault;
   - a destructive **Force Reset Password Vault...** button.

All groups use the same leading and trailing edges. Setting labels share a text
column, controls share a trailing alignment, and action rows use the same insets.
Feedback appears directly below the action that produced it instead of inside the
unrelated locking group. The page remains a single column at every supported width,
so wrapping does not reorder or offset the cards.

The forced-reset action remains visually secondary until opened. It uses destructive
styling but not an oversized danger banner on the main preference page.

### Secure reset sheet

The normal reset sheet contains:

- title: **Reset Master Password**;
- a concise explanation that Pastera will use this Mac's authentication;
- new master password;
- confirmation;
- the existing permanent warning that forgotten master passwords cannot otherwise
  be recovered;
- Cancel and **Authenticate & Reset** actions.

The current-master-password field is removed. Submission first validates the two new
fields, then presents system authentication. On success, Pastera reuses that authorized
authentication context when reading a protected quick-unlock key, so the user is not
asked to authenticate twice, and then runs the transactional rekey. The sheet stays
open with an inline error if authentication is cancelled, the unlock material is
unavailable, a sync conflict is detected, or the file transaction fails.

When unlock material is unavailable, the sheet does not automatically perform a
destructive reset. It explains that the data-preserving path cannot continue and
offers a separate **Review Force Reset...** action.

### Forced reset sheet

The forced-reset sheet uses a separate destructive confirmation flow. Its primary
message is:

> No usable unlock key is available. Because the existing password vault is
> encrypted, Pastera cannot decrypt or recover it. Continuing will preserve one
> latest encrypted archive and create a new empty password vault. Only the original
> master password can open the archive.

The localized Simplified Chinese text is:

> 当前没有可用的解锁密钥。受加密方式限制，Pastera 无法解密或找回原密码箱。继续后将保留一份最新的加密归档，并创建一个空密码箱。只有原主密码才能打开该归档。

The sheet additionally states that another forced reset replaces the currently saved
archive. It contains new-password and confirmation fields plus an unchecked
acknowledgement: **I understand that my old entries will not appear in the new
password vault.** The destructive button remains disabled until the passwords match
and the acknowledgement is checked.

Submission performs a second, fresh macOS device-owner authentication. Successful
authentication authorizes only this attempt; cancelling returns to the sheet without
changing local files, sync metadata, Keychain items, or Agent access.

### Completion feedback

A successful secure reset reports that folders and entries were preserved. A
successful forced reset reports that a new empty vault is ready and shows whether the
OneDrive replacement is complete or pending.

When OneDrive is unavailable, the completion text says:

> The new local password vault is ready. Password-vault sync is paused until Pastera
> can archive and replace the previous OneDrive vault.

The page must continue to show the pending state after the sheet closes and after app
restart.

## Architecture

### Store contract

`PasswordVaultStore` separates the two operations:

- a data-preserving reset that accepts the new password and uses current store-owned
  unlock material; and
- a forced local reset that accepts the new password and a verified archive target.

The data-preserving operation must not accept an old password. It resolves unlock
material in this order:

1. reuse the readable session's `UnlockData`; otherwise
2. load the quick-unlock raw key through the existing user-presence-protected
   Keychain item and verify that it opens the active vault; otherwise
3. load the automation-unlock raw key only after the reset's macOS authorization and
   verify that it opens the active vault; otherwise
4. fail with a dedicated `resetRequiresForcedReset` error.

The existing `VaultArtifactRekeyTransaction` remains the only multi-file replacement
path for secure reset. It re-encrypts the active vault and all currently managed KDBX
artifacts, verifies every staged file with the new key, checks source revisions, and
rolls back before commit on failure.

Forced reset runs under the same local exclusive file transaction and Agent serial
executor as other vault lifecycle changes. It:

1. reads and validates the KDBX signature of the current active vault;
2. stages and verifies the single local latest archive;
3. creates and verifies a new empty `Pastera` KDBX with the requested password;
4. atomically replaces the archive slot and active vault as one recoverable
   transaction;
5. removes stale managed backup/conflict artifacts only after the new active vault
   and archive are durable;
6. replaces quick-unlock material according to the user's current System Unlock
   preference;
7. deletes the old automation-unlock key;
8. publishes a distinct forced-reset commit to the sync controller.

The local archive lives outside the existing managed-artifact enumeration so a later
normal master-password reset cannot mistake an old-key archive for a current vault
artifact.

### Controller authorization

`PasswordVaultUIController` owns both reset entrypoints and reuses
`PasswordVaultAuthorizing`. The authorizer returns an opaque, single-attempt authorized
context rather than only `Void`. The Keychain adapter can consume that context when
loading the quick-unlock key; readable-session resets do not need to consume it again.
This keeps one visible authentication prompt per attempt. Authentication callbacks
return to the existing store queue, keeping reset, clipboard UI work, sync merges, and
Agent operations serialized.

Before invoking the destructive store transaction, the controller uses a shared
`VaultAgentAuthorizationPolicy` reset coordinator to revoke every persisted and
in-memory Agent grant. The coordinator is registered with the live deferred Agent
runtime; when that runtime has not started, it loads and revokes the durable grants
directly on the same executor. Revocation deliberately happens first: if the later
file transaction fails, users may need to authorize Agent clients again, but no stale
grant can ever observe a newly reset vault.

The controller exposes reset capability in the security-settings snapshot:

- `preservesData` when a readable session or quick-unlock key is available;
- `requiresForcedReset` when the vault exists but no unlock material is available;
- `unavailable` during file, migration, read-only, or lifecycle failure states.

The UI may explain the capability before opening a sheet, but the store rechecks it
inside the serialized operation. A stale UI snapshot never authorizes a reset.

### Local archive transaction

`PasswordVaultLocalPaths` gains one explicit latest-archive URL beneath a dedicated
recovery directory. The archive replacement uses staged write, disk readback, digest
verification, source-revision comparison, and rollback semantics equivalent to the
existing rekey transaction.

If a previous archive exists, it is not removed first. The transaction stages the
new archive, verifies it, swaps it into the latest slot, and retains the previous file
as rollback material until the new active vault has also committed. Any pre-commit
failure restores the previous active vault and previous latest archive.

### OneDrive forced-reset state

`PasswordVaultSyncMetadata` gains an explicit pending forced-reset record containing
the pre-reset local digest, the new local vault digest when known, and the remote
digest observed for the old vault when one was available. This is a lifecycle state,
not an ordinary pending local edit.

Before the local destructive transaction starts, the controller asks the sync
controller to persist a prepared forced-reset record. After the local transaction
commits, it records the returned new encrypted digest. If the local transaction fails,
the prepared record is cancelled. On startup, a prepared record with no new digest is
reconciled against the active local digest: an unchanged digest means no reset occurred
and the record can be cancelled; a changed digest means the local reset committed
before the app stopped, so that digest becomes the pending remote replacement. This
closes the crash window between local file commit and ordinary asynchronous commit
observation.

While the record exists:

- normal download and merge decisions are disabled;
- the old remote vault can never be merged into the new empty generation;
- the password-vault sync UI reports a paused, pending-reset state;
- retries perform only the forced-reset remote transaction.

OneDrive and its File Provider cannot guarantee one atomic commit spanning the archive
and active-vault paths. The sync service therefore implements an idempotent, durable
state machine in `PasswordVaultSyncMetadata`. When OneDrive is reachable, it advances
through this sequence:

1. read the current remote active vault and capture its digest;
2. stage, replace, and read back the single remote latest-archive slot;
3. compare-and-swap the new local vault into the remote active path, requiring the
   active remote digest to remain unchanged;
4. update sync baselines and clear the pending forced-reset record only after the
   uploaded active vault reads back with the expected digest.

A crash or provider failure after step 2 leaves the old active vault in place and the
new latest archive already verified; retry resumes at step 3. A crash after step 3 is
recognized from the expected new active digest and finishes the metadata commit instead
of attempting a merge or creating another archive. Replacing the latest archive may
discard the previous archive, but only after the currently active old vault has been
staged and verified as its replacement.

If the remote changes during the operation, the sync service does not overwrite it.
It remains paused and asks the user to retry after reviewing the conflict. If
OneDrive is offline, local forced reset still completes and persists the pending
record; the same transaction resumes when OneDrive becomes available.

A later forced reset replaces the pending local generation and latest local archive in
the local recoverable transaction. The remote state machine subsequently replaces the
single remote archive slot. It still keeps only one archive per location.

## Error and Security Semantics

- System authentication failure or cancellation never mutates vault state.
- No master password, derived key, raw unlock key, entry plaintext, or authentication
  value is logged or persisted outside its existing protected destination.
- A valid Mac login does not imply that the old KDBX can be decrypted. The UI and
  error types keep authorization and decryption capability distinct.
- Secure reset never falls through into forced reset without a separate explanation,
  acknowledgement, and fresh system authentication.
- Local archive creation or verification failure aborts forced reset.
- OneDrive failure after local commit leaves a durable pending state and pauses only
  password-vault synchronization; it does not report full completion.
- Remote compare-and-swap failure never overwrites an unobserved remote revision.
- Forced reset invalidates automation access and prior Agent grants even if the Agent
  is not currently connected.
- The existing encrypted archive is never exposed through ordinary password-vault
  browsing, search, Agent APIs, or sync merge logic.

## Test Strategy

### Store and transaction tests

- secure reset succeeds without the old password from a readable session;
- secure reset succeeds from a Keychain raw key after system authentication;
- secure reset succeeds from an automation-unlock key only after system
  authentication;
- missing or invalid unlock material returns `resetRequiresForcedReset` without
  changing any artifact;
- secure reset continues to rekey all managed artifacts and preserves merged content;
- forced reset produces an empty vault readable only with the new password;
- the latest archive remains byte-for-byte equal to the pre-reset active vault and
  opens only with the old password;
- a second forced reset replaces the previous archive and leaves exactly one archive;
- injected stage, verification, revision, replacement, Keychain, and cleanup failures
  exercise rollback or warning behavior at the defined commit boundary;
- old automation keys and Agent grants are revoked before the new empty vault becomes
  readable.

### Sync tests

- online forced reset archives and compare-and-swaps the remote vault before clearing
  pending state;
- offline forced reset persists pending state across service and app restart;
- ordinary synchronization cannot merge or upload while forced reset is pending;
- a remote revision race preserves the remote file and keeps sync paused;
- retry completes the pending transaction and establishes the new baseline;
- repeated forced reset leaves one local archive and one remote archive.

### UI and accessibility tests

- preference groups are full-width, ordered, and share leading/trailing alignment at
  default and minimum window sizes;
- status, action feedback, and pending-OneDrive text remain attached to their owning
  groups;
- secure reset has two password fields, no current-password field, correct key loop,
  validation, busy state, and system-authentication errors;
- forced reset requires matching passwords, acknowledgement, and fresh authorization;
- exact English and Simplified Chinese recovery-limit wording is present;
- destructive controls expose appropriate accessibility roles and labels;
- Return, Escape, visibility toggles, focus restoration, dark mode, increased text
  height, and Reduce Motion remain usable.

### Verification

Run the focused master-password, security-settings, sync, transaction, preference
layout, localization, keyboard, and accessibility suites first. Then run the default
serial full test command with isolated package caches as required by the repository.
After build and test verification, reinstall `/Applications/Pastera.app` using the
repository install script for manual acceptance.

## Acceptance Criteria

- A user who forgot the old master password can preserve data when Pastera still has
  valid unlock material, using the Mac login password instead of requiring Touch ID.
- Pastera never claims to recover encrypted data when no unlock material exists.
- Forced reset requires explicit acknowledgement and fresh macOS authentication.
- Forced reset leaves a new empty vault and at most one latest encrypted archive in
  local storage and OneDrive.
- An offline or failed OneDrive replacement cannot reintroduce the old vault; sync
  remains visibly paused until the pending replacement completes.
- Existing Agent automation cannot access the newly reset vault without being
  authorized again.
- The password-vault preference page uses a visually stable, aligned single-column
  layout at all supported sizes.
- All affected focused tests, the full regression suite, and the local installation
  verification pass before the work is reported complete.

## Non-Goals

- Recovering an old vault without its original master password or an existing unlock
  key.
- Keeping multiple forced-reset archives or offering archive-history management.
- Uploading secrets, recovery keys, or master passwords to a Pastera service.
- Changing KDBX encryption algorithms or file compatibility.
- Redesigning password entries, folders, clipboard actions, or unrelated preference
  panes.
