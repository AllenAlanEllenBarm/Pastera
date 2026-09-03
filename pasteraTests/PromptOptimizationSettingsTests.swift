import Foundation
import Security
import Testing
@testable import Pastera

// swiftlint:disable:next type_body_length
struct PromptOptimizationSettingsTests {
    @Test
    func presetsExposeEditableProviderDefaults() {
        #expect(OpenAICompatiblePreset.openAI.defaultBaseURL == "https://api.openai.com/v1")
        #expect(OpenAICompatiblePreset.openAI.defaultModel == "gpt-5.6-luna")
        #expect(OpenAICompatiblePreset.deepSeek.defaultBaseURL == "https://api.deepseek.com")
        #expect(OpenAICompatiblePreset.deepSeek.defaultModel == "deepseek-v4-flash")
        #expect(OpenAICompatiblePreset.deepSeek.disablesThinking)
        #expect(OpenAICompatiblePreset.ollama.defaultModel == "qwen3.5:4b")
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

    @Test
    func repairActiveRemoteProfileSelectsTheFirstConfiguredProfileForAnUnknownID() {
        let profile = PromptOptimizationRemoteProfile.makeDefault(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            preset: .ollama
        )
        var settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [profile],
            activeRemoteProfileID: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            confirmedOrigins: []
        )

        settings.repairActiveRemoteProfile()

        #expect(settings.activeRemoteProfileID == profile.id)
        #expect(settings.activeRemoteProfile?.id == profile.id)
    }

    @Test
    func repairActiveRemoteProfileCreatesAnOpenAIProfileForAnEmptyList() {
        var settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [],
            activeRemoteProfileID: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            confirmedOrigins: []
        )

        settings.repairActiveRemoteProfile()

