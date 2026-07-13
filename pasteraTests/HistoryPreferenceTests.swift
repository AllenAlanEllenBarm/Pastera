//
//  HistoryPreferenceTests.swift
//
//  Pastera
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct HistoryPreferenceTests {
    @Test
    func pageOwnsExactAnchorsAndClearHistoryConfirmationAction() throws {
        let controller = CPYHistoryPreferenceViewController()
        _ = controller.view

        #expect(controller.paneID == .history)
        for anchorID in PasteraPreferenceCatalog.default.pages
            .first(where: { $0.paneID == .history })?.searchItems.map(\.anchorID) ?? [] {
            #expect(controller.revealSetting(anchorID: anchorID, animated: false))
        }

        let clearButton = try #require(historyButtons(in: controller.view).first {
            $0.title == String(localized: "Clear History")
        })
        #expect(clearButton.action == #selector(AppDelegate.clearAllHistory))
        #expect(clearButton.target == nil)
    }

    @Test
    func mediaLimitFieldsUseLocalizedVoiceOverLabels() throws {
        let controller = CPYHistoryPreferenceViewController()
        _ = controller.view
        let labels = Set(historyTextFields(in: controller.view).compactMap { $0.accessibilityLabel() })

        #expect(labels.contains(pasteraPreferenceString("Image History Limit")))
        #expect(labels.contains(pasteraPreferenceString("File History Limit")))
    }

    @Test
    func changedLimitCommitClampsWritesAndPrunesWhileUnchangedCommitDoesNot() throws {
        let suiteName = "HistoryPreferenceTests.limitCommit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let repository = HistoryPreferenceRepository()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(15, forKey: Constants.UserDefaults.maxImageHistorySize)
        defaults.set(15, forKey: Constants.UserDefaults.maxFileHistorySize)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        try withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let controller = CPYHistoryPreferenceViewController()
            _ = controller.view
            let imageField = try #require(historyTextFields(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Image History Limit")
            })
            let fileField = try #require(historyTextFields(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("File History Limit")
            })

            imageField.stringValue = "0"
            #expect(try sendHistoryControlAction(imageField))
            #expect(defaults.integer(forKey: Constants.UserDefaults.maxImageHistorySize) == 1)
            #expect(imageField.stringValue == "1")
            #expect(repository.pruneSettings.map(\.maxImageHistorySize) == [1])

            fileField.stringValue = "99"
            #expect(try sendHistoryControlAction(fileField))
            #expect(defaults.integer(forKey: Constants.UserDefaults.maxFileHistorySize) == 50)
            #expect(fileField.stringValue == "50")
            #expect(repository.pruneSettings.map(\.maxFileHistorySize) == [15, 50])

            fileField.stringValue = "50"
            #expect(try sendHistoryControlAction(fileField))
            #expect(repository.pruneSettings.count == 2)

            fileField.stringValue = "34"
            controller.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: fileField)
            )
            #expect(defaults.integer(forKey: Constants.UserDefaults.maxFileHistorySize) == 34)
            #expect(repository.pruneSettings.map(\.maxFileHistorySize) == [15, 50, 34])
        }
    }

    @Test
    func invalidAndBlankLimitDraftsDoNotWriteAndEscapeRestoresLastValidValue() throws {
        let suiteName = "HistoryPreferenceTests.limitDraft.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(12, forKey: Constants.UserDefaults.maxImageHistorySize)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYHistoryPreferenceViewController()
        _ = controller.view
        let imageField = try #require(historyTextFields(in: controller.view).first {
            $0.accessibilityLabel() == pasteraPreferenceString("Image History Limit")
        })

        imageField.stringValue = "invalid"
        #expect(try sendHistoryControlAction(imageField))
        #expect(imageField.stringValue == "invalid")
        #expect(defaults.integer(forKey: Constants.UserDefaults.maxImageHistorySize) == 12)
        #expect(historyTextFields(in: controller.view).contains { !$0.isHidden && !$0.stringValue.isEmpty && $0.textColor == .systemRed })

        imageField.stringValue = ""
        #expect(try sendHistoryControlAction(imageField))
        #expect(imageField.stringValue.isEmpty)
        #expect(defaults.integer(forKey: Constants.UserDefaults.maxImageHistorySize) == 12)

        #expect(controller.control(
            imageField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))
        #expect(imageField.stringValue == "12")
    }

    @Test
    func savedTypeSwitchWritesImmediatelyAndPreservesUnknownLegacyKeys() throws {
        let suiteName = "HistoryPreferenceTests.savedTypes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([
            PasteboardAvailableType.string.rawValue: true,
            "LegacyCustomType": false
        ], forKey: Constants.UserDefaults.storeTypes)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYHistoryPreferenceViewController()
        _ = controller.view
        let buttons = historyButtons(in: controller.view)
        let expectedKeys = Set(PasteboardAvailableType.allCases.map(\.rawValue))
        let typeButtons = buttons.filter { button in
            button.identifier.map { expectedKeys.contains($0.rawValue) } ?? false
        }

        #expect(Set(typeButtons.compactMap { $0.identifier?.rawValue }) == expectedKeys)
        let stringButton = try #require(typeButtons.first {
            $0.identifier?.rawValue == PasteboardAvailableType.string.rawValue
        })
        stringButton.performClick(nil)

        let stored = try #require(defaults.dictionary(forKey: Constants.UserDefaults.storeTypes))
        #expect((stored[PasteboardAvailableType.string.rawValue] as? NSNumber)?.boolValue == false)
        #expect((stored["LegacyCustomType"] as? NSNumber)?.boolValue == false)
    }

    @Test
    func filePreviewUsesFiveCurrentKeysAndFilenamesDisablesWithoutErasingValues() throws {
        let suiteName = "HistoryPreferenceTests.previewTypes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([PasteboardAvailableType.filenames.rawValue: true], forKey: Constants.UserDefaults.storeTypes)
        let initialPreviewValues: [String: Any] = [
            PasteraFilePreviewKind.image.rawValue: true,
            PasteraFilePreviewKind.document.rawValue: false,
            PasteraFilePreviewKind.archive.rawValue: true,
            PasteraFilePreviewKind.code.rawValue: false,
            PasteraFilePreviewKind.other.rawValue: true,
            "LegacyPreviewKind": false
        ]
        defaults.set(initialPreviewValues, forKey: Constants.UserDefaults.filePreviewTypes)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYHistoryPreferenceViewController()
        _ = controller.view
        let previewKeys = Set(PasteraFilePreviewKind.allCases.map(\.rawValue))
        let previewButtons = historyButtons(in: controller.view).filter { button in
            button.identifier.map { previewKeys.contains($0.rawValue) } ?? false
        }
        #expect(Set(previewButtons.compactMap { $0.identifier?.rawValue }) == previewKeys)

        let imageButton = try #require(previewButtons.first {
            $0.identifier?.rawValue == PasteraFilePreviewKind.image.rawValue
        })
        imageButton.performClick(nil)
        let changedPreviewValues = try #require(defaults.dictionary(forKey: Constants.UserDefaults.filePreviewTypes))
        #expect((changedPreviewValues[PasteraFilePreviewKind.image.rawValue] as? NSNumber)?.boolValue == false)
        #expect((changedPreviewValues["LegacyPreviewKind"] as? NSNumber)?.boolValue == false)

        let filenamesButton = try #require(historyButtons(in: controller.view).first {
            $0.identifier?.rawValue == PasteboardAvailableType.filenames.rawValue
        })
        filenamesButton.performClick(nil)
        #expect(previewButtons.allSatisfy { !$0.isEnabled })
        #expect(defaults.dictionary(forKey: Constants.UserDefaults.filePreviewTypes) as NSDictionary? == changedPreviewValues as NSDictionary)
    }

    @Test
    func duplicateCopySwitchControlsOverwriteAvailabilityWithoutErasingItsValue() throws {
        let suiteName = "HistoryPreferenceTests.duplicates.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: Constants.UserDefaults.copySameHistory)
        defaults.set(true, forKey: Constants.UserDefaults.overwriteSameHistory)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYHistoryPreferenceViewController()
        _ = controller.view
        let copyButton = try #require(historyButtons(in: controller.view).first {
            $0.accessibilityIdentifier() == "history.copySameHistory"
        })
        let overwriteButton = try #require(historyButtons(in: controller.view).first {
            $0.accessibilityIdentifier() == "history.overwriteSameHistory"
        })

        #expect(!overwriteButton.isEnabled)
        #expect(defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory))
        copyButton.performClick(nil)
        #expect(defaults.bool(forKey: Constants.UserDefaults.copySameHistory))
        #expect(overwriteButton.isEnabled)
        #expect(defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory))
    }

    @Test
    func checkboxRowsOwnVisibleMeaningWithoutRepeatingItInsideControls() throws {
        let controller = CPYHistoryPreferenceViewController()
        _ = controller.view

        let typeKeys = Set(PasteboardAvailableType.allCases.map(\.rawValue))
        let previewKeys = Set(PasteraFilePreviewKind.allCases.map(\.rawValue))
        let allButtons = historyButtons(in: controller.view)
        let typeAndPreviewButtons = allButtons.filter { button in
            guard let key = button.identifier?.rawValue else { return false }
            return typeKeys.contains(key) || previewKeys.contains(key)
        }
        let visibleRowText = Set(historyTextFields(in: controller.view).map(\.stringValue).filter { !$0.isEmpty })

        #expect(typeAndPreviewButtons.count == typeKeys.count + previewKeys.count)
        for button in typeAndPreviewButtons {
            let accessibilityLabel = try #require(button.accessibilityLabel())
            #expect(button.title.isEmpty)
            #expect(visibleRowText.contains(accessibilityLabel))
        }

        let duplicateControls = try [
            #require(allButtons.first { $0.accessibilityIdentifier() == "history.copySameHistory" }),
            #require(allButtons.first { $0.accessibilityIdentifier() == "history.overwriteSameHistory" })
        ]
        #expect(duplicateControls.allSatisfy { $0.title.isEmpty })
        #expect(visibleRowText.contains("把已经复制的历史置顶"))
        #expect(visibleRowText.contains(
            pasteraPreferenceString("Move instead of copying (removes the older one from the list)")
        ))
    }

    @Test
    func historyPreferenceReloadKeepsStableHierarchyAndLiveDefaultsActions() throws {
        let suiteName = "HistoryPreferenceTests.reload.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([
            PasteboardAvailableType.string.rawValue: true
        ], forKey: Constants.UserDefaults.storeTypes)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let controller = CPYHistoryPreferenceViewController()
        let initialView = controller.view
        let initialGroupCount = historyPreferenceGroups(in: initialView).count
        let initialButtonCount = historyButtons(in: initialView).count

        controller.loadView()
        let reloadedView = controller.view

        #expect(initialGroupCount == 5)
        #expect(historyPreferenceGroups(in: reloadedView).count == initialGroupCount)
        #expect(historyButtons(in: reloadedView).count == initialButtonCount)
        let stringButton = try #require(historyButtons(in: reloadedView).first {
            $0.identifier?.rawValue == PasteboardAvailableType.string.rawValue
        })
        stringButton.performClick(nil)
        let stored = try #require(defaults.dictionary(forKey: Constants.UserDefaults.storeTypes))
        #expect((stored[PasteboardAvailableType.string.rawValue] as? NSNumber)?.boolValue == false)
    }
}

private func historyButtons(in view: NSView) -> [NSButton] {
    var values = view.subviews.compactMap { $0 as? NSButton }
    view.subviews.forEach { values.append(contentsOf: historyButtons(in: $0)) }
    return values
}

private func historyTextFields(in view: NSView) -> [NSTextField] {
    var values = view.subviews.compactMap { $0 as? NSTextField }
    view.subviews.forEach { values.append(contentsOf: historyTextFields(in: $0)) }
    return values
}

private func historyPreferenceGroups(in view: NSView) -> [PasteraPreferenceGroupView] {
    var values = view.subviews.compactMap { $0 as? PasteraPreferenceGroupView }
    view.subviews.forEach { values.append(contentsOf: historyPreferenceGroups(in: $0)) }
    return values
}

private func sendHistoryControlAction(_ control: NSControl) throws -> Bool {
    NSApp.sendAction(try #require(control.action), to: control.target, from: control)
}

private final class HistoryPreferenceRepository: PasteboardHistoryRepositoryProtocol {
    private(set) var pruneSettings = [HistoryRetentionSettings]()

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { false }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail] {
        []
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        []
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { nil }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}

    func pruneHistories(settings: HistoryRetentionSettings) {
        pruneSettings.append(settings)
    }
}
