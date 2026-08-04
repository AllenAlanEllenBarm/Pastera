import Foundation

protocol OpenAICompatiblePromptOptimizing: AnyObject {
    func optimize(
        text: String,
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String
    ) async -> Result<String, PromptOptimizationError>

    func testConnection(
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String
    ) async -> Result<Void, PromptOptimizationError>
}

extension OpenAICompatiblePromptOptimizing {
    func testConnection(
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String
    ) async -> Result<Void, PromptOptimizationError> {
        await optimize(
            text: "Return OK",
            configuration: configuration,
            apiKey: apiKey
        ).map { _ in () }
    }
}

final class OpenAICompatiblePromptOptimizer: OpenAICompatiblePromptOptimizing {
    private let session: URLSession
    private let endpointPolicy: PromptOptimizationEndpointPolicy

    init(
        session: URLSession = OpenAICompatiblePromptOptimizer.makeSession(),
        endpointPolicy: PromptOptimizationEndpointPolicy = PromptOptimizationEndpointPolicy()
    ) {
        self.session = session
        self.endpointPolicy = endpointPolicy
    }

    func optimize(
        text: String,
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String
    ) async -> Result<String, PromptOptimizationError> {
        await send(
            text: text,
            configuration: configuration,
            apiKey: apiKey,
            maximumOutputTokens: nil
        )
    }

    func testConnection(
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String
    ) async -> Result<Void, PromptOptimizationError> {
        await send(
            text: "Return OK",
            configuration: configuration,
            apiKey: apiKey,
            maximumOutputTokens: 8
        ).map { _ in () }
    }

    private func send(
        text: String,
        configuration: PromptOptimizationRemoteConfiguration,
        apiKey: String,
        maximumOutputTokens: Int?
    ) async -> Result<String, PromptOptimizationError> {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return .failure(.missingModel) }

        let endpoint: PromptOptimizationEndpoint
        do {
            endpoint = try endpointPolicy.validate(configuration)
        } catch let error as PromptOptimizationError {
            return .failure(error)
        } catch {
            return .failure(.invalidEndpoint)
        }

        do {
            try Task.checkCancellation()
            var request = URLRequest(url: endpoint.chatCompletionsURL)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(
                ChatCompletionRequest(
                    model: model,
                    messages: [
                        Message(role: "system", content: PromptRewriteInstruction.text),
                        Message(role: "user", content: "<source_prompt>\n\(text)\n</source_prompt>")
                    ],
                    maximumOutputTokens: maximumOutputTokens,
                    preset: configuration.preset
                )
            )

            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 401, 403:
                return .failure(.unauthorized)
            case 429:
                return .failure(.rateLimited)
            default:
                return .failure(.serverRejected(statusCode: httpResponse.statusCode))
            }

            guard let content = try? JSONDecoder().decode(
                ChatCompletionResponse.self,
                from: data
            ).choices.first?.message.content else {
                return .failure(.invalidResponse)
            }
            let rawOutput = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawOutput.isEmpty else { return .failure(.invalidResponse) }
            guard rawOutput.count <= PromptOptimizationService.maximumOutputCharacters else {
                return .failure(
                    .outputTooLong(maxCharacters: PromptOptimizationService.maximumOutputCharacters)
                )
            }
            guard let output = PromptRewriteOutputSanitizer.sanitize(
                source: text,
                output: rawOutput
            ) else {
                return .failure(.invalidResponse)
            }
            return .success(output)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.requestTimedOut)
        } catch {
            if Task.isCancelled { return .failure(.cancelled) }
            return .failure(.requestFailed)
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        return URLSession(
            configuration: configuration,
            delegate: PromptOptimizationRedirectRejectingDelegate(),
            delegateQueue: nil
        )
    }
}

private final class PromptOptimizationRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream = false
    let temperature = 0
    let maximumOutputTokens: Int?
    let thinking: ThinkingConfiguration?

    init(
        model: String,
        messages: [Message],
        maximumOutputTokens: Int?,
        preset: OpenAICompatiblePreset
    ) {
        self.model = model
        self.messages = messages
        self.maximumOutputTokens = maximumOutputTokens
        self.thinking = preset.disablesThinking ? ThinkingConfiguration() : nil
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maximumOutputTokens = "max_tokens"
        case thinking
    }

    struct ThinkingConfiguration: Encodable {
        let type = "disabled"
    }
}

