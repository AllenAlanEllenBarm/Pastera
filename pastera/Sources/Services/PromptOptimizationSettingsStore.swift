import Foundation

protocol PromptOptimizationSettingsStoring: AnyObject {
    func load() -> PromptOptimizationSettings
    func save(_ settings: PromptOptimizationSettings)
    func confirmRemoteOrigin(_ origin: String)
}

final class PromptOptimizationSettingsStore: PromptOptimizationSettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func load() -> PromptOptimizationSettings {
        let provider = PromptOptimizationProviderSelection(
            rawValue: defaults.string(forKey: Constants.UserDefaults.promptOptimizationProvider) ?? ""
        ) ?? .automaticFree
        let preset = OpenAICompatiblePreset(
            rawValue: defaults.string(forKey: Constants.UserDefaults.promptOptimizationPreset) ?? ""
        ) ?? .openAI
        let remote = PromptOptimizationRemoteConfiguration(
            preset: preset,
            baseURL: defaults.string(forKey: Constants.UserDefaults.promptOptimizationBaseURL) ?? "",
            model: defaults.string(forKey: Constants.UserDefaults.promptOptimizationModel) ?? "",
            allowsInsecureHTTP: defaults.bool(
                forKey: Constants.UserDefaults.promptOptimizationAllowsInsecureHTTP
            )
        )
        let origins = defaults.stringArray(
            forKey: Constants.UserDefaults.promptOptimizationConfirmedOrigins
        ) ?? []
        return PromptOptimizationSettings(
            provider: provider,
            remote: remote,
            confirmedOrigins: Set(origins)
        )
    }

    func save(_ settings: PromptOptimizationSettings) {
        defaults.set(
            settings.provider.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationProvider
        )
        defaults.set(
            settings.remote.preset.rawValue,
            forKey: Constants.UserDefaults.promptOptimizationPreset
        )
        defaults.set(
            settings.remote.baseURL,
            forKey: Constants.UserDefaults.promptOptimizationBaseURL
        )
        defaults.set(
            settings.remote.model,
            forKey: Constants.UserDefaults.promptOptimizationModel
        )
        defaults.set(
            settings.remote.allowsInsecureHTTP,
            forKey: Constants.UserDefaults.promptOptimizationAllowsInsecureHTTP
        )
        defaults.set(
            settings.confirmedOrigins.sorted(),
            forKey: Constants.UserDefaults.promptOptimizationConfirmedOrigins
        )
    }

    func confirmRemoteOrigin(_ origin: String) {
        guard !origin.isEmpty else { return }
        var settings = load()
        settings.confirmedOrigins.insert(origin)
        save(settings)
    }
}
