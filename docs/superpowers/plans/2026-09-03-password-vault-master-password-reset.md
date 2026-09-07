# Password Vault Master Password Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users reset a forgotten password-vault master password through macOS authentication when an unlock key remains available, and provide an explicit forced-reset fallback that creates a new empty vault while retaining only one latest encrypted archive locally and in OneDrive.

**Architecture:** Extend the existing KDBX rekey path to consume store-owned session, quick-unlock, or automation-unlock material after a single macOS device-owner authentication. Add a recoverable local forced-reset transaction plus a durable OneDrive replacement state machine that archives the old encrypted active vault before replacing it and never routes the old generation through normal merge logic. Rebuild the preference UI as three aligned full-width groups with separate non-destructive and destructive sheets.

**Tech Stack:** Swift 6, AppKit, LocalAuthentication, Security/Keychain, KDBXKit, Foundation file coordination, Swift Testing, Xcode 26.5, macOS 13+

**Spec:** `docs/superpowers/specs/2026-09-03-password-vault-master-password-reset-design.md`

## Global Constraints

- `LAPolicy.deviceOwnerAuthentication` is the authorization boundary; Touch ID is optional and the Mac login password must remain a valid fallback.
- A normal reset never asks for the current master password and preserves data only when the readable session, quick-unlock key, or automation-unlock key can actually decrypt the active KDBX.
- Missing decryption material returns a dedicated forced-reset requirement; it never silently clears or replaces the active vault.
- Forced reset requires a separate explanation, acknowledgement, and fresh system authentication.
- Local storage and OneDrive each retain at most one latest encrypted forced-reset archive; a newer verified archive replaces the previous slot.
- The archive is the exact encrypted active KDBX snapshot from before replacement. It is never decrypted, merged, rekeyed, exposed in normal vault browsing, or used by Agent APIs.
- When OneDrive replacement is pending, normal remote download and merge are disabled. Offline local reset is allowed, but password-vault sync remains visibly paused until archive and replacement finish.
- No plaintext password, KDBX content, derived key, raw unlock key, login credential, or authentication value may enter logs, fixtures committed to the repository, sync metadata, or UI accessibility values.
- Vault file operations, reset authorization completion, sync metadata mutation, and Agent grant revocation remain serialized through the existing vault executor.
- Do not change KDBX algorithms, clipboard behavior, folder/entry behavior, unrelated preference panes, or Windows code.
- Use temporary KDBX roots and fake cloud replicas for destructive automated and manual verification. Never force-reset the user's only real vault during development.
- Do not commit, push, publish, or create a release unless the user separately authorizes that Git or distribution action.

---

## Business Scope / Out of Scope

### In Scope

- Rename the normal action to “Reset Master Password” and remove the current-password field.
- Authorize reset with the Mac login password, Touch ID, or Apple Watch through the same system policy.
- Preserve all KDBX data when any existing local unlock material is valid.
- Add a separate forced-reset flow for the unrecoverable case.
- Keep one verified local archive and one verified OneDrive archive.
- Persist and resume an offline/interrupted OneDrive replacement without merging the old vault.
- Revoke Agent grants and delete the prior automation-unlock key before a new forced-reset vault becomes readable.
- Replace the uneven two-column password-vault preference layout with a stable single-column hierarchy.
- Update English, German, Italian, Japanese, and Simplified Chinese localizations and preference search metadata.

### Out of Scope

- Recovery codes, security questions, hosted escrow, account recovery, or decrypting a vault without an existing key/catalogued master password.
- Multiple archive versions, archive browsing, archive export UI, or automatic archive deletion beyond replacement of the single latest slot.
- Cross-device coordination beyond the existing OneDrive file replica.
- Redesigning password entries, folders, search, paste, clipboard history, or other settings pages.
- Git commits, pushes, tags, release packaging, or external distribution.

## Acceptance Mapping

| Acceptance | Automated evidence | Manual evidence |
| --- | --- | --- |
| Normal reset works without the old password | KDBX tests cover readable session, quick key, automation key, invalid key, and all managed artifacts | Reset a temporary vault after forgetting the typed password; verify folders and entries remain |
| Touch ID is not required | authorizer tests assert `.deviceOwnerAuthentication` context is returned and reused | On a Mac without Touch ID, complete reset using the Mac login password |
| Forced reset never pretends to recover data | sheet/controller tests assert dedicated error, warning text, acknowledgement, and second authentication | Observe the exact Chinese limitation message before reset |
| Only one local archive remains | transaction tests perform two resets and assert one archive path with the newest pre-reset bytes | Inspect the temporary recovery directory after repeated reset |
| Only one OneDrive archive remains | cloud/state-machine tests replace the archive slot twice with compare-and-swap verification | Inspect a temporary OneDrive root after repeated reset |
| Offline reset cannot merge the old remote generation | metadata and sync tests restart with pending reset and assert zero merge calls | Disconnect OneDrive, reset locally, reconnect, and confirm archive-before-replace |
| Agent access is invalidated | coordinator tests cover live and not-yet-started policy; controller tests prove revocation precedes file mutation | Previously authorized Agent client must request authorization again |
| Preference layout remains aligned | AppKit layout tests assert three full-width groups and stable insets at minimum/default/wide sizes | Review light/dark mode and wrapped Chinese text |
| No regressions | focused suites, serial full suite, `git diff --check`, localization parse, and build pass | Installed app launches and both reset sheets are keyboard accessible |

## File Map

