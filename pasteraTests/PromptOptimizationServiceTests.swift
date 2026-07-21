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

private final class StubPromptOptimizationAPIKeyStore: PromptOptimizationAPIKeyStoring {
    var containsAPIKey = false

    func save(_ apiKey: String) throws {}
    func load() throws -> String? { nil }
    func delete() throws {}
}
