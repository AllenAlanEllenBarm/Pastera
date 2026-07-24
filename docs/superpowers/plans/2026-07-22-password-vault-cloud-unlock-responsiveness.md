# Password Vault Cloud Unlock Responsiveness Implementation Plan

> **Historical status:** This direct-cloud unlock design was completed on 2026-07-22 and was subsequently superseded by `2026-07-22-password-vault-local-first-onedrive-sync.md`. The delivery record below is retained as investigation history; its cloud-file working-copy architecture must not be reapplied to the current local-first implementation.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make password-vault unlock feel immediate and remain visibly responsive when the encrypted KDBX file is a OneDrive cloud placeholder, while distinguishing an unavailable cloud item from a corrupted KDBX database.

**Architecture:** Keep the OneDrive KDBX file as the synchronization source of truth, but prefetch its encrypted bytes on the existing serial vault queue and retain only that encrypted payload in memory. `VaultFileCoordinator` validates the cached payload against inexpensive file metadata before unlock, while synchronization reads still go directly to the cloud-backed file. The main menu renders its local in-flight access state immediately so slow cloud materialization is shown as an active unlock instead of a frozen stale screen.

**Tech Stack:** Swift 6, AppKit, Foundation, Swift Testing, KDBXKit, macOS File Provider/OneDrive filesystem metadata.

## Global Constraints

- Never cache or persist the plaintext master password, decrypted entries, or derived unlock key outside the existing protected session objects.
- Preserve the configured OneDrive KDBX location and current merge/conflict behavior.
- Do not make KDBX parsing, OneDrive materialization, or Keychain access run on the main thread.
- Cached bytes must be the encrypted KDBX payload only and must be invalidated when file size or modification time changes.
- Preserve automatic quick unlock, automation unlock, master-password reset, auto-lock, and read-only warning behavior.
- Preserve unrelated dirty-worktree files.

## Business Scope / Out of Scope

### In Scope

- Warm the encrypted KDBX payload before the user submits the master password.
- Reuse the warm payload for password, quick-key, and automation unlock when the cloud file metadata is unchanged.
- Show the embedded access form in a disabled, visibly busy state immediately after submit.
- Ensure success, cancellation, and failure always clear the in-flight presentation state.

### Out of Scope

- Moving the password vault out of the configured synchronization root.
- Replacing OneDrive/File Provider or adding a second persistent vault database.
- Changing KDBX encryption parameters, credentials, Keychain access control, or recovery policy.
- Adding cancellation for a filesystem read already executing inside File Provider.

## Root Cause Evidence

- The installed app's configured `PasteraVault.kdbx` initially reported macOS flags `compressed,dataless`; File Provider reported `isDownloaded=0` and `isUploaded=1`, while the OneDrive desktop process was not running.
- A real Finder download attempt for the configured KDBX and its `.bak` both failed with `未能打开该文件`; coordinated reads failed with underlying `OneDrive` error `-17`.
- A direct data read returned zero bytes while filesystem metadata still reported 1469 bytes. The old coordinator accepted that result and KDBX parsing subsequently surfaced the misleading internal state code `corrupted`.
- A live five-second process sample after the incident showed the main thread idle in the AppKit event loop and no active KDBX/store thread, excluding a persistent main-thread deadlock or compute loop.
- `PasswordVaultUIController.publishBusyState()` updates the snapshot, but `MainMenuPanelController.submitPasswordVaultAccess` does not immediately reload. While a slow unlock is in flight, the old access/content view therefore remains visible and looks frozen until completion.

## Acceptance Mapping

| Acceptance | Evidence |
| --- | --- |
| A prefetched encrypted vault does not perform a second cloud data read before unlock when metadata is unchanged. | New `PasswordVaultStoreTests` coordinator cache test. |
| A changed cloud file bypasses stale encrypted bytes. | New metadata-invalidation store test. |
| A short cloud-placeholder read is reported as retryable cloud unavailability, not KDBX corruption. | New coordinator short-read test plus real Finder/File Provider reproduction. |
| Internal failure state codes are never rendered directly in the menu. | New localized-failure menu test. |
| Submitting a password immediately replaces the form with a disabled `Unlocking…` state while completion is pending. | New `PasswordVaultMenuTests` pending-unlock test. |
| Success/failure returns to folders or the usable unlock form and does not leave a stale busy state. | Existing embedded flow tests plus new completion assertions. |
| Password, quick-key, and automation KDBX lifecycle behavior remains compatible. | Focused password-vault menu/store suites. |
| The app remains regression-safe and installable. | Full clean test, `git diff --check`, local install, signing/process readback. |

