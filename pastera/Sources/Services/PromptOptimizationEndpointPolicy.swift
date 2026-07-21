import Foundation

struct PromptOptimizationEndpoint: Equatable, Sendable {
    let baseURL: URL
    let origin: String
    let chatCompletionsURL: URL
}

struct PromptOptimizationEndpointPolicy: Sendable {
    func validate(
        _ configuration: PromptOptimizationRemoteConfiguration
    ) throws -> PromptOptimizationEndpoint {
        let enteredBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString: String
        if enteredBaseURL.isEmpty {
            baseURLString = OpenAICompatiblePreset.presetBaseURLs[configuration.preset] ?? ""
        } else {
            baseURLString = enteredBaseURL
        }
        guard let url = URL(string: baseURLString), !baseURLString.isEmpty else {
            throw PromptOptimizationError.invalidEndpoint
        }
        return try validate(url, allowInsecureHTTP: configuration.allowsInsecureHTTP)
    }

    func validate(
        _ url: URL,
        allowInsecureHTTP: Bool
    ) throws -> PromptOptimizationEndpoint {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sourceScheme = components.scheme?.lowercased(),
              let sourceHost = components.host?.lowercased(),
              !sourceHost.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.query == nil else {
            throw PromptOptimizationError.invalidEndpoint
        }
        guard sourceScheme == "https" || sourceScheme == "http" else {
            throw PromptOptimizationError.invalidEndpoint
        }
        if sourceScheme == "http", !isLoopback(sourceHost), !allowInsecureHTTP {
            throw PromptOptimizationError.insecureEndpoint
        }

        components.scheme = sourceScheme
        components.host = sourceHost
        if (sourceScheme == "https" && components.port == 443)
            || (sourceScheme == "http" && components.port == 80) {
            components.port = nil
        }

        var pathParts = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if pathParts.suffix(2) != ["chat", "completions"] {
            pathParts.append(contentsOf: ["chat", "completions"])
        }
        components.percentEncodedPath = "/" + pathParts.joined(separator: "/")
        guard let chatCompletionsURL = components.url else {
            throw PromptOptimizationError.invalidEndpoint
        }

        var baseComponents = components
        baseComponents.percentEncodedPath = "/" + pathParts.dropLast(2).joined(separator: "/")
        if baseComponents.percentEncodedPath == "/" {
            baseComponents.percentEncodedPath = ""
        }
        guard let baseURL = baseComponents.url else {
            throw PromptOptimizationError.invalidEndpoint
        }

        var originComponents = components
        originComponents.percentEncodedPath = ""
        originComponents.query = nil
        originComponents.fragment = nil
        guard let origin = originComponents.url?.absoluteString else {
            throw PromptOptimizationError.invalidEndpoint
        }
        return PromptOptimizationEndpoint(
            baseURL: baseURL,
            origin: origin,
            chatCompletionsURL: chatCompletionsURL
        )
    }

    private func isLoopback(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return normalized == "localhost"
            || normalized == "::1"
            || normalized == "127.0.0.1"
            || normalized.hasPrefix("127.")
    }
}
