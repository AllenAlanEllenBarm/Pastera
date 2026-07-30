//
//  HotKeyService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/19.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Carbon
import Dependencies
import Foundation
import Magnet

struct RemoteSessionHotKeyPolicy {
    private static let remoteSessionBundleIdentifiers: Set<String> = [
        "com.apple.ScreenSharing",
        "com.apple.RemoteDesktop"
    ]

    static func shouldSuspendLocalHotKeys(
        frontmostApplicationBundleIdentifier bundleIdentifier: String?,
        isEnabled: Bool = AppEnvironment.current.defaults.bool(forKey: Constants.HotKey.suspendDuringRemoteSession)
    ) -> Bool {
        guard isEnabled else {
            return false
        }
        guard let bundleIdentifier else { return false }
        return remoteSessionBundleIdentifiers.contains(bundleIdentifier)
    }
}

enum HistoryPanelShortcut: CaseIterable, Hashable {
    case search
    case previousPage
    case nextPage

    var isUserConfigurable: Bool {
        self == .search
    }

    var userDefaultsKey: String {
        switch self {
        case .search:
            return Constants.HotKey.historySearchKeyCombo
        case .previousPage:
            return Constants.HotKey.historyPreviousPageKeyCombo
        case .nextPage:
            return Constants.HotKey.historyNextPageKeyCombo
        }
    }

    var defaultKeyCombo: KeyCombo {
        switch self {
        case .search:
            return KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey)!
        case .previousPage:
            return KeyCombo(QWERTYKeyCode: 123, carbonModifiers: 0)!
        case .nextPage:
            return KeyCombo(QWERTYKeyCode: 124, carbonModifiers: 0)!
        }
    }

    var commandDefaultKeyCombo: KeyCombo {
        switch self {
        case .search:
            return KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey)!
        case .previousPage:
            return KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey)!
        case .nextPage:
            return KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey)!
        }
    }

    var optionCommandDefaultKeyCombo: KeyCombo {
        switch self {
        case .search:
            return KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | optionKey)!
        case .previousPage:
            return KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey | optionKey)!
        case .nextPage:
            return KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey | optionKey)!
        }
    }

    var incorrectLegacyDefaultKeyCombos: [KeyCombo] {
        switch self {
        case .search:
            return [KeyCombo(QWERTYKeyCode: 17, carbonModifiers: cmdKey | optionKey)!]
        case .previousPage:
            return []
        case .nextPage:
            return [
                KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey)!,
                KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey | optionKey)!
            ]
        }
    }

    func shouldMigrateToCanonicalDefault(_ keyCombo: KeyCombo) -> Bool {
        if keyCombo == commandDefaultKeyCombo {
            return true
        }
        if keyCombo == optionCommandDefaultKeyCombo {
            return true
        }
        if incorrectLegacyDefaultKeyCombos.contains(keyCombo) {
            return true
        }
        return false
    }

    func matches(_ event: NSEvent, keyCombo: KeyCombo?) -> Bool {
        guard event.type == .keyDown, let keyCombo, !keyCombo.doubledModifiers else { return false }
        let ignoredSystemFlags: NSEvent.ModifierFlags = [.numericPad, .function]
        let eventFlags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(ignoredSystemFlags)
        let comboFlags = keyCombo.keyEquivalentModifierMask
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(ignoredSystemFlags)
        return Int(event.keyCode) == keyCombo.QWERTYKeyCode && eventFlags == comboFlags
    }

    static func matching(_ event: NSEvent, hotKeyService: HotKeyService) -> HistoryPanelShortcut? {
        allCases.first { shortcut in
            shortcut.matches(event, keyCombo: hotKeyService.historyPanelKeyCombo(for: shortcut))
        }
    }
}

