# Prompt Optimization Multi-Model Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independently persisted and selectable OpenAI/ChatGPT, Ollama, DeepSeek-V4-Flash, and custom OpenAI-compatible gateway profiles without weakening Pastera's Keychain, endpoint-consent, or rewrite-safety boundaries.

**Architecture:** Keep one OpenAI Chat Completions transport and introduce UUID-backed remote profiles around the existing `PromptOptimizationRemoteConfiguration`. Persist the complete non-secret settings snapshot as versioned Codable data, store each profile's key in a separate Keychain account, and route optimization and connection tests through only the selected profile. Keep profile editing state outside the AppKit view so switching, validation, deletion, and persisted-key eligibility are independently testable.

**Tech Stack:** Swift 6, AppKit, Foundation `URLSession`, Security Keychain APIs, Swift Testing, Xcode 26.5, macOS 13+.

## Global Constraints

- Work from `/Users/feeyo/workspace/github.com/pastera-app/Pastera` on the existing `develop` checkout; do not discard or overwrite unrelated work.
- Preserve the three pre-existing prompt-rewrite changes in `AppleFoundationModelPromptOptimizer.swift`, `OpenAICompatiblePromptOptimizer.swift`, and `OpenAICompatiblePromptOptimizerTests.swift`; Task 0 verifies and commits them separately before profile work.
- Reuse OpenAI Chat Completions. Do not add Responses API, Anthropic Messages API, provider-specific clients, automatic failover, load balancing, or a new dependency.
- Keep `PromptOptimizationProviderSelection.automaticFree` and the Apple/local fallback behavior unchanged.
- New profiles must cover OpenAI/ChatGPT (`https://api.openai.com/v1`, `gpt-5.6-luna`), DeepSeek (`https://api.deepseek.com`, `deepseek-v4-flash`), Ollama (`http://127.0.0.1:11434/v1`, `qwen2.5:7b-instruct`), and arbitrary custom gateways.
- The custom gateway acceptance fixture uses `https://aigateway.variflight.com/api` and `aliyun/deepseek-v4-flash-0731`; never place an API key in source, docs, commands, test data, logs, screenshots, or UserDefaults.
- Treat the previously exposed gateway credential as revoked. Authenticated installed-app verification may use only a rotated key entered through Pastera's secure field and stored in Keychain.
- Keep endpoint policy fail-closed: no URL credentials/query/fragment, non-loopback HTTP requires explicit opt-in, and every new origin requires confirmation.
- Connection testing sends only `Return OK`; optimization failures never try another profile and never overwrite the user's draft.
- DeepSeek-specific `thinking: {"type":"disabled"}` is sent only for the `.deepSeek` preset, never by inspecting a custom model name.
- Preserve the existing deterministic `temperature: 0`, response length checks, `PromptRewriteOutputSanitizer`, and `.invalidResponse` fallback semantics.
- Use `apply_patch` for source and documentation edits. Stage only files named by the current task and do not push unless the user separately requests it.
- After focused and full verification pass, run `./script/install_local.sh` and verify the installed app before declaring completion.

## File Responsibility Map

- Modify `pastera/Sources/Models/PromptOptimization.swift`: preset defaults, remote profile value type, active-profile settings model, and temporary migration compatibility accessors.
- Modify `pastera/Sources/Constants.swift`: versioned settings and pending legacy-credential migration UserDefaults keys.
- Modify `pastera/Sources/Utility/CPYUtilities.swift`: stop registering new profile state as separate scalar defaults; retain legacy defaults for one migration cycle.
- Modify `pastera/Sources/Services/PromptOptimizationSettingsStore.swift`: V2 snapshot encoding, legacy scalar migration, stable UUID repair, and migration marker lifecycle.
- Modify `pastera/Sources/Services/PromptOptimizationAPIKeyStore.swift`: UUID-scoped Keychain accounts and idempotent legacy account migration.
- Modify `pastera/Sources/Services/PromptOptimizationEndpointPolicy.swift`: preserve path behavior and only add coverage-driven changes if tests expose a defect.
- Modify `pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift`: DeepSeek request option while retaining the shared transport and sanitizer.
- Modify `pastera/Sources/Services/PromptOptimizationService.swift`: resolve and use the active profile, keyed credential, consent, and no-failover behavior.
- Create `pastera/Sources/Preferences/Panels/PromptOptimizationRemoteProfileDraft.swift`: non-AppKit draft, selection, unique naming, preset application, persisted-ID tracking, and last-profile reset.
- Modify `pastera/Sources/Preferences/Panels/PromptOptimizationPreferenceSection.swift`: profile controls and UUID-scoped credential actions.
- Modify `pastera.xcodeproj/project.pbxproj`: compile the new draft file in the Pastera target.
- Modify `pasteraTests/PromptOptimizationSettingsTests.swift`: profile defaults, V2 persistence/migration, Keychain isolation, and credential migration.
- Modify `pasteraTests/OpenAICompatiblePromptOptimizerTests.swift`: custom gateway path/model and DeepSeek request-body coverage while preserving existing sanitizer tests.
- Modify `pasteraTests/PromptOptimizationServiceTests.swift`: active-profile routing, keyed credential, consent ordering, and no-failover coverage.
- Modify `pasteraTests/PromptOptimizationPreferenceTests.swift`: draft behavior and AppKit profile-management behavior.

---

### Task 0: Preserve the Existing Rewrite-Safety Baseline

**Files:**
- Modify: `pastera/Sources/Services/AppleFoundationModelPromptOptimizer.swift`
- Modify: `pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift`
- Test: `pasteraTests/OpenAICompatiblePromptOptimizerTests.swift`

**Interfaces:**
- Consumes: existing `PromptRewriteInstruction`, `ChatCompletionRequest`, and `PromptRewriteOutputSanitizer` changes already present in the worktree.
- Produces: a clean, committed deterministic rewrite-safety baseline on which later request changes build.

- [ ] **Step 1: Review the pre-existing diff and confirm it contains only approved rewrite rules, deterministic request fields, sanitizer logic, and tests**

```bash
git diff -- pastera/Sources/Services/AppleFoundationModelPromptOptimizer.swift pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift pasteraTests/OpenAICompatiblePromptOptimizerTests.swift
git diff --check -- pastera/Sources/Services/AppleFoundationModelPromptOptimizer.swift pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift pasteraTests/OpenAICompatiblePromptOptimizerTests.swift
```

