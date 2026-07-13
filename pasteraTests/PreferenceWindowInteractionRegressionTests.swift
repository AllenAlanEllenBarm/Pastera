//
//  PreferenceWindowInteractionRegressionTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct PreferenceWindowInteractionRegressionTests {
    @Test
    func productionRouteSelectsAboutPane() {
        let controller = CPYPreferencesWindowController(
            frameAutosaveName: "PreferenceWindowInteractionRegressionTests.About.\(UUID().uuidString)",
            reduceMotion: { true },
            deactivateApplication: {}
        )
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePane(.about)

        #expect(controller.selectedPreferencePaneIDForTesting == .about)
    }

    @Test
    func escapeRestoresNumericDraftBeforeClosingWindow() throws {
        let defaults = AppEnvironment.current.defaults
        let previousValue = defaults.object(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: Constants.UserDefaults.maxMenuItemTitleLength)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
            }
        }
        defaults.set(20, forKey: Constants.UserDefaults.maxMenuItemTitleLength)

        let controller = CPYPreferencesWindowController(
            frameAutosaveName: "PreferenceWindowInteractionRegressionTests.\(UUID().uuidString)",
            reduceMotion: { true },
            deactivateApplication: {}
        )
        defer { controller.close() }
        controller.showWindow(nil)
        let contentView = try #require(controller.window?.contentView)
        let field = try #require(textFields(in: contentView).first {
            $0.accessibilityLabel() == pasteraPreferenceString("Menu Title Length")
        })
        #expect(controller.window?.makeFirstResponder(field) == true)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = "invalid"

        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
        controller.window?.keyDown(with: escape)

        #expect(controller.window?.isVisible == true)
        #expect(field.stringValue == "20")
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var fields = view.subviews.compactMap { $0 as? NSTextField }
        view.subviews.forEach { fields.append(contentsOf: textFields(in: $0)) }
        return fields
    }
}