final class HotKeyService: NSObject {
    // MARK: - Properties
    static var defaultKeyCombos: [String: Any] = {
        return [
            Constants.Menu.clip: [
                "keyCode": defaultMainKeyCombo.QWERTYKeyCode,
                "modifiers": defaultMainKeyCombo.modifiers
            ],
            Constants.Menu.history: [
                "keyCode": defaultHistoryKeyCombo.QWERTYKeyCode,
                "modifiers": defaultHistoryKeyCombo.modifiers
            ],
            Constants.Menu.snippet: [
                "keyCode": defaultSnippetKeyCombo.QWERTYKeyCode,
                "modifiers": defaultSnippetKeyCombo.modifiers
            ]
        ]
    }()

    private static let defaultMainKeyCombo = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey)!
    private static let defaultHistoryKeyCombo = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | optionKey)!
    private static let oldOptionCommandSnippetKeyCombo = KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | optionKey)!
    private static let previousDefaultSnippetKeyCombo = KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | optionKey)!
    private static let defaultSnippetKeyCombo = KeyCombo(QWERTYKeyCode: 46, carbonModifiers: cmdKey | shiftKey)!
    private static let defaultPasswordVaultKeyCombo = KeyCombo(QWERTYKeyCode: 35, carbonModifiers: controlKey | optionKey)!
    private static let legacyDefaultHistoryKeyCombo = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | controlKey)!
    private static let legacyDefaultSnippetKeyCombo = KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | shiftKey)!
    private static let defaultSnippetFolderHotKeyModifiers = cmdKey | optionKey
    private static let defaultSnippetFolderHotKeyCodes = [12, 13, 14, 17, 16, 32]

    fileprivate(set) var mainKeyCombo: KeyCombo?
    fileprivate(set) var historyKeyCombo: KeyCombo?
    fileprivate(set) var snippetKeyCombo: KeyCombo?
    fileprivate(set) var passwordVaultKeyCombo: KeyCombo?
    fileprivate(set) var clearHistoryKeyCombo: KeyCombo?
    fileprivate(set) var scriptTransformKeyCombo: KeyCombo?
    private var historyPanelKeyCombos = [HistoryPanelShortcut: KeyCombo]()
    fileprivate(set) var isSuspendedForRemoteSession = false
    private var remoteSessionObserver: NSObjectProtocol?
    private let defaults: UserDefaults

    @Dependency(\.snippetRepository)
    private var snippetRepository

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    deinit {
        if let remoteSessionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(remoteSessionObserver)
        }
    }
}

enum PasteraShortcutFormatter {
    static func string(for keyCombo: KeyCombo?) -> String? {
        guard let keyCombo else { return nil }
        let modifiers = keyCombo.keyEquivalentModifierMaskString

        if keyCombo.doubledModifiers {
            guard !modifiers.isEmpty else { return nil }
            return modifiers + modifiers
        }

        if let arrowKey = arrowKeyEquivalent(for: keyCombo.QWERTYKeyCode) {
            return modifiers + arrowKey
        }

        let key = keyCombo.keyEquivalent.uppercased()
        let text = modifiers + key
        return text.isEmpty ? nil : text
    }

    private static func arrowKeyEquivalent(for keyCode: Int) -> String? {
        switch keyCode {
        case 123:
            return "←"
        case 124:
            return "→"
        default:
            return nil
        }
    }

    static func numericString(forRowIndex index: Int, startsAtZero: Bool) -> String? {
        HistoryMenuNumberShortcutMapper.shortcutText(forRowIndex: index, startsAtZero: startsAtZero)
    }
}

// MARK: - Actions
extension HotKeyService {
    @objc func popupMainMenu() {
        AppEnvironment.current.menuManager.popUpMenu(.main)
    }

    @objc func popupHistoryMenu(_ object: AnyObject) {
        let triggerKeyCombo = (object as? HotKey)?.keyCombo ?? historyKeyCombo
        AppEnvironment.current.menuManager.popUpMenu(.history, triggerKeyCombo: triggerKeyCombo)
    }

