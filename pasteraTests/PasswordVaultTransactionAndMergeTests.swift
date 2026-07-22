import Foundation
import KDBXKit
import Testing
@testable import Pastera

extension PasswordVaultStoreTests {
    @Test("barrier-started KDBX writers preserve both stores' changes")
    func concurrentVaultWritersMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        let second = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try first.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        try second.unlock(masterPassword: "shared password", rememberQuickUnlock: false)

        let stores = [first, second]
        let ready = DispatchSemaphore(value: 0)
        let start = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        let outcomes = LockedReviewResults<PasswordVaultFolder>()
        for index in stores.indices {
            finished.enter()
            Thread.detachNewThread {
                ready.signal()
                _ = start.wait(timeout: .now() + 30)
                outcomes.append(Result {
                    try stores[index].createFolder(name: index == 0 ? "First" : "Second")
                })
                finished.leave()
            }
        }
        #expect(ready.wait(timeout: .now() + 30) == .success)
        #expect(ready.wait(timeout: .now() + 30) == .success)
        start.signal()
        start.signal()
        #expect(finished.wait(timeout: .now() + 30) == .success)
        for outcome in outcomes.values {
            _ = try outcome.get()
        }

        let verifier = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try verifier.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        #expect(Set(try verifier.listFolders().map(\.name)) == ["First", "Second"])
    }

    @Test("a stale store merges a remote snapshot with the latest local disk revision")
    func staleRemoteMergePreservesLatestLocalDiskChange() throws {
        let localRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let remoteRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: localRoot)
            try? FileManager.default.removeItem(at: remoteRoot)
        }
        let active = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: localRoot))
        let stale = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: localRoot))
        try active.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        try stale.unlock(masterPassword: "shared password", rememberQuickUnlock: false)

        let latestFolder = try active.createFolder(name: "Latest")
        _ = try active.create(.init(
            folderID: latestFolder.id, title: "Latest Disk Entry", website: "",
            username: "latest", note: "", password: "latest-secret"
        ))

        let remote = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: remoteRoot))
        try remote.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        let remoteFolder = try remote.createFolder(name: "Remote")
        _ = try remote.create(.init(
            folderID: remoteFolder.id, title: "Remote Entry", website: "",
            username: "remote", note: "", password: "remote-secret"
        ))

        _ = try stale.mergeRemoteSnapshot(remote.encryptedSnapshot().data, remoteMasterPassword: nil)

        let verifier = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: localRoot))
        try verifier.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        #expect(Set(try verifier.listEntries().map(\.title)) == ["Latest Disk Entry", "Remote Entry"])
    }

    @Test("commit observers run outside the shared local transaction lock")
    func commitObserverCanReenterThroughAnotherStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        let second = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try first.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        try second.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        let outcomes = LockedReviewResults<Void>()
        let completed = DispatchSemaphore(value: 0)
        first.setCommitObserver { _ in
            outcomes.append(Result { _ = try second.createFolder(name: "Observer") })
        }

        Thread.detachNewThread {
            outcomes.append(Result { _ = try first.createFolder(name: "Primary") })
            completed.signal()
        }

        #expect(completed.wait(timeout: .now() + 30) == .success)
        for outcome in outcomes.values {
            _ = try outcome.get()
        }
        let verifier = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try verifier.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        #expect(Set(try verifier.listFolders().map(\.name)) == ["Primary", "Observer"])
    }

    @Test("same current content merges and deduplicates history from both sides")
    func mergerPreservesBothHistoriesForSameCurrentContent() throws {
        let folderID = UUID()
        let entryID = UUID()
        let shared = makeReviewEntry(id: entryID, title: "Shared History", modifiedAt: 5)
        let localEntry = makeReviewEntry(
            id: entryID, title: "Current", modifiedAt: 30,
            history: [shared, makeReviewEntry(id: entryID, title: "Local History", modifiedAt: 10)]
        )
        let remoteEntry = makeReviewEntry(
            id: entryID, title: "Current", modifiedAt: 40,
            history: [shared, makeReviewEntry(id: entryID, title: "Remote History", modifiedAt: 20)]
        )
        let local = makeReviewContent(groupID: folderID, modifiedAt: 30, entries: [localEntry])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 40, entries: [remoteEntry])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entry = try #require(result.content.database.root.group.groups.first?.entries.first)

        #expect(reviewTitle(entry) == "Current")
        #expect(entry.history.map(reviewTitle) == ["Shared History", "Local History", "Remote History"])
    }

    @Test("different current content retains both existing histories and the losing current version")
    func mergerPreservesBothHistoriesForDifferentContent() throws {
        let folderID = UUID()
        let entryID = UUID()
        let localEntry = makeReviewEntry(
            id: entryID, title: "New", modifiedAt: 50,
            history: [makeReviewEntry(id: entryID, title: "Local History", modifiedAt: 10)]
        )
        let remoteEntry = makeReviewEntry(
            id: entryID, title: "Old", modifiedAt: 40,
            history: [makeReviewEntry(id: entryID, title: "Remote History", modifiedAt: 20)]
        )
        let local = makeReviewContent(groupID: folderID, modifiedAt: 50, entries: [localEntry])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 40, entries: [remoteEntry])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entry = try #require(result.content.database.root.group.groups.first?.entries.first)

        #expect(reviewTitle(entry) == "New")
        #expect(Set(entry.history.map(reviewTitle)) == ["Local History", "Remote History", "Old"])
        #expect(entry.history.count == 3)
    }

    @Test("merged entry history keeps the ten most recent unique versions")
    func mergerCapsCombinedHistoryAtTen() throws {
        let folderID = UUID()
        let entryID = UUID()
        let localHistory = (15 ... 21).map {
            makeReviewEntry(id: entryID, title: "Local \($0)", modifiedAt: TimeInterval($0))
        }
        let remoteHistory = (1 ... 13).map {
            makeReviewEntry(id: entryID, title: "Remote \($0)", modifiedAt: TimeInterval($0))
        }
        let localEntry = makeReviewEntry(
            id: entryID, title: "Current", modifiedAt: 30, history: localHistory
        )
        let remoteEntry = makeReviewEntry(
            id: entryID, title: "Remote Current", modifiedAt: 14, history: remoteHistory
        )
        let local = makeReviewContent(groupID: folderID, modifiedAt: 30, entries: [localEntry])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 14, entries: [remoteEntry])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entry = try #require(result.content.database.root.group.groups.first?.entries.first)

        #expect(entry.history.count == 10)
        #expect(entry.history.map(reviewTitle) == [
            "Remote 12", "Remote 13", "Remote Current",
            "Local 15", "Local 16", "Local 17", "Local 18", "Local 19", "Local 20", "Local 21"
        ])
    }

    @Test("merge rebuilds the exact preferred entry UUID order")
    func mergerPreservesPreferredEntryOrder() throws {
        let folderID = UUID()
        let entries = (0 ..< 8).map {
            makeReviewEntry(id: UUID(), title: "Entry \($0)", modifiedAt: 20)
        }
        let localOnly = makeReviewEntry(id: UUID(), title: "Local Only", modifiedAt: 20)
        let local = makeReviewContent(groupID: folderID, modifiedAt: 20, entries: entries + [localOnly])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 20, entries: Array(entries.reversed()))

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let merged = try #require(result.content.database.root.group.groups.first?.entries)

        #expect(result.conflictCopyCount == 0)
        #expect(merged.map(\.uuid) == Array(entries.reversed()).map(\.uuid) + [localOnly.uuid])
    }
}