Expected: only the three named files appear; `git diff --check` exits 0; no credentials or provider-specific gateway values appear.

- [ ] **Step 2: Run the focused optimizer suite**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests
```

Expected: `** TEST SUCCEEDED **`; all existing deterministic request and sanitizer tests pass.

- [ ] **Step 3: Commit only the verified baseline**

```bash
git add pastera/Sources/Services/AppleFoundationModelPromptOptimizer.swift \
  pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift \
  pasteraTests/OpenAICompatiblePromptOptimizerTests.swift
git commit -m "fix(prompt): harden compatible model rewrites"
```

Expected: the commit contains exactly the three named files.

---

### Task 1: Add Preset Defaults and the Remote Profile Model

**Files:**
- Modify: `pastera/Sources/Models/PromptOptimization.swift:8-47`
- Test: `pasteraTests/PromptOptimizationSettingsTests.swift:6-38`

**Interfaces:**
- Consumes: existing `OpenAICompatiblePreset` and `PromptOptimizationRemoteConfiguration`.
- Produces: `OpenAICompatiblePreset.defaultBaseURL`, `defaultModel`, `defaultProfileName`, and `disablesThinking`; `PromptOptimizationRemoteProfile`; `PromptOptimizationSettings.remoteProfiles`, `activeRemoteProfileID`, `activeRemoteProfile`, `makeDefault(profileID:)`, and `repairActiveRemoteProfile()`.

- [ ] **Step 1: Write failing preset and default-profile tests**

```swift
@Test
func presetsExposeEditableProviderDefaults() {
    #expect(OpenAICompatiblePreset.openAI.defaultBaseURL == "https://api.openai.com/v1")
    #expect(OpenAICompatiblePreset.openAI.defaultModel == "gpt-5.6-luna")
    #expect(OpenAICompatiblePreset.deepSeek.defaultBaseURL == "https://api.deepseek.com")
    #expect(OpenAICompatiblePreset.deepSeek.defaultModel == "deepseek-v4-flash")
    #expect(OpenAICompatiblePreset.deepSeek.disablesThinking)
    #expect(OpenAICompatiblePreset.ollama.defaultModel == "qwen2.5:7b-instruct")
    #expect(OpenAICompatiblePreset.custom.defaultBaseURL.isEmpty)
    #expect(!OpenAICompatiblePreset.custom.disablesThinking)
}

@Test
func defaultSettingsUseFreeProviderWithOneConfiguredOpenAIProfile() throws {
    let id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let settings = PromptOptimizationSettings.makeDefault(profileID: id)

    #expect(settings.provider == .automaticFree)
    #expect(settings.activeRemoteProfileID == id)
    #expect(settings.remoteProfiles.count == 1)
    #expect(settings.activeRemoteProfile?.displayName == "OpenAI")
    #expect(settings.activeRemoteProfile?.model == "gpt-5.6-luna")
    #expect(settings.activeRemoteProfile?.configuration.preset == .openAI)
}
```

- [ ] **Step 2: Run the settings suite and verify the new API is missing**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationSettingsTests
```

Expected: compile failure for missing `.deepSeek`, `defaultBaseURL`, or `PromptOptimizationSettings.makeDefault`.

- [ ] **Step 3: Implement the profile and defaults while keeping a temporary single-configuration compatibility bridge**

```swift
enum OpenAICompatiblePreset: String, Codable, CaseIterable, Sendable {
    case openAI, deepSeek, gemini, ollama, lmStudio, custom

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .ollama: "http://127.0.0.1:11434/v1"
        case .lmStudio: "http://127.0.0.1:1234/v1"
        case .custom: ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5.6-luna"
        case .deepSeek: "deepseek-v4-flash"
        case .ollama: "qwen2.5:7b-instruct"
        case .gemini, .lmStudio, .custom: ""
        }
    }

    var disablesThinking: Bool { self == .deepSeek }
}

struct PromptOptimizationRemoteProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var preset: OpenAICompatiblePreset
    var baseURL: String
    var model: String
    var allowsInsecureHTTP: Bool

    var configuration: PromptOptimizationRemoteConfiguration {
        PromptOptimizationRemoteConfiguration(
            preset: preset,
            baseURL: baseURL,
            model: model,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
    }

    static func makeDefault(
        id: UUID = UUID(),
        preset: OpenAICompatiblePreset = .openAI,
        displayName: String? = nil
    ) -> Self {
        Self(
            id: id,
            displayName: displayName ?? preset.defaultProfileName,
            preset: preset,
            baseURL: preset.defaultBaseURL,
            model: preset.defaultModel,
            allowsInsecureHTTP: false
        )
    }
}
```

Add `defaultProfileName`, store `[PromptOptimizationRemoteProfile]` plus `activeRemoteProfileID`, and make `defaultValue` a computed property calling `makeDefault()`. Keep a temporary `remote` computed property and legacy initializer so the settings store, service, and preference view continue compiling until their dedicated tasks migrate; mark the bridge for removal in Task 7 without adding a source comment containing a placeholder marker.

- [ ] **Step 4: Run the focused settings suite**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationSettingsTests
```

Expected: `** TEST SUCCEEDED **` and the updated default/profile assertions pass.

- [ ] **Step 5: Commit the model boundary**

```bash
git add pastera/Sources/Models/PromptOptimization.swift \
  pasteraTests/PromptOptimizationSettingsTests.swift
