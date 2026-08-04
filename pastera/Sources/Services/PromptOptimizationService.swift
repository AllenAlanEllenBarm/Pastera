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
        switch settingsStore.load().provider {
        case .automaticFree:
            return appleOptimizer.availability
        case .openAICompatible:
            let settings = settingsStore.load()
            guard !settings.remote.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (try? endpointPolicy.validate(settings.remote)) != nil else {
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

        switch settingsStore.load().provider {
        case .automaticFree:
            return await optimizeAutomatically(text)
        case .openAICompatible:
            return await optimizeRemotely(text)
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
        do {
            try settingsStore.migrateLegacyAPIKeyIfNeeded(using: apiKeyStore)
        } catch {
            return .failure(.keychainUnavailable)
        }
        let endpoint: PromptOptimizationEndpoint
        do {
            endpoint = try endpointPolicy.validate(settings.remote)
        } catch let error as PromptOptimizationError {
            return .failure(error)
        } catch {
            return .failure(.invalidEndpoint)
        }
        guard settings.confirmedOrigins.contains(endpoint.origin) else {
            return .failure(.originNotConfirmed(origin: endpoint.origin))
        }
        let apiKey: String
        do {
            apiKey = try apiKeyStore.load(for: settings.activeRemoteProfileID) ?? ""
        } catch {
            return .failure(.keychainUnavailable)
        }
        return await remoteOptimizer.testConnection(
            configuration: settings.remote,
            apiKey: apiKey
        )
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

    private func optimizeRemotely(_ text: String) async -> PromptOptimizationOutcome {
        let settings = settingsStore.load()
        do {
            try settingsStore.migrateLegacyAPIKeyIfNeeded(using: apiKeyStore)
        } catch {
            return .failed(.keychainUnavailable)
        }
        guard !settings.remote.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed(.missingModel)
        }
        let endpoint: PromptOptimizationEndpoint
        do {
            endpoint = try endpointPolicy.validate(settings.remote)
        } catch let error as PromptOptimizationError {
            return .failed(error)
        } catch {
            return .failed(.invalidEndpoint)
        }
        guard settings.confirmedOrigins.contains(endpoint.origin) else {
            return .consentRequired(origin: endpoint.origin)
        }
        let apiKey: String
        do {
            apiKey = try apiKeyStore.load(for: settings.activeRemoteProfileID) ?? ""
        } catch {
            return .failed(.keychainUnavailable)
        }
        let result = await remoteOptimizer.optimize(
            text: text,
            configuration: settings.remote,
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
}
