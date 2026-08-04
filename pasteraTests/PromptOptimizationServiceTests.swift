import Foundation
import Testing
@testable import Pastera

struct PromptOptimizationServiceTests {
    @Test
    func environmentSharesPromptOptimizationService() {
        let service = RecordingPromptOptimizationService()

        let environment = Environment(promptOptimizationService: service)

        #expect(environment.promptOptimizationService === service)
    }

    @Test
    func defaultEnvironmentBuildsOnePromptOptimizationService() {
        let environment = Environment()

        #expect(environment.promptOptimizationService === environment.promptOptimizationService)
    }

    @Test
    func automaticFreePrefersAvailableAppleModel() async {
        let service = makeService(
            appleAvailability: .available,
            appleResult: .success("Improved prompt")
        )

        #expect(
            await service.optimize("Draft")
                == .optimized(text: "Improved prompt", source: .appleFoundationModel)
        )
    }

    @Test
    func automaticFreeFallsBackWhenAppleModelIsUnavailable() async {
        let service = makeService(
            appleAvailability: .unavailable(.deviceNotEligible),
            appleResult: .success("unused")
        )

        #expect(
            await service.optimize("  Draft\r\n\r\n\r\n")
                == .optimized(text: "Draft", source: .localFormatter)
        )
    }

    @Test
    func automaticFreeReportsLocalFallbackWhenAppleModelIsUnavailable() {
        let service = makeService(
            appleAvailability: .unavailable(.deviceNotEligible),
            appleResult: .success("unused")
        )

        #expect(service.availability == .unavailable(.deviceNotEligible))
    }

    @Test
    func automaticFreeFallsBackAfterAppleFailure() async {
        let service = makeService(
            appleAvailability: .available,
            appleResult: .failure(PromptOptimizationError.requestFailed)
        )

        #expect(
            await service.optimize("Draft   ")
                == .optimized(text: "Draft", source: .localFormatter)
        )
    }

    @Test
    func cancellationDoesNotRunFallback() async {
        let apple = StubApplePromptOptimizer(
            availability: .available,
            result: .failure(CancellationError())
        )
        let formatter = RecordingLocalPromptFormatter(result: "fallback")
        let service = makeService(apple: apple, formatter: formatter)

        #expect(await service.optimize("Draft") == .failed(.cancelled))
        #expect(formatter.receivedText == nil)
    }

    @Test
    func rejectsBlankAndOversizedInputBeforeSelectingAnEngine() async {
        let apple = StubApplePromptOptimizer(
            availability: .available,
            result: .success("unused")
        )
        let formatter = RecordingLocalPromptFormatter(result: "unused")
        let service = makeService(apple: apple, formatter: formatter)

        #expect(await service.optimize(" \n ") == .failed(.emptyInput))
        #expect(
            await service.optimize(
                String(repeating: "x", count: PromptOptimizationService.maximumInputCharacters + 1)
            ) == .failed(
                .inputTooLong(maxCharacters: PromptOptimizationService.maximumInputCharacters)
            )
        )
        #expect(apple.receivedText == nil)
        #expect(formatter.receivedText == nil)
    }

    @Test
    func unchangedAppleOutputDoesNotReplaceTheDraft() async {
        let service = makeService(
            appleAvailability: .available,
            appleResult: .success(" Draft ")
        )

        #expect(await service.optimize("Draft") == .unchanged(source: .appleFoundationModel))
    }

    @Test
    func localFormatterPreservesCodeFencesURLsAndPlaceholders() {
        let formatter = LocalPromptFormatter()
        let source = "Use {{name}} at https://example.com  \n```swift\nlet x = 1  \n```"

        let result = formatter.format(source)

        #expect(result.contains("{{name}}"))
        #expect(result.contains("https://example.com"))
        #expect(result.contains("```swift\nlet x = 1  \n```"))
        #expect(result.hasPrefix("Use {{name}} at https://example.com\n"))
    }

    @Test
    func localFormatterNormalizesLineEndingsAndConsecutiveBlankLines() {
        let formatter = LocalPromptFormatter()

        #expect(formatter.format("  First  \r\n\r\n\r\n\r\nSecond  ") == "First\n\n\nSecond")
    }

    @Test
    func localFormatterCorrectsConfirmedChineseContextualTypo() {
        let formatter = LocalPromptFormatter()

        #expect(formatter.format("先帮我把代码分工翰") == "先帮我把代码分功能")
    }

    @Test
    func localFormatterDoesNotCorrectTextInsideCodeFence() {
        let formatter = LocalPromptFormatter()
        let source = "请修正先帮我把代码分工翰\n```\n先帮我把代码分工翰\n```"

        #expect(
            formatter.format(source)
                == "请修正先帮我把代码分功能\n```\n先帮我把代码分工翰\n```"
        )
    }

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
        let keyStore = StubPromptOptimizationAPIKeyStore()
        let service = makeRemoteService(
            settings: settings,
            keyStore: keyStore,
            remote: RecordingRemotePromptOptimizer(result: .success("OK")),
            pendingLegacyCredentialProfileID: settings.activeRemoteProfileID
        )

        let result = await service.testRemoteConnection()

        if case let .failure(error) = result {
            #expect(error == .originNotConfirmed(origin: "https://api.openai.com"))
        } else {
            Issue.record("Expected the unconfirmed origin to prevent the connection test.")
        }
        #expect(keyStore.migratedProfileIDs.isEmpty)
        #expect(keyStore.loadedProfileIDs.isEmpty)
    }

    @Test
    func remoteProfileWithoutAKeyDoesNotCallTheOptimizer() async {
        let profile = PromptOptimizationRemoteProfile.makeDefault(preset: .openAI)
        let settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [profile],
            activeRemoteProfileID: profile.id,
            confirmedOrigins: ["https://api.openai.com"]
        )
        let remote = RecordingRemotePromptOptimizer(result: .success("Improved"))
        let service = makeRemoteService(
            settings: settings,
            keyStore: StubPromptOptimizationAPIKeyStore(),
            remote: remote
        )

        #expect(await service.optimize("Draft") == .failed(.missingAPIKey))
        #expect(remote.configurations.isEmpty)
    }

    @Test
    func remoteConnectionWithoutAKeyDoesNotCallTheOptimizer() async {
        let profile = PromptOptimizationRemoteProfile.makeDefault(preset: .openAI)
        let settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [profile],
            activeRemoteProfileID: profile.id,
            confirmedOrigins: ["https://api.openai.com"]
        )
        let remote = RecordingRemotePromptOptimizer(result: .success("OK"))
        let service = makeRemoteService(
            settings: settings,
            keyStore: StubPromptOptimizationAPIKeyStore(),
            remote: remote
        )

        let result = await service.testRemoteConnection()

        if case let .failure(error) = result {
            #expect(error == .missingAPIKey)
        } else {
            Issue.record("Expected the missing remote credential to prevent the connection test.")
        }
        #expect(remote.configurations.isEmpty)
    }

    @Test
    func ollamaProfileWithoutAKeyCallsTheOptimizer() async {
        let profile = PromptOptimizationRemoteProfile.makeDefault(preset: .ollama)
        let settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remoteProfiles: [profile],
            activeRemoteProfileID: profile.id,
            confirmedOrigins: ["http://127.0.0.1:11434"]
        )
        let remote = RecordingRemotePromptOptimizer(result: .success("Improved"))
        let service = makeRemoteService(
            settings: settings,
            keyStore: StubPromptOptimizationAPIKeyStore(),
            remote: remote
        )

        #expect(
            await service.optimize("Draft")
                == .optimized(text: "Improved", source: .openAICompatible)
        )
        #expect(remote.configurations.map(\.preset) == [.ollama])
        #expect(remote.apiKeys == [""])
    }

    private func makeService(
        appleAvailability: PromptOptimizationAvailability,
        appleResult: Result<String, Error>
    ) -> PromptOptimizationService {
        makeService(
            apple: StubApplePromptOptimizer(
                availability: appleAvailability,
                result: appleResult
            ),
            formatter: RecordingLocalPromptFormatter(result: "Draft")
        )
    }

    private func makeService(
        apple: ApplePromptOptimizing,
        formatter: LocalPromptFormatting
    ) -> PromptOptimizationService {
        let defaults = UserDefaults(
            suiteName: "PromptOptimizationServiceTests.\(UUID().uuidString)"
        )!
        let settingsStore = PromptOptimizationSettingsStore(defaults: defaults)
        settingsStore.save(.defaultValue)
        return PromptOptimizationService(
            settingsStore: settingsStore,
            apiKeyStore: StubPromptOptimizationAPIKeyStore(),
            appleOptimizer: apple,
            localFormatter: formatter
        )
    }

    private func makeRemoteService(
        settings: PromptOptimizationSettings,
        keyStore: StubPromptOptimizationAPIKeyStore,
        remote: RecordingRemotePromptOptimizer,
        pendingLegacyCredentialProfileID: UUID? = nil
    ) -> PromptOptimizationService {
        PromptOptimizationService(
            settingsStore: StubPromptOptimizationSettingsStore(
                settings: settings,
                pendingLegacyCredentialProfileID: pendingLegacyCredentialProfileID
            ),
            apiKeyStore: keyStore,
            appleOptimizer: StubApplePromptOptimizer(
                availability: .unavailable(.deviceNotEligible),
                result: .success("unused")
            ),
            localFormatter: RecordingLocalPromptFormatter(result: "unused"),
            remoteOptimizer: remote
        )
    }
}