git commit -m "feat(prompt): add remote model profiles"
```

---

### Task 2: Persist and Migrate the Versioned Settings Snapshot

**Files:**
- Modify: `pastera/Sources/Constants.swift:102-107`
- Modify: `pastera/Sources/Utility/CPYUtilities.swift:116-133`
- Modify: `pastera/Sources/Services/PromptOptimizationSettingsStore.swift:3-69`
- Modify: `pasteraTests/PromptOptimizationSettingsTests.swift`
- Modify: `pasteraTests/PromptOptimizationPreferenceTests.swift:221-233`

**Interfaces:**
- Consumes: `PromptOptimizationSettings.makeDefault(profileID:)`, `PromptOptimizationRemoteProfile`, and legacy scalar UserDefaults keys.
- Produces: `Constants.UserDefaults.promptOptimizationSettingsV2`, `promptOptimizationLegacyCredentialProfileID`; `PromptOptimizationSettingsStoring.pendingLegacyCredentialProfileID`; `completeLegacyCredentialMigration(for:)`; stable V2 load/save/repair behavior.

- [ ] **Step 1: Write failing V2 round-trip, legacy migration, and repair tests**

```swift
@Test
func persistsProfilesAndActiveSelectionAsOneVersionedSnapshot() {
    let defaults = makeIsolatedDefaults()
    let store = PromptOptimizationSettingsStore(defaults: defaults)
    let first = PromptOptimizationRemoteProfile.makeDefault(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        preset: .ollama
    )
    let second = PromptOptimizationRemoteProfile(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        displayName: "Gateway",
        preset: .custom,
        baseURL: "https://aigateway.variflight.com/api",
        model: "aliyun/deepseek-v4-flash-0731",
        allowsInsecureHTTP: false
    )
    let settings = PromptOptimizationSettings(
        provider: .openAICompatible,
        remoteProfiles: [first, second],
        activeRemoteProfileID: second.id,
        confirmedOrigins: ["https://aigateway.variflight.com"]
    )

    store.save(settings)

    #expect(store.load() == settings)
    #expect(defaults.data(forKey: Constants.UserDefaults.promptOptimizationSettingsV2) != nil)
}

@Test
func migratesLegacyOllamaSettingsOnceWithStableProfileID() {
    let defaults = makeIsolatedDefaults()
    defaults.set(OpenAICompatiblePreset.ollama.rawValue,
                 forKey: Constants.UserDefaults.promptOptimizationPreset)
    defaults.set("http://127.0.0.1:11434/v1",
                 forKey: Constants.UserDefaults.promptOptimizationBaseURL)
    defaults.set("qwen2.5:7b-instruct",
                 forKey: Constants.UserDefaults.promptOptimizationModel)
    let store = PromptOptimizationSettingsStore(defaults: defaults)

    let firstLoad = store.load()
    let secondLoad = store.load()

    #expect(firstLoad == secondLoad)
    #expect(firstLoad.activeRemoteProfile?.preset == .ollama)
    #expect(firstLoad.activeRemoteProfile?.model == "qwen2.5:7b-instruct")
    #expect(store.pendingLegacyCredentialProfileID == firstLoad.activeRemoteProfileID)
}

@Test
func repairsMissingActiveProfileWithoutDroppingOtherProfiles() {
    let defaults = makeIsolatedDefaults()
    let store = PromptOptimizationSettingsStore(defaults: defaults)
    var settings = PromptOptimizationSettings.makeDefault()
    settings.activeRemoteProfileID = UUID()
    store.save(settings)

    let repaired = store.load()

    #expect(repaired.activeRemoteProfileID == repaired.remoteProfiles.first?.id)
    #expect(repaired.remoteProfiles.count == 1)
}

@Test
func malformedV2DataFallsBackToOneSafeDefaultProfile() {
    let defaults = makeIsolatedDefaults()
    defaults.set(Data("not-json".utf8),
                 forKey: Constants.UserDefaults.promptOptimizationSettingsV2)
    let store = PromptOptimizationSettingsStore(defaults: defaults)

    let settings = store.load()

    #expect(settings.provider == .automaticFree)
    #expect(settings.remoteProfiles.count == 1)
    #expect(settings.activeRemoteProfile?.preset == .openAI)
}
```

- [ ] **Step 2: Run the settings suite and verify persistence/migration tests fail**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationSettingsTests
```

Expected: compile failure for the V2 keys/protocol members or assertion failure because the old scalar store does not preserve multiple profiles.

- [ ] **Step 3: Implement the versioned snapshot and legacy migration marker**

```swift
protocol PromptOptimizationSettingsStoring: AnyObject {
    var pendingLegacyCredentialProfileID: UUID? { get }
    func load() -> PromptOptimizationSettings
    func save(_ settings: PromptOptimizationSettings)
    func confirmRemoteOrigin(_ origin: String)
    func completeLegacyCredentialMigration(for profileID: UUID)
}

private struct StoredPromptOptimizationSettings: Codable {
    static let currentVersion = 2
    let version: Int
    let settings: PromptOptimizationSettings
}
```

Use `JSONEncoder`/`JSONDecoder` with one `Data` value under `promptOptimizationSettingsV2`. On V2 load, repair an empty profile list with `makeDefault()`, repair a missing active ID to the first profile, and immediately rewrite the repaired snapshot. On first load without V2 data, read the legacy scalar keys; preserve the exact legacy configuration when provider/preset/base/model/HTTP/origins differ from defaults, otherwise create the prefilled OpenAI default. Save the generated profile UUID in `promptOptimizationLegacyCredentialProfileID`, encode V2 immediately, and never write the scalar keys again. A malformed or unsupported V2 envelope must follow the same safe migration/default path instead of returning a partially decoded object.

Update the `PreferenceSettingsStore` test double with an optional `pendingLegacyCredentialProfileID` and a matching completion method so the target compiles.

- [ ] **Step 4: Run settings and preference suites**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationSettingsTests \
  -only-testing:pasteraTests/PromptOptimizationPreferenceTests
```

Expected: `** TEST SUCCEEDED **`; V2 data exists, legacy UUID is stable, and existing preference tests still compile.

- [ ] **Step 5: Commit the settings migration**

```bash
git add pastera/Sources/Constants.swift pastera/Sources/Utility/CPYUtilities.swift \
  pastera/Sources/Services/PromptOptimizationSettingsStore.swift \
  pasteraTests/PromptOptimizationSettingsTests.swift \
  pasteraTests/PromptOptimizationPreferenceTests.swift