        #expect(settings.remoteProfiles.count == 1)
        #expect(settings.activeRemoteProfileID == settings.remoteProfiles.first?.id)
        #expect(settings.activeRemoteProfile?.preset == .openAI)
    }

    @Test
    func defaultsToFreeAutomaticWithOnePrefilledOpenAIProfile() {
        let store = PromptOptimizationSettingsStore(defaults: makeIsolatedDefaults())

        let settings = store.load()

        #expect(settings.provider == .automaticFree)
        #expect(settings.activeRemoteProfile?.model == "gpt-5.6-luna")
        #expect(settings.activeRemoteProfile?.baseURL == "https://api.openai.com/v1")
        #expect(settings.confirmedOrigins.isEmpty)
        #expect(settings.activeRemoteProfile?.allowsInsecureHTTP == false)
    }

    @Test
    func persistsRemoteConfigurationAndConfirmedOrigins() {
        let defaults = makeIsolatedDefaults()
        let store = PromptOptimizationSettingsStore(defaults: defaults)
        let profile = PromptOptimizationRemoteProfile(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            displayName: "Private model",
            preset: .custom,
            baseURL: "https://models.example.com/v1",
            model: "private-model",
            allowsInsecureHTTP: false
        )
        let settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [profile],
            activeRemoteProfileID: profile.id,
            confirmedOrigins: ["https://models.example.com"]
        )

        store.save(settings)

        let loaded = store.load()
        #expect(loaded.provider == settings.provider)
        #expect(loaded.activeRemoteProfile == profile)
        #expect(loaded.confirmedOrigins == settings.confirmedOrigins)
    }

    @Test
    func stalePreferenceSnapshotCannotEraseOriginConfirmedByServiceStore() {
        let defaults = makeIsolatedDefaults()
        let preferenceStore = PromptOptimizationSettingsStore(defaults: defaults)
        let serviceStore = PromptOptimizationSettingsStore(defaults: defaults)
        var stalePreferenceSnapshot = preferenceStore.load()

        serviceStore.confirmRemoteOrigin("https://api.example.com")
        stalePreferenceSnapshot.provider = .openAICompatible
        preferenceStore.save(stalePreferenceSnapshot)

        #expect(serviceStore.load().confirmedOrigins == ["https://api.example.com"])
    }

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
        defaults.set(
            OpenAICompatiblePreset.ollama.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationPreset
        )
        defaults.set(
            "http://127.0.0.1:11434/v1",
            forKey: Constants.UserDefaults.promptOptimizationBaseURL
        )
        defaults.set(
            "qwen2.5:7b-instruct",
            forKey: Constants.UserDefaults.promptOptimizationModel
        )
        let store = PromptOptimizationSettingsStore(defaults: defaults)

        let firstLoad = store.load()
        let secondLoad = store.load()

        #expect(firstLoad == secondLoad)
        #expect(firstLoad.activeRemoteProfile?.preset == .ollama)
        #expect(firstLoad.activeRemoteProfile?.model == "qwen2.5:7b-instruct")
        #expect(store.pendingLegacyCredentialProfileID == firstLoad.activeRemoteProfileID)
    }

    @Test
    func migratesLegacyConfigurationWithoutChangingProviderHTTPOrOrigins() {
        let defaults = makeIsolatedDefaults()
        defaults.set(
            PromptOptimizationProviderSelection.openAICompatible.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationProvider
        )
        defaults.set(
            OpenAICompatiblePreset.custom.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationPreset
        )
        defaults.set(
            "http://models.example.com/v1",
            forKey: Constants.UserDefaults.promptOptimizationBaseURL
        )
        defaults.set(
            "legacy-model",
            forKey: Constants.UserDefaults.promptOptimizationModel
        )
        defaults.set(
            true,
            forKey: Constants.UserDefaults.promptOptimizationAllowsInsecureHTTP
        )
        defaults.set(
            ["http://models.example.com"],
            forKey: Constants.UserDefaults.promptOptimizationConfirmedOrigins
        )
        let store = PromptOptimizationSettingsStore(defaults: defaults)

        let settings = store.load()

        #expect(settings.provider == .openAICompatible)
        #expect(settings.activeRemoteProfile?.preset == .custom)
        #expect(settings.activeRemoteProfile?.baseURL == "http://models.example.com/v1")
        #expect(settings.activeRemoteProfile?.model == "legacy-model")
        #expect(settings.activeRemoteProfile?.allowsInsecureHTTP == true)
        #expect(settings.confirmedOrigins == ["http://models.example.com"])
    }

    @Test
    func completesLegacyCredentialMigrationOnlyForThePendingProfile() {
        let defaults = makeIsolatedDefaults()
        defaults.set(
            OpenAICompatiblePreset.ollama.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationPreset
        )
        let store = PromptOptimizationSettingsStore(defaults: defaults)
        let pendingID = store.load().activeRemoteProfileID

        store.completeLegacyCredentialMigration(for: UUID())
        #expect(store.pendingLegacyCredentialProfileID == pendingID)

        store.completeLegacyCredentialMigration(for: pendingID)
        #expect(store.pendingLegacyCredentialProfileID == nil)
    }

    @Test
    func apiKeysUseSeparateNonSynchronizingAccounts() throws {
        let keychain = InMemoryPromptOptimizationKeychain()
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )
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
        #expect(keychain.addQueries.allSatisfy {
            $0[kSecAttrService as String] as? String == PromptOptimizationAPIKeyStore.service
        })
        #expect(keychain.addQueries.allSatisfy {
            $0[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        })
    }

    @Test
    func keyAvailabilityDistinguishesQueryFailureFromMissingItem() {
        let keychain = InMemoryPromptOptimizationKeychain()
        keychain.copyStatus = errSecAuthFailed
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        #expect(throws: PromptOptimizationError.keychainUnavailable) {
            try store.containsAPIKey(for: UUID())
        }
    }

    @Test
    func legacyKeyMigrationCopiesThenDeletesAndIsIdempotent() throws {
        let keychain = InMemoryPromptOptimizationKeychain(items: [
            PromptOptimizationAPIKeyStore.legacyAccount: Data("legacy-secret".utf8)
        ])
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )
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
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.migrateLegacyAPIKeyIfNeeded(to: profileID)

        #expect(try store.load(for: profileID) == "new-secret")
        #expect(!keychain.contains(account: PromptOptimizationAPIKeyStore.legacyAccount))
    }

    @Test
    func migrationKeepsAProfileKeyInsertedDuringTheLegacyCopy() throws {
        let profileID = UUID(uuidString: "30000000-0000-0000-0000-000000000005")!
        let account = PromptOptimizationAPIKeyStore.account(for: profileID)
        let keychain = InMemoryPromptOptimizationKeychain(items: [
            PromptOptimizationAPIKeyStore.legacyAccount: Data("legacy-secret".utf8)
        ])
        keychain.itemToInsertBeforeNextAdd = (account, Data("newer-secret".utf8))
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.migrateLegacyAPIKeyIfNeeded(to: profileID)

        #expect(try store.load(for: profileID) == "newer-secret")
        #expect(!keychain.contains(account: PromptOptimizationAPIKeyStore.legacyAccount))
        #expect(keychain.updateQueries.isEmpty)
    }

    @Test
    func failedLegacyCopyKeepsTheMigrationMarkerForRetry() throws {
        let defaults = makeIsolatedDefaults()
        let settingsStore = PromptOptimizationSettingsStore(defaults: defaults)
        _ = settingsStore.load()
        let profileID = try #require(settingsStore.pendingLegacyCredentialProfileID)
        let keychain = InMemoryPromptOptimizationKeychain(items: [
            PromptOptimizationAPIKeyStore.legacyAccount: Data("legacy-secret".utf8)
        ])
        keychain.addStatus = errSecAuthFailed
        let keyStore = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        #expect(throws: PromptOptimizationError.keychainUnavailable) {
            try settingsStore.migrateLegacyAPIKeyIfNeeded(using: keyStore)
        }
        #expect(settingsStore.pendingLegacyCredentialProfileID == profileID)

        keychain.addStatus = errSecSuccess
        try settingsStore.migrateLegacyAPIKeyIfNeeded(using: keyStore)
        #expect(settingsStore.pendingLegacyCredentialProfileID == nil)
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

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "PromptOptimizationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

}

