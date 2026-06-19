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

    @Test
    func imageHistoryRowShowsThumbnailWhenRetiredImagePreferenceWasDisabled() throws {
        try withRegisteredDefaultEnvironment { defaults in
            defaults.set(false, forKey: Constants.UserDefaults.showImageInTheMenu)
            let historyID = PasteboardHistory.ID("legacy-disabled-image")
            let image = NSImage.create(with: .red, size: NSSize(width: 24, height: 18))
            let imageData = try #require(image.tiffRepresentation)
            let detail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: historyID,
                    title: "Screenshot",
                    pasteboardTypes: [.tiff],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: PasteboardHistoryThumbnailAsset(
                    pasteboardHistoryID: historyID,
                    kind: .image,
                    data: imageData
                )
            )

            let row = MenuManager().makeHistoryRowViewForTesting(detail, index: 0)

            #expect(row.frame.height > 28)
            #expect(row.textValuesForTesting.contains("(Image)"))
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