git commit -m "feat(prompt): migrate remote profile settings"
```

---

### Task 3: Isolate API Keys by Profile and Migrate the Legacy Item

**Files:**
- Modify: `pastera/Sources/Services/PromptOptimizationAPIKeyStore.swift:4-121`
- Modify: `pastera/Sources/Services/PromptOptimizationService.swift:1-150`
- Modify: `pastera/Sources/Preferences/Panels/PromptOptimizationPreferenceSection.swift:7-9,316-385,481-526`
- Modify: `pasteraTests/PromptOptimizationSettingsTests.swift:40-139`
- Modify: `pasteraTests/OpenAICompatiblePromptOptimizerTests.swift:419-565`
- Modify: `pasteraTests/PromptOptimizationServiceTests.swift:228-234`
- Modify: `pasteraTests/PromptOptimizationPreferenceTests.swift:235-255`

**Interfaces:**
- Consumes: stable profile UUIDs and `PromptOptimizationSettingsStoring.pendingLegacyCredentialProfileID`.
- Produces: keyed `PromptOptimizationAPIKeyStoring` methods and `PromptOptimizationSettingsStoring.migrateLegacyAPIKeyIfNeeded(using:)` orchestration used by the service and preference UI.

- [ ] **Step 1: Replace single-account tests with failing profile-isolation and migration tests**

```swift
@Test
func apiKeysUseSeparateNonSynchronizingAccounts() throws {
    let keychain = InMemoryPromptOptimizationKeychain()
    let store = PromptOptimizationAPIKeyStore(keychain: keychain, usesDataProtectionKeychain: false)
    let first = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    let second = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!

    try store.save("first-secret", for: first)
    try store.save("second-secret", for: second)

    #expect(try store.load(for: first) == "first-secret")
    #expect(try store.load(for: second) == "second-secret")
    #expect(PromptOptimizationAPIKeyStore.account(for: first) !=
            PromptOptimizationAPIKeyStore.account(for: second))
    #expect(keychain.addQueries.allSatisfy {
        $0[kSecAttrSynchronizable as String] as? Bool == false
    })
}

@Test
func legacyKeyMigrationCopiesThenDeletesAndIsIdempotent() throws {
    let keychain = InMemoryPromptOptimizationKeychain(items: [
        PromptOptimizationAPIKeyStore.legacyAccount: Data("legacy-secret".utf8)
    ])
    let store = PromptOptimizationAPIKeyStore(keychain: keychain, usesDataProtectionKeychain: false)
    let profileID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    try store.migrateLegacyAPIKeyIfNeeded(to: profileID)
    try store.migrateLegacyAPIKeyIfNeeded(to: profileID)

    #expect(try store.load(for: profileID) == "legacy-secret")
    #expect(!keychain.contains(account: PromptOptimizationAPIKeyStore.legacyAccount))
}

@Test
func migrationNeverOverwritesAnExistingProfileKey() throws {
    let profileID = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!
    let keychain = InMemoryPromptOptimizationKeychain(items: [
        PromptOptimizationAPIKeyStore.legacyAccount: Data("legacy-secret".utf8),
        PromptOptimizationAPIKeyStore.account(for: profileID): Data("new-secret".utf8)
    ])
    let store = PromptOptimizationAPIKeyStore(keychain: keychain, usesDataProtectionKeychain: false)

    try store.migrateLegacyAPIKeyIfNeeded(to: profileID)

    #expect(try store.load(for: profileID) == "new-secret")
}

@Test
func failedLegacyDeletionKeepsTheMigrationMarkerForRetry() throws {
    let defaults = makeIsolatedDefaults()
    let settingsStore = PromptOptimizationSettingsStore(defaults: defaults)
    _ = settingsStore.load()
    let profileID = try #require(settingsStore.pendingLegacyCredentialProfileID)
    let keychain = InMemoryPromptOptimizationKeychain(items: [
        PromptOptimizationAPIKeyStore.legacyAccount: Data("legacy-secret".utf8)
    ])
    keychain.deleteStatus = errSecAuthFailed
    let keyStore = PromptOptimizationAPIKeyStore(
        keychain: keychain,
        usesDataProtectionKeychain: false
    )

    #expect(throws: PromptOptimizationError.keychainUnavailable) {
        try settingsStore.migrateLegacyAPIKeyIfNeeded(using: keyStore)
    }
    #expect(settingsStore.pendingLegacyCredentialProfileID == profileID)

    keychain.deleteStatus = errSecSuccess
    try settingsStore.migrateLegacyAPIKeyIfNeeded(using: keyStore)
    #expect(settingsStore.pendingLegacyCredentialProfileID == nil)
}
```

The in-memory Keychain test double must index items by `kSecAttrAccount`, record add/update/delete queries, and expose injected add/delete failures so a separate test proves the legacy marker is retained after a failed copy or delete.

- [ ] **Step 2: Run the settings suite and verify the keyed API is missing**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationSettingsTests
```

Expected: compile failure for `save(_:for:)`, `load(for:)`, `account(for:)`, or `migrateLegacyAPIKeyIfNeeded(to:)`.

- [ ] **Step 3: Implement the keyed protocol and idempotent legacy migration**

```swift
protocol PromptOptimizationAPIKeyStoring: AnyObject {
    func containsAPIKey(for profileID: UUID) -> Bool
    func save(_ apiKey: String, for profileID: UUID) throws
    func load(for profileID: UUID) throws -> String?
    func delete(for profileID: UUID) throws
    func migrateLegacyAPIKeyIfNeeded(to profileID: UUID) throws
}

extension PromptOptimizationSettingsStoring {
    func migrateLegacyAPIKeyIfNeeded(
        using apiKeyStore: any PromptOptimizationAPIKeyStoring
    ) throws {
        guard let profileID = pendingLegacyCredentialProfileID else { return }
        try apiKeyStore.migrateLegacyAPIKeyIfNeeded(to: profileID)
        completeLegacyCredentialMigration(for: profileID)
    }
}
```

Keep service `com.pastera-app.Pastera.prompt-optimization.v1`; rename the old fixed account to `legacyAccount`; return `"PasteraPromptOptimizationAPIKey.\(profileID.uuidString.lowercased())"` from `account(for:)`. Each query must include `kSecAttrSynchronizable: false` and the existing accessibility/Data Protection settings. Migration algorithm: if the new item is missing, read the legacy item and save it under the UUID account; if the new item exists, keep it; then delete the legacy item. Treat missing legacy/delete items as success. Throw on copy/add/delete errors so the settings marker remains and a later call retries safely.

Update service and UI call sites immediately to pass the current `activeRemoteProfileID`; call the settings-store migration helper before reading status or a key. Update every test double to store `[UUID: String]` and implement the keyed methods so all targets compile; later tasks add routing/UI assertions.

- [ ] **Step 4: Run all prompt optimization suites**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationSettingsTests \
  -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests \
  -only-testing:pasteraTests/PromptOptimizationServiceTests \
  -only-testing:pasteraTests/PromptOptimizationPreferenceTests
