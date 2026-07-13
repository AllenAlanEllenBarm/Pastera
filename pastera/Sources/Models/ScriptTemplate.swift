import Foundation

enum ScriptTemplateCategory: String, CaseIterable, Sendable {
    case all
    case text
    case json
    case extract
}

struct ScriptTemplate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let category: ScriptTemplateCategory
    let keywords: [String]
    let code: String

    func makeDraft(now: Int = Int(Date().timeIntervalSince1970)) -> ScriptTransform {
        ScriptTransform(
            id: UUID(),
            name: name,
            code: code,
            isEnabled: true,
            runOnCopy: false,
            runOnPaste: false,
            runManually: true,
            sortIndex: now,
            createdAt: now,
            updatedAt: now
        )
    }
}