    @objc func popUpSnippetMenu(_ object: AnyObject) {
        let triggerKeyCombo = (object as? HotKey)?.keyCombo ?? snippetKeyCombo
        AppEnvironment.current.menuManager.popUpMenu(.snippet, triggerKeyCombo: triggerKeyCombo)
    }

    @objc func popupPasswordVaultMenu() {
        AppEnvironment.current.menuManager.popUpMenu(.passwordVault)
    }

    @objc func popUpClearHistoryAlert() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.clearAllHistory()
    }

    @objc func runClipboardScriptTransform() {
        Task {
            await AppEnvironment.current.clipboardScriptCoordinator.runManualTransform()
        }
    }
}

// MARK: - Setup
extension HotKeyService {
    func setupDefaultHotKeys() {
        // Migration new framework
        if !defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) {
            migrationKeyCombos()
            defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
            defaults.synchronize()
        }
        migrateOptionCommandDefaultKeyCombosIfNeeded()
        migrateSnippetDefaultKeyComboToFIfNeeded()
        migrateSnippetDefaultKeyComboToShiftCommandMIfNeeded()
        migratePasswordVaultDefaultKeyComboIfNeeded()
        migrateHistoryPanelShortcutDefaultsIfNeeded()
        migrateHistoryPanelDefaultsV2IfNeeded()
        migrateHistoryPanelCanonicalDefaultsIfNeeded()
        migrateHistoryPanelCanonicalDefaultsV2IfNeeded()
        migrateHistoryPanelCommandDefaultsIfNeeded()
        // Snippet hotkey
        setupSnippetHotKeys()

        // Main menu
        change(with: .main, keyCombo: savedKeyCombo(forKey: Constants.HotKey.mainKeyCombo))
        // History menu
        change(with: .history, keyCombo: savedKeyCombo(forKey: Constants.HotKey.historyKeyCombo))
        // Snippet menu
        change(with: .snippet, keyCombo: savedKeyCombo(forKey: Constants.HotKey.snippetKeyCombo))
        change(with: .passwordVault, keyCombo: savedKeyCombo(forKey: Constants.HotKey.passwordVaultKeyCombo))
        // Clear History
        changeClearHistoryKeyCombo(savedKeyCombo(forKey: Constants.HotKey.clearHistoryKeyCombo))
        changeScriptTransformKeyCombo(savedKeyCombo(forKey: Constants.HotKey.scriptTransformKeyCombo))
        setupHistoryPanelKeyCombos()
        startMonitoringRemoteSessionApplications()
        updateRemoteSessionHotKeyState(
            frontmostApplicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    func change(with type: MenuType, keyCombo: KeyCombo?) {
        switch type {
        case .main:
            mainKeyCombo = keyCombo
        case .history:
            historyKeyCombo = keyCombo
        case .snippet:
            snippetKeyCombo = keyCombo
        case .passwordVault:
            passwordVaultKeyCombo = keyCombo
        }
        register(with: type, keyCombo: keyCombo)
    }

    func resetMenuShortcutsToDefaults() {
        change(with: .main, keyCombo: Self.defaultMainKeyCombo)
        change(with: .history, keyCombo: Self.defaultHistoryKeyCombo)
        change(with: .snippet, keyCombo: Self.defaultSnippetKeyCombo)
        change(with: .passwordVault, keyCombo: Self.defaultPasswordVaultKeyCombo)
    }

    func changeClearHistoryKeyCombo(_ keyCombo: KeyCombo?) {
        clearHistoryKeyCombo = keyCombo
        defaults.set(keyCombo?.archive(), forKey: Constants.HotKey.clearHistoryKeyCombo)
        defaults.synchronize()
        // Reset hotkey
        HotKeyCenter.shared.unregisterHotKey(with: "ClearHistory")
        // Register new hotkey
        guard !isSuspendedForRemoteSession, let keyCombo else { return }
        let hotkey = HotKey(identifier: "ClearHistory", keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popUpClearHistoryAlert))
        hotkey.register()
    }