- Modify: `pastera/Sources/Services/PasswordVaultStore.swift` — reset authorization value, capability/result/error contracts, Keychain context-aware load, and protocol methods.
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift` — resolve existing unlock material, share the rekey implementation, and create the new empty forced-reset vault.
- Modify: `pastera/Sources/Services/PasswordVaultLocalStorage.swift` — computed local recovery paths.
- Create: `pastera/Sources/Services/VaultForcedResetTransaction.swift` — verified local archive/new-vault staging, replacement, rollback, and stale-artifact cleanup boundary.
- Create: `pastera/Sources/Services/VaultAgentAuthorizationResetCoordinator.swift` — revoke durable grants through the live policy or a temporary policy on the same executor.
- Modify: `pastera/Sources/Services/VaultAgentRuntime.swift` — register/unregister the live authorization policy with the reset coordinator.
- Modify: `pastera/Sources/Services/PasswordVaultSyncModels.swift` — forced-reset commit origin, durable pending reset metadata, and visible pending phase.
- Modify: `pastera/Sources/Services/PasswordVaultSyncMetadataStore.swift` — backward-compatible additive metadata decoding and validation.
- Modify: `pastera/Sources/Services/PasswordVaultCloudReplica.swift` — verified single-slot remote archive read/write operations.
- Modify: `pastera/Sources/Services/PasswordVaultSyncService.swift` — prepare/cancel recovery record, startup reconciliation, archive-before-replace state machine, retry, and merge suppression.
- Modify: `pastera/Sources/Services/LocalOnlyPasswordVaultSyncController.swift` — conservative no-op implementations for the new reset lifecycle methods.
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift` — single-prompt authorization, reset orchestration, Agent revocation, sync preparation, result mapping, and sync observation.
- Modify: `pastera/Sources/Environments/Environment.swift` — construct and share the Agent reset coordinator.
- Modify: `pastera/Sources/Preferences/Panels/PasswordVaultMasterPasswordSheetController.swift` — convert the three-field change sheet into the two-field data-preserving reset sheet.
- Create: `pastera/Sources/Preferences/Panels/PasswordVaultForceResetSheetController.swift` — destructive explanation, acknowledgement, new-password inputs, and second authentication flow.
- Modify: `pastera/Sources/Preferences/Panels/CPYPasswordVaultPreferenceViewController.swift` — three-group single-column page and contextual feedback.
- Modify: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift` — System Unlock, reset, and forced-reset search entries.
- Modify: `pastera/Resources/Localizable.xcstrings` — five-language UI copy.
- Modify: `pastera.xcodeproj/project.pbxproj` — add new production and test files.
- Modify: `pasteraTests/PasswordVaultMasterPasswordTests.swift` — data-preserving reset coverage.
- Create: `pasteraTests/PasswordVaultForcedResetTests.swift` — local archive/new-vault transaction and rollback coverage.
- Modify: `pasteraTests/PasswordVaultSyncMetadataTests.swift` — pending-record persistence and legacy decoding.
- Modify: `pasteraTests/PasswordVaultCloudReplicaTests.swift` — remote archive slot behavior.
- Modify: `pasteraTests/PasswordVaultSyncServiceTests.swift` — online/offline/restart/race forced-reset flow.
- Modify: `pasteraTests/PasswordVaultSyncServiceTestSupport.swift` — fake archive and pending-reset support.
- Modify: `pasteraTests/PasswordVaultSecuritySettingsTests.swift` — capability and controller orchestration.
- Modify: `pasteraTests/VaultAgentAuthorizationPolicyTests.swift` — live/fallback grant revocation.
- Modify: `pasteraTests/KeyboardAccessibilityTests.swift` — both sheets, focus, validation, busy state, and exact warning copy.
- Modify: `pasteraTests/PreferencePaneAlignmentTests.swift` — full-width layout at all supported sizes.
- Modify: `pasteraTests/PreferenceSearchTests.swift` — renamed and new search anchors.

### Task 1: Replace old-password verification with authorized existing-key reset

**Files:**

- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pasteraTests/PasswordVaultMasterPasswordTests.swift`
- Modify: `pasteraTests/PasswordVaultStoreTests.swift`
- Modify: test authorizer/key-store fakes in `pasteraTests/PasswordVaultMenuTests.swift` and `pasteraTests/VaultAutomationUnlockKeyStoreTests.swift`

**Interfaces:**

- Produces:

```swift
struct PasswordVaultAuthorizationContext {
    let localAuthenticationContext: LAContext?
}

enum PasswordVaultMasterPasswordResetCapability: Equatable {
    case preservesData
    case requiresForcedReset
    case unavailable
}

enum PasswordVaultMasterPasswordResetWarning: String, Hashable {
    case systemUnlockDisabled
    case automationUnlockDisabled
    case credentialCleanupFailed
    case conflictArchivePending
    case rekeyArtifactCleanupPending
}

struct PasswordVaultMasterPasswordResetResult: Equatable {
    let warnings: [PasswordVaultMasterPasswordResetWarning]
}

func resetMasterPassword(
    newPassword: String,
    keepSystemUnlockEnabled: Bool,
    authorization: PasswordVaultAuthorizationContext
) throws -> PasswordVaultMasterPasswordResetResult
```

Tests define the explicit non-production convenience instead of adding a test branch
to production behavior:

```swift
extension PasswordVaultAuthorizationContext {
    static var testing: Self { .init(localAuthenticationContext: nil) }
}
```

- Extends `VaultUnlockKeyStoring` with:

```swift
func load(
    reason: String,
    authenticationContext: LAContext?
) throws -> Data
```

  The protocol extension delegates to the existing `load(reason:)` so test and legacy stores remain source-compatible; `VaultUnlockKeyStore` overrides it and sets `kSecUseAuthenticationContext` when a context is provided.

- Removes the production use of `changeMasterPassword(currentPassword:newPassword:keepQuickUnlockEnabled:)`. Existing test-only stubs move to the new reset contract rather than retaining a parallel old-password path.

- [x] **Step 1: Write the failing readable-session and Keychain-source tests**

Add tests with these core assertions:

```swift
@Test("readable session resets the master password without the old password")
func readableSessionResetPreservesData() throws {
    let fixture = try RekeyFixture()
    defer { fixture.remove() }
    try fixture.addLocalEntry(title: "Preserved Entry")

    _ = try fixture.store.resetMasterPassword(
        newPassword: fixture.newPassword,
        keepSystemUnlockEnabled: true,
        authorization: .testing
    )

    #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
    #expect(fixture.canOpen(fixture.vaultURL, password: fixture.newPassword))
    #expect(!fixture.canOpen(fixture.vaultURL, password: fixture.oldPassword))
}

@Test("locked vault uses the authorized quick-unlock key once")
func quickKeyResetPreservesData() throws {
    let fixture = try RekeyFixture()
    defer { fixture.remove() }
    try fixture.addLocalEntry(title: "Preserved Entry")
    try fixture.store.enableQuickUnlock()
    fixture.store.lock()

    _ = try fixture.store.resetMasterPassword(
        newPassword: fixture.newPassword,
        keepSystemUnlockEnabled: true,
        authorization: .testing
    )

    #expect(fixture.quickKey.authorizationContextLoadCount == 1)
    #expect(fixture.canOpen(fixture.vaultURL, password: fixture.newPassword))
}
```

Add a parallel locked-vault test for the automation-unlock key and a no-key test that expects `.resetRequiresForcedReset` and byte-for-byte unchanged managed artifacts. Update the existing wrong-current-password test into the no-key contract; retain the existing staging, revision-race, rollback, managed-artifact, and cleanup-warning cases.