```

Expected: `** TEST SUCCEEDED **`; UUID isolation, migration success, migration failure recovery, and existing prompt tests pass.

- [ ] **Step 5: Commit profile-scoped credentials**

```bash
git add pastera/Sources/Services/PromptOptimizationAPIKeyStore.swift \
  pastera/Sources/Services/PromptOptimizationService.swift \
  pastera/Sources/Preferences/Panels/PromptOptimizationPreferenceSection.swift \
  pasteraTests/PromptOptimizationSettingsTests.swift \
  pasteraTests/OpenAICompatiblePromptOptimizerTests.swift \
  pasteraTests/PromptOptimizationServiceTests.swift \
  pasteraTests/PromptOptimizationPreferenceTests.swift
git commit -m "feat(prompt): isolate profile API keys"
```

---

### Task 4: Add DeepSeek Request Options and Custom Gateway Coverage

**Files:**
- Modify: `pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift:25-142`
- Modify: `pasteraTests/OpenAICompatiblePromptOptimizerTests.swift`

**Interfaces:**
- Consumes: `PromptOptimizationRemoteConfiguration.preset`, `OpenAICompatiblePreset.disablesThinking`, and existing endpoint policy.
- Produces: optional `thinking` JSON for direct DeepSeek profiles; exact custom gateway URL/model behavior with no vendor-specific fields.

- [ ] **Step 1: Write failing request-shape tests**

```swift
@Test
func deepSeekPresetDisablesThinking() async throws {
    let client = makeClient(status: 200, body: #"{"choices":[{"message":{"content":"Improved"}}]}"#)
    var configuration = PromptOptimizationRemoteConfiguration.fixture
    configuration.preset = .deepSeek
    configuration.baseURL = "https://api.deepseek.com"
    configuration.model = "deepseek-v4-flash"

    _ = try await client.optimize(text: "Draft", configuration: configuration, apiKey: "key").get()

    let body = try #require(PromptOptimizationURLProtocolStub.lastRequestBody)
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect((payload["thinking"] as? [String: String])?["type"] == "disabled")
    #expect(payload["temperature"] as? Int == 0)
}

@Test
func customGatewayKeepsPathAndModelWithoutDeepSeekFields() async throws {
    let client = makeClient(status: 200, body: #"{"choices":[{"message":{"content":"Improved"}}]}"#)
    let configuration = PromptOptimizationRemoteConfiguration(
        preset: .custom,
        baseURL: "https://aigateway.variflight.com/api",
        model: "aliyun/deepseek-v4-flash-0731",
        allowsInsecureHTTP: false
    )

    _ = try await client.optimize(text: "Draft", configuration: configuration, apiKey: "gateway-key").get()

    #expect(PromptOptimizationURLProtocolStub.lastRequest?.url?.absoluteString ==
            "https://aigateway.variflight.com/api/chat/completions")
    let body = try #require(PromptOptimizationURLProtocolStub.lastRequestBody)
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(payload["model"] as? String == "aliyun/deepseek-v4-flash-0731")
    #expect(payload["thinking"] == nil)
    #expect(PromptOptimizationURLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Authorization") ==
            "Bearer gateway-key")
}
```

Retain or add a separate assertion that an empty key omits the Authorization header and that a Base URL already ending in `/chat/completions` is not duplicated.

- [ ] **Step 2: Run the optimizer suite and verify the DeepSeek body test fails**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests
```

Expected: the custom path/model assertions already pass through the generic client, while the DeepSeek assertion fails because `thinking` is absent.

- [ ] **Step 3: Add an optional encoded thinking configuration**

```swift
private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream = false
    let temperature = 0
    let maximumOutputTokens: Int?
    let thinking: ThinkingConfiguration?

    init(
        model: String,
        messages: [Message],
        maximumOutputTokens: Int?,
        preset: OpenAICompatiblePreset
    ) {
        self.model = model
        self.messages = messages
        self.maximumOutputTokens = maximumOutputTokens
        self.thinking = preset.disablesThinking ? ThinkingConfiguration() : nil
    }

    struct ThinkingConfiguration: Encodable {
        let type = "disabled"
    }
}
```

Pass `configuration.preset` into the request initializer and add `thinking` to `CodingKeys`. Do not inspect `configuration.model` and do not change endpoint, error mapping, sanitizer, timeout, fixed probe, or response handling.

- [ ] **Step 4: Run the optimizer suite**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests
```

Expected: `** TEST SUCCEEDED **`; DeepSeek includes only the approved extra field, custom gateway omits it, and all sanitizer/probe/error tests remain green.

- [ ] **Step 5: Commit the request capability**

```bash
git add pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift \
  pasteraTests/OpenAICompatiblePromptOptimizerTests.swift
git commit -m "feat(prompt): support DeepSeek flash requests"
```

---

### Task 5: Route the Service Through Only the Active Profile

**Files:**
- Modify: `pastera/Sources/Services/PromptOptimizationService.swift:28-150`
- Modify: `pasteraTests/PromptOptimizationServiceTests.swift`
- Modify: `pasteraTests/OpenAICompatiblePromptOptimizerTests.swift:419-446,531-565`

**Interfaces:**
- Consumes: `PromptOptimizationSettings.activeRemoteProfile`, `PromptOptimizationRemoteProfile.configuration`, keyed API-key methods, and the shared optimizer.
- Produces: active-profile-only availability, optimization, connection test, consent ordering, keyed credential lookup, and no failover.

- [ ] **Step 1: Write failing active-profile and no-failover tests**

```swift
@Test
func remoteOptimizationUsesOnlyTheActiveProfileAndItsKey() async {
    let first = PromptOptimizationRemoteProfile.makeDefault(
        id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
        preset: .ollama
    )
    let second = PromptOptimizationRemoteProfile(
        id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
        displayName: "Gateway",
        preset: .custom,
        baseURL: "https://aigateway.variflight.com/api",
        model: "aliyun/deepseek-v4-flash-0731",
        allowsInsecureHTTP: false
    )
    let settings = PromptOptimizationSettings(
        provider: .openAICompatible,
        remoteProfiles: [first, second],
        activeRemoteProfileID: second.id,
        confirmedOrigins: ["https://aigateway.variflight.com"]
    )
    let keyStore = StubPromptOptimizationAPIKeyStore(values: [second.id: "gateway-key"])
    let remote = RecordingRemotePromptOptimizer(result: .failure(.requestTimedOut))
    let service = makeRemoteService(settings: settings, keyStore: keyStore, remote: remote)

    #expect(await service.optimize("Draft") == .failed(.requestTimedOut))
    #expect(keyStore.loadedProfileIDs == [second.id])
    #expect(remote.configurations.map(\.model) == ["aliyun/deepseek-v4-flash-0731"])
    #expect(remote.apiKeys == ["gateway-key"])
}

