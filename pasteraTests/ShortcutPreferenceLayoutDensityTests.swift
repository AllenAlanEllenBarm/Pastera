//
//  ShortcutPreferenceLayoutDensityTests.swift
//
//  Pastera
//

import AppKit
import KeyHolder
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct ShortcutPreferenceLayoutDensityTests {
    @Test
    func shortcutsPaneUsesTwoNativeGroupCardsWithoutDuplicateLabelsOrClipping() throws {
        let controller = CPYPreferencesWindowController(deactivateApplication: {})
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let page = try #require(
            controller.cachedPreferencePageForTesting(paneID: .shortcuts)
                as? CPYShortcutsPreferenceViewController
        )
        page.view.layoutSubtreeIfNeeded()
        let groups = preferenceGroups(in: page.view)
        let recordViews = preferenceRecordViews(in: page.view)
        let textFields = preferenceTextFields(in: page.view)
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let menuCard = try #require(groups.first {
            $0.accessibilityIdentifier() == "shortcuts.menu"
        })
        let historyPanelCard = try #require(groups.first {
            $0.accessibilityIdentifier() == "shortcuts.historyPanel"
        })
        let expectedRows: [(String, String, PasteraPreferenceGroupView)] = [
            (pasteraPreferenceString("Main"), "shortcuts.main", menuCard),
            (pasteraPreferenceString("History"), "shortcuts.history", menuCard),
            (pasteraPreferenceString("Snippets"), "shortcuts.snippet", menuCard),
            (pasteraPreferenceString("Password Vault"), "shortcuts.passwordVault", menuCard),
            (pasteraPreferenceString("Search"), "shortcuts.historyPanel.search", historyPanelCard),
            (
                pasteraPreferenceString("Previous Page"),
                "shortcuts.historyPanel.previousPage",
                historyPanelCard
            ),
            (pasteraPreferenceString("Next Page"), "shortcuts.historyPanel.nextPage", historyPanelCard)
        ]

        #expect(page.paneID == .shortcuts)
        #expect(groups.count == 2)
        #expect(recordViews.count == 7)
        #expect(Set(recordViews.compactMap { $0.accessibilityIdentifier() }).count == 7)
        for (label, recordIdentifier, card) in expectedRows {
            let matchingLabels = textFields.filter { $0.stringValue == label }
            let matchingRecordViews = recordViews.filter {
                $0.accessibilityIdentifier() == recordIdentifier
            }
            #expect(matchingLabels.count == 1)
            #expect(matchingRecordViews.count == 1)
            let labelView = try #require(matchingLabels.first)
            let recordView = try #require(matchingRecordViews.first)
            #expect(!labelView.isHidden)
            #expect(!recordView.isHidden)
            #expect(labelView.isDescendant(of: card))
            #expect(recordView.isDescendant(of: card))
            expectContained(labelView, in: card)
            expectContained(recordView, in: card)
            expectContained(recordView, in: paneFrame, contentView: contentView)
            expectContained(labelView, in: paneFrame, contentView: contentView)
            #expect(recordView.frame.width >= 180)
            #expect(recordView.frame.height == 24)
        }

        for (identifier, card) in [
            ("shortcuts.menu.reset", menuCard),
            ("shortcuts.historyPanel.reset", historyPanelCard)
        ] {
            let matchingButtons = preferenceButtons(in: page.view).filter {
                $0.accessibilityIdentifier() == identifier
            }
            #expect(matchingButtons.count == 1)
            let button = try #require(matchingButtons.first)
            #expect(!button.isHidden)
            #expect(button.isDescendant(of: card))
            expectContained(button, in: card)
            expectContained(button, in: paneFrame, contentView: contentView)
        }
        #expect(controller.selectedPaneDocumentHeightForTesting <= controller.preferencePaneViewportHeightForTesting)
        #expect(page.shortcutRowMinimumHeightForTesting == 38)
        #expect(page.shortcutRecordHeightForTesting == 24)
        #expect(controller.preferencePaneVisibleBottomGapForTesting >= 56)
        #expect(page.revealSetting(anchorID: "shortcuts.menu", animated: false))
        #expect(page.revealSetting(anchorID: "shortcuts.historyPanel", animated: false))
    }

    private func preferenceGroups(in view: NSView) -> [PasteraPreferenceGroupView] {
        shortcutLayoutSubviews(in: view).compactMap { $0 as? PasteraPreferenceGroupView }
    }

    private func preferenceRecordViews(in view: NSView) -> [RecordView] {
        shortcutLayoutSubviews(in: view).compactMap { $0 as? RecordView }
    }

    private func preferenceTextFields(in view: NSView) -> [NSTextField] {
        shortcutLayoutSubviews(in: view).compactMap { $0 as? NSTextField }
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        shortcutLayoutSubviews(in: view).compactMap { $0 as? NSButton }
    }

    private func shortcutLayoutSubviews(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + shortcutLayoutSubviews(in: $0) }
    }

    private func expectContained(_ view: NSView, in container: NSView) {
        let alignmentFrame = view.alignmentRect(forFrame: view.frame)
        let frame = container.convert(alignmentFrame, from: view.superview)
        expectContained(
            frame,
            in: container.bounds,
            context: "\(description(of: view)) in \(container.accessibilityIdentifier() ?? "card")"
        )
    }

    private func expectContained(_ view: NSView, in bounds: NSRect, contentView: NSView) {
        let alignmentFrame = view.alignmentRect(forFrame: view.frame)
        let frame = contentView.convert(alignmentFrame, from: view.superview)
        expectContained(frame, in: bounds, context: "\(description(of: view)) in visible pane")
    }

    private func expectContained(_ frame: NSRect, in bounds: NSRect, context: String) {
        let tolerance: CGFloat = 0.5
        #expect(frame.minX >= bounds.minX - tolerance, "\(context): leading overflow")
        #expect(frame.maxX <= bounds.maxX + tolerance, "\(context): trailing overflow")
        #expect(frame.minY >= bounds.minY - tolerance, "\(context): bottom overflow")
        #expect(frame.maxY <= bounds.maxY + tolerance, "\(context): top overflow")
    }

    private func description(of view: NSView) -> String {
        if let textField = view as? NSTextField { return textField.stringValue }
        return view.accessibilityIdentifier() ?? String(describing: type(of: view))
    }
}