- [x] **Step 2: Run the focused suite and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test -only-testing:pasteraTests/PasswordVaultMasterPasswordTests
```

Expected: FAIL because the reset authorization, capability, error, result, and `resetMasterPassword` APIs do not exist.

- [x] **Step 3: Add reset types and context-aware Keychain loading**

In `PasswordVaultStore.swift`, add `.resetRequiresForcedReset`, the types above, the new store property `masterPasswordResetCapability`, and the reset method. Provide conservative protocol defaults: capability `.unavailable` and reset throws `.unsupportedFormat`.

Implement the live Keychain override with the already-authorized context:

```swift
func load(reason: String, authenticationContext: LAContext?) throws -> Data {
    let context = authenticationContext ?? LAContext()
    context.localizedReason = reason
    var query = Self.baseLoadQuery
    query[kSecUseAuthenticationContext as String] = context
    return try copyUnlockKey(using: query)
}
```

Keep error mapping for cancellation, authentication failure, missing item, and invalid key length identical to the current `load(reason:)` behavior.

- [x] **Step 4: Refactor KDBX rekey to accept verified unlock material**

Extract the body of the current master-password change after old-password parsing into:

```swift
private func rekeyManagedArtifacts(
    from oldUnlock: UnlockData,
    to newPassword: String,
    keepSystemUnlockEnabled: Bool
) throws -> PasswordVaultMasterPasswordResetResult
```

Resolve `oldUnlock` in order: current `unlockData`, quick-unlock raw key using the passed authentication context, then automation-unlock raw key. Every non-session candidate must successfully parse the active vault before rekey begins. Map absent/invalid stored key material to `.resetRequiresForcedReset`; preserve `.userCancelled` and `.authenticationFailed` if the authorized Keychain read itself is cancelled or rejected.

After success, keep readable sessions readable and locked sessions locked, refresh quick/automation keys under the new unlock data, and preserve the existing multi-artifact rollback and warning behavior.

- [x] **Step 5: Update controller authorizer result without adding reset orchestration yet**

Change the authorization protocol to return the evaluated context:

```swift
protocol PasswordVaultAuthorizing {
    func authorize(
        reason: String,
        completion: @escaping (Result<PasswordVaultAuthorizationContext, PasswordVaultError>) -> Void
    )
}
```

`SystemPasswordVaultAuthorizer` creates one `LAContext`, evaluates `.deviceOwnerAuthentication`, and returns `PasswordVaultAuthorizationContext(localAuthenticationContext: context)` on success. Update the three existing fake authorizers to return `.testing`; existing clipboard and entry authorization closures ignore the returned context and keep their current behavior.

- [x] **Step 6: Run focused reset and store regression suites**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultMasterPasswordTests \
  -only-testing:pasteraTests/PasswordVaultStoreTests
```

Expected: PASS; all old/new password assertions, multi-artifact rollback cases, and existing store lifecycle tests pass. Run `git diff --check` and review only Task 1 files before continuing.

### Task 2: Add the recoverable single-slot local forced-reset transaction

**Files:**

- Modify: `pastera/Sources/Services/PasswordVaultLocalStorage.swift`
- Create: `pastera/Sources/Services/VaultForcedResetTransaction.swift`
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Create: `pasteraTests/PasswordVaultForcedResetTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces computed paths without changing every `PasswordVaultLocalPaths` initializer:

```swift
extension PasswordVaultLocalPaths {
    var forcedResetRecoveryDirectoryURL: URL {
        directoryURL.appendingPathComponent("ForcedResetRecovery", isDirectory: true)
    }

    var latestForcedResetArchiveURL: URL {
        forcedResetRecoveryDirectoryURL.appendingPathComponent("PasteraVault-latest.kdbx")
    }
}
```

- Produces:

```swift
enum PasswordVaultForcedResetWarning: String, Hashable {
    case systemUnlockDisabled
    case credentialCleanupFailed
    case resetArtifactCleanupPending
}

struct PasswordVaultForcedResetResult: Equatable {
    let encryptedSnapshot: PasswordVaultEncryptedSnapshot
    let localArchiveDigest: String
    let warnings: [PasswordVaultForcedResetWarning]
}

func forceReset(
    newPassword: String,
    rememberSystemUnlock: Bool
) throws -> PasswordVaultForcedResetResult
```

- `VaultForcedResetTransaction` accepts active/archive URLs, new KDBX bytes, a validation closure, and an injectable checkpoint. It returns only after the archive and new active vault have both been read back and verified.

- [x] **Step 1: Write failing transaction and store tests**

Create `PasswordVaultForcedResetTests.swift` with these behaviors:

```swift
@Test("forced reset archives the old encrypted vault and creates an empty new vault")
func forcedResetArchivesAndCreatesEmptyVault() throws {
    let fixture = try ForcedResetFixture()
    defer { fixture.remove() }
    try fixture.addEntry(title: "Old Entry")
    let oldBytes = try Data(contentsOf: fixture.activeURL)

    let result = try fixture.store.forceReset(
        newPassword: fixture.newPassword,
        rememberSystemUnlock: true
    )

    #expect(try Data(contentsOf: fixture.archiveURL) == oldBytes)
    #expect(result.localArchiveDigest == PasswordVaultDigest.hex(oldBytes))
    #expect(try fixture.store.listEntries().isEmpty)
    #expect(fixture.canOpen(fixture.archiveURL, password: fixture.oldPassword))
    #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
}

@Test("a second forced reset replaces the only archive")
func repeatedForcedResetKeepsOneLatestArchive() throws {
    let fixture = try ForcedResetFixture()
    defer { fixture.remove() }
    _ = try fixture.store.forceReset(newPassword: fixture.newPassword, rememberSystemUnlock: false)
    let secondPreResetBytes = try Data(contentsOf: fixture.activeURL)

    _ = try fixture.store.forceReset(newPassword: fixture.thirdPassword, rememberSystemUnlock: false)

    #expect(try fixture.archiveFiles() == [fixture.archiveURL])
    #expect(try Data(contentsOf: fixture.archiveURL) == secondPreResetBytes)
}
```

Add table-driven injected failures for archive stage write, archive readback, new-vault stage write, new-vault readback, revision check, archive replacement, and active replacement. Before the commit boundary, assert active bytes and the prior archive are restored and no temporary/rollback files remain. Add invalid/empty new-password and corrupted-active-file cases.

- [x] **Step 2: Run the new suite and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test -only-testing:pasteraTests/PasswordVaultForcedResetTests
```

Expected: FAIL because the forced-reset transaction, paths, result, and store API do not exist.

- [x] **Step 3: Implement the local transaction**

Implement explicit checkpoints and replacement bookkeeping:

```swift
enum VaultForcedResetCheckpoint: Equatable {
    case archiveStageWrite
    case archiveReadback
    case newVaultStageWrite
    case newVaultReadback
    case revisionCheck
    case archiveReplace
    case activeReplace
}
```

The transaction must validate the KDBX signature of old/new bytes, compare the active source digest immediately before replacement, keep the previous archive as rollback material, move replacements with `rename`, and restore in reverse order on pre-commit failure. After commit, overwrite any undeletable rollback copy with verified new-vault ciphertext before reporting `.resetArtifactCleanupPending`; therefore only the latest archive can retain the old encrypted generation. It never enumerates the recovery directory as a normal conflict/rekey artifact.

- [x] **Step 4: Implement KDBX forced reset**

Build the new vault with the same canonical empty content used by `createDatabase`:

```swift
var newContent = KDBXContent.makeEmpty(databaseName: "Pastera", generator: "Pastera")
newContent.database.meta.historyMaxItems = .value(10)
```