extension PromptOptimizationSettingsTests {
    @Test
    func savingV2SettingsDoesNotRewriteLegacyScalars() {
        let defaults = makeRecoveryIsolatedDefaults()
        let legacyBefore = seedLegacyScalars(in: defaults)
        let store = PromptOptimizationSettingsStore(defaults: defaults)

        store.save(.makeDefault())

        #expect(legacyScalars(in: defaults) == legacyBefore)
    }

    @Test
    func repairsRawV2EmptyProfilesAndRewritesThePersistedSnapshot() throws {
        let defaults = makeRecoveryIsolatedDefaults()
        let legacyBefore = seedLegacyScalars(in: defaults)
        let store = PromptOptimizationSettingsStore(defaults: defaults)
        let rawSettings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [],
            activeRemoteProfileID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            confirmedOrigins: []
        )
        try seedRawV2Snapshot(rawSettings, version: 2, in: defaults)

        let repaired = store.load()
        let persisted = try persistedV2Snapshot(in: defaults)

        #expect(repaired.activeRemoteProfileID == repaired.remoteProfiles.first?.id)
        #expect(repaired.remoteProfiles.count == 1)
        #expect(persisted.version == 2)
        #expect(persisted.settings == repaired)
        #expect(legacyScalars(in: defaults) == legacyBefore)
    }

    @Test
    func repairsRawV2MissingActiveIDWithoutDroppingOtherProfiles() throws {
        let defaults = makeRecoveryIsolatedDefaults()
        let legacyBefore = seedLegacyScalars(in: defaults)
        let store = PromptOptimizationSettingsStore(defaults: defaults)
        let first = PromptOptimizationRemoteProfile.makeDefault(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            preset: .ollama
        )
        let second = PromptOptimizationRemoteProfile.makeDefault(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            preset: .deepSeek
        )
        let rawSettings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [first, second],
            activeRemoteProfileID: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!,
            confirmedOrigins: []
        )
        try seedRawV2Snapshot(rawSettings, version: 2, in: defaults)

        let repaired = store.load()
        let persisted = try persistedV2Snapshot(in: defaults)

        #expect(repaired.activeRemoteProfileID == first.id)
        #expect(repaired.remoteProfiles == [first, second])
        #expect(persisted.version == 2)
        #expect(persisted.settings == repaired)
        #expect(legacyScalars(in: defaults) == legacyBefore)
    }

    @Test
    func unsupportedRawV2VersionFallsBackWithoutReturningPartiallyDecodedSettings() throws {
        let defaults = makeRecoveryIsolatedDefaults()
        let legacyBefore = seedLegacyScalars(in: defaults)
        let store = PromptOptimizationSettingsStore(defaults: defaults)
        let unsupportedProfile = PromptOptimizationRemoteProfile.makeDefault(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000005")!,
            preset: .ollama
        )
        let unsupportedSettings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [unsupportedProfile],
            activeRemoteProfileID: unsupportedProfile.id,
            confirmedOrigins: []
        )
        try seedRawV2Snapshot(unsupportedSettings, version: 3, in: defaults)

        let settings = store.load()
        let persisted = try persistedV2Snapshot(in: defaults)

        #expect(settings.provider == .openAICompatible)
        #expect(settings.remoteProfiles.count == 1)
        #expect(settings.activeRemoteProfile?.preset == .custom)
        #expect(settings.activeRemoteProfile?.baseURL == "https://legacy.example.com/v1")
        #expect(settings.activeRemoteProfile?.model == "legacy-model")
        #expect(settings.activeRemoteProfile?.id != unsupportedProfile.id)
        #expect(persisted.version == 2)
        #expect(persisted.settings == settings)
        #expect(legacyScalars(in: defaults) == legacyBefore)
    }

    @Test
    func malformedV2DataFallsBackAndRewritesThePersistedSnapshot() throws {
        let defaults = makeRecoveryIsolatedDefaults()
        let legacyBefore = seedLegacyScalars(in: defaults)
        defaults.set(
            Data("not-json".utf8),
            forKey: Constants.UserDefaults.promptOptimizationSettingsV2
        )
        let store = PromptOptimizationSettingsStore(defaults: defaults)

        let settings = store.load()
        let persisted = try persistedV2Snapshot(in: defaults)

        #expect(settings.provider == .openAICompatible)
        #expect(settings.remoteProfiles.count == 1)
        #expect(settings.activeRemoteProfile?.preset == .custom)
        #expect(settings.activeRemoteProfile?.baseURL == "https://legacy.example.com/v1")
        #expect(settings.activeRemoteProfile?.model == "legacy-model")
        #expect(persisted.version == 2)
        #expect(persisted.settings == settings)
        #expect(legacyScalars(in: defaults) == legacyBefore)
    }

    @Test
    func malformedV2DataUsesSafeDefaultWhenNoLegacyConfigurationExists() throws {
        let defaults = makeRecoveryIsolatedDefaults()
        defaults.set(
            Data("not-json".utf8),
            forKey: Constants.UserDefaults.promptOptimizationSettingsV2
        )
        let store = PromptOptimizationSettingsStore(defaults: defaults)

        let settings = store.load()
        let persisted = try persistedV2Snapshot(in: defaults)

        #expect(settings.provider == .automaticFree)
        #expect(settings.remoteProfiles.count == 1)
        #expect(settings.activeRemoteProfile?.preset == .openAI)
        #expect(persisted.version == 2)
        #expect(persisted.settings == settings)
    }

    private func makeRecoveryIsolatedDefaults() -> UserDefaults {
        let suiteName = "PromptOptimizationSettingsTests.Recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func seedRawV2Snapshot(
        _ settings: PromptOptimizationSettings,
        version: Int,
        in defaults: UserDefaults
    ) throws {
        let data = try JSONEncoder().encode(RawV2Snapshot(version: version, settings: settings))
        defaults.set(data, forKey: Constants.UserDefaults.promptOptimizationSettingsV2)
    }

    private func persistedV2Snapshot(in defaults: UserDefaults) throws -> RawV2Snapshot {
        let data = try #require(defaults.data(
            forKey: Constants.UserDefaults.promptOptimizationSettingsV2
        ))
        return try JSONDecoder().decode(RawV2Snapshot.self, from: data)
    }

    private func seedLegacyScalars(in defaults: UserDefaults) -> LegacyScalarSnapshot {
        defaults.set(
            PromptOptimizationProviderSelection.openAICompatible.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationProvider
        )
        defaults.set(
            OpenAICompatiblePreset.custom.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationPreset
        )
        defaults.set(
            "https://legacy.example.com/v1",
            forKey: Constants.UserDefaults.promptOptimizationBaseURL
        )
        defaults.set("legacy-model", forKey: Constants.UserDefaults.promptOptimizationModel)
        defaults.set(
            true,
            forKey: Constants.UserDefaults.promptOptimizationAllowsInsecureHTTP
        )
        defaults.set(
            ["https://legacy.example.com"],
            forKey: Constants.UserDefaults.promptOptimizationConfirmedOrigins
        )
        return legacyScalars(in: defaults)
    }

    private func legacyScalars(in defaults: UserDefaults) -> LegacyScalarSnapshot {
        LegacyScalarSnapshot(
            provider: defaults.string(forKey: Constants.UserDefaults.promptOptimizationProvider),
            preset: defaults.string(forKey: Constants.UserDefaults.promptOptimizationPreset),
            baseURL: defaults.string(forKey: Constants.UserDefaults.promptOptimizationBaseURL),
            model: defaults.string(forKey: Constants.UserDefaults.promptOptimizationModel),
            allowsInsecureHTTP: defaults.bool(
                forKey: Constants.UserDefaults.promptOptimizationAllowsInsecureHTTP
            ),
            confirmedOrigins: defaults.stringArray(
                forKey: Constants.UserDefaults.promptOptimizationConfirmedOrigins
            )
        )
    }
}

