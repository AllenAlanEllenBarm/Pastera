//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Carbon
import Dependencies
import Foundation
import Sauce

struct PasteTargetContext {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let application: NSRunningApplication?
    let focusedElement: AXUIElement?

    static func capture() -> PasteTargetContext? {
        capture(from: NSWorkspace.shared.frontmostApplication)
    }

    static func capture(from application: NSRunningApplication?) -> PasteTargetContext? {
        guard let application else { return nil }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }

        return PasteTargetContext(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            application: application,
            focusedElement: focusedElement(for: application.processIdentifier)
        )
    }

    private static func focusedElement(for processIdentifier: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

struct PasteboardHistorySelectionRequest {
    let id: PasteboardHistory.ID
    let targetContext: PasteTargetContext?
}

struct SnippetSelectionRequest {
    let id: Snippet.ID
    let targetContext: PasteTargetContext?
}

final class PasteService {
    private enum RestoreMetrics {
        static let interval: TimeInterval = 0.02
        static let focusSettleDelay: TimeInterval = 0.04
        static let maxAttempts = 12
    }

    // MARK: - Properties
    fileprivate let lock = NSRecursiveLock(name: "com.pastera-app.Pastera.Pastable")

    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository

    var inputPasteCommandEnabledProvider: () -> Bool
    var accessibilityEnabledProvider: () -> Bool
    var accessibilityAlertPresenter: () -> Void
    var frontmostProcessIdentifierProvider: () -> pid_t?
    var targetApplicationActivator: (PasteTargetContext) -> Void
    var focusedElementRestorer: (PasteTargetContext) -> Void
    var pasteCommandSender: () -> Void
    var secureEventInputEnabledProvider: () -> Bool
    var textInputSender: (String) -> Void
    var scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void

    init(
        inputPasteCommandEnabledProvider: @escaping () -> Bool = {
            AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand)
        },
        accessibilityEnabledProvider: @escaping () -> Bool = {
            AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false)
        },
        accessibilityAlertPresenter: @escaping () -> Void = {
            AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
        },
        frontmostProcessIdentifierProvider: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        targetApplicationActivator: @escaping (PasteTargetContext) -> Void = { context in
            PasteService.activateTargetApplication(for: context)
        },
        focusedElementRestorer: @escaping (PasteTargetContext) -> Void = { context in
            PasteService.restoreFocusedElement(for: context)
        },
        pasteCommandSender: @escaping () -> Void = {
            PasteService.postPasteCommand()
        },
        secureEventInputEnabledProvider: @escaping () -> Bool = {
            IsSecureEventInputEnabled()
        },
        textInputSender: @escaping (String) -> Void = { text in
            PasteService.postTextInput(text)
        },
        scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.inputPasteCommandEnabledProvider = inputPasteCommandEnabledProvider
        self.accessibilityEnabledProvider = accessibilityEnabledProvider
        self.accessibilityAlertPresenter = accessibilityAlertPresenter
        self.frontmostProcessIdentifierProvider = frontmostProcessIdentifierProvider
        self.targetApplicationActivator = targetApplicationActivator
        self.focusedElementRestorer = focusedElementRestorer
        self.pasteCommandSender = pasteCommandSender
        self.secureEventInputEnabledProvider = secureEventInputEnabledProvider
        self.textInputSender = textInputSender
        self.scheduleAfter = scheduleAfter
    }

    fileprivate var isPastePlainText: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pastePlainText) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pastePlainTextModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.deleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.deleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isPasteAndDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pasteAndDeleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pasteAndDeleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }

    // MARK: - Modifiers
    private func isPressedModifier(_ flag: Int) -> Bool {
        let flags = NSEvent.modifierFlags
        if flag == 0 && flags.contains(.command) {
            return true
        } else if flag == 1 && flags.contains(.shift) {
            return true
        } else if flag == 2 && flags.contains(.control) {
            return true
        } else if flag == 3 && flags.contains(.option) {
            return true
        }
        return false
    }
}

// MARK: - Copy
extension PasteService {
    func paste(with history: PasteboardHistory) {
        paste(with: history, restoring: nil)
    }

