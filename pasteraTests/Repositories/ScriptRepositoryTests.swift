import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
@testable import Pastera

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct ScriptRepositoryTests {
    private let repository = ScriptRepository()

    @Test
    func crudRoundTripPreservesScriptDefinition() throws {
        let script = ScriptTransform(
            id: UUID(),
            name: "Uppercase",
            code: "function transform(clip) { return clip.text.toUpperCase(); }",
            isEnabled: true,
            runOnCopy: true,
            runOnPaste: false,
            runManually: true,
            sortIndex: 0,
            createdAt: 100,
            updatedAt: 100
        )

        try repository.insert(script)
        #expect(try repository.fetchAll() == [script])

        var updated = script
        updated.name = "Uppercase text"
        updated.runOnPaste = true
        updated.updatedAt = 200
        try repository.update(updated)
        #expect(try repository.fetchAll() == [updated])

        try repository.delete(id: script.id)
        #expect(try repository.fetchAll().isEmpty)
    }

    @Test
    func enabledScriptsUseStableOrderAndTriggerFilter() throws {
        let second = makeScript(name: "second", runOnCopy: true, sortIndex: 20, createdAt: 200)
        let firstLater = makeScript(name: "first later", runOnCopy: true, sortIndex: 10, createdAt: 200)
        let firstEarlier = makeScript(name: "first earlier", runOnCopy: true, sortIndex: 10, createdAt: 100)
        let paste = makeScript(name: "paste", runOnPaste: true, sortIndex: 0, createdAt: 50)
        let disabled = makeScript(name: "disabled", isEnabled: false, runOnCopy: true, sortIndex: -1, createdAt: 1)

        for script in [second, firstLater, firstEarlier, paste, disabled] {
            try repository.insert(script)
        }

        #expect(
            try repository.fetchEnabled(for: .copy).map(\.name) == [
                "first earlier",
                "first later",
                "second"
            ]
        )
        #expect(try repository.fetchEnabled(for: .paste).map(\.name) == ["paste"])
        #expect(try repository.fetchEnabled(for: .manual).isEmpty)
    }

    @Test
    func replaceOrderReindexesOnlyKnownScripts() throws {
        let first = makeScript(name: "first", runManually: true, sortIndex: 0, createdAt: 100)
        let second = makeScript(name: "second", runManually: true, sortIndex: 1, createdAt: 200)
        try repository.insert(first)
        try repository.insert(second)

        try repository.replaceOrder(ids: [second.id, UUID(), first.id])

        let reordered = try repository.fetchAll()
        #expect(reordered.map(\.id) == [second.id, first.id])
        #expect(reordered.map(\.sortIndex) == [0, 1])
    }

    private func makeScript(
        name: String,
        isEnabled: Bool = true,
        runOnCopy: Bool = false,
        runOnPaste: Bool = false,
        runManually: Bool = false,
        sortIndex: Int,
        createdAt: Int
    ) -> ScriptTransform {
        ScriptTransform(
            id: UUID(),
            name: name,
            code: "function transform(clip) { return clip.text; }",
            isEnabled: isEnabled,
            runOnCopy: runOnCopy,
            runOnPaste: runOnPaste,
            runManually: runManually,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