@Test
func connectionConsentIsCheckedBeforeTheActiveProfileKeyIsRead() async {
    var settings = PromptOptimizationSettings.makeDefault()
    settings.provider = .openAICompatible
    settings.confirmedOrigins = []
    let keyStore = StubPromptOptimizationAPIKeyStore()
    let service = makeRemoteService(
        settings: settings,
        keyStore: keyStore,
        remote: RecordingRemotePromptOptimizer(result: .success("OK"))
    )

    #expect(await service.testRemoteConnection() ==
            .failure(.originNotConfirmed(origin: "https://api.openai.com")))
    #expect(keyStore.loadedProfileIDs.isEmpty)
}
```

The first test's single remote call is the no-failover assertion: a timeout from the active gateway must not invoke the Ollama profile.

- [ ] **Step 2: Run service and optimizer suites and verify active routing fails**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationServiceTests \
  -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests
```

Expected: assertion failure if the service still reads the compatibility `remote` value or a non-keyed credential.

- [ ] **Step 3: Resolve one remote context per operation**

```swift
private struct ActiveRemoteContext {
    let profile: PromptOptimizationRemoteProfile
    let endpoint: PromptOptimizationEndpoint
}

private func activeRemoteContext(
    from settings: PromptOptimizationSettings
) throws -> ActiveRemoteContext {
    guard let profile = settings.activeRemoteProfile else {
        throw PromptOptimizationError.missingModel
    }
    guard !profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw PromptOptimizationError.missingModel
    }
    return ActiveRemoteContext(
        profile: profile,
        endpoint: try endpointPolicy.validate(profile.configuration)
    )
}
```

Use the same loaded settings snapshot and resolved context for each availability/test/optimize operation. Check `confirmedOrigins` before calling the settings/key migration helper or reading Keychain. After consent, run the idempotent migration helper, load `apiKeyStore.load(for: profile.id)`, and call the optimizer once with `profile.configuration`. Preserve automatic-free behavior and all existing error mappings.

- [ ] **Step 4: Run service and optimizer suites**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationServiceTests \
  -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests
```

Expected: `** TEST SUCCEEDED **`; only the active profile/key is observed, consent precedes Keychain access, and timeout does not fall through to another profile.

- [ ] **Step 5: Commit service routing**

```bash
git add pastera/Sources/Services/PromptOptimizationService.swift \
  pasteraTests/PromptOptimizationServiceTests.swift \
  pasteraTests/OpenAICompatiblePromptOptimizerTests.swift
git commit -m "feat(prompt): route the active remote profile"
```

---

### Task 6: Add an Independently Tested Profile Draft State

**Files:**
- Create: `pastera/Sources/Preferences/Panels/PromptOptimizationRemoteProfileDraft.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pasteraTests/PromptOptimizationPreferenceTests.swift`

**Interfaces:**
- Consumes: `PromptOptimizationSettings`, `PromptOptimizationRemoteProfile`, and preset defaults.
- Produces: `PromptOptimizationRemoteProfileDraft` with selection, staging, unique add, explicit preset application, persisted-ID tracking, snapshot, and remove/reset behavior.

- [ ] **Step 1: Write failing draft-state tests**

```swift
@Test
func profileDraftStagesAcrossSwitchesAndGeneratesUniqueNames() throws {
    let firstID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    let secondID = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
    var draft = PromptOptimizationRemoteProfileDraft(
        settings: .makeDefault(profileID: firstID)
    )

    let addedID = draft.addProfile(preset: .openAI, id: secondID)
    #expect(draft.settings.remoteProfiles.map(\.displayName) == ["OpenAI", "OpenAI 2"])
    draft.updateSelected(
        displayName: "Gateway",
        preset: .custom,
        baseURL: "https://aigateway.variflight.com/api",
        model: "aliyun/deepseek-v4-flash-0731",
        allowsInsecureHTTP: false
    )
    draft.selectProfile(id: firstID)

    #expect(addedID == secondID)
    #expect(draft.selectedProfile?.displayName == "OpenAI")
    draft.selectProfile(id: secondID)
    #expect(draft.selectedProfile?.model == "aliyun/deepseek-v4-flash-0731")
    #expect(!draft.isPersisted(secondID))
}

@Test
func lastProfileRemovalResetsItWithoutChangingItsID() {
    let id = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
    var draft = PromptOptimizationRemoteProfileDraft(settings: .makeDefault(profileID: id))
    draft.updateSelected(
        displayName: "Gateway",
        preset: .custom,
        baseURL: "https://aigateway.variflight.com/api",
        model: "aliyun/deepseek-v4-flash-0731",
        allowsInsecureHTTP: false
    )

    draft.removeOrResetSelectedProfile()

    #expect(draft.settings.remoteProfiles.count == 1)
    #expect(draft.selectedProfile?.id == id)
    #expect(draft.selectedProfile?.preset == .openAI)
    #expect(draft.selectedProfile?.model == "gpt-5.6-luna")
}
```

Add a third test proving `selectProfile` alone preserves custom address/model, while `applyPresetDefaults()` explicitly replaces them with the selected preset defaults.

- [ ] **Step 2: Run preference tests and verify the draft type is missing**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationPreferenceTests
```

Expected: compile failure for `PromptOptimizationRemoteProfileDraft`.

- [ ] **Step 3: Implement the focused draft state**

```swift
struct PromptOptimizationRemoteProfileDraft {
    private(set) var settings: PromptOptimizationSettings
    private(set) var selectedProfileID: UUID
    private var persistedProfileIDs: Set<UUID>

    init(settings: PromptOptimizationSettings) {
        var repaired = settings
        repaired.repairActiveRemoteProfile()
        self.settings = repaired
        self.selectedProfileID = repaired.activeRemoteProfileID
        self.persistedProfileIDs = Set(repaired.remoteProfiles.map(\.id))
    }

    var selectedProfile: PromptOptimizationRemoteProfile? {
        settings.remoteProfiles.first { $0.id == selectedProfileID }
    }

    func isPersisted(_ profileID: UUID) -> Bool {
        persistedProfileIDs.contains(profileID)
    }

    mutating func markSaved() {
        persistedProfileIDs = Set(settings.remoteProfiles.map(\.id))
    }
}
```