## Risks, Rollback and Observation

- **Risk:** Returning stale encrypted bytes after a remote update. **Mitigation:** compare file size and modification time before every cache hit; direct synchronization reads never use the cache.
- **Risk:** Prefetch and a concurrent sync write race. **Mitigation:** protect cached payload/fingerprint with a lock, cache only fingerprint-stable reads, and invalidate the prepared payload around writes.
- **Risk:** OneDrive is offline or cannot retrieve the item on the first read. **Mitigation:** coordinated reads reject short payloads, return a retryable cloud-unavailable error, and show localized feedback; no plaintext fallback is introduced.
- **Rollback:** remove the prefetch/cache methods and the immediate busy reload; the vault remains readable through the existing direct cloud path.
- **Observation:** after local install, confirm the configured vault is materialized or the app remains responsive with `Unlocking…` while OneDrive is unavailable; sample the process if latency persists.

## Delivery Metadata

- **Plan Path:** `docs/superpowers/plans/2026-07-22-password-vault-cloud-unlock-responsiveness.md`
- **Plan Status:** `superseded-by-local-first`
- **Evidence Profile:** `standard`
- **Story ID:** `not-created`
- **Task IDs:** `not-created`; Tasks 1-3 are one local bug-fix delivery authorized directly by the user.
- **ZenTao Sync Status:** `not-synced` (no repository ZenTao contract or requested task ID exists for this change).
- **ZenTao Readback Evidence / Time:** `not-applicable`
- **Last Updated:** `2026-07-22`

## Tasks

### Task 1: Prove the cloud-read and stale-busy regressions

**Files:**
- Modify: `pasteraTests/PasswordVaultStoreTests.swift`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`

- [x] Add a coordinator test proving a prepared encrypted payload is reused without a second data read.
- [x] Add a coordinator test proving changed file metadata invalidates the prepared payload.
- [x] Add an embedded-menu test with a pending unlock completion and assert the busy view appears synchronously and disables submission.
- [x] Run the focused tests and record the expected RED failures before production edits.

### Task 2: Prefetch encrypted KDBX bytes and render in-flight UI immediately

**Files:**
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`

- [x] Add a default no-op `prepareForUnlock()` store boundary and implement KDBX encrypted-byte prefetch on the existing vault queue.
- [x] Add a lock-protected encrypted payload/fingerprint cache to `VaultFileCoordinator`.
- [x] Use cache-aware reads only for unlock paths; leave sync/merge reads direct.
- [x] Invalidate cached encrypted bytes around vault writes so the next unlock performs a fingerprint-stable read.
- [x] Render the local in-flight mode immediately after create/password/quick unlock begins and preserve completion cleanup.
- [x] Run the focused tests and record GREEN evidence.

### Task 3: Regression, install, and runtime readback

**Files:**
- Test: `pasteraTests/PasswordVaultMenuTests.swift`
- Test: `pasteraTests/PasswordVaultStoreTests.swift`
- Update: this plan's `Delivery Record`.

- [x] Run `git diff --check` and focused password-vault suites.
- [x] Run the repository default clean full test command.
- [x] Install the revised cloud-error mapping with `./script/install_local.sh --verify`.
- [x] Reproduce the pre-recovery failure through Finder and File Provider; both the main file and `.bak` failed outside Pastera while OneDrive was not running.
- [x] Start OneDrive, materialize the main KDBX, verify its KDBX header, restart Pastera, and confirm coordinated reads complete without a File Provider error.
- [x] Update task checkboxes, actual diff, deviations, verification, and residual risk below.

## Delivery Record

### Actual Implementation

