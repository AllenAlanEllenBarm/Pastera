import Foundation

enum ScriptTrigger: Equatable, Sendable {
    case copy
    case paste
    case manual
}

struct ScriptTransform: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var code: String
    var isEnabled: Bool
    var runOnCopy: Bool
    var runOnPaste: Bool
    var runManually: Bool
    var sortIndex: Int
    let createdAt: Int
    var updatedAt: Int

    func runs(on trigger: ScriptTrigger) -> Bool {
        guard isEnabled else { return false }
        switch trigger {
        case .copy: return runOnCopy
        case .paste: return runOnPaste
        case .manual: return runManually
        }
    }
}