private struct RawV2Snapshot: Codable, Equatable {
    let version: Int
    let settings: PromptOptimizationSettings
}

private struct LegacyScalarSnapshot: Equatable {
    let provider: String?
    let preset: String?
    let baseURL: String?
    let model: String?
    let allowsInsecureHTTP: Bool
    let confirmedOrigins: [String]?
}

private final class InMemoryPromptOptimizationKeychain: PromptOptimizationKeychainAccessing {
    var addStatus: OSStatus = errSecSuccess
    var copyStatus: OSStatus?
    var deleteStatus: OSStatus = errSecSuccess
    var itemToInsertBeforeNextAdd: (account: String, value: Data)?

    private var items: [String: Data]
    private(set) var copyQueries: [[String: Any]] = []
    private(set) var updateQueries: [[String: Any]] = []
    private(set) var addQueries: [[String: Any]] = []
    private(set) var deleteQueries: [[String: Any]] = []

    init(items: [String: Data] = [:]) {
        self.items = items
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        copyQueries.append(query)
        if let copyStatus {
            return (copyStatus, nil)
        }
        guard let account = account(in: query), let item = items[account] else {
            return (errSecItemNotFound, nil)
        }
        return (errSecSuccess, item as CFTypeRef)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateQueries.append(query)
        guard let account = account(in: query), items[account] != nil else {
            return errSecItemNotFound
        }
        guard let value = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }
        items[account] = value
        return errSecSuccess
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        addQueries.append(attributes)
        guard addStatus == errSecSuccess else { return addStatus }
        guard let account = account(in: attributes),
              let value = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }
        if let itemToInsertBeforeNextAdd {
            items[itemToInsertBeforeNextAdd.account] = itemToInsertBeforeNextAdd.value
            self.itemToInsertBeforeNextAdd = nil
        }
        guard items[account] == nil else { return errSecDuplicateItem }
        items[account] = value
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteQueries.append(query)
        guard deleteStatus == errSecSuccess else { return deleteStatus }
        guard let account = account(in: query), items.removeValue(forKey: account) != nil else {
            return errSecItemNotFound
        }
        return errSecSuccess
    }

    func contains(account: String) -> Bool {
        items[account] != nil
    }

    private func account(in query: [String: Any]) -> String? {
        query[kSecAttrAccount as String] as? String
    }
}