private struct Message: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String
    }
}

private enum PromptRewriteOutputSanitizer {
    private static let openingTag = "<rewritten_prompt>"
    private static let closingTag = "</rewritten_prompt>"
    // This is a closed structural guard, not an open-ended semantic classifier.
    private static let rewriteActionPattern = #"\b(?:rewrit(?:e|es|ing|ten)|restat(?:e|es|ed|ing)|transform(?:s|ed|ing)?|convert(?:s|ed|ing)?|recast(?:s|ing)?|reshap(?:e|es|ed|ing))\b"#
    private static let rewriteMaterialPattern = #"\b(?:source|input|prompts?|requests?|materials?|texts?|submissions?|responses?|what\s+was\s+provided)\b"#
    private static let rewriteConstraintPattern = #"\b(?:must|cannot|can't|may\s+not|should\s+not|will\s+(?:not|only)|(?:am|is|are|be|been|being)\s+(?:constrained|obliged|required|bound)|(?:my\s+)?role\s+is\s+to)\b"#
    private static let privateGovernancePattern = #"\b(?:system|developer|hidden|internal|confidential|private|nonpublic)\s+(?:operating\s+)?(?:instructions?|polic(?:y|ies)|rules?|directives?|guidelines?|prompts?|frameworks?)\b"#
    private static let nonAnswerPattern = #"\b(?:instead\s+of|rather\s+than)\s+(?:answer(?:s|ed|ing)?|respond(?:s|ed|ing)?)\b"#
    private static let protectedAnchorPatterns = [
        #"(?<![A-Za-z0-9_])(?:[A-Z]{2,}|[A-Z][A-Za-z0-9_]*[A-Z][A-Za-z0-9_]*|[A-Za-z0-9_]+[_.-][A-Za-z0-9_.-]+|(?=[A-Za-z0-9_]*[a-z])(?=[A-Za-z0-9_]*[0-9])[A-Za-z0-9_]+)(?![A-Za-z0-9_])"#,
        #"https?://[^\s<>()，。；、]+"#,
        #"\$\{[^}\n]+\}|\{\{[^}\n]+\}\}"#,
        #"[0-9]+(?:\.[0-9]+)?\s*(?:MB|GB|KB|ms|s|%|秒|分钟|小时|天)"#,
        #"[零〇一二三四五六七八九十百千万两几]+(?:秒|分钟|小时|天)"#
    ]
    private static let leadingLabels = [
        "Rewrite the source prompt:",
        "Rewritten prompt:",
        "Optimized prompt:",
        "改写后的提示词：",
        "优化后的提示词："
    ]

    private struct MetaRewriteStructure: OptionSet {
        let rawValue: UInt8

        static let governedRewrite = MetaRewriteStructure(rawValue: 1 << 0)
        static let suppressedAnswer = MetaRewriteStructure(rawValue: 1 << 1)
    }

    static func sanitize(source: String, output: String) -> String? {
        var candidate = output.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = stripEnclosingRewriteTag(from: candidate)
        candidate = stripLeadingLabel(from: candidate)
        candidate = stripTrailingEmptyListItems(from: candidate)
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty,
              !disclosesRewriteInstruction(source: source, output: candidate),
              preservesEastAsianLanguage(source: source, output: candidate),
              preservesProtectedAnchors(source: source, output: candidate) else {
            return nil
        }
        return candidate
    }

