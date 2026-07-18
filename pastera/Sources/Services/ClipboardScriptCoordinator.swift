import AppKit
import Foundation

enum ScriptTransformOutcome: Equatable {
    case unchanged
    case transformed(String)
    case failed(ScriptExecutionError)
}

protocol ScriptPasteboard: AnyObject {
    var changeCount: Int { get }
    func readString() -> String?
    @discardableResult func writeString(_ string: String) -> Int
}

final class SystemScriptPasteboard: ScriptPasteboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    @discardableResult
    func writeString(_ string: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        return pasteboard.changeCount
    }
}

protocol ClipboardScriptCoordinating: AnyObject {
    func hasEnabledScripts(for trigger: ScriptTrigger) -> Bool
    func availableHistoryScripts() -> [ScriptTransform]
    func transform(
        text: String,
        sourceAppBundleIdentifier: String?,
        trigger: ScriptTrigger
    ) async -> ScriptTransformOutcome
    func transformHistoryText(
        _ text: String,
        using scriptID: UUID,
        sourceAppBundleIdentifier: String?
    ) async -> ScriptTransformOutcome
    func writeHistoryTransformResult(_ text: String)
    func runManualTransform() async
    func consumeSuppression(changeCount: Int) -> Bool
}

final class ClipboardScriptCoordinator: ClipboardScriptCoordinating {
    private let repository: ScriptRepositoryProtocol
    private let executor: ScriptExecuting
    private let pasteboard: ScriptPasteboard
    private let sourceAppBundleIdentifierProvider: () -> String?
    private let suppressionLock = NSLock()
    private var suppressedChangeCounts = Set<Int>()

    init(
        repository: ScriptRepositoryProtocol,
        executor: ScriptExecuting,
        pasteboard: ScriptPasteboard = SystemScriptPasteboard(),
        sourceAppBundleIdentifierProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.repository = repository
        self.executor = executor
        self.pasteboard = pasteboard
        self.sourceAppBundleIdentifierProvider = sourceAppBundleIdentifierProvider
    }

    func hasEnabledScripts(for trigger: ScriptTrigger) -> Bool {
        guard let scripts = try? repository.fetchEnabled(for: trigger) else { return false }
        return !scripts.isEmpty
    }

    func availableHistoryScripts() -> [ScriptTransform] {
        guard let scripts = try? repository.fetchAll() else { return [] }
        return scripts
            .filter { $0.isEnabled && $0.runManually }
            .sorted { lhs, rhs in
                if lhs.sortIndex == rhs.sortIndex {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortIndex < rhs.sortIndex
            }
    }

    func transform(
        text: String,
        sourceAppBundleIdentifier: String?,
        trigger: ScriptTrigger
    ) async -> ScriptTransformOutcome {
        guard let scripts = try? repository.fetchEnabled(for: trigger), !scripts.isEmpty else {
            return .unchanged
        }
        let result = await executor.execute(
            scripts: scripts,
            input: ScriptExecutionInput(
                text: text,
                sourceAppBundleIdentifier: sourceAppBundleIdentifier
            )
        )
        switch result {
        case let .success(output):
            return output == text ? .unchanged : .transformed(output)
        case let .failure(error):
            return .failed(error)
        }
    }

    func transformHistoryText(
        _ text: String,
        using scriptID: UUID,
        sourceAppBundleIdentifier: String?
    ) async -> ScriptTransformOutcome {
        guard let script = availableHistoryScripts().first(where: { $0.id == scriptID }) else {
            return .unchanged
        }
        let result = await executor.execute(
            scripts: [script],
            input: ScriptExecutionInput(
                text: text,
                sourceAppBundleIdentifier: sourceAppBundleIdentifier
            )
        )
        switch result {
        case let .success(output):
            return output == text ? .unchanged : .transformed(output)
        case let .failure(error):
            return .failed(error)
        }
    }

    func runManualTransform() async {
        guard let text = pasteboard.readString() else { return }
        let outcome = await transform(
            text: text,
            sourceAppBundleIdentifier: sourceAppBundleIdentifierProvider(),
            trigger: .manual
        )
        guard case let .transformed(output) = outcome else { return }
        let changeCount = pasteboard.writeString(output)
        suppressionLock.lock()
        suppressedChangeCounts.insert(changeCount)
        suppressionLock.unlock()
    }

    func writeHistoryTransformResult(_ text: String) {
        let changeCount = pasteboard.writeString(text)
        suppressionLock.lock()
        suppressedChangeCounts.insert(changeCount)
        suppressionLock.unlock()
    }

    func consumeSuppression(changeCount: Int) -> Bool {
        suppressionLock.lock()
        defer { suppressionLock.unlock() }
        return suppressedChangeCounts.remove(changeCount) != nil
    }
}