Implement exact mutating methods `setProvider(_:)`, `selectProfile(id:)`, `updateSelected(displayName:preset:baseURL:model:allowsInsecureHTTP:)`, `addProfile(preset:id:) -> UUID`, `applyPresetDefaults()`, `removeOrResetSelectedProfile()`, and `snapshot() -> PromptOptimizationSettings`. `addProfile` must use preset defaults and choose a case-insensitively unique display name by appending ` 2`, ` 3`, and so on. Removing from a multi-profile list selects the first remaining profile; removing the last profile resets the same UUID to OpenAI defaults. `snapshot()` must set `activeRemoteProfileID` to `selectedProfileID`.

Add PBX build/file references `C5F740012FFF400000B7C0DE` and `C5F740022FFF400000B7C0DE` to the existing Preferences/Panels group and Pastera Sources build phase so the new file compiles.

- [ ] **Step 4: Run preference tests**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationPreferenceTests
```

Expected: `** TEST SUCCEEDED **`; draft switching, explicit preset application, persisted-ID state, unique naming, removal, and reset pass without constructing AppKit controls.

- [ ] **Step 5: Commit the draft state**

```bash
git add pastera/Sources/Preferences/Panels/PromptOptimizationRemoteProfileDraft.swift \
  pastera.xcodeproj/project.pbxproj \
  pasteraTests/PromptOptimizationPreferenceTests.swift
git commit -m "feat(prompt): add remote profile draft state"
```

---

### Task 7: Add Multi-Profile Controls to the Preference Section

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/PromptOptimizationPreferenceSection.swift:6-674`
- Modify: `pastera/Sources/Models/PromptOptimization.swift`
- Modify: `pasteraTests/PromptOptimizationPreferenceTests.swift`
- Modify: `pasteraTests/PromptOptimizationSettingsTests.swift`

**Interfaces:**
- Consumes: `PromptOptimizationRemoteProfileDraft`, keyed API-key store, endpoint policy, settings snapshot store, and current service connection test.
- Produces: profile selector/name/add/delete/apply-default controls; active-profile save; profile-scoped key status/save/delete; immediate safe profile deletion; removal of the temporary single-configuration settings bridge.

- [ ] **Step 1: Write failing AppKit behavior tests**

```swift
@Test
func switchingProfilesPreservesDraftFieldsAndShowsTheSelectedKeyStatus() {
    let fixture = makeFixture()
    fixture.section.selectProviderForTesting(.openAICompatible)
    let firstID = fixture.section.activeProfileIDForTesting
    fixture.section.setProfileFieldsForTesting(
        name: "OpenAI Work",
        baseURL: "https://api.openai.com/v1",
        model: "gpt-5.6-luna"
    )
    let gatewayID = fixture.section.addProfileForTesting(preset: .custom)
    fixture.section.setProfileFieldsForTesting(
        name: "Gateway",
        baseURL: "https://aigateway.variflight.com/api",
        model: "aliyun/deepseek-v4-flash-0731"
    )
    fixture.section.selectProfileForTesting(firstID)

    #expect(gatewayID != firstID)
    #expect(fixture.section.profileNameForTesting == "OpenAI Work")
    #expect(fixture.section.modelForTesting == "gpt-5.6-luna")
    #expect(fixture.section.activeProfileIDForTesting == firstID)
}

@Test
func savingCustomGatewayPersistsExactPathModelAndSelectedProfile() {
    let fixture = makeFixture()
    fixture.section.selectProviderForTesting(.openAICompatible)
    let gatewayID = fixture.section.addProfileForTesting(preset: .custom)
    fixture.section.setProfileFieldsForTesting(
        name: "Gateway",
        baseURL: "https://aigateway.variflight.com/api",
        model: "aliyun/deepseek-v4-flash-0731"
    )

    #expect(fixture.section.saveSettingsForTesting())

    #expect(fixture.settingsStore.settings.activeRemoteProfileID == gatewayID)
    #expect(fixture.settingsStore.settings.activeRemoteProfile?.baseURL ==
            "https://aigateway.variflight.com/api")
    #expect(fixture.settingsStore.settings.activeRemoteProfile?.model ==
            "aliyun/deepseek-v4-flash-0731")
}

@Test
func failedKeyDeletionKeepsTheProfileVisible() {
    let fixture = makeFixture()
    fixture.section.selectProviderForTesting(.openAICompatible)
    let profileID = fixture.section.activeProfileIDForTesting
    fixture.apiKeyStore.deleteFailures.insert(profileID)

    fixture.section.deleteSelectedProfileForTesting(confirmed: true)

    #expect(fixture.settingsStore.settings.remoteProfiles.contains { $0.id == profileID })
    #expect(fixture.section.statusForTesting.contains("Unable") ||
            fixture.section.statusForTesting.contains("无法"))
}
```

Add tests proving an unsaved profile cannot invoke the standalone “Save Key” action, profile key status uses the selected UUID, preset selection does not overwrite custom fields until `applyPresetDefaultsForTesting()`, and deleting the only profile resets it after deleting its key.

