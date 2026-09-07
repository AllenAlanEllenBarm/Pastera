// Copyright 2026 Feeyo

import AppKit
import Testing
@testable import Pastera

extension KeyboardAccessibilityTests {
    @Test
    func forceResetSaveFailureStaysInSheetWithExactArchiveCopyAndPreservesInput() throws {
        let page = CPYPasswordVaultPreferenceViewController(
            forceResetPassword: { _, completion in completion(.failure(.saveFailed)) }
        )
        page.loadView()
        page.applySecurityStateForTesting(.init(
            vaultState: .unlocked,
            isBusy: false,
            autoLockInterval: 300,
            quickUnlockEnabled: true,
            quickUnlockAvailable: true,
            masterPasswordResetCapability: .preservesData,
            forcedResetPending: false,
            forcedResetPendingFailure: nil
        ))
        let parent = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        parent.contentView = page.view
        parent.orderFront(nil)
        defer {
            if let sheet = parent.attachedSheet {
                parent.endSheet(sheet)
                sheet.orderOut(nil)
            }
            parent.orderOut(nil)
        }

        page.openForceResetSheetForTesting()
        let sheetController = try #require(page.forceSheetForTesting)
        let sheet = try #require(sheetController.window)
        sheetController.setValuesForTesting(new: "new-password", confirmation: "new-password")
        sheetController.setAcknowledgementForTesting(true)

        sheetController.submitForTesting()

        let contentView = try #require(sheet.contentView)
        let errorLabel = try #require(allSubviews(in: contentView)
            .compactMap { $0 as? NSTextField }
            .first { $0.accessibilityIdentifier() == "forceReset.generalError" })
        let acknowledgement = try #require(allSubviews(in: contentView)
            .compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "forceReset.acknowledgement" })
        #expect(parent.attachedSheet === sheet)
        #expect(errorLabel.stringValue == String(localized:
            "The local encrypted archive could not be created, so no reset occurred."
        ))
        #expect(sheetController.valuesForTesting.new == "new-password")
        #expect(sheetController.valuesForTesting.confirmation == "new-password")
        #expect(acknowledgement.state == .on)
        #expect(!page.passwordVaultForceFeedbackVisibleForTesting)
    }

    @Test
    func forceResetRecoveryErrorPointsToTheLocalRecoveryAction() throws {
        let controller = PasswordVaultForceResetSheetController { _, completion in
            completion(.failure(.recoveryRequired))
        }
        let window = try #require(controller.window)
        controller.showWindow(nil)
        defer { window.orderOut(nil) }
        controller.setValuesForTesting(new: "new-password", confirmation: "new-password")
        controller.setAcknowledgementForTesting(true)

        controller.submitForTesting()

        let contentView = try #require(window.contentView)
        let errorLabel = try #require(allSubviews(in: contentView)
            .compactMap { $0 as? NSTextField }
            .first { $0.accessibilityIdentifier() == "forceReset.generalError" })
        #expect(errorLabel.stringValue == String(localized:
            "Open Password Vault settings, choose Retry Local Recovery, then try the forced reset again."
        ))
        #expect(window.isVisible)
    }

    @Test
    func masterPasswordResetRecoveryErrorPointsToSettingsAndAccessibleRetryAction() throws {
        let controller = PasswordVaultMasterPasswordSheetController { _, completion in
            completion(.failure(.recoveryRequired))
        }
        let window = try #require(controller.window)
        controller.showWindow(nil)
        defer { window.orderOut(nil) }
        controller.setValuesForTesting(new: "new-password", confirmation: "new-password")

        controller.submitForTesting()

        let expected = String(localized:
            "Close this window, open Password Vault settings, choose Retry Local Recovery, then try again."
        )
        let contentView = try #require(window.contentView)
        let errorLabel = try #require(allSubviews(in: contentView)
            .compactMap { $0 as? NSTextField }
            .first { $0.accessibilityIdentifier() == "masterPassword.generalError" })
        #expect(errorLabel.stringValue == expected)
        #expect(errorLabel.accessibilityLabel() == expected)
        #expect(controller.valuesForTesting.new == "new-password")
        #expect(controller.valuesForTesting.confirmation == "new-password")
        #expect(window.isVisible)
    }

    @Test
    func resetSheetRealKeyLoopUsesActiveFieldsForEveryVisibilityCombination() throws {
        for visibility in passwordVisibilityCombinations {
            let controller = PasswordVaultMasterPasswordSheetController { _, _ in }
            let window = try #require(controller.window)
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try setPasswordVisibility(
                newVisible: visibility.new,
                confirmationVisible: visibility.confirmation,
                in: window,
                newIdentifier: "masterPassword.new",
                confirmationIdentifier: "masterPassword.confirmation"
            )
            let newField = try activePasswordField(identifier: "masterPassword.new", in: window)

            #expect(realKeyViewLoop(from: newField, count: 4) == [
                "masterPassword.new",
                "masterPassword.confirmation",
                "masterPassword.cancel",
                "masterPassword.submit"
            ])
            #expect(realKeyView(after: 4, from: newField) === newField)
        }
    }

    @Test
    func forceResetSheetRealKeyLoopUsesActiveFieldsForEveryVisibilityCombination() throws {
        for visibility in passwordVisibilityCombinations {
            let controller = PasswordVaultForceResetSheetController { _, _ in }
            let window = try #require(controller.window)
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try setPasswordVisibility(
                newVisible: visibility.new,
                confirmationVisible: visibility.confirmation,
                in: window,
                newIdentifier: "forceReset.new",
                confirmationIdentifier: "forceReset.confirmation"
            )
            let newField = try activePasswordField(identifier: "forceReset.new", in: window)

            #expect(realKeyViewLoop(from: newField, count: 5) == [
                "forceReset.new",
                "forceReset.confirmation",
                "forceReset.acknowledgement",
                "forceReset.cancel",
                "forceReset.submit"
            ])
            #expect(realKeyView(after: 5, from: newField) === newField)
        }
    }

    @Test
    func resetSheetRealEscapeWaitsForIdleThenEndsSheetRestoresFocusAndClearsSecrets() throws {
        var pendingCompletion: ((Result<PasswordVaultMasterPasswordResetResult, PasswordVaultError>) -> Void)?
        let controller = PasswordVaultMasterPasswordSheetController { _, completion in
            pendingCompletion = completion
        }
        let sheet = try #require(controller.window)
        let fixture = try SheetLifecycleFixture(sheet: sheet) { controller.beginSheet(for: $0) }
        defer { fixture.orderOutWithoutClosing() }
        controller.setValuesForTesting(new: "new-password", confirmation: "new-password")
        controller.submitForTesting()

        fixture.sendEscape()

        #expect(fixture.parent.attachedSheet === controller.window)
        #expect(controller.valuesForTesting.new == "new-password")
        #expect(controller.valuesForTesting.confirmation == "new-password")

        pendingCompletion?(.failure(.userCancelled))
        fixture.sendEscape()

        #expect(fixture.parent.attachedSheet == nil)
        #expect(fixture.parent.firstResponder === fixture.priorFirstResponder)
        #expect(controller.valuesForTesting.new.isEmpty)
        #expect(controller.valuesForTesting.confirmation.isEmpty)
    }

    @Test
    func forceResetSheetRealEscapeWaitsForIdleThenEndsSheetRestoresFocusAndClearsSecrets() throws {
        var pendingCompletion: ((Result<PasswordVaultForcedResetOutcome, PasswordVaultError>) -> Void)?
        let controller = PasswordVaultForceResetSheetController { _, completion in
            pendingCompletion = completion
        }
        let sheet = try #require(controller.window)
        let fixture = try SheetLifecycleFixture(sheet: sheet) { controller.beginSheet(for: $0) }
        defer { fixture.orderOutWithoutClosing() }
        controller.setValuesForTesting(new: "new-password", confirmation: "new-password")
        controller.setAcknowledgementForTesting(true)
        controller.submitForTesting()

        fixture.sendEscape()

        #expect(fixture.parent.attachedSheet === controller.window)
        #expect(controller.valuesForTesting.new == "new-password")
        #expect(controller.valuesForTesting.confirmation == "new-password")

        pendingCompletion?(.failure(.authenticationFailed))
        fixture.sendEscape()

        #expect(fixture.parent.attachedSheet == nil)
        #expect(fixture.parent.firstResponder === fixture.priorFirstResponder)
        #expect(controller.valuesForTesting.new.isEmpty)
        #expect(controller.valuesForTesting.confirmation.isEmpty)
    }
}

