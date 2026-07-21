import Foundation

enum PromptOptimizationProviderSelection: String, Codable, CaseIterable, Sendable {
    case automaticFree
    case openAICompatible
}

enum OpenAICompatiblePreset: String, Codable, CaseIterable, Sendable {
    case openAI
    case gemini
    case ollama
    case lmStudio
    case custom

    static let presetBaseURLs: [OpenAICompatiblePreset: String] = [
        .openAI: "https://api.openai.com/v1",
        .gemini: "https://generativelanguage.googleapis.com/v1beta/openai",
        .ollama: "http://127.0.0.1:11434/v1",
        .lmStudio: "http://127.0.0.1:1234/v1"
    ]
}

struct PromptOptimizationRemoteConfiguration: Codable, Equatable, Sendable {
    var preset: OpenAICompatiblePreset
    var baseURL: String
    var model: String
    var allowsInsecureHTTP: Bool

    static let empty = PromptOptimizationRemoteConfiguration(
        preset: .openAI,
        baseURL: "",
        model: "",
        allowsInsecureHTTP: false
    )
}

struct PromptOptimizationSettings: Codable, Equatable, Sendable {
    var provider: PromptOptimizationProviderSelection
    var remote: PromptOptimizationRemoteConfiguration
    var confirmedOrigins: Set<String>

    static let defaultValue = PromptOptimizationSettings(
        provider: .automaticFree,
        remote: .empty,
        confirmedOrigins: []
    )
}

enum PromptOptimizationSource: Equatable, Sendable {
    case appleFoundationModel
    case localFormatter
    case openAICompatible
}

enum PromptOptimizationUnavailabilityReason: Equatable, Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case remoteNotConfigured
}

enum PromptOptimizationAvailability: Equatable, Sendable {
    case available
    case unavailable(PromptOptimizationUnavailabilityReason)
}

enum PromptOptimizationError: Error, Equatable, Sendable {
    case emptyInput
    case inputTooLong(maxCharacters: Int)
    case outputTooLong(maxCharacters: Int)
    case cancelled
    case unavailable(PromptOptimizationUnavailabilityReason)
    case missingAPIKey
    case missingModel
    case invalidEndpoint
    case insecureEndpoint
    case originNotConfirmed(origin: String)
    case unauthorized
    case rateLimited
    case requestTimedOut
    case requestFailed
    case invalidResponse
    case serverRejected(statusCode: Int)
    case keychainUnavailable
}

enum PromptOptimizationOutcome: Equatable, Sendable {
    case optimized(text: String, source: PromptOptimizationSource)
    case unchanged(source: PromptOptimizationSource)
    case consentRequired(origin: String)
    case failed(PromptOptimizationError)
}

protocol PromptOptimizationServicing: AnyObject {
    var availability: PromptOptimizationAvailability { get }

    func optimize(_ text: String) async -> PromptOptimizationOutcome
    func confirmRemoteOrigin(_ origin: String)
    func testRemoteConnection() async -> Result<Void, PromptOptimizationError>
}
