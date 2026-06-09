//
//  HistoryDisplayContentTests.swift
//
//  Clipy
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct HistoryDisplayContentTests {
    @Test
    func historyPanelRowsUseLongerReadableTitlesThanLegacyMenuDefault() throws {
        try withRegisteredDefaultEnvironment { _ in
            let longCommand = "curl --request 'GET' https://example.com/api/v1/clipboard/history/search"
            let detail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: PasteboardHistory.ID("long-command"),
                    title: longCommand,
                    pasteboardTypes: [.string],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: nil
            )

            let row = MenuManager().makeHistoryRowViewForTesting(detail, index: 0)

            #expect(row.textValuesForTesting.contains("curl --request 'GET' https://example.com/api/v1/clipboard..."))
            #expect(!row.textValuesForTesting.contains("curl --request 'G..."))
        }
    }

    private func withRegisteredDefaultEnvironment(
        operation: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "HistoryDisplayContentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        AppEnvironment.push(defaults: defaults)
        defer {
            _ = AppEnvironment.popLast()
            defaults.removePersistentDomain(forName: suiteName)
        }

        CPYUtilities.registerUserDefaultKeys()
        try operation(defaults)
    }
}