private let passwordVisibilityCombinations = [
    (new: false, confirmation: false),
    (new: false, confirmation: true),
    (new: true, confirmation: false),
    (new: true, confirmation: true)
]

private func setPasswordVisibility(
    newVisible: Bool,
    confirmationVisible: Bool,
    in window: NSWindow,
    newIdentifier: String,
    confirmationIdentifier: String
) throws {
    if newVisible {
        let button = try visibilityButton(for: newIdentifier, in: window)
        button.performClick(nil)
    }
    if confirmationVisible {
        let button = try visibilityButton(for: confirmationIdentifier, in: window)
        button.performClick(nil)
    }
}

private func visibilityButton(for identifier: String, in window: NSWindow) throws -> NSButton {
    let field = try activePasswordField(identifier: identifier, in: window)
    let row = try #require(field.superview?.superview)
    return try #require(row.subviews.compactMap { $0 as? NSButton }.first)
}

private func activePasswordField(identifier: String, in window: NSWindow) throws -> NSTextField {
    let contentView = try #require(window.contentView)
    return try #require(allSubviews(in: contentView).compactMap { $0 as? NSTextField }.first {
        !$0.isHidden && $0.accessibilityIdentifier() == identifier
    })
}

private func allSubviews(in view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(allSubviews(in:))
}

private func realKeyViewLoop(from start: NSView, count: Int) -> [String] {
    var current: NSView? = start
    return (0..<count).map { _ in
        defer { current = current?.nextValidKeyView }
        return current?.accessibilityIdentifier() ?? "<missing>"
    }
}

private func realKeyView(after steps: Int, from start: NSView) -> NSView? {
    (0..<steps).reduce(Optional(start)) { current, _ in current?.nextValidKeyView }
}

@MainActor
private final class SheetLifecycleFixture {
    let parent: NSPanel
    let priorFirstResponder: NSResponder
    private let sheet: NSWindow

    init(sheet: NSWindow, beginSheet: (NSPanel) -> Void) throws {
        parent = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        let priorField = NSTextField(string: "prior")
        parent.contentView = priorField
        parent.orderFront(nil)
        #expect(parent.makeFirstResponder(priorField))
        priorFirstResponder = try #require(parent.firstResponder)
        self.sheet = sheet
        beginSheet(parent)
        #expect(parent.attachedSheet === sheet)
    }

    func sendEscape() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: sheet.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        )!
        sheet.keyDown(with: event)
    }

    func orderOutWithoutClosing() {
        if let attachedSheet = parent.attachedSheet {
            parent.endSheet(attachedSheet)
            attachedSheet.orderOut(nil)
        }
        sheet.orderOut(nil)
        parent.orderOut(nil)
    }
}