Before file replacement, delete the automation-unlock key; failure aborts the reset before vault bytes change. After the transaction commits, remove or sanitize stale `.bak`, immediate conflict copies, and resolved-conflict artifacts; save or delete the quick key according to `rememberSystemUnlock`; set the new vault session readable; publish a `.forcedReset` commit containing the new encrypted digest; and return warnings for a disabled System Unlock key, credential cleanup failure, or post-commit sanitized artifact awaiting deletion. Failures before commit restore the original state/content/unlock/revision, while prior Agent grants/automation unlock may remain conservatively revoked.

- [x] **Step 5: Run local reset regressions**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultForcedResetTests \
  -only-testing:pasteraTests/PasswordVaultMasterPasswordTests \
  -only-testing:pasteraTests/PasswordVaultStoreTests \
  -only-testing:pasteraTests/PasswordVaultTransactionAndMergeTests
```

Expected: PASS and `git diff --check` exits 0. Confirm the test directory contains exactly one latest archive after repeated reset.

### Task 3: Persist crash-safe forced-reset sync preparation

**Files:**

- Modify: `pastera/Sources/Services/PasswordVaultSyncModels.swift`
- Modify: `pastera/Sources/Services/PasswordVaultSyncMetadataStore.swift`
- Modify: `pastera/Sources/Services/PasswordVaultSyncService.swift`
- Modify: `pastera/Sources/Services/LocalOnlyPasswordVaultSyncController.swift`
- Modify: `pasteraTests/PasswordVaultSyncMetadataTests.swift`
- Modify: `pasteraTests/PasswordVaultSyncServiceTests.swift`
- Modify: `pasteraTests/PasswordVaultSyncServiceTestSupport.swift`

**Interfaces:**

- Produces:

```swift
struct PasswordVaultPendingForcedReset: Codable, Equatable {
    let previousLocalDigest: String
    var replacementLocalDigest: String?
    var didInspectRemote: Bool
    var observedRemoteDigest: String?
    var archivedRemoteDigest: String?
}

enum PasswordVaultSyncPhase: Equatable {
    case pendingForcedReset(PasswordVaultSyncFailure?)
    // existing cases remain unchanged
}
```

- Adds `pendingForcedReset: PasswordVaultPendingForcedReset?` to `PasswordVaultSyncMetadata` using backward-compatible decoding; legacy schema-1 JSON without this key decodes it as `nil`.

- Extends `PasswordVaultSyncControlling`:

```swift
func prepareForcedReset(previousLocalDigest: String) throws
func cancelPreparedForcedReset(previousLocalDigest: String)
func retryForcedReset(completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void)
```

- [x] **Step 1: Write failing metadata and crash-window tests**

Add assertions that legacy metadata decodes with `pendingForcedReset == nil`, the new record round-trips without plaintext fields, and `prepareForcedReset` persists before local mutation.

Add restart reconciliation cases:

```swift
@Test("startup cancels a prepared reset when the local digest never changed")
func unchangedPreparedResetIsCancelled() throws {
    let fixture = try makePreparedResetFixture(localData: oldLocalData)
    fixture.service.reconcilePendingForcedResetForTesting()
    #expect(fixture.metadata.value.pendingForcedReset == nil)
}

@Test("startup adopts the changed local digest after a crash")
func committedLocalResetIsRecoveredAfterRestart() throws {
    let fixture = try makePreparedResetFixture(localData: newLocalData)
    fixture.service.reconcilePendingForcedResetForTesting()
    #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest
        == PasswordVaultDigest.hex(newLocalData))
}
```

- [x] **Step 2: Run metadata and sync tests and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultSyncMetadataTests \
  -only-testing:pasteraTests/PasswordVaultSyncServiceTests
```

Expected: FAIL on missing metadata fields, phase, protocol methods, and reconciliation behavior.

- [x] **Step 3: Implement prepared-reset metadata and reentrant serialization**

Give `PasswordVaultSyncService` a `VaultAgentSerialExecutor` created from its existing queue. Use its `sync` method for `prepareForcedReset` and `cancelPreparedForcedReset`, and its `async` method for existing scheduled sync work. Because production passes the same dispatch queue to the store/controller and sync service, its dispatch-specific key makes the synchronous preparation reentrant rather than deadlocking.

`prepareForcedReset` stores the current mode plus `previousLocalDigest` before the destructive transaction. It is a no-op in local-only mode. Cancellation removes only a still-prepared record whose previous digest matches the caller's value and whose replacement digest is still `nil`.

- [x] **Step 4: Reconcile the crash window on service initialization**

After loading metadata, read `access.encryptedSnapshot()` only when a prepared record exists. Apply exactly this table:

| Stored replacement | Current digest equals previous | Result |
| --- | --- | --- |
| `nil` | yes | clear the unused preparation |
| `nil` | no | set replacement to current digest and publish pending |
| non-`nil` | either | retain pending and publish pending |

If the local snapshot cannot be read, retain the record and publish `.pendingForcedReset(.remoteUnavailable)` rather than erasing it or falling back to ordinary sync.

- [x] **Step 5: Record the store's forced-reset commit**

Add `.forcedReset` to `PasswordVaultCommitOrigin`. In `recordOnQueue`, increment `localRevision`, set the prepared record's `replacementLocalDigest` to the commit digest, keep ordinary `pendingChangeCount` out of the merge path, and publish `.pendingForcedReset(nil)`. Existing `.userMutation`, `.syncMerge`, and `.migration` cases retain their behavior.

- [x] **Step 6: Run metadata/restart regressions**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultSyncMetadataTests \
  -only-testing:pasteraTests/PasswordVaultSyncServiceTests \
  -only-testing:pasteraTests/PasswordVaultSyncMigrationCommitTests
```

Expected: PASS; legacy metadata remains readable, forced-reset state survives restart, and existing migrations retain their prior counters/baselines.

### Task 4: Archive and replace the OneDrive active vault with an idempotent state machine

**Files:**

- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/PasswordVaultCloudReplica.swift`
- Modify: `pastera/Sources/Services/PasswordVaultSyncService.swift`
- Modify: `pasteraTests/PasswordVaultCloudReplicaTests.swift`
- Modify: `pasteraTests/PasswordVaultSyncServiceTests.swift`
- Modify: `pasteraTests/PasswordVaultSyncServiceTestSupport.swift`

**Interfaces:**

- Produces the remote path:

```swift
static func latestForcedResetArchiveURL(for syncRootURL: URL) -> URL {
    vaultURL(for: syncRootURL)
        .deletingLastPathComponent()
        .appendingPathComponent("recovery", isDirectory: true)
        .appendingPathComponent("PasteraVault-latest.kdbx")
}
```

- Extends `PasswordVaultCloudReplica`:

```swift
func readLatestForcedResetArchive(rootURL: URL) throws -> PasswordVaultCloudSnapshot?

func writeLatestForcedResetArchiveAtomically(
    _ data: Data,
    rootURL: URL,
    expecting expectation: PasswordVaultRemoteExpectation
) throws -> String
```

- [x] **Step 1: Write failing cloud single-slot tests**

Cover first archive creation, replacement of an existing archive, KDBX signature rejection, readback digest verification, a stale digest expectation, and cleanup of temporary files. The replacement test must assert the recovery directory contains exactly `PasteraVault-latest.kdbx` after two writes.

- [x] **Step 2: Write failing online/offline/idempotency sync tests**

Add these observable cases:

```swift
@Test("pending forced reset archives remote before replacing active")
func forcedResetArchivesBeforeActiveReplacement() throws {
    let fixture = try makePendingForcedResetFixture()
    fixture.service.synchronize(reason: .localChange)
    fixture.drain()

    #expect(fixture.cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite])
    #expect(fixture.cloud.archiveSnapshot?.data == fixture.oldRemoteData)
    #expect(fixture.cloud.snapshot?.data == fixture.newLocalData)
    #expect(fixture.metadata.value.pendingForcedReset == nil)
    #expect(fixture.access.mergeCount == 0)
}

@Test("offline forced reset stays pending and never merges")
func offlineForcedResetPausesSync() throws {
    let fixture = try makePendingForcedResetFixture()
    fixture.processStatus.status = .notRunning
    fixture.service.synchronize(reason: .localChange)
    fixture.drain()

    #expect(fixture.metadata.value.pendingForcedReset != nil)
    #expect(fixture.service.snapshot.phase == .pendingForcedReset(.oneDriveNotRunning))
    #expect(fixture.access.mergeCount == 0)
}
```

Also cover: remote absent (upload new active without an archive), failure after verified archive (retry only replaces active), crash after active replacement (readback finalizes metadata without another archive), remote CAS race (preserve changed remote and remain pending), explicit retry after a race (archive the newest remote, then replace), local edits while pending (upload latest local snapshot), and repeated reset (one remote archive).

- [x] **Step 3: Run cloud and sync suites and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultCloudReplicaTests \
  -only-testing:pasteraTests/PasswordVaultSyncServiceTests
```

Expected: FAIL because the archive operations and pending-reset branch do not exist.

- [x] **Step 4: Implement the remote archive operations**

Refactor the existing coordinated read/write helpers to accept an explicit target URL while keeping public active-vault behavior unchanged. Archive writes use the same KDBX signature validation, stage file, digest readback, and compare-and-swap expectation as active writes. Never call `removeItem` on the existing latest archive before the replacement has been verified.

- [x] **Step 5: Implement the pending-reset state machine before normal decision logic**

At the beginning of `synchronizeOnQueue`, branch to `resumeForcedReset` whenever metadata contains a pending record. The branch performs:

1. resolve and validate the OneDrive root;
2. read the latest current local snapshot and persist its digest as the intended active replacement;
3. inspect remote active once and persist whether it was absent or its observed digest;
4. if present, write/read back that exact remote active data into the one latest archive slot and persist `archivedRemoteDigest`;
5. compare-and-swap local data into active remote using the observed digest or `.absent`;
6. read back the active digest, update normal sync baselines, clear pending state, and publish `.synced`.

If the active remote already equals the intended replacement digest after restart, verify the archive step was previously recorded and finalize metadata. Any other remote revision mismatch remains `.pendingForcedReset(.remoteVerificationFailed)` and requires `retryForcedReset`, which clears only the remote observation/archive progress before rerunning. It never calls `mergeRemoteSnapshot`.

- [x] **Step 6: Run all sync regressions**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultCloudReplicaTests \
  -only-testing:pasteraTests/PasswordVaultSyncServiceTests \
  -only-testing:pasteraTests/PasswordVaultCloudReplicaMissingFileTests \
  -only-testing:pasteraTests/PasswordVaultSyncMetadataTests \
  -only-testing:pasteraTests/PasswordVaultSyncMigrationCommitTests
```

Expected: PASS. Confirm every pending-reset test has `mergeCount == 0`, every archive replacement leaves one remote archive, and existing normal sync decisions still pass.

### Task 5: Revoke Agent grants and orchestrate both reset paths in the UI controller

**Files:**

- Create: `pastera/Sources/Services/VaultAgentAuthorizationResetCoordinator.swift`
- Modify: `pastera/Sources/Services/VaultAgentRuntime.swift`
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pastera/Sources/Environments/Environment.swift`
- Modify: `pasteraTests/VaultAgentAuthorizationPolicyTests.swift`
- Modify: `pasteraTests/PasswordVaultSecuritySettingsTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces:

```swift
protocol VaultAgentAuthorizationResetting: AnyObject {
    func revokeAll() throws
}

final class VaultAgentAuthorizationResetCoordinator: VaultAgentAuthorizationResetting {
    func install(_ policy: VaultAgentAuthorizationPolicy)
    func uninstall(_ policy: VaultAgentAuthorizationPolicy)
    func revokeAll() throws
}
```

- Produces controller APIs:

```swift
func resetMasterPassword(
    newPassword: String,
    completion: @escaping (Result<PasswordVaultMasterPasswordResetResult, PasswordVaultError>) -> Void
)

func forceResetPasswordVault(
    newPassword: String,
    completion: @escaping (Result<PasswordVaultForcedResetOutcome, PasswordVaultError>) -> Void
)

struct PasswordVaultForcedResetOutcome: Equatable {
    let localArchiveDigest: String
    let oneDriveReplacementPending: Bool
    let warnings: [PasswordVaultForcedResetWarning]
}
```

`PasswordVaultForcedResetOutcome` contains no path, plaintext, or unlock material.

- [x] **Step 1: Write failing live/fallback Agent revocation tests**

Test the coordinator with a real in-memory grant store:

- with an installed live policy, `revokeAll()` updates both its in-memory decisions and durable store;
- after uninstalling the live policy, `revokeAll()` creates a temporary policy on the same executor and revokes durable grants;
- a later policy created from the same store sees every grant as revoked;
- store failure is propagated and no forced-reset store operation is invoked.

- [x] **Step 2: Write failing controller-ordering tests**

Use an event recorder and assert exact order:

```swift
#expect(events == [
    .systemAuthorized,
    .agentGrantsRevoked,
    .syncResetPrepared,
    .localVaultReset,
    .syncRequested
])
```

Add normal reset tests asserting one authorization call, one store reset call with the same authorization context, preserved-data success, forced-reset-required failure, and no forced fallback. Add forced reset tests for authentication cancellation, Agent revocation failure, sync preparation failure, local transaction failure with preparation cancellation, OneDrive-pending success, and local-only success.

- [x] **Step 3: Run controller and Agent tests and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests \
  -only-testing:pasteraTests/VaultAgentAuthorizationPolicyTests