    func paste(with history: PasteboardHistory, restoring targetContext: PasteTargetContext?) {
        guard let content = pasteboardHistoryRepository.fetchContent(id: history.id) else { return }

        // Handling modifier actions
        let isPastePlainText = self.isPastePlainText
        let isPasteAndDeleteHistory = self.isPasteAndDeleteHistory
        let isDeleteHistory = self.isDeleteHistory
        guard isPastePlainText || isPasteAndDeleteHistory || isDeleteHistory else {
            copyToPasteboard(with: content)
            paste(restoring: targetContext)
            return
        }

        // Increment change count for don't copy paste item
        if isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.incrementChangeCount()
        }
        // Paste history
        if isPastePlainText {
            copyToPasteboard(with: content.stringValue)
            paste(restoring: targetContext)
        } else if isPasteAndDeleteHistory {
            copyToPasteboard(with: content)
            paste(restoring: targetContext)
        }
        // Delete clip
        if isDeleteHistory || isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.delete(with: history)
        }
    }

    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(string, forType: .string)
    }

    private func copyToPasteboard(with content: PasteboardContent) {
        if isPastePlainText {
            copyToPasteboard(with: content.stringValue)
            return
        }

        copyContentToPasteboard(content, to: .general)
    }

    func copyContentToPasteboard(_ content: PasteboardContent, to pasteboard: NSPasteboard) {
        lock.lock(); defer { lock.unlock() }

        let items = pasteboardItems(for: content)
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    private func pasteboardItems(for content: PasteboardContent) -> [NSPasteboardItem] {
        var countsByType: [NSPasteboard.PasteboardType: Int] = [:]
        var generalItems = [NSPasteboardItem]()
        var items = [NSPasteboardItem]()

        for asset in content.assets {
            if asset.type.isClipyImageType {
                let item = NSPasteboardItem()
                setImageAsset(asset, on: item)
                items.append(item)
            } else {
                let index = countsByType[asset.type] ?? 0
                countsByType[asset.type] = index + 1
                if !generalItems.indices.contains(index) {
                    let item = NSPasteboardItem()
                    generalItems.append(item)
                    items.append(item)
                }
                generalItems[index].setData(asset.data, forType: asset.type)
            }
        }

        return items
    }

    private func setImageAsset(_ asset: PasteboardContent.Asset, on item: NSPasteboardItem) {
        switch asset.type {
        case .clipySnipastePNG:
            item.setData(asset.data, forType: asset.type)
            item.setData(asset.data, forType: .png)
        case .clipyApplePNG:
            item.setData(asset.data, forType: .png)
        case .deprecatedTIFF:
            item.setData(asset.data, forType: .tiff)
        default:
            item.setData(asset.data, forType: asset.type)
            guard asset.type != .png, asset.type != .tiff,
                  let image = NSImage(data: asset.data),
                  let pngData = PasteraImageEncoding.pngData(from: image)
            else {
                return
            }
            item.setData(pngData, forType: .png)
        }
    }
}

// MARK: - Paste
extension PasteService {
    func paste() {
        paste(restoring: nil)
    }

    func paste(restoring targetContext: PasteTargetContext?) {
        paste(restoring: targetContext) { [weak self] in
            self?.pasteCommandSender()
        }
    }

    func pasteText(_ text: String, restoring targetContext: PasteTargetContext?) {
        copyToPasteboard(with: text)
        paste(restoring: targetContext) { [weak self] in
            guard let self else { return }
            if self.secureEventInputEnabledProvider() {
                self.textInputSender(text)
            } else {
                self.pasteCommandSender()
            }
        }
    }

    private func paste(restoring targetContext: PasteTargetContext?, sendPaste: @escaping () -> Void) {
        guard inputPasteCommandEnabledProvider() else { return }
        // Check Accessibility Permission
        guard accessibilityEnabledProvider() else {
            accessibilityAlertPresenter()
            return
        }

        guard let targetContext else {
            scheduleAfter(0) { [weak self] in
                guard self != nil else { return }
                sendPaste()
            }
            return
        }

        targetApplicationActivator(targetContext)
        waitForTargetAndPaste(targetContext, attempt: 0, sendPaste: sendPaste)
    }

    private func waitForTargetAndPaste(
        _ targetContext: PasteTargetContext,
        attempt: Int,
        sendPaste: @escaping () -> Void
    ) {
        if frontmostProcessIdentifierProvider() == targetContext.processIdentifier || attempt >= RestoreMetrics.maxAttempts {
            restoreFocusThenPaste(targetContext, sendPaste: sendPaste)
            return
        }

        scheduleAfter(RestoreMetrics.interval) { [weak self] in
            self?.waitForTargetAndPaste(targetContext, attempt: attempt + 1, sendPaste: sendPaste)
        }
    }

    private func restoreFocusThenPaste(_ targetContext: PasteTargetContext, sendPaste: @escaping () -> Void) {
        focusedElementRestorer(targetContext)
        scheduleAfter(RestoreMetrics.focusSettleDelay) { [weak self] in
            guard self != nil else { return }
            sendPaste()
        }
    }

    private static func activateTargetApplication(for context: PasteTargetContext) {
        guard let application = context.application ?? NSRunningApplication(processIdentifier: context.processIdentifier) else {
            return
        }
        guard !application.isTerminated else { return }
        application.activate(options: [.activateIgnoringOtherApps])
    }

    private static func restoreFocusedElement(for context: PasteTargetContext) {
        guard let focusedElement = context.focusedElement else { return }
        AXUIElementSetAttributeValue(focusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func postPasteCommand() {
        let vKeyCode = Sauce.shared.keyCode(for: .v, cocoaModifiers: .command)
        let source = CGEventSource(stateID: .combinedSessionState)
        // Disable local keyboard events while pasting
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        // Press Command + V
        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyVDown?.flags = .maskCommand
        // Release Command + V
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyVUp?.flags = .maskCommand
        // Post Paste Command
        keyVDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyVUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func postTextInput(_ text: String) {
        guard !text.isEmpty else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        for character in text {
            let utf16 = Array(String(character).utf16)
            utf16.withUnsafeBufferPointer { buffer in
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buffer.baseAddress)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buffer.baseAddress)
                keyDown?.post(tap: .cgAnnotatedSessionEventTap)
                keyUp?.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }
}