- [ ] **Step 2: Run preference tests and verify the profile-control API is missing**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationPreferenceTests
```

Expected: compile failure for the new profile testing helpers.

- [ ] **Step 3: Build profile controls around the draft state**

```swift
private let profilePopup = NSPopUpButton()
private let profileNameField = NSTextField()
private let addProfileButton = NSButton()
private let deleteProfileButton = NSButton()
private let applyPresetDefaultsButton = NSButton()
private var profileDraft: PromptOptimizationRemoteProfileDraft
```

Initialize the draft from `settingsStore.load()`. Add a profile row before the preset row, with accessible labels and localized Add/Delete actions; add the profile name field and an explicit “Apply Preset Defaults” button. Before switching, saving, adding, or deleting, stage the current controls with `updateSelected`. Switching then loads the selected profile, clears the secure field and transient connection result, refreshes UUID-scoped key status, and triggers content-size invalidation.

`persistSettings()` must stage current controls, trim and require every profile name/model, reject case-insensitive duplicate names, validate every profile configuration with `PromptOptimizationEndpointPolicy`, set provider/active ID in the snapshot, save once, and call `profileDraft.markSaved()`. A standalone key save is disabled/rejected until `isPersisted(selectedID)` is true; Save Settings may persist the profile first and then save a pending key for that UUID.

Profile deletion flow must be exact:

```swift
guard confirmation.confirmed, let profileID = profileDraft.selectedProfile?.id else { return }
do {
    if profileDraft.isPersisted(profileID) {
        try apiKeyStore.delete(for: profileID)
    }
    profileDraft.removeOrResetSelectedProfile()
    settingsStore.save(profileDraft.snapshot())
    profileDraft.markSaved()
    loadSelectedProfileIntoControls()
} catch {
    setError(promptPreferenceString(
        "Unable to remove this model profile.",
        "无法移除此模型配置。"
    ))
}
```

Update the preference test double to keep `values: [UUID: String]`, `loadedProfileIDs`, and
`deleteFailures`. Expose narrow test helpers matching the test names above, including a
nonoptional `activeProfileIDForTesting: UUID` backed by the draft's repaired selected ID; do
not expose secure field contents through status text.

- [ ] **Step 4: Remove the temporary single-configuration bridge and prove no old settings access remains**

Remove the legacy `PromptOptimizationSettings.remote` computed property and legacy initializer added in Task 1. Convert remaining fixtures to construct `remoteProfiles` and `activeRemoteProfileID`, then run:

```bash
rg -n "settings\.remote\b|PromptOptimizationSettings\([^)]*remote:" pastera pasteraTests
```

Expected: no matches. `PromptOptimizationRemoteConfiguration` remains in the endpoint/transport APIs and tests because it is the shared request value.

- [ ] **Step 5: Run all prompt optimization suites**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PromptOptimizationSettingsTests \
  -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests \
  -only-testing:pasteraTests/PromptOptimizationServiceTests \
  -only-testing:pasteraTests/PromptOptimizationPreferenceTests
```

Expected: `** TEST SUCCEEDED **`; multi-profile UI, keyed credentials, request shape, active routing, existing cancellation, and layout tests pass.

- [ ] **Step 6: Commit the preference UI**

```bash
git add pastera/Sources/Preferences/Panels/PromptOptimizationPreferenceSection.swift \
  pastera/Sources/Models/PromptOptimization.swift \
  pasteraTests/PromptOptimizationPreferenceTests.swift \
  pasteraTests/PromptOptimizationSettingsTests.swift
git commit -m "feat(prompt): manage multiple model profiles"
```

---

### Task 8: Full Regression, Local Installation, and Safe Acceptance

**Files:**
- Verify: all files changed by Tasks 0-7
- Verify: `docs/superpowers/specs/2026-08-04-prompt-optimization-multi-model-gateway-design.md`
- Verify: `docs/superpowers/plans/2026-08-04-prompt-optimization-multi-model-gateway.md`

**Interfaces:**
- Consumes: complete multi-profile implementation and installed Ollama service.
- Produces: focused/full test evidence, installed signed app, local Ollama acceptance, and credential-safe gateway acceptance status.

- [ ] **Step 1: Run the four focused suites together from a clean test invocation**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  clean test \
  -only-testing:pasteraTests/PromptOptimizationSettingsTests \
  -only-testing:pasteraTests/OpenAICompatiblePromptOptimizerTests \
  -only-testing:pasteraTests/PromptOptimizationServiceTests \
  -only-testing:pasteraTests/PromptOptimizationPreferenceTests
```

Expected: `** TEST SUCCEEDED **` with zero failures.

- [ ] **Step 2: Run the repository's full regression command**

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

Expected: `** TEST SUCCEEDED **` with zero failures. If failures are confined to the known shared-state Vault Agent suites, do not change prompt code; rerun these exact suites with `-parallel-testing-enabled NO` before classification:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -parallel-testing-enabled NO test \
  -only-testing:pasteraTests/VaultAgentBrokerTests \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests \
  -only-testing:pasteraTests/VaultAgentAuthorizationPolicyTests \
  -only-testing:pasteraTests/VaultAgentIntegrationInstallerTests
```

Expected serial classification: all four suites pass. Any prompt-suite or repeatable non-Vault failure remains a blocker and must be debugged before installation.

- [ ] **Step 3: Verify diff scope and credential hygiene**

```bash
git diff --check
git status --short --branch
git log --oneline --decorate -10
! rg -n 'sk-[A-Za-z0-9_-]{20,}' \
  pastera pasteraTests docs/superpowers/specs docs/superpowers/plans
```

Expected: `git diff --check` exits 0; only intended files/commits exist; the credential scan finds no literal secret. A reference to the header name or secure-field label is acceptable only when no value is present.

- [ ] **Step 4: Install and validate the app bundle**

```bash
./script/install_local.sh
codesign --verify --deep --strict /Applications/Pastera.app
codesign -dv --verbose=4 /Applications/Pastera.app
```

Expected: installation succeeds, `/Applications/Pastera.app` is replaced and launched, and
`codesign` reports valid-on-disk behavior plus the installed bundle's ad-hoc signature metadata.

- [ ] **Step 5: Perform installed-app profile acceptance without exposing credentials**

Use the Pastera Preferences UI only:

1. Confirm the migrated Ollama profile still shows `http://127.0.0.1:11434/v1` and `qwen2.5:7b-instruct`; test connection and expect “连接成功”.
2. Add a DeepSeek profile and confirm preset defaults are `https://api.deepseek.com` and `deepseek-v4-flash`; do not authenticate unless a separately provisioned direct DeepSeek key is available in Keychain.
3. Add a Custom profile with `https://aigateway.variflight.com/api` and `aliyun/deepseek-v4-flash-0731`; confirm it saves and switches without changing the Ollama profile.
4. If a rotated gateway key is available, enter it only in the secure field, save it, confirm the origin prompt, and test connection. Do not paste it into Terminal, screenshots, test fixtures, notes, or the final report.
5. Switch between profiles and confirm key status, model, Base URL, and connection result do not leak across profiles.

Expected: Ollama acceptance passes; profile switching and exact gateway path/model persistence pass. Authenticated gateway acceptance is reported as passed only after the rotated-key UI test succeeds; otherwise report it as awaiting rotated credential, without weakening the implementation-complete claim supported by mock transport tests.

- [ ] **Step 6: Record final repository state without pushing**

```bash
git status --short --branch
git rev-parse HEAD
git diff --check
```

Expected: the working tree contains no unintended changes, HEAD identifies the last scoped implementation commit, and no push has occurred.