private func makeReviewLocalStorage(at root: URL) -> FilePasswordVaultLocalStorage {
    let directory = root.appendingPathComponent("PasswordVault", isDirectory: true)
    return FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
        directoryURL: directory,
        vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
        backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
        metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
    ))
}

private func makeReviewContent(
    groupID: UUID,
    modifiedAt: TimeInterval,
    entries: [KDBX.Entry]
) -> KDBXContent {
    var content = KDBXContent.makeEmpty(databaseName: "Pastera", generator: "PasteraTests")
    var group = KDBX.Group(
        uuid: groupID,
        name: "Shared",
        times: .init(
            creationTime: Date(timeIntervalSince1970: modifiedAt),
            lastModificationTime: Date(timeIntervalSince1970: modifiedAt)
        ),
        isExpanded: true
    )
    group.entries = entries
    content.database.root.group.groups = [group]
    return content
}

private func makeReviewEntry(
    id: UUID,
    title: String,
    modifiedAt: TimeInterval,
    history: [KDBX.Entry] = []
) -> KDBX.Entry {
    var entry = KDBX.Entry(uuid: id)
    let date = Date(timeIntervalSince1970: modifiedAt)
    entry.times = .init(creationTime: date, lastModificationTime: date)
    entry.strings = [
        .init(key: "Title", value: .regular(title)),
        .init(key: "Password", value: .protectedInMemory("fixture-secret"))
    ]
    entry.history = history
    return entry
}

private func reviewTitle(_ entry: KDBX.Entry) -> String {
    entry.strings.first(where: { $0.key == "Title" })?.value.revealedString ?? ""
}

private final class LockedReviewResults<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [Result<Value, Error>]()

    var values: [Result<Value, Error>] {
        lock.withLock { storage }
    }

    func append(_ result: Result<Value, Error>) {
        lock.withLock { storage.append(result) }
    }
}
