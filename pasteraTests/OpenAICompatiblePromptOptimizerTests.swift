import Foundation
import Testing
@testable import Pastera

@Suite(.serialized)
struct OpenAICompatiblePromptOptimizerTests {
    @Test
    func rejectsRemoteHTTPUnlessExplicitlyAllowed() {
        let policy = PromptOptimizationEndpointPolicy()

        #expect(throws: PromptOptimizationError.insecureEndpoint) {
            try policy.validate(
                URL(string: "http://192.168.1.8:11434/v1")!,
                allowInsecureHTTP: false
            )
        }
    }

    @Test
    func acceptsLoopbackHTTPAndAppendsChatCompletionsOnce() throws {
        let policy = PromptOptimizationEndpointPolicy()

        let endpoint = try policy.validate(
            URL(string: "http://127.0.0.1:11434/v1")!,
            allowInsecureHTTP: false
        )
        let completeEndpoint = try policy.validate(
            URL(string: "http://localhost:1234/v1/chat/completions")!,
            allowInsecureHTTP: false
        )
        let ipv6Endpoint = try policy.validate(
            URL(string: "http://[::1]:1234/v1")!,
            allowInsecureHTTP: false
        )

        #expect(endpoint.origin == "http://127.0.0.1:11434")
        #expect(endpoint.chatCompletionsURL.absoluteString == "http://127.0.0.1:11434/v1/chat/completions")
        #expect(completeEndpoint.chatCompletionsURL.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(ipv6Endpoint.chatCompletionsURL.absoluteString == "http://[::1]:1234/v1/chat/completions")
    }

    @Test
    func rejectsCredentialsFragmentsAndUnsupportedSchemes() {
        let policy = PromptOptimizationEndpointPolicy()

        #expect(throws: PromptOptimizationError.invalidEndpoint) {
            try policy.validate(
                URL(string: "https://user:pass@example.com/v1")!,
                allowInsecureHTTP: false
            )
        }
        #expect(throws: PromptOptimizationError.invalidEndpoint) {
            try policy.validate(
                URL(string: "https://example.com/v1#fragment")!,
                allowInsecureHTTP: false
            )
        }
        #expect(throws: PromptOptimizationError.invalidEndpoint) {
            try policy.validate(
                URL(string: "ftp://example.com/v1")!,
                allowInsecureHTTP: false
            )
        }
    }

    @Test
    func sendsBearerKeyAndReturnsOnlyAssistantContent() async throws {
        let client = makeClient(
            status: 200,
            body: #"{"choices":[{"message":{"content":"Improved"}}]}"#
        )

        let result = await client.optimize(
            text: "Draft",
            configuration: .fixture,
            apiKey: "key"
        )

        #expect(try result.get() == "Improved")
        #expect(
            PromptOptimizationURLProtocolStub.lastRequest?
                .value(forHTTPHeaderField: "Authorization") == "Bearer key"
        )
        #expect(PromptOptimizationURLProtocolStub.lastRequest?.httpMethod == "POST")
        #expect(
            PromptOptimizationURLProtocolStub.lastRequest?.url?.absoluteString
                == "https://models.example.com/v1/chat/completions"
        )
    }

    @Test
    func rewriteInstructionRequiresContextualTypoCorrection() async throws {
        let client = makeClient(
            status: 200,
            body: #"{"choices":[{"message":{"content":"先帮我把代码分工"}}]}"#
        )

        _ = try await client.optimize(
            text: "先帮我把代码分工翰",
            configuration: .fixture,
            apiKey: ""
        ).get()

        let body = try #require(PromptOptimizationURLProtocolStub.lastRequestBody)
        let payload = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try #require(payload["messages"] as? [[String: Any]])
        let instruction = try #require(messages.first?["content"] as? String)
        #expect(instruction.localizedCaseInsensitiveContains("typo"))
        #expect(instruction.localizedCaseInsensitiveContains("context"))
    }

    @Test
    func connectionProbeUsesFixedTextAndTinyOutputLimit() async throws {
        let client = makeClient(
            status: 200,
            body: #"{"choices":[{"message":{"content":"OK"}}]}"#
        )

        let result = await client.testConnection(
            configuration: .fixture,
            apiKey: "key"
        )

        _ = try result.get()
        let body = try #require(PromptOptimizationURLProtocolStub.lastRequestBody)
        let payload = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(payload["max_tokens"] as? Int == 8)
        let messages = try #require(payload["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "<source_prompt>\nReturn OK\n</source_prompt>")
    }

    @Test
    func mapsHTTPAndResponseFailuresWithoutReturningResponseBodies() async {
        #expect(
            await makeClient(status: 401, body: #"{"secret":"do-not-return"}"#)
                .optimize(text: "Draft", configuration: .fixture, apiKey: "")
                == .failure(.unauthorized)
        )
        #expect(
            await makeClient(status: 429, body: "rate limited")
                .optimize(text: "Draft", configuration: .fixture, apiKey: "")
                == .failure(.rateLimited)
        )
        #expect(
            await makeClient(status: 503, body: "private upstream detail")
                .optimize(text: "Draft", configuration: .fixture, apiKey: "")
                == .failure(.serverRejected(statusCode: 503))
        )
        #expect(
            await makeClient(status: 200, body: "not-json")
                .optimize(text: "Draft", configuration: .fixture, apiKey: "")
                == .failure(.invalidResponse)
        )
        #expect(
            await makeClient(
                status: 200,
                body: #"{"choices":[{"message":{"content":"   "}}]}"#
            )
                .optimize(text: "Draft", configuration: .fixture, apiKey: "")
                == .failure(.invalidResponse)
        )
    }

    @Test
    func serviceRequiresOriginConsentBeforeReadingTheAPIKey() async {
        let defaults = UserDefaults(
            suiteName: "OpenAICompatiblePromptOptimizerTests.\(UUID().uuidString)"
        )!
        let settingsStore = PromptOptimizationSettingsStore(defaults: defaults)
        settingsStore.save(
            PromptOptimizationSettings(
                provider: .openAICompatible,
                remote: .fixture,
                confirmedOrigins: []
            )
        )
        let keyStore = RecordingPromptOptimizationAPIKeyStore()
        let service = PromptOptimizationService(
            settingsStore: settingsStore,
            apiKeyStore: keyStore,
            appleOptimizer: StubUnavailableAppleOptimizer(),
            localFormatter: LocalPromptFormatter(),
            remoteOptimizer: StubRemotePromptOptimizer(result: .success("Improved"))
        )

        #expect(
            await service.optimize("Draft")
                == .consentRequired(origin: "https://models.example.com")
        )
        #expect(keyStore.loadCount == 0)
    }

    private func makeClient(status: Int, body: String) -> OpenAICompatiblePromptOptimizer {
        PromptOptimizationURLProtocolStub.status = status
        PromptOptimizationURLProtocolStub.body = Data(body.utf8)
        PromptOptimizationURLProtocolStub.lastRequest = nil
        PromptOptimizationURLProtocolStub.lastRequestBody = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PromptOptimizationURLProtocolStub.self]
        return OpenAICompatiblePromptOptimizer(session: URLSession(configuration: configuration))
    }
}

private extension PromptOptimizationRemoteConfiguration {
    static let fixture = PromptOptimizationRemoteConfiguration(
        preset: .custom,
        baseURL: "https://models.example.com/v1",
        model: "private-model",
        allowsInsecureHTTP: false
    )
}

private final class PromptOptimizationURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = Self.readBody(from: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }
}

private final class RecordingPromptOptimizationAPIKeyStore: PromptOptimizationAPIKeyStoring {
    var containsAPIKey = true
    private(set) var loadCount = 0

    func save(_ apiKey: String) throws {}

    func load() throws -> String? {
        loadCount += 1
        return "key"
    }

    func delete() throws {}
}

private final class StubUnavailableAppleOptimizer: ApplePromptOptimizing {
    let availability: PromptOptimizationAvailability = .unavailable(.deviceNotEligible)

    func optimize(_ text: String) async throws -> String { text }
}

private final class StubRemotePromptOptimizer: OpenAICompatiblePromptOptimizing {
    let result: Result<String, PromptOptimizationError>

    init(result: Result<String, PromptOptimizationError>) {
        self.result = result
    }

    func optimize(
        text: String,
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String
    ) async -> Result<String, PromptOptimizationError> {
        result
    }
}