    func changeScriptTransformKeyCombo(_ keyCombo: KeyCombo?) {
        scriptTransformKeyCombo = keyCombo
        defaults.set(keyCombo?.archive(), forKey: Constants.HotKey.scriptTransformKeyCombo)
        defaults.synchronize()
        HotKeyCenter.shared.unregisterHotKey(with: "ScriptTransform")
        guard !isSuspendedForRemoteSession, let keyCombo else { return }
        let hotKey = HotKey(
            identifier: "ScriptTransform",
            keyCombo: keyCombo,
            target: self,
            action: #selector(HotKeyService.runClipboardScriptTransform)
        )
        hotKey.register()
    }

    func historyPanelKeyCombo(for shortcut: HistoryPanelShortcut) -> KeyCombo? {
        guard shortcut.isUserConfigurable else {
            return shortcut.defaultKeyCombo
        }
        return historyPanelKeyCombos[shortcut]
    }

    func changeHistoryPanelKeyCombo(_ shortcut: HistoryPanelShortcut, keyCombo: KeyCombo?) {
        guard shortcut.isUserConfigurable else { return }
        if let keyCombo {
            historyPanelKeyCombos[shortcut] = keyCombo
            defaults.set(keyCombo.archive(), forKey: shortcut.userDefaultsKey)
        } else {
            historyPanelKeyCombos.removeValue(forKey: shortcut)
            defaults.removeObject(forKey: shortcut.userDefaultsKey)
        }
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.synchronize()
    }

    func resetHistoryPanelShortcutsToDefaults() {
        let migrationFlag = defaults.object(forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        HistoryPanelShortcut.allCases.filter(\.isUserConfigurable).forEach { shortcut in
            changeHistoryPanelKeyCombo(shortcut, keyCombo: shortcut.defaultKeyCombo)
        }
        if let migrationFlag {
            defaults.set(migrationFlag, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        } else {
            defaults.removeObject(forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        }
        defaults.synchronize()
    }

    private func savedKeyCombo(forKey key: String) -> KeyCombo? {
        guard let data = defaults.object(forKey: key) as? Data else { return nil }
        guard let keyCombo = NSKeyedUnarchiver.unarchiveObject(with: data) as? KeyCombo else { return nil }
        return keyCombo
    }

    private func setupHistoryPanelKeyCombos() {
        var keyCombos = [HistoryPanelShortcut: KeyCombo]()
        HistoryPanelShortcut.allCases.filter(\.isUserConfigurable).forEach { shortcut in
            if let keyCombo = savedKeyCombo(forKey: shortcut.userDefaultsKey) {
                keyCombos[shortcut] = keyCombo
            } else {
                let keyCombo = shortcut.defaultKeyCombo
                keyCombos[shortcut] = keyCombo
                defaults.set(keyCombo.archive(), forKey: shortcut.userDefaultsKey)
            }
        }
        historyPanelKeyCombos = keyCombos
        defaults.synchronize()
    }

    private func migrateOptionCommandDefaultKeyCombosIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos) else { return }

        migrateDefaultKeyComboIfNeeded(
            forKey: Constants.HotKey.historyKeyCombo,
            legacyDefault: Self.legacyDefaultHistoryKeyCombo,
            newDefault: Self.defaultHistoryKeyCombo
        )
        migrateDefaultKeyComboIfNeeded(
            forKey: Constants.HotKey.snippetKeyCombo,
            legacyDefault: Self.legacyDefaultSnippetKeyCombo,
            newDefault: Self.previousDefaultSnippetKeyCombo
        )
        defaults.set(true, forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        defaults.synchronize()
    }

    private func migrateDefaultKeyComboIfNeeded(forKey key: String, legacyDefault: KeyCombo, newDefault: KeyCombo) {
        guard savedKeyCombo(forKey: key) == legacyDefault else { return }
        defaults.set(newDefault.archive(), forKey: key)
    }

    private func migrateSnippetDefaultKeyComboToFIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToF) else { return }
        migrateDefaultKeyComboIfNeeded(
            forKey: Constants.HotKey.snippetKeyCombo,
            legacyDefault: Self.oldOptionCommandSnippetKeyCombo,
            newDefault: Self.previousDefaultSnippetKeyCombo
        )
        defaults.set(true, forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToF)
        defaults.synchronize()
    }