```

Expected: FAIL on the missing coordinator and controller reset APIs.

- [x] **Step 4: Implement the shared Agent reset coordinator**

The coordinator stores only a weak live-policy reference under a lock. `revokeAll()` uses the live policy when present; otherwise it constructs a temporary `VaultAgentAuthorizationPolicy` from the injected `VaultAgentGrantStoring` factory and calls `revokeAll(at:)`. Both paths use the existing `VaultAgentSerialExecutor`, whose reentrant `sync` prevents self-deadlock on the vault queue.

Update `VaultAgentApplicationRuntime.production`/`makeProduction` to receive the coordinator, install the newly created policy before accepting socket work, and uninstall it when that runtime stops. Do not create a second persistent grant store when a live policy is registered.

- [x] **Step 5: Wire production ownership in `Environment`**

After creating `PasswordVaultUIController`, create one reset coordinator with `resolvedPasswordVaultUIController.vaultAgentExecutor`, bind it to the controller, and pass it into the default Agent runtime factory. Custom injected controllers/runtimes retain explicit test injection and never fall back to silently successful grant revocation.

- [x] **Step 6: Implement controller orchestration**

Normal reset sequence:

```swift
authorizer.authorize(reason: resetReason) { result in
    // on success: perform on store queue with the returned authorization
    store.resetMasterPassword(
        newPassword: newPassword,
        keepSystemUnlockEnabled: quickUnlockIntent,
        authorization: authorization
    )
}
```

Forced reset sequence on the same serialized executor:

1. perform a fresh system authorization;
2. revoke all Agent grants;
3. get the current encrypted local digest;
4. persist `prepareForcedReset(previousLocalDigest:)` when OneDrive mode is enabled;
5. call `store.forceReset`;
6. on store failure, cancel only the matching prepared record;
7. on success, allow the `.forcedReset` commit to fill the replacement digest, request synchronization, and report local/remote-pending status.

Observe sync snapshots in `PasswordVaultUIController` and include forced-reset pending state in `PasswordVaultSecuritySettingsState`, so the preference page updates after sheet closure and after remote retry.

- [x] **Step 7: Run orchestration and runtime regressions**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests \
  -only-testing:pasteraTests/VaultAgentAuthorizationPolicyTests \
  -only-testing:pasteraTests/VaultAgentBrokerTests \
  -only-testing:pasteraTests/VaultAgentIntegrationInstallerTests \
  -only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests
```

Expected: PASS; old grants cannot access the new vault, and unrelated Agent lifecycle behavior remains unchanged.

### Task 6: Replace the old change sheet and add the destructive forced-reset sheet

**Files:**

- Modify: `pastera/Sources/Preferences/Panels/PasswordVaultMasterPasswordSheetController.swift`
- Create: `pastera/Sources/Preferences/Panels/PasswordVaultForceResetSheetController.swift`
- Modify: `pasteraTests/KeyboardAccessibilityTests.swift`
- Modify: `pasteraTests/PasswordVaultSecuritySettingsTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**

- The existing sheet controller keeps its file but changes to two inputs and calls `PasswordVaultUIController.resetMasterPassword`.
- The forced sheet calls `PasswordVaultUIController.forceResetPasswordVault` only after matching passwords and acknowledgement.
- Both sheets retain secure/visible mirrored inputs, secret clearing, busy-state duplicate-submit protection, Escape behavior, and a complete key-view loop.

- [x] **Step 1: Rewrite old sheet tests as failing reset tests**

Replace three-field expectations with:

```swift
#expect(controller.secureFieldCountForTesting == 2)
#expect(controller.fieldLabelsForTesting == [
    pasteraPreferenceString("New Master Password"),
    pasteraPreferenceString("Confirm New Master Password")
])
#expect(controller.keyViewOrderForTesting == [
    "masterPassword.new",
    "masterPassword.confirmation",
    "masterPassword.cancel",
    "masterPassword.submit"
])
```

Assert the submitted operation receives only the new password, the current-password accessibility identifier is absent, cancellation does not mutate values outside the sheet, and `.resetRequiresForcedReset` shows the explanation plus `Review Force Reset...` without invoking forced reset.

- [x] **Step 2: Add failing forced-sheet tests**

Assert:

- exact English and Simplified Chinese limitation text;
- the one-archive replacement warning is visible before input;
- the destructive button is disabled for empty/mismatched passwords or unchecked acknowledgement;
- a valid submit invokes exactly one force-reset operation;
- busy state blocks duplicate Return/Escape;
- cancellation/authentication failure leaves the sheet open and secrets clear only when the sheet actually closes;
- success closes and reports local-only versus OneDrive-pending feedback.

- [x] **Step 3: Run keyboard/accessibility tests and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/KeyboardAccessibilityTests \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests
```

Expected: FAIL because the current sheet still has a current-password field and no force-reset sheet exists.

- [x] **Step 4: Implement the two-field reset sheet**

Keep the existing reusable password input view. Remove `currentInput`, update title/subtitle/button text to “Reset Master Password” and “Authenticate & Reset”, pass only `newInput.value`, and map `.resetRequiresForcedReset` to an inline recovery panel with a callback that closes the normal sheet and opens the force-reset review flow. Authentication cancellation remains a non-destructive inline error.

- [x] **Step 5: Implement the forced-reset sheet**

Use a full-width warning status view, two password inputs, one `NSButton` checkbox, Cancel, and a destructive button. Use these accessibility identifiers:

```text
forceReset.warning
forceReset.new
forceReset.confirmation
forceReset.acknowledgement
forceReset.cancel
forceReset.submit
forceReset.generalError
```

The key loop is new password → confirmation → acknowledgement → Cancel → Force Reset. The button label is “Force Reset Password Vault”; it must not be the window default until acknowledgement and validation succeed.

