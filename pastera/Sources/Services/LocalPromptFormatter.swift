import Foundation

protocol LocalPromptFormatting: AnyObject {
    func format(_ text: String) -> String
}

final class LocalPromptFormatter: LocalPromptFormatting {
    func format(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var result = [String]()
        var activeFence: String?
        var consecutiveBlankLines = 0

        for lineValue in lines {
            let line = String(lineValue)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let fenceMarker = marker(for: trimmed)

            if let currentFence = activeFence {
                result.append(line)
                if fenceMarker == currentFence {
                    activeFence = nil
                }
                continue
            }

            if let fenceMarker {
                result.append(removingTrailingWhitespace(from: line))
                activeFence = fenceMarker
                consecutiveBlankLines = 0
                continue
            }

            let cleaned = removingTrailingWhitespace(from: line)
            if cleaned.isEmpty {
                consecutiveBlankLines += 1
                if consecutiveBlankLines <= 2 {
                    result.append("")
                }
            } else {
                consecutiveBlankLines = 0
                result.append(cleaned)
            }
        }

        return result
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func marker(for trimmedLine: String) -> String? {
        if trimmedLine.hasPrefix("```") { return "```" }
        if trimmedLine.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private func removingTrailingWhitespace(from line: String) -> String {
        String(line.drop(whileFromEnd: { $0 == " " || $0 == "\t" }))
    }

}

private extension String {
    func drop(whileFromEnd predicate: (Character) -> Bool) -> Substring {
        var endIndex = endIndex
        while endIndex > startIndex {
            let previous = index(before: endIndex)
            guard predicate(self[previous]) else { break }
            endIndex = previous
        }
        return self[..<endIndex]
    }
}
