import Dependencies
import Foundation
import SQLiteData

protocol ScriptRepositoryProtocol {
    func fetchAll() throws -> [ScriptTransform]
    func fetchEnabled(for trigger: ScriptTrigger) throws -> [ScriptTransform]
    func insert(_ script: ScriptTransform) throws
    func update(_ script: ScriptTransform) throws
    func delete(id: UUID) throws
    func replaceOrder(ids: [UUID]) throws
}

final class ScriptRepository: ScriptRepositoryProtocol {
    private var database: any DatabaseWriter {
        @Dependency(\.defaultDatabase) var database
        return database
    }

    func fetchAll() throws -> [ScriptTransform] {
        try database.read { database in
            try ScriptTransformRecord.all.fetchAll(database)
                .map(ScriptTransform.init(record:))
                .sorted(by: Self.isOrderedBefore)
        }
    }

    func fetchEnabled(for trigger: ScriptTrigger) throws -> [ScriptTransform] {
        try fetchAll().filter { $0.runs(on: trigger) }
    }

    func insert(_ script: ScriptTransform) throws {
        try database.write { database in
            try ScriptTransformRecord.insert { script.recordDraft }.execute(database)
        }
    }

    func update(_ script: ScriptTransform) throws {
        try database.write { database in
            let id = ScriptTransformRecord.ID(script.id)
            try ScriptTransformRecord.where { $0.id.eq(id) }
                .update {
                    $0.name = script.name
                    $0.code = script.code
                    $0.isEnabled = script.isEnabled
                    $0.runOnCopy = script.runOnCopy
                    $0.runOnPaste = script.runOnPaste
                    $0.runManually = script.runManually
                    $0.sortIndex = script.sortIndex
                    $0.updatedAt = script.updatedAt
                }
                .execute(database)
        }
    }

    func delete(id: UUID) throws {
        try database.write { database in
            try ScriptTransformRecord.delete()
                .where { $0.id.eq(ScriptTransformRecord.ID(id)) }
                .execute(database)
        }
    }

    func replaceOrder(ids: [UUID]) throws {
        try database.write { database in
            let knownIDs = Set(try ScriptTransformRecord.all.select(\.id).fetchAll(database))
            var nextIndex = 0
            for id in ids {
                let recordID = ScriptTransformRecord.ID(id)
                guard knownIDs.contains(recordID) else { continue }
                try ScriptTransformRecord.where { $0.id.eq(recordID) }
                    .update { $0.sortIndex = nextIndex }
                    .execute(database)
                nextIndex += 1
            }
        }
    }

    private static func isOrderedBefore(_ lhs: ScriptTransform, _ rhs: ScriptTransform) -> Bool {
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension ScriptTransform {
    init(record: ScriptTransformRecord) {
        self.init(
            id: record.id.rawValue,
            name: record.name,
            code: record.code,
            isEnabled: record.isEnabled,
            runOnCopy: record.runOnCopy,
            runOnPaste: record.runOnPaste,
            runManually: record.runManually,
            sortIndex: record.sortIndex,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    var recordDraft: ScriptTransformRecord.Draft {
        ScriptTransformRecord.Draft(
            id: ScriptTransformRecord.ID(id),
            name: name,
            code: code,
            isEnabled: isEnabled,
            runOnCopy: runOnCopy,
            runOnPaste: runOnPaste,
            runManually: runManually,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
