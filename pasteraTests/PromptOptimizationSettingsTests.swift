import Foundation
import Security
import Testing
@testable import Pastera

struct PromptOptimizationSettingsTests {
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
        let settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remote: PromptOptimizationRemoteConfiguration(
                preset: .custom,
                baseURL: "https://models.example.com/v1",
                model: "private-model",
                allowsInsecureHTTP: false
            ),
            confirmedOrigins: ["https://models.example.com"]
        )

        store.save(settings)

        let loaded = store.load()
        #expect(loaded.provider == settings.provider)
        #expect(loaded.remote == settings.remote)
        #expect(loaded.confirmedOrigins == settings.confirmedOrigins)
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
        defaults.set(
            Data("not-json".utf8),
            forKey: Constants.UserDefaults.promptOptimizationSettingsV2
        )
        let store = PromptOptimizationSettingsStore(defaults: defaults)

        let settings = store.load()

        #expect(settings.provider == .automaticFree)
        #expect(settings.remoteProfiles.count == 1)
        #expect(settings.activeRemoteProfile?.preset == .openAI)
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
    func apiKeyUsesDedicatedNonSynchronizingKeychainItem() throws {
        let keychain = RecordingPromptOptimizationKeychain()
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.save("secret")

        #expect(keychain.lastAddQuery?[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(
            keychain.lastAddQuery?[kSecAttrService as String] as? String
                == PromptOptimizationAPIKeyStore.service
        )
        #expect(
            PromptOptimizationAPIKeyStore.service
                == "com.pastera-app.Pastera.prompt-optimization.v1"
        )
        #expect(
            keychain.lastAddQuery?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    @Test
    func apiKeyUpdatesLoadsAndDeletesWithoutSynchronizing() throws {
        let keychain = RecordingPromptOptimizationKeychain()
        keychain.updateStatus = errSecSuccess
        keychain.copyResult = (errSecSuccess, Data("stored".utf8) as CFTypeRef)
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.save("replacement")
        #expect(try store.load() == "stored")
        try store.delete()

        #expect(keychain.lastUpdateQuery?[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(keychain.lastCopyQuery?[kSecReturnData as String] as? Bool == true)
        #expect(keychain.lastDeleteQuery?[kSecAttrSynchronizable as String] as? Bool == false)
    }

    @Test
    func emptyAPIKeyInputDoesNotDeleteExistingCredential() throws {
        let keychain = RecordingPromptOptimizationKeychain()
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.save("   ")

        #expect(keychain.lastAddQuery == nil)
        #expect(keychain.lastUpdateQuery == nil)
        #expect(keychain.lastDeleteQuery == nil)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "PromptOptimizationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class RecordingPromptOptimizationKeychain: PromptOptimizationKeychainAccessing {
    var updateStatus: OSStatus = errSecItemNotFound
    var addStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess
    var copyResult: (OSStatus, CFTypeRef?) = (errSecItemNotFound, nil)

    private(set) var lastCopyQuery: [String: Any]?
    private(set) var lastUpdateQuery: [String: Any]?
    private(set) var lastUpdateAttributes: [String: Any]?
    private(set) var lastAddQuery: [String: Any]?
    private(set) var lastDeleteQuery: [String: Any]?

    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lastCopyQuery = query
        return copyResult
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lastUpdateQuery = query
        lastUpdateAttributes = attributes
        return updateStatus
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lastAddQuery = attributes
        return addStatus
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lastDeleteQuery = query
        return deleteStatus
    }
}