- Added an encrypted KDBX payload cache to `VaultFileCoordinator`, keyed by standardized URL, file size, and modification time.
- Added background `prepareForUnlock()` dispatch during password-vault controller startup and cache-aware reads for password, quick-key, and automation unlock.
- Kept synchronization, merge, conflict, and rekey reads on the direct cloud-backed path.
- Added immediate main-menu busy rendering after password/create/quick-unlock submission.
- Made File Provider metadata lookup best-effort: unavailable metadata bypasses the cache and continues through the direct encrypted-data read.
- Cached a read only when its pre-read and post-read fingerprints match; vault writes invalidate the prepared payload so a concurrent remote replacement cannot bind stale bytes to new metadata.
- Added regression tests for cache reuse, cache invalidation, replacement-during-read, metadata fallback, controller prefetch, disabled busy controls, and completion convergence.
- Switched the default KDBX read to `NSFileCoordinator`, rejected metadata/data length mismatches, kept cloud-unavailable failures retryable, and localized internal failure state codes instead of rendering values such as `corrupted`.

### Plan Deviations

- A native spinner was not added because the existing localized `Unlocking…` state and disabled controls provide deterministic progress feedback with less UI churn.
- The plan initially proposed refreshing the cache after successful writes. Review exposed a remote-replacement race, so writes now invalidate it and the next unlock performs a fingerprint-stable read instead.

### Impact

- Password-vault startup may proactively materialize the small encrypted KDBX file from OneDrive on the existing background vault queue.
- Only encrypted KDBX bytes are retained in memory; plaintext credentials and unlock keys retain their previous lifetime and storage boundaries.
- No password-vault storage path, KDBX format, sync merge, Keychain policy, or recovery behavior changed.

### Verification

- Root-cause diagnostics completed: live process sample and configured KDBX filesystem flags.
- RED: `PasswordVaultMenuTests.pendingCloudUnlockShowsBusyStateImmediately` failed because the visible button remained `Unlock Vault`.
- RED: coordinator cache tests initially failed to compile because `dataReader`, `prepareForUnlock`, and `readForUnlock` did not exist.
- RED: the cloud-replacement-during-prefetch test failed with stale bytes and one read, proving the read/fingerprint race before the review fix.
- GREEN: `PasswordVaultMenuTests`, `PasswordVaultStoreTests`, and `PasswordVaultSecuritySettingsTests` passed 63/63. These include short-read rejection, localized failure feedback, production-controller prefetch, and disabled-busy-control assertions.
- The first repository `clean test` completed 973 tests but reported 8 failures in timing/system suites. All affected suites then passed in isolation: security settings 6/6 and performance/authorization/Broker/system integration 115/115.
- A second repository `clean test` reached Xcode result-bundle finalization but failed to save the action log, then left `xcodebuild` waiting with no `xctest` process; it was stopped after the result writer hung. Therefore no passing full-suite result is claimed.
- `git diff --check` passed.
- `./script/install_local.sh --verify` built and installed successfully; `/Applications/Pastera.app` passed deep strict signing verification and the exact installed executable was running.
- Real Finder and File Provider validation reproduced the failure without Pastera: the main KDBX and `.bak` both failed to download/open, with the provider returning `OneDrive` error `-17` while the OneDrive desktop process was absent.
- After starting OneDrive, the main KDBX changed to `isDownloaded=1`, exposed the valid KDBX signature, and a full 1469-byte read completed in less than the timer's 0.01-second resolution. Pastera was restarted and its coordinated reads were granted in roughly 5 ms without a File Provider error.

### Remaining Risks

- OneDrive must remain running long enough to materialize online-only vault data; if it is stopped and the file is evicted again, Pastera will now return localized retryable feedback rather than `corrupted`.
- File size plus modification time cannot detect an external replacement that deliberately preserves both metadata values; synchronization remains the source of truth and direct sync reads still bypass the cache.
- A clean full-suite pass is still missing because of timing-sensitive failures under the first overloaded run and Xcode's result-bundle writer failure on the second run. Every originally failing suite passed when isolated.
- A true successful unlock still requires the user to enter the master password; no credential was requested, recorded, or handled during automated verification.

### Follow-ups

- Have the user enter the master password once in the restarted app; the encrypted file and coordinated-read path are now locally available.

### ZenTao Closeout

- Not synchronized; no ZenTao contract or task ID was present for this user-authorized local bug fix.
