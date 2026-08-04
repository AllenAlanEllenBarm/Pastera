import Foundation

final class PromptOptimizationService: PromptOptimizationServicing {
    static let maximumInputCharacters = 32_000
    static let maximumOutputCharacters = 64_000

    private let settingsStore: PromptOptimizationSettingsStoring
    private let apiKeyStore: PromptOptimizationAPIKeyStoring
    private let appleOptimizer: ApplePromptOptimizing
    private let localFormatter: LocalPromptFormatting
    private let endpointPolicy: PromptOptimizationEndpointPolicy
    private let remoteOptimizer: OpenAICompatiblePromptOptimizing

    init(
        settingsStore: PromptOptimizationSettingsStoring,
        apiKeyStore: PromptOptimizationAPIKeyStoring,
        appleOptimizer: ApplePromptOptimizing = ApplePromptOptimizerFactory.make(),
        localFormatter: LocalPromptFormatting = LocalPromptFormatter(),
        endpointPolicy: PromptOptimizationEndpointPolicy = PromptOptimizationEndpointPolicy(),
        remoteOptimizer: OpenAICompatiblePromptOptimizing = OpenAICompatiblePromptOptimizer()
    ) {
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.appleOptimizer = appleOptimizer
        self.localFormatter = localFormatter
        self.endpointPolicy = endpointPolicy
        self.remoteOptimizer = remoteOptimizer
    }

    var availability: PromptOptimizationAvailability {
        let settings = settingsStore.load()
        switch settings.provider {
        case .automaticFree:
            return appleOptimizer.availability
        case .openAICompatible:
            guard (try? activeRemoteContext(from: settings)) != nil else {
                return .unavailable(.remoteNotConfigured)
            }
            return .available
        }
    }

    func optimize(_ text: String) async -> PromptOptimizationOutcome {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .failed(.emptyInput) }
        guard text.count <= Self.maximumInputCharacters else {
            return .failed(.inputTooLong(maxCharacters: Self.maximumInputCharacters))
        }

        let settings = settingsStore.load()
        switch settings.provider {
        case .automaticFree:
            return await optimizeAutomatically(text)
        case .openAICompatible:
            return await optimizeRemotely(text, settings: settings)
        }
    }

    func confirmRemoteOrigin(_ origin: String) {
        settingsStore.confirmRemoteOrigin(origin)
    }

    func testRemoteConnection() async -> Result<Void, PromptOptimizationError> {
        let settings = settingsStore.load()
        guard settings.provider == .openAICompatible else {
            return .failure(.unavailable(.remoteNotConfigured))
        }
        let context: ActiveRemoteContext
        do {
            context = try activeRemoteContext(from: settings)
        } catch let error as PromptOptimizationError {
            return .failure(error)
        } catch {
            return .failure(.invalidEndpoint)
        }
        guard settings.confirmedOrigins.contains(context.endpoint.origin) else {
            return .failure(.originNotConfirmed(origin: context.endpoint.origin))
        }
        let apiKeyResult = loadRemoteAPIKey(for: context.profile)
        switch apiKeyResult {
        case let .success(apiKey):
            return await remoteOptimizer.testConnection(
                configuration: context.profile.configuration,
                apiKey: apiKey
            )
        case let .failure(error):
            return .failure(error)
        }
    }

    private func optimizeAutomatically(_ text: String) async -> PromptOptimizationOutcome {
        if case .available = appleOptimizer.availability {
            do {
                try Task.checkCancellation()
                let output = try await appleOptimizer.optimize(text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard !output.isEmpty else { return fallbackToLocalFormatter(text) }
                guard output.count <= Self.maximumOutputCharacters else {
                    return fallbackToLocalFormatter(text)
                }
                if output == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return .unchanged(source: .appleFoundationModel)
                }
                return .optimized(text: output, source: .appleFoundationModel)
            } catch is CancellationError {
                return .failed(.cancelled)
            } catch {
                if Task.isCancelled { return .failed(.cancelled) }
            }
        }
        return fallbackToLocalFormatter(text)
    }

    private func fallbackToLocalFormatter(_ text: String) -> PromptOptimizationOutcome {
        let output = localFormatter.format(text)
        guard !output.isEmpty else { return .failed(.invalidResponse) }
        guard output.count <= Self.maximumOutputCharacters else {
            return .failed(.outputTooLong(maxCharacters: Self.maximumOutputCharacters))
        }
        if output == text {
            return .unchanged(source: .localFormatter)
        }
        return .optimized(text: output, source: .localFormatter)
    }

    private func optimizeRemotely(
        _ text: String,
        settings: PromptOptimizationSettings
    ) async -> PromptOptimizationOutcome {
        let context: ActiveRemoteContext
        do {
            context = try activeRemoteContext(from: settings)
        } catch let error as PromptOptimizationError {
            return .failed(error)
        } catch {
            return .failed(.invalidEndpoint)
        }
        guard settings.confirmedOrigins.contains(context.endpoint.origin) else {
            return .consentRequired(origin: context.endpoint.origin)
        }
        let apiKeyResult = loadRemoteAPIKey(for: context.profile)
        let apiKey: String
        switch apiKeyResult {
        case let .success(value):
            apiKey = value
        case let .failure(error):
            return .failed(error)
        }
        let result = await remoteOptimizer.optimize(
            text: text,
            configuration: context.profile.configuration,
            apiKey: apiKey
        )
        switch result {
        case let .success(output):
            if output == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                return .unchanged(source: .openAICompatible)
            }
            return .optimized(text: output, source: .openAICompatible)
        case let .failure(error):
            return .failed(error)
        }
    }

    private struct ActiveRemoteContext {
        let profile: PromptOptimizationRemoteProfile
        let endpoint: PromptOptimizationEndpoint
    }

    private func activeRemoteContext(
        from settings: PromptOptimizationSettings
    ) throws -> ActiveRemoteContext {
        guard let profile = settings.activeRemoteProfile,
              !profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptOptimizationError.missingModel
        }
        return ActiveRemoteContext(
            profile: profile,
            endpoint: try endpointPolicy.validate(profile.configuration)
        )
    }

    private func loadRemoteAPIKey(
        for profile: PromptOptimizationRemoteProfile
    ) -> Result<String, PromptOptimizationError> {
        do {
            try settingsStore.migrateLegacyAPIKeyIfNeeded(using: apiKeyStore)
            let apiKey = try apiKeyStore.load(for: profile.id) ?? ""
            guard !apiKey.isEmpty || profile.preset == .ollama || profile.preset == .lmStudio else {
                return .failure(.missingAPIKey)
            }
            return .success(apiKey)
        } catch {
            return .failure(.keychainUnavailable)
        }
    }
}