private final class RecordingPromptOptimizationService: PromptOptimizationServicing {
    var availability: PromptOptimizationAvailability = .available

    func optimize(_ text: String) async -> PromptOptimizationOutcome {
        .unchanged(source: .localFormatter)
    }

    func confirmRemoteOrigin(_ origin: String) {}

    func testRemoteConnection() async -> Result<Void, PromptOptimizationError> {
        .success(())
    }
}

private final class StubApplePromptOptimizer: ApplePromptOptimizing {
    let availability: PromptOptimizationAvailability
    let result: Result<String, Error>
    private(set) var receivedText: String?

    init(availability: PromptOptimizationAvailability, result: Result<String, Error>) {
        self.availability = availability
        self.result = result
    }

    func optimize(_ text: String) async throws -> String {
        receivedText = text
        return try result.get()
    }
}

private final class RecordingLocalPromptFormatter: LocalPromptFormatting {
    let result: String
    private(set) var receivedText: String?

    init(result: String) {
        self.result = result
    }

    func format(_ text: String) -> String {
        receivedText = text
        return result
    }
}

private final class StubPromptOptimizationSettingsStore: PromptOptimizationSettingsStoring {
    private var settings: PromptOptimizationSettings
    let pendingLegacyCredentialProfileID: UUID?