    private func migrateSnippetDefaultKeyComboToShiftCommandMIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToShiftCommandM) else { return }
        migrateDefaultKeyComboIfNeeded(
            forKey: Constants.HotKey.snippetKeyCombo,
            legacyDefault: Self.previousDefaultSnippetKeyCombo,
            newDefault: Self.defaultSnippetKeyCombo
        )
        defaults.set(true, forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToShiftCommandM)
        defaults.synchronize()
    }

    private func migratePasswordVaultDefaultKeyComboIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migratePasswordVaultDefaultKeyCombo) else { return }
        if savedKeyCombo(forKey: Constants.HotKey.passwordVaultKeyCombo) == nil {
            defaults.set(Self.defaultPasswordVaultKeyCombo.archive(), forKey: Constants.HotKey.passwordVaultKeyCombo)
        }
        defaults.set(true, forKey: Constants.HotKey.migratePasswordVaultDefaultKeyCombo)
        defaults.synchronize()
    }

    private func migrateHistoryPanelShortcutDefaultsIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated) else { return }
        HistoryPanelShortcut.allCases.filter(\.isUserConfigurable).forEach { shortcut in
            guard savedKeyCombo(forKey: shortcut.userDefaultsKey) == nil else { return }
            defaults.set(shortcut.defaultKeyCombo.archive(), forKey: shortcut.userDefaultsKey)
        }
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.synchronize()
    }

    private func migrateHistoryPanelDefaultsV2IfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateHistoryPanelOptionCommand) else { return }
        HistoryPanelShortcut.allCases.filter(\.isUserConfigurable).forEach { shortcut in
            guard savedKeyCombo(forKey: shortcut.userDefaultsKey) == shortcut.commandDefaultKeyCombo else { return }
            defaults.set(shortcut.defaultKeyCombo.archive(), forKey: shortcut.userDefaultsKey)
        }
        defaults.set(true, forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)
        defaults.synchronize()
    }

    private func migrateHistoryPanelCanonicalDefaultsIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaults) else { return }
        HistoryPanelShortcut.allCases.filter(\.isUserConfigurable).forEach { shortcut in
            guard let keyCombo = savedKeyCombo(forKey: shortcut.userDefaultsKey) else {
                defaults.set(shortcut.defaultKeyCombo.archive(), forKey: shortcut.userDefaultsKey)
                return
            }
            guard shortcut.shouldMigrateToCanonicalDefault(keyCombo) else { return }
            defaults.set(shortcut.defaultKeyCombo.archive(), forKey: shortcut.userDefaultsKey)
        }
        defaults.set(true, forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaults)
        defaults.synchronize()
    }

    private func migrateHistoryPanelCanonicalDefaultsV2IfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaultsV2) else { return }
        HistoryPanelShortcut.allCases.filter(\.isUserConfigurable).forEach { shortcut in
            guard let keyCombo = savedKeyCombo(forKey: shortcut.userDefaultsKey) else { return }
            guard shortcut.shouldMigrateToCanonicalDefault(keyCombo) else { return }
            defaults.set(shortcut.defaultKeyCombo.archive(), forKey: shortcut.userDefaultsKey)
        }
        defaults.set(true, forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaultsV2)
        defaults.synchronize()
    }

    private func migrateHistoryPanelCommandDefaultsIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateHistoryPanelCommandDefaults) else { return }
        HistoryPanelShortcut.allCases.filter(\.isUserConfigurable).forEach { shortcut in
            guard let keyCombo = savedKeyCombo(forKey: shortcut.userDefaultsKey) else { return }
            guard shortcut.shouldMigrateToCanonicalDefault(keyCombo) else { return }
            defaults.set(shortcut.defaultKeyCombo.archive(), forKey: shortcut.userDefaultsKey)
        }
        defaults.set(true, forKey: Constants.HotKey.migrateHistoryPanelCommandDefaults)
        defaults.synchronize()
    }
}