- [x] **Step 6: Run sheet regressions**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/KeyboardAccessibilityTests \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests
```

Expected: PASS with no current-password field, exact warning copy, one submission per action, correct focus restoration, and both sheets fitting the minimum supported preference width.

### Task 7: Rebuild the password-vault preference page as one aligned column

**Files:**

- Modify: `pastera/Sources/Preferences/Panels/CPYPasswordVaultPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pasteraTests/PreferencePaneAlignmentTests.swift`
- Modify: `pasteraTests/PreferenceSearchTests.swift`
- Modify: `pasteraTests/KeyboardAccessibilityTests.swift`

**Interfaces:**

- Reuses `PasteraPreferenceGroupView`, `PasteraPreferenceSettingRowView`, and a vertical `NSStackView` added as one adaptive-grid item. No global change to other preference pages is needed.
- Search anchors become `vault.autoLock`, `vault.systemUnlock`, `vault.masterPassword`, and `vault.forceReset`.

- [x] **Step 1: Write failing single-column layout tests**

Replace the weighted-column test with:

```swift
@Test("password vault groups remain full width at every supported size")
func passwordVaultGroupsUseOneAlignedColumn() throws {
    let page = CPYPasswordVaultPreferenceViewController()
    page.loadView()

    for width: CGFloat in [480, 600, 900] {
        page.view.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
        page.view.layoutSubtreeIfNeeded()
        #expect(page.passwordVaultGroupFramesForTesting.count == 3)
        #expect(page.passwordVaultGroupFramesForTesting.allSatisfy {
            abs($0.minX - page.passwordVaultGroupFramesForTesting[0].minX) < 0.5
                && abs($0.width - page.passwordVaultGroupFramesForTesting[0].width) < 0.5
        })
    }
}
```

Also assert vertical order, consistent action insets, no overlap under wrapped Chinese text, and all four search anchors inside document bounds.

- [x] **Step 2: Write failing search and localization tests**

Update search expectations from “Quick Unlock”/“Change Master Password” to “System Unlock”/“Reset Master Password”, and add “Force Reset Password Vault”. Search keywords include `Mac password`, `login password`, `forgot password`, `force reset`, `Mac 登录密码`, `忘记密码`, and `强制重置`.

Add a localization test that parses `Localizable.xcstrings` and requires non-empty `en`, `de`, `it`, `ja`, and `zh-Hans` values for every new reset, forced-reset, archive, pending-OneDrive, and System Unlock key.

- [x] **Step 3: Run layout/search tests and verify RED**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PreferencePaneAlignmentTests \
  -only-testing:pasteraTests/PreferenceSearchTests \
  -only-testing:pasteraTests/KeyboardAccessibilityTests
```

Expected: FAIL because the page still creates two weighted grid items and the new actions/copy do not exist.

- [x] **Step 4: Build the three-group layout**

Create one vertical stack containing:

1. **Vault Status** with status badge/detail, Automatic Lock, and System Unlock rows;
2. **Master Password** with the permanent encryption warning, action-local feedback, and Reset Master Password button;
3. **Can't Unlock?** with restrained warning text, pending-OneDrive status/retry when applicable, action-local feedback, and Force Reset Password Vault button.

Add that stack as a single adaptive item, constrain it to the content width, use 12-point group spacing, and keep 14-point internal action insets. Do not modify `PasteraPreferenceAdaptiveGridView` or alter other panes.

- [x] **Step 5: Wire sheet transitions and feedback**

The normal button opens the reset sheet. Its forced-reset-required action closes cleanly before opening the forced sheet. The danger-group button opens the forced sheet directly. Success feedback stays in the owning group. While remote replacement is pending, disable another reset, show the paused status and Retry action, and keep normal locking controls usable only when the underlying vault state permits.

- [x] **Step 6: Add complete localized copy**

Use the exact Simplified Chinese limitation copy from the spec. Translate every new key into the repository's five locales. Preserve the distinction among:

- authorization succeeded but no decryption key exists;
- local forced reset succeeded while OneDrive replacement is pending;
- remote revision changed and requires explicit retry;
- local archive creation failed and no reset occurred;
- Agent authorizations were revoked and must be granted again.

- [x] **Step 7: Run UI-focused regressions**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PreferencePaneAlignmentTests \
  -only-testing:pasteraTests/PreferenceSearchTests \
  -only-testing:pasteraTests/KeyboardAccessibilityTests \
  -only-testing:pasteraTests/PreferenceWindowShellTests \
  -only-testing:pasteraTests/PasswordVaultMenuTests
```

Expected: PASS; the password-vault page has one stable column at all widths and other preference pages keep their existing adaptive layouts.

### Task 8: Complete security, regression, runtime, and local-install verification

**Files:**

- Modify only if evidence finds an in-scope defect: files listed in Tasks 1–7 and their corresponding tests.
- Update during implementation: this plan's task checkboxes and `Delivery Record` with actual evidence; do not create another report.

**Interfaces:**

- Consumes all Task 1–7 production/test contracts.
- Produces a verified local app and an evidence-backed Delivery Record.

- [x] **Step 1: Run the complete focused reset matrix**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO \
  test \
  -only-testing:pasteraTests/PasswordVaultMasterPasswordTests \
  -only-testing:pasteraTests/PasswordVaultForcedResetTests \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests \
  -only-testing:pasteraTests/PasswordVaultCloudReplicaTests \
  -only-testing:pasteraTests/PasswordVaultSyncServiceTests \
  -only-testing:pasteraTests/PasswordVaultSyncMetadataTests \
  -only-testing:pasteraTests/VaultAgentAuthorizationPolicyTests \
  -only-testing:pasteraTests/VaultAgentBrokerTests \
  -only-testing:pasteraTests/KeyboardAccessibilityTests \
  -only-testing:pasteraTests/PreferencePaneAlignmentTests \
  -only-testing:pasteraTests/PreferenceSearchTests
```

Expected: `** TEST SUCCEEDED **` with zero failures.

- [x] **Step 2: Validate localization and repository hygiene**

Run:

```bash
jq empty pastera/Resources/Localizable.xcstrings
git diff --check
git status --short
rg -n "masterPassword|rawKey|unlockData|password" pastera/Sources/Services pastera/Sources/Managers \
  | rg "NSLog|print\(|Logger|os_log" || true
```

Expected: localization parses, whitespace check passes, only scoped files are changed, and no new secret-bearing log call is present. Review all matches manually; existing safe generic log text is not a failure by itself.

- [x] **Step 3: Run the serial full regression suite in isolated build state**

Create an explicit temporary directory and run:

```bash
PASTERA_DERIVED_DATA="$(mktemp -d /tmp/pastera-reset-derived.XXXXXX)"
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -derivedDataPath "$PASTERA_DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  clean test
```

Expected: `** TEST SUCCEEDED **`. Preserve the result bundle until any failure is classified. Do not treat an independent rerun as proof that an unexplained repeatable full-suite failure is harmless.

- [x] **Step 4: Build and install the app locally**

Run:

```bash
./script/install_local.sh
```

Expected: `** BUILD SUCCEEDED **`; `/Applications/Pastera.app` is ad-hoc signed, replaced, and launched from its installed path.

- [ ] **Step 5: Perform manual temporary-vault acceptance**

Using only a temporary vault and temporary OneDrive root, verify:

1. normal reset with the Mac login password preserves folders/entries and invalidates the old master password;
2. locked reset with a valid system-unlock or automation key preserves data without a typed old password;
3. no-key reset shows the exact recovery limitation and never starts forced reset automatically;
4. forced reset requires acknowledgement plus a fresh Mac authentication and creates an empty vault;
5. a second forced reset leaves one latest local archive;
6. online OneDrive reset leaves one remote archive and the new active vault;
7. offline reset shows paused sync across relaunch, then completes archive-before-replace after reconnect;
8. a previously authorized Agent client is rejected until reauthorized;
9. the preference page remains aligned at minimum/default/wide widths, light/dark modes, and with wrapped Chinese text;
10. Return, Escape, Tab order, visibility toggles, and VoiceOver labels work in both sheets.