    private static func stripEnclosingRewriteTag(from text: String) -> String {
        let lowercased = text.lowercased()
        guard lowercased.hasPrefix(openingTag),
              lowercased.hasSuffix(closingTag) else {
            return text
        }
        let start = text.index(text.startIndex, offsetBy: openingTag.count)
        let end = text.index(text.endIndex, offsetBy: -closingTag.count)
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingLabel(from text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              leadingLabels.contains(where: {
                  $0.caseInsensitiveCompare(firstLine) == .orderedSame
              }) else {
            return text
        }
        lines.removeFirst()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTrailingEmptyListItems(from text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        while let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              lastLine.isEmpty || lastLine == "-" || lastLine == "*" || lastLine == "•" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func disclosesRewriteInstruction(source: String, output: String) -> Bool {
        let normalizedOutput = normalizeWhitespace(output)
        let normalizedSource = normalizeWhitespace(source)
        let quotesRewriteInstruction = PromptRewriteInstruction.text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map(normalizeWhitespace)
            .filter { $0.count >= 32 }
            .contains { normalizedOutput.contains($0) && !normalizedSource.contains($0) }
        return quotesRewriteInstruction || introducesMetaRewriteCommentary(
            source: source,
            output: output
        )
    }

    private static func introducesMetaRewriteCommentary(source: String, output: String) -> Bool {
        let sourceStructures = metaRewriteStructures(in: source)
        return metaRewriteStructures(in: output).contains { outputStructure in
            !outputStructure.isEmpty && !sourceStructures.contains { sourceStructure in
                sourceStructure.isSuperset(of: outputStructure)
            }
        }
    }

    private static func metaRewriteStructures(in text: String) -> [MetaRewriteStructure] {
        let statements = text.split(whereSeparator: { ".!?;。！？；\n\r".contains($0) }).map(String.init)
        let statementStructures = statements.map(metaRewriteStructure)
        let adjacentStructures = zip(statements, statements.dropFirst()).map { first, second in
            guard containsRewriteCore(in: first) || containsRewriteCore(in: second) else {
                return MetaRewriteStructure()
            }
            return metaRewriteStructure(in: "\(first) \(second)")
        }
        return statementStructures + adjacentStructures
    }

    private static func metaRewriteStructure(in statement: String) -> MetaRewriteStructure {
        let normalizedStatement = normalizeWhitespace(statement)
        guard !matches(pattern: rewriteConstraintPattern, in: normalizedStatement).isEmpty else {
            return []
        }

        var structure: MetaRewriteStructure = []
        if !matches(pattern: privateGovernancePattern, in: normalizedStatement).isEmpty {
            structure.insert(.governedRewrite)
        }
        if containsRewriteCore(in: normalizedStatement),
           !matches(pattern: nonAnswerPattern, in: normalizedStatement).isEmpty {
            structure.insert(.suppressedAnswer)
        }
        return structure
    }

    private static func containsRewriteCore(in statement: String) -> Bool {
        let normalizedStatement = normalizeWhitespace(statement)
        return !matches(pattern: rewriteActionPattern, in: normalizedStatement).isEmpty
            && !matches(pattern: rewriteMaterialPattern, in: normalizedStatement).isEmpty
            && !matches(pattern: rewriteConstraintPattern, in: normalizedStatement).isEmpty
    }

    private static func preservesEastAsianLanguage(source: String, output: String) -> Bool {
        let sourceCounts = languageCounts(in: proseOnly(source))
        guard sourceCounts.eastAsian >= 4,
              sourceCounts.eastAsian * 2 >= sourceCounts.latin else {
            return true
        }
        let outputCounts = languageCounts(in: proseOnly(output))
        return outputCounts.eastAsian >= 4
            && outputCounts.eastAsian * 2 >= outputCounts.latin
    }

    private static func preservesProtectedAnchors(source: String, output: String) -> Bool {
        return protectedAnchorPatterns.allSatisfy { pattern in
            matches(pattern: pattern, in: source).allSatisfy(output.contains)
        }
    }

    private static func matches(pattern: String, in text: String) -> Set<String> {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        })
    }

    private static func proseOnly(_ text: String) -> String {
        text.components(separatedBy: "```")
            .enumerated()
            .filter { $0.offset.isMultiple(of: 2) }
            .map(\.element)
            .joined(separator: "\n")
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.contains("://") }
            .joined(separator: " ")
    }

    private static func languageCounts(in text: String) -> (eastAsian: Int, latin: Int) {
        var eastAsian = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x3040...0x30FF, 0x31F0...0x31FF,
                 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
                eastAsian += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latin += 1
            default:
                break
            }
        }
        return (eastAsian, latin)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
