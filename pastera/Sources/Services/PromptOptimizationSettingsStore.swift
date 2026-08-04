import Foundation

protocol PromptOptimizationSettingsStoring: AnyObject {
    var pendingLegacyCredentialProfileID: UUID? { get }

    func load() -> PromptOptimizationSettings
    func save(_ settings: PromptOptimizationSettings)
    func confirmRemoteOrigin(_ origin: String)
    func completeLegacyCredentialMigration(for profileID: UUID)
}

final class PromptOptimizationSettingsStore: PromptOptimizationSettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    var pendingLegacyCredentialProfileID: UUID? {
        UUID(uuidString: defaults.string(
            forKey: Constants.UserDefaults.promptOptimizationLegacyCredentialProfileID
        ) ?? "")
    }

    func load() -> PromptOptimizationSettings {
        guard let stored = loadStoredSettings(), stored.version == StoredPromptOptimizationSettings.currentVersion else {
            return migrateLegacySettings()
        }
        var settings = stored.settings
        let originalSettings = settings
        settings.repairActiveRemoteProfile()
        if settings != originalSettings {
            save(settings)
        }
        return settings
    }

    func save(_ settings: PromptOptimizationSettings) {
        var repairedSettings = settings
        repairedSettings.repairActiveRemoteProfile()
        guard let data = try? JSONEncoder().encode(StoredPromptOptimizationSettings(settings: repairedSettings)) else {
            return
        }
        defaults.set(data, forKey: Constants.UserDefaults.promptOptimizationSettingsV2)
    }

    func confirmRemoteOrigin(_ origin: String) {
        guard !origin.isEmpty else { return }
        var settings = load()
        settings.confirmedOrigins.insert(origin)
        save(settings)
    }

    func completeLegacyCredentialMigration(for profileID: UUID) {
        guard pendingLegacyCredentialProfileID == profileID else { return }
        defaults.removeObject(forKey: Constants.UserDefaults.promptOptimizationLegacyCredentialProfileID)
    }

    private func loadStoredSettings() -> StoredPromptOptimizationSettings? {
        guard let data = defaults.data(forKey: Constants.UserDefaults.promptOptimizationSettingsV2) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredPromptOptimizationSettings.self, from: data)
    }

    private func migrateLegacySettings() -> PromptOptimizationSettings {
        let legacySettings = legacySettings()
        let settings: PromptOptimizationSettings
        if legacySettings == Self.defaultLegacySettings {
            settings = .makeDefault()
        } else {
            let profile = PromptOptimizationRemoteProfile(
                id: UUID(),
                displayName: legacySettings.remote.preset.defaultProfileName,
                preset: legacySettings.remote.preset,
                baseURL: legacySettings.remote.baseURL,
                model: legacySettings.remote.model,
                allowsInsecureHTTP: legacySettings.remote.allowsInsecureHTTP
            )
            settings = PromptOptimizationSettings(
                provider: legacySettings.provider,
                remoteProfiles: [profile],
                activeRemoteProfileID: profile.id,
                confirmedOrigins: legacySettings.confirmedOrigins
            )
        }
        defaults.set(
            settings.activeRemoteProfileID.uuidString,
            forKey: Constants.UserDefaults.promptOptimizationLegacyCredentialProfileID
        )
        save(settings)
        return settings
    }

    private func legacySettings() -> LegacyPromptOptimizationSettings {
        let provider = PromptOptimizationProviderSelection(
            rawValue: defaults.string(forKey: Constants.UserDefaults.promptOptimizationProvider) ?? ""
        ) ?? .automaticFree
        let preset = OpenAICompatiblePreset(
            rawValue: defaults.string(forKey: Constants.UserDefaults.promptOptimizationPreset) ?? ""
        ) ?? .openAI
        return LegacyPromptOptimizationSettings(
            provider: provider,
            remote: PromptOptimizationRemoteConfiguration(
                preset: preset,
                baseURL: defaults.string(forKey: Constants.UserDefaults.promptOptimizationBaseURL) ?? "",
                model: defaults.string(forKey: Constants.UserDefaults.promptOptimizationModel) ?? "",
                allowsInsecureHTTP: defaults.bool(
                    forKey: Constants.UserDefaults.promptOptimizationAllowsInsecureHTTP
                )
            ),
            confirmedOrigins: Set(defaults.stringArray(
                forKey: Constants.UserDefaults.promptOptimizationConfirmedOrigins
            ) ?? [])
        )
    }

    private static let defaultLegacySettings = LegacyPromptOptimizationSettings(
        provider: .automaticFree,
        remote: .empty,
        confirmedOrigins: []
    )
}

private struct StoredPromptOptimizationSettings: Codable {
    static let currentVersion = 2

    let version: Int
    let settings: PromptOptimizationSettings

    init(settings: PromptOptimizationSettings) {
        self.version = Self.currentVersion
        self.settings = settings
    }
}

private struct LegacyPromptOptimizationSettings: Equatable {
    let provider: PromptOptimizationProviderSelection
    let remote: PromptOptimizationRemoteConfiguration
    let confirmedOrigins: Set<String>
}
