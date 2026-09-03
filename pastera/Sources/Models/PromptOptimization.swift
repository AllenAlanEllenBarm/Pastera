import Foundation

enum PromptOptimizationProviderSelection: String, Codable, CaseIterable, Sendable {
    case automaticFree
    case openAICompatible
}

enum OpenAICompatiblePreset: String, Codable, CaseIterable, Sendable {
    case openAI
    case deepSeek
    case gemini
    case ollama
    case lmStudio
    case custom

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .ollama: "http://127.0.0.1:11434/v1"
        case .lmStudio: "http://127.0.0.1:1234/v1"
        case .custom: ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5.6-luna"
        case .deepSeek: "deepseek-v4-flash"
        case .ollama: "qwen3.5:4b"
        case .gemini, .lmStudio, .custom: ""
        }
    }

    var defaultProfileName: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .gemini: "Gemini"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .custom: "Custom"
        }
    }

    var disablesThinking: Bool { self == .deepSeek }
    var disablesReasoning: Bool { self == .ollama }

    static let presetBaseURLs: [OpenAICompatiblePreset: String] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.defaultBaseURL) }
    )
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

struct PromptOptimizationRemoteProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var preset: OpenAICompatiblePreset
    var baseURL: String
    var model: String
    var allowsInsecureHTTP: Bool

    var configuration: PromptOptimizationRemoteConfiguration {
        PromptOptimizationRemoteConfiguration(
            preset: preset,
            baseURL: baseURL,
            model: model,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
    }

    static func makeDefault(
        id: UUID = UUID(),
        preset: OpenAICompatiblePreset = .openAI,
        displayName: String? = nil
    ) -> Self {
        Self(
            id: id,
            displayName: displayName ?? preset.defaultProfileName,
            preset: preset,
            baseURL: preset.defaultBaseURL,
            model: preset.defaultModel,
            allowsInsecureHTTP: false
        )
    }
}

struct PromptOptimizationSettings: Codable, Equatable, Sendable {
    var provider: PromptOptimizationProviderSelection
    var remoteProfiles: [PromptOptimizationRemoteProfile]
    var activeRemoteProfileID: UUID
    var confirmedOrigins: Set<String>

    var activeRemoteProfile: PromptOptimizationRemoteProfile? {
        remoteProfiles.first { $0.id == activeRemoteProfileID }
    }

    static var defaultValue: Self { makeDefault() }

    static func makeDefault(profileID: UUID = UUID()) -> Self {
        Self(
            provider: .automaticFree,
            remoteProfiles: [.makeDefault(id: profileID)],
            activeRemoteProfileID: profileID,
            confirmedOrigins: []
        )
    }

    mutating func repairActiveRemoteProfile() {
        guard !remoteProfiles.isEmpty else {
            let profile = PromptOptimizationRemoteProfile.makeDefault()
            remoteProfiles = [profile]
            activeRemoteProfileID = profile.id
            return
        }
        guard !remoteProfiles.contains(where: { $0.id == activeRemoteProfileID }) else {
            return
        }
        activeRemoteProfileID = remoteProfiles[0].id
    }
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