// MARK: - Register
private extension HotKeyService {
    func register(with type: MenuType, keyCombo: KeyCombo?) {
        save(with: type, keyCombo: keyCombo)
        // Reset hotkey
        HotKeyCenter.shared.unregisterHotKey(with: type.rawValue)
        // Register new hotkey
        guard !isSuspendedForRemoteSession, let keyCombo else { return }
        let hotKey = HotKey(identifier: type.rawValue, keyCombo: keyCombo, target: self, action: type.hotKeySelector)
        hotKey.register()
    }

    func save(with type: MenuType, keyCombo: KeyCombo?) {
        defaults.set(keyCombo?.archive(), forKey: type.userDefaultsKey)
        defaults.synchronize()
    }
}

// MARK: - Remote Sessions
extension HotKeyService {
    func refreshRemoteSessionHotKeyState() {
        updateRemoteSessionHotKeyState(
            frontmostApplicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    func startMonitoringRemoteSessionApplications() {
        guard remoteSessionObserver == nil else { return }
        remoteSessionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateRemoteSessionHotKeyState(
                frontmostApplicationBundleIdentifier: application?.bundleIdentifier
            )
        }
    }

    func updateRemoteSessionHotKeyState(frontmostApplicationBundleIdentifier bundleIdentifier: String?) {
        let shouldSuspend = RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
            frontmostApplicationBundleIdentifier: bundleIdentifier,
            isEnabled: defaults.bool(forKey: Constants.HotKey.suspendDuringRemoteSession)
        )
        guard shouldSuspend != isSuspendedForRemoteSession else { return }
        isSuspendedForRemoteSession = shouldSuspend

        if shouldSuspend {
            unregisterAllRegisteredHotKeys()
        } else {
            restoreRegisteredHotKeys()
        }
    }

    private func unregisterAllRegisteredHotKeys() {
        [MenuType.main.rawValue, MenuType.history.rawValue, MenuType.snippet.rawValue, MenuType.passwordVault.rawValue, "ClearHistory", "ScriptTransform"].forEach {
            HotKeyCenter.shared.unregisterHotKey(with: $0)
        }
        folderKeyCombos?.keys.forEach {
            HotKeyCenter.shared.unregisterHotKey(with: $0)
        }
    }

    private func restoreRegisteredHotKeys() {
        register(with: .main, keyCombo: mainKeyCombo)
        register(with: .history, keyCombo: historyKeyCombo)
        register(with: .snippet, keyCombo: snippetKeyCombo)
        register(with: .passwordVault, keyCombo: passwordVaultKeyCombo)
        changeClearHistoryKeyCombo(clearHistoryKeyCombo)
        changeScriptTransformKeyCombo(scriptTransformKeyCombo)
        setupSnippetHotKeys()
    }
}

// MARK: - Migration
private extension HotKeyService {
    /**
     *  Migration for changing the storage with v1.1.0
     *  Changed framework, PTHotKey to Magnet
     */
    func migrationKeyCombos() {
        guard let keyCombos = defaults.object(forKey: Constants.UserDefaults.hotKeys) as? [String: Any] else { return }

        // Main menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.clip) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                defaults.set(keyCombo.archive(), forKey: Constants.HotKey.mainKeyCombo)
            }
        }
        // History menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.history) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                defaults.set(keyCombo.archive(), forKey: Constants.HotKey.historyKeyCombo)
            }
        }
        // Snippet menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.snippet) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                defaults.set(keyCombo.archive(), forKey: Constants.HotKey.snippetKeyCombo)
            }
        }
    }

    func parse(with keyCombos: [String: Any], forKey key: String) -> (Int, Int)? {
        guard let combos = keyCombos[key] as? [String: Any] else { return nil }
        guard let keyCode = combos["keyCode"] as? Int, let modifiers = combos["modifiers"] as? Int else { return nil }
        return (keyCode, modifiers)
    }
}