    init(
        settings: PromptOptimizationSettings,
        pendingLegacyCredentialProfileID: UUID? = nil
    ) {
        self.settings = settings
        self.pendingLegacyCredentialProfileID = pendingLegacyCredentialProfileID
    }

    func load() -> PromptOptimizationSettings { settings }
    func save(_ settings: PromptOptimizationSettings) { self.settings = settings }

    func confirmRemoteOrigin(_ origin: String) {
        settings.confirmedOrigins.insert(origin)
    }

    func completeLegacyCredentialMigration(for profileID: UUID) {}
}

private final class StubPromptOptimizationAPIKeyStore: PromptOptimizationAPIKeyStoring {
    private var apiKeys: [UUID: String]
    private(set) var loadedProfileIDs: [UUID] = []
    private(set) var migratedProfileIDs: [UUID] = []

    init(values: [UUID: String] = [:]) {
        apiKeys = values
    }

    func containsAPIKey(for profileID: UUID) -> Bool { apiKeys[profileID] != nil }
    func save(_ apiKey: String, for profileID: UUID) throws { apiKeys[profileID] = apiKey }
    func load(for profileID: UUID) throws -> String? {
        loadedProfileIDs.append(profileID)
        return apiKeys[profileID]
    }
    func delete(for profileID: UUID) throws { apiKeys[profileID] = nil }
    func migrateLegacyAPIKeyIfNeeded(to profileID: UUID) throws {
        migratedProfileIDs.append(profileID)
    }
}

private final class RecordingRemotePromptOptimizer: OpenAICompatiblePromptOptimizing {
    let result: Result<String, PromptOptimizationError>
    private(set) var configurations: [PromptOptimizationRemoteConfiguration] = []
    private(set) var apiKeys: [String] = []

    init(result: Result<String, PromptOptimizationError>) {
        self.result = result
    }

    func optimize(
        text: String,
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String
    ) async -> Result<String, PromptOptimizationError> {
        configurations.append(configuration)
        apiKeys.append(apiKey)
        return result
    }
}