- [x] **Step 6: Review the final diff and update this plan's Delivery Record**

Run:

```bash
git diff --stat
git diff -- pastera/Sources/Services pastera/Sources/Managers \
  pastera/Sources/Preferences pastera/Resources/Localizable.xcstrings \
  pasteraTests pastera.xcodeproj/project.pbxproj
```

Record actual implementation, deviations, exact passing commands/counts, installation result, and remaining risks below. Do not commit or push unless separately authorized.

## Risks, Rollback and Observation

- **Risk: a valid Mac login is mistaken for a decryption key.** Keep authorization and KDBX verification as separate typed steps; only verified session/quick/automation material may enter rekey.
- **Risk: two authentication prompts appear.** Return the evaluated `LAContext` and reuse it for the protected Keychain read.
- **Risk: forced reset loses both the old active vault and prior archive.** Stage/read back the new archive and new active KDBX, retain rollback files until both replacements commit, and inject every failure checkpoint.
- **Risk: OneDrive exposes intermediate two-file state.** Use durable idempotent phases: verified archive first, active CAS second, metadata finalization last. Resume rather than merge after interruption.
- **Risk: local reset commits before pending sync metadata is updated.** Persist preparation before file mutation and reconcile active digest at startup.
- **Risk: another device changes remote active data.** Compare against the observed digest; pause on mismatch and require explicit retry, which archives the newest observed remote before replacement.
- **Risk: old Agent grants see a new unlocked vault.** Revoke live and durable grants before local reset; abort file mutation if revocation cannot be confirmed.
- **Risk: the page grows too tall.** Use a single scrolling column with concise group-local status. Verify minimum window size and wrapped localization rather than compressing controls.
- **Rollback before local forced-reset commit:** transaction restores the original active vault and previous latest archive.
- **Rollback after local commit:** do not reactivate the archived generation automatically. Keep the new local vault and pending OneDrive reset; the encrypted latest archive remains available if the original password is remembered.
- **Code rollback:** revert Tasks 7 through 1 in reverse order only while preserving user-created KDBX files and recovery archives. Never delete runtime vault data as part of source rollback.
- **Observation:** after local install, watch Keychain denial, File Provider disconnect/reconnect, remote CAS races, app restart during pending reset, and Agent reauthorization behavior.

## Delivery Metadata

- Plan: `docs/superpowers/plans/2026-09-03-password-vault-master-password-reset.md`
- Status: Implemented and installed locally; real-credential and live-OneDrive manual acceptance remains
- Evidence Profile: standard
- Source: user-confirmed design on 2026-09-03
- Spec: `docs/superpowers/specs/2026-09-03-password-vault-master-password-reset-design.md`
- Historical predecessor: `docs/superpowers/plans/2026-07-21-password-vault-preferences-master-password.md` documents the completed old-password-required change flow and is not rewritten
- ZenTao Story ID: absent
- ZenTao Task ID: absent
- ZenTao Sync: not requested
- Git authorization: no commit or push authorization

## Delivery Record

- Actual Implementation: Implemented the old-password-free reset through one
  `LAPolicy.deviceOwnerAuthentication` authorization and verified existing session,
  system-unlock, or automation-unlock material. Added the separately authenticated
  forced-reset path, single-slot encrypted local and OneDrive archives, durable
  offline/restart replacement metadata, Agent grant and automation-key revocation,
  fail-closed versioned local transaction recovery, durable deletion of the stale
  quick-unlock key before recovery-marker clearance, and an explicit
  retry-local-recovery UI. Rebuilt the Password Vault preference page into three aligned
  groups, added the two reset sheets and main-menu recovery state, and completed English,
  German, Italian, Japanese, and Simplified Chinese copy.
- Plan Deviations: The implementation added a versioned, secret-free local recovery
  record and visible `Retry Local Recovery` state after fault-injection review proved
  that a presence-only marker could not safely distinguish prepared rollback from a
  committed new generation. This is an in-scope safety hardening; it does not expose
  archives or add another recovery mechanism. Cumulative review also moved stale
  quick-key deletion ahead of committed-marker removal; deletion failure now preserves
  the durable recovery gate and succeeds through idempotent retry. Final isolated builds reused the main
  checkout's complete SwiftPM cache because the worktree cache contained an interrupted
  GRDB mirror; dependency versions remained those in the resolved graph.
- Impact: Normal reset no longer requests the current master password and preserves
  data only after existing unlock material opens the active KDBX. Forced reset always
  explains that the old vault cannot be recovered under the current conditions,
  creates a new empty vault only after acknowledgement and fresh system authorization,
  keeps at most one latest encrypted archive per storage location, pauses OneDrive
  replacement while offline or locally unrecovered, and invalidates prior Agent access.
- Verification: The final implementation tree is
  `429dae76d6f441bdc087a385d7f7c1abd1618265`. The final structured focused matrix
  passed 315/315 tests in 11 suites with 0 failures/skips (337 parameterized
  executions). The final cumulative recovery matrix passed 148/148. An initial full
  run exhausted disk while Xcode grew a 495 MB result bundle; its five history-database
  issues were explicitly `No space left on device`. After generated-cache cleanup, a
  fresh serial `clean test` exited 0 and reported 1388/1388 tests in 102 suites with
  `** TEST SUCCEEDED **`; Xcode again failed only while finalizing that
  full result bundle with the previously classified `writerNotOpen` environment issue,
  so its structured summary is unavailable. `git diff --check`, project plist parsing,
  string-catalog JSON parsing, five-locale string compilation, translation completeness,
  and secret-log review passed. Native AppKit captures verified 480-point light,
  900-point dark, and main-menu recovery layouts. The app target built successfully;
  `/Applications/Pastera.app` was ad-hoc signed, verified, installed, and launched as
  version 3.0.2 (302), bundle `com.pastera-app.Pastera.debug`, from its installed path.
- Remaining Risks: Task 8 Step 5 remains open. Automated temporary KDBX roots and fake
  cloud replicas cover reset, rollback, restart, archive-before-replace, offline, race,
  recovery, and Agent boundaries, but this run intentionally did not submit a real Mac
  login/Touch ID/Apple Watch prompt, mutate the user's vault or Keychain, connect a real
  OneDrive root, or exercise a real Agent client. The menu-bar app did not expose a
  normal accessibility window to the UI automation connection, so live Return/Escape/
  VoiceOver and German/Italian/Japanese rendering still need human confirmation. The
  full-suite structured-result limitation remains a local Xcode evidence gap despite
  the successful exit code and complete console count.
- Follow-ups: Perform Step 5 with a disposable vault and disposable OneDrive root,
  including Mac-login authentication on the target Mac mini, offline reconnect, Agent
  reauthorization, keyboard/VoiceOver checks, and non-Chinese localization spot checks.
  No commit, push, tag, release, or external distribution was performed.
- ZenTao Closeout: Not requested.