// MARK: - Snippet HotKey
extension HotKeyService {
    private var folderKeyCombos: [String: KeyCombo]? {
        get {
            guard let data = defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data else { return nil }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: KeyCombo]
        }
        set {
            if let value = newValue {
                defaults.set(NSKeyedArchiver.archivedData(withRootObject: value), forKey: Constants.HotKey.folderKeyCombos)
            } else {
                defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
            }
            defaults.synchronize()
        }
    }

    func snippetKeyCombo(forIdentifier identifier: String) -> KeyCombo? {
        return folderKeyCombos?[identifier]
    }

    @discardableResult
    func registerDefaultSnippetHotKeyIfAvailable(forIdentifier identifier: String) -> KeyCombo? {
        if let existingKeyCombo = snippetKeyCombo(forIdentifier: identifier) {
            return existingKeyCombo
        }

        let usedKeyCombos = snippetFolderDefaultReservedKeyCombos()
        guard let keyCombo = Self.defaultSnippetFolderHotKeyCodes
            .compactMap({ KeyCombo(QWERTYKeyCode: $0, carbonModifiers: Self.defaultSnippetFolderHotKeyModifiers) })
            .first(where: { candidate in !usedKeyCombos.contains(candidate) }) else {
            return nil
        }
        registerSnippetHotKey(with: identifier, keyCombo: keyCombo)
        return keyCombo
    }

    func registerSnippetHotKey(with identifier: String, keyCombo: KeyCombo) {
        // Reset hotkey
        unregisterSnippetHotKey(with: identifier)
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos[identifier] = keyCombo
        folderKeyCombos = keyCombos
        // Register new hotkey
        guard !isSuspendedForRemoteSession else { return }
        let hotKey = HotKey(identifier: identifier, keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
        hotKey.register()
    }

    func unregisterSnippetHotKey(with identifier: String) {
        // Unregister
        HotKeyCenter.shared.unregisterHotKey(with: identifier)
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos.removeValue(forKey: identifier)
        folderKeyCombos = keyCombos
    }

    @objc func popupSnippetFolder(_ object: AnyObject) {
        guard let hotKey = object as? HotKey, let folderID = UUID(uuidString: hotKey.identifier) else { return }

        guard let folderDetail = snippetRepository.fetchFolderDetail(id: SnippetFolder.ID(rawValue: folderID)) else {
            // When already deleted folder, remove keycombos
            unregisterSnippetHotKey(with: hotKey.identifier)
            return
        }
        guard folderDetail.folder.isEnabled else { return }
        AppEnvironment.current.menuManager.popUpSnippetFolder(folderDetail, triggerKeyCombo: hotKey.keyCombo)
    }

    fileprivate func setupSnippetHotKeys() {
        guard !isSuspendedForRemoteSession else { return }
        folderKeyCombos?.forEach {
            let hotKey = HotKey(identifier: $0, keyCombo: $1, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
            hotKey.register()
        }
    }

    private func snippetFolderDefaultReservedKeyCombos() -> [KeyCombo] {
        var keyCombos = folderKeyCombos?.values.map { $0 } ?? []
        keyCombos.append(contentsOf: [
            mainKeyCombo ?? savedKeyCombo(forKey: Constants.HotKey.mainKeyCombo),
            historyKeyCombo ?? savedKeyCombo(forKey: Constants.HotKey.historyKeyCombo),
            snippetKeyCombo ?? savedKeyCombo(forKey: Constants.HotKey.snippetKeyCombo),
            clearHistoryKeyCombo ?? savedKeyCombo(forKey: Constants.HotKey.clearHistoryKeyCombo)
        ].compactMap { $0 })
        return keyCombos
    }
}
