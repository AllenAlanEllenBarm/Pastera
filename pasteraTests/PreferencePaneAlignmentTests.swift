//
//  PreferencePaneAlignmentTests.swift
//
//  Pastera
//

// swiftlint:disable file_length

import AppKit
import Testing
@testable import Pastera

private let passwordVaultTask7Chinese: [String: String] = [
    "The master password encrypts your password vault. If forgotten, it cannot be recovered by any other means.":
        "主密码用于加密密码箱。如果忘记主密码且没有可用的解锁密钥，Pastera 无法解密或找回原密码箱。",
    "A forced reset creates a new empty password vault. Only the original master password can open the retained encrypted archive.":
        "强制重置会创建一个空密码箱。保留的加密归档仍然只能使用原主密码打开，旧条目不会出现在新密码箱中。",
    "Password Vault sync is paused until Pastera archives and replaces the previous OneDrive vault.":
        "密码箱同步已暂停，直到 Pastera 完成归档并替换之前的 OneDrive 密码箱。",
    "OneDrive changed elsewhere. Retry will archive the latest remote encrypted vault before replacing the active vault.":
        "OneDrive 上的密码箱已在其他位置发生变化。重试后，Pastera 会先归档最新的远程加密密码箱，再替换当前密码箱。"
]

@MainActor
private func renderPasswordVaultPage(
    _ page: CPYPasswordVaultPreferenceViewController,
    state: PasswordVaultSecuritySettingsState,
    width: CGFloat,
    appearance: NSAppearance.Name,
    to url: URL
) throws {
    page.loadView()
    page.view.appearance = NSAppearance(named: appearance)
    page.applySecurityStateForTesting(state)
    page.view.frame = NSRect(x: 0, y: 0, width: width, height: 1_400)
    page.view.layoutSubtreeIfNeeded()
    let height = ceil(max(page.view.fittingSize.height, 1))
    page.view.frame = NSRect(x: 0, y: 0, width: width, height: height)

    let background = PasswordVaultScreenshotBackgroundView(frame: page.view.bounds)
    background.appearance = NSAppearance(named: appearance)
    page.view.autoresizingMask = [.width, .height]
    background.addSubview(page.view)
    background.layoutSubtreeIfNeeded()

    let representation = try #require(background.bitmapImageRepForCachingDisplay(in: background.bounds))
    background.cacheDisplay(in: background.bounds, to: representation)
    let data = try #require(representation.representation(using: .png, properties: [:]))
    try data.write(to: url, options: .atomic)
}

private final class PasswordVaultScreenshotBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

private final class PasswordVaultPreferenceActionStore: PasswordVaultStore {
    private let recoveryLock = NSLock()
    private var recoveryCalls = 0
    var state: PasswordVaultState
    var canQuickUnlock = false
    var canAutomationUnlock = false
    var masterPasswordResetCapability: PasswordVaultMasterPasswordResetCapability
    var quickUnlockError: PasswordVaultError?
    var recoveryHandler: (() throws -> PasswordVaultForcedResetRecoveryResult)?

    var recoveryCallCount: Int { recoveryLock.withLock { recoveryCalls } }

    init(
        state: PasswordVaultState = .locked,
        capability: PasswordVaultMasterPasswordResetCapability = .preservesData
    ) {
        self.state = state
        masterPasswordResetCapability = capability
    }

    func enableQuickUnlock() throws {
        if let quickUnlockError { throw quickUnlockError }
        canQuickUnlock = true
    }

    func disableQuickUnlock() throws { canQuickUnlock = false }
    func listFolders() throws -> [PasswordVaultFolder] { [] }
    func listEntries() throws -> [PasswordVaultEntry] { [] }
    func createFolder(name: String) throws -> PasswordVaultFolder { throw PasswordVaultError.unsupportedFormat }
    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder {
        throw PasswordVaultError.unsupportedFormat
    }
    func deleteFolder(id: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func reorderFolders(_ folderIDs: [UUID]) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws {
        throw PasswordVaultError.unsupportedFormat
    }
    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        throw PasswordVaultError.unsupportedFormat
    }
    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        throw PasswordVaultError.unsupportedFormat
    }
    func revealPassword(id: UUID, reason: String) throws -> String { throw PasswordVaultError.unsupportedFormat }
    func delete(id: UUID, reason: String) throws { throw PasswordVaultError.unsupportedFormat }

    func retryForcedResetRecovery() throws -> PasswordVaultForcedResetRecoveryResult {
        recoveryLock.withLock { recoveryCalls += 1 }
        guard let recoveryHandler else { throw PasswordVaultForcedResetError.recoveryRequired }
        return try recoveryHandler()
    }
}

private final class PasswordVaultPreferenceRetrySyncController: PasswordVaultSyncControlling {
    private let lock = NSLock()
    private var observers = [UUID: (PasswordVaultSyncSnapshot) -> Void]()
    private var storedSnapshot: PasswordVaultSyncSnapshot
    private var retryCompletions = [(Result<Void, PasswordVaultSyncFailure>) -> Void]()
    private(set) var retryCallCount = 0

    init(pendingFailure: PasswordVaultSyncFailure? = nil) {
        storedSnapshot = PasswordVaultSyncSnapshot(
            mode: .oneDrive,
            phase: .pendingForcedReset(pendingFailure),
            localVaultAvailable: true,
            remoteVaultAvailable: true,
            pendingChangeCount: 0,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
    }

    var snapshot: PasswordVaultSyncSnapshot { lock.withLock { storedSnapshot } }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        let initial = lock.withLock {
            observers[identifier] = observer
            return storedSnapshot
        }
        observer(initial)
        return identifier
    }

    func removeObserver(_ identifier: UUID) { _ = lock.withLock { observers.removeValue(forKey: identifier) } }
    func record(_ commit: PasswordVaultCommit) {}
    func synchronize(reason: SyncCoordinator.Reason) {}
    func retryForcedReset(completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void) {
        retryCallCount += 1
        retryCompletions.append(completion)
    }
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(.success(())) }

    func completeOldestRetry(with result: Result<Void, PasswordVaultSyncFailure>) {
        retryCompletions.removeFirst()(result)
    }
}

private struct PasswordVaultResetActionCase {
    let vaultState: PasswordVaultState
    let capability: PasswordVaultMasterPasswordResetCapability
    let isBusy: Bool
    let isPending: Bool
    let isEnabled: Bool
}

private func passwordVaultDescendants(in view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(passwordVaultDescendants(in:))
}

private func passwordVaultView(identifier: String, in root: NSView) -> NSView? {
    passwordVaultDescendants(in: root).first { $0.accessibilityIdentifier() == identifier }
}

private func passwordVaultAncestor<T: NSView>(of view: NSView, type: T.Type) -> T? {
    var current = view.superview
    while let candidate = current {
        if let typed = candidate as? T { return typed }
        current = candidate.superview
    }
    return nil
}

private func passwordVaultFeedbackFollowsAction(
    actionContainer: NSView,
    feedback: NSView,
    in page: NSView
) -> Bool {
    guard
        let footer = actionContainer.superview as? NSStackView,
        feedback.superview === footer,
        let actionIndex = footer.arrangedSubviews.firstIndex(where: { $0 === actionContainer }),
        let feedbackIndex = footer.arrangedSubviews.firstIndex(where: { $0 === feedback }),
        passwordVaultAncestor(of: actionContainer, type: PasteraPreferenceGroupView.self)
            === passwordVaultAncestor(of: feedback, type: PasteraPreferenceGroupView.self)
    else { return false }
    let actionFrame = actionContainer.convert(actionContainer.bounds, to: page)
    let feedbackFrame = feedback.convert(feedback.bounds, to: page)
    return feedbackIndex == actionIndex + 1 && feedbackFrame.minY >= actionFrame.maxY - 0.5
}

private func passwordVaultColorIsRed(_ color: NSColor?) -> Bool {
    guard let rgb = color?.usingColorSpace(.deviceRGB) else { return false }
    return rgb.redComponent > rgb.greenComponent * 1.5
        && rgb.redComponent > rgb.blueComponent * 1.25
}

@MainActor
private func passwordVaultWaitUntil(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

@MainActor
@Suite(.serialized)
struct PreferenceSidebarTests {
    @Test
    func preferenceWindowRestoresDefaultFrameSize() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        let window = try #require(controller.window)
        window.setFrame(NSRect(x: 20, y: 30, width: 1400, height: 900), display: false)

        window.performZoom(nil)

        #expect(window.frame.size == controller.defaultPreferenceWindowFrameSizeForTesting)
    }

    @Test
    func sidebarUsesApprovedTitlesAndDistinctServiceIcons() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)

        let titles = controller.preferenceSidebarTitlesForTesting
        let symbolNames = controller.preferenceSidebarSymbolNamesForTesting
        let syncIndex = try #require(titles.firstIndex(of: "云同步"))
        let updateIndex = try #require(titles.firstIndex(of: "软件更新"))
        let aboutIndex = try #require(titles.firstIndex(of: "关于"))

        #expect(titles == [
            "基础设置",
            "历史记录",
            "提示词优化",
            "脚本",
            "快捷键",
            "密码箱",
            "忽略应用",
            "Agent 集成",
            "云同步",
            "软件更新",
            "关于"
        ])
        #expect(!titles.contains("Types"))
        #expect(!titles.contains("Exclude"))
        #expect(!titles.contains("Update"))
        #expect(!titles.contains("Beta"))
        #expect(!titles.contains("测试"))
        #expect(symbolNames.count == titles.count)
        #expect(symbolNames[syncIndex] != symbolNames[aboutIndex])
        #expect(symbolNames[updateIndex] != symbolNames[syncIndex])
        #expect(symbolNames[updateIndex] != symbolNames[aboutIndex])
    }
}

@MainActor
@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct PreferencePaneAlignmentTests {
    @Test
    func passwordVaultRepeatedLoadKeepsOneItemAndExactlyThreeRealGroups() {
        let page = CPYPasswordVaultPreferenceViewController()

        page.loadView()
        page.loadView()
        page.view.frame = NSRect(x: 0, y: 0, width: 600, height: 1_200)
        page.view.layoutSubtreeIfNeeded()

        let groups = passwordVaultDescendants(in: page.view).compactMap { $0 as? PasteraPreferenceGroupView }
        #expect(page.adaptiveRowCountForTesting == 1)
        #expect(page.adaptiveItemWidthsForTesting.count == 1)
        #expect(groups.count == 3)
        #expect(Set(groups.map(ObjectIdentifier.init)).count == 3)
    }

    @Test
    func passwordVaultResetActionsRespectVaultStateCapabilityPendingAndBusy() throws {
        let page = CPYPasswordVaultPreferenceViewController()
        page.loadView()
        let reset = try #require(passwordVaultView(
            identifier: "vault.masterPassword.button", in: page.view
        ) as? NSButton)
        let force = try #require(passwordVaultView(identifier: "vault.forceReset.button", in: page.view) as? NSButton)
        let cases = [
            PasswordVaultResetActionCase(
                vaultState: .locked, capability: .preservesData, isBusy: false, isPending: false, isEnabled: true
            ),
            PasswordVaultResetActionCase(
                vaultState: .unlocked, capability: .requiresForcedReset,
                isBusy: false, isPending: false, isEnabled: true
            ),
            PasswordVaultResetActionCase(
                vaultState: .locked, capability: .unavailable, isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .notConfigured, capability: .preservesData,
                isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .preparingLocalCopy, capability: .preservesData,
                isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .localCopyUnavailable(.localWriteFailed), capability: .preservesData,
                isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .unlocking, capability: .preservesData,
                isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .readOnlyWarning("read only"), capability: .preservesData,
                isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .recoveryRequired("recovery"), capability: .preservesData,
                isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .failed("failed"), capability: .preservesData,
                isBusy: false, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .locked, capability: .preservesData, isBusy: true, isPending: false, isEnabled: false
            ),
            PasswordVaultResetActionCase(
                vaultState: .unlocked, capability: .requiresForcedReset,
                isBusy: false, isPending: true, isEnabled: false
            )
        ]

        for testCase in cases {
            page.applySecurityStateForTesting(.init(
                vaultState: testCase.vaultState,
                isBusy: testCase.isBusy,
                autoLockInterval: 300,
                quickUnlockEnabled: false,
                quickUnlockAvailable: false,
                masterPasswordResetCapability: testCase.capability,
                forcedResetPending: testCase.isPending,
                forcedResetPendingFailure: testCase.isPending ? .remoteUnavailable : nil
            ))
            #expect(reset.isEnabled == testCase.isEnabled)
            #expect(force.isEnabled == testCase.isEnabled)
        }
    }

    @Test
    func forceResetUsesVisibleSecondaryDestructiveStylingOnlyWhileEnabled() throws {
        let page = CPYPasswordVaultPreferenceViewController()
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
        let button = try #require(passwordVaultView(
            identifier: "vault.forceReset.button", in: page.view
        ) as? NSButton)
        let titleColor = button.attributedTitle.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        let borderColor = button.layer?.borderColor.flatMap(NSColor.init(cgColor:))

        #expect(button.isEnabled)
        #expect(button.image != nil)
        #expect(passwordVaultColorIsRed(titleColor))
        #expect(passwordVaultColorIsRed(button.contentTintColor))
        #expect(passwordVaultColorIsRed(borderColor))
        #expect((button.layer?.borderWidth ?? 0) > 0)

        button.isEnabled = false
        let disabledTitleColor = button.attributedTitle.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        #expect(!passwordVaultColorIsRed(disabledTitleColor))
        #expect(!passwordVaultColorIsRed(button.contentTintColor))
    }

    @Test
    func actionFeedbackAppearsDirectlyBelowItsProducingActionAndOwnedGroup() async throws {
        let store = PasswordVaultPreferenceActionStore()
        store.quickUnlockError = .saveFailed
        let syncController = PasswordVaultPreferenceRetrySyncController()
        let defaultsName = "PreferencePaneAlignmentTests.feedback.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let controller = PasswordVaultUIController(
            store: store,
            syncController: syncController,
            defaults: defaults,
            storeQueue: DispatchQueue(label: defaultsName)
        )
        let page = CPYPasswordVaultPreferenceViewController(
            controller: controller,
            localizedString: { $0 },
            resetPassword: { _, completion in completion(.success(.init(warnings: []))) },
            forceResetPassword: { _, completion in
                completion(.success(.init(
                    localArchiveDigest: "archive",
                    oneDriveReplacementPending: false,
                    warnings: []
                )))
            }
        )
        page.loadView()
        let parent = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 900),
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
        let usableState = PasswordVaultSecuritySettingsState(
            vaultState: .locked,
            isBusy: false,
            autoLockInterval: 300,
            quickUnlockEnabled: false,
            quickUnlockAvailable: false,
            masterPasswordResetCapability: .preservesData,
            forcedResetPending: false,
            forcedResetPendingFailure: nil
        )
        page.applySecurityStateForTesting(usableState)

        let systemUnlock = try #require(passwordVaultView(
            identifier: "vault.systemUnlock.control", in: page.view
        ) as? NSSwitch)
        systemUnlock.performClick(nil)
        let statusFeedback = try #require(passwordVaultView(identifier: "vault.status.feedback", in: page.view))
        #expect(await passwordVaultWaitUntil { !statusFeedback.isHidden })
        page.view.layoutSubtreeIfNeeded()
        let systemUnlockRow = try #require(passwordVaultAncestor(
            of: systemUnlock, type: PasteraPreferenceSettingRowView.self
        ))
        #expect(passwordVaultFeedbackFollowsAction(
            actionContainer: systemUnlockRow,
            feedback: statusFeedback,
            in: page.view
        ))
        let statusText = passwordVaultDescendants(in: statusFeedback)
            .compactMap { $0 as? NSTextField }.map(\.stringValue).joined()
        #expect(statusText == "The security setting could not be updated. Please try again.")

        page.applySecurityStateForTesting(usableState)
        let resetButton = try #require(passwordVaultView(
            identifier: "vault.masterPassword.button", in: page.view
        ) as? NSButton)
        resetButton.performClick(nil)
        let resetSheet = try #require(page.resetSheetForTesting)
        resetSheet.setValuesForTesting(new: "new-password", confirmation: "new-password")
        resetSheet.submitForTesting()
        let masterFeedback = try #require(passwordVaultView(
            identifier: "vault.masterPassword.feedback", in: page.view
        ))
        page.view.layoutSubtreeIfNeeded()
        #expect(!masterFeedback.isHidden)
        #expect(passwordVaultFeedbackFollowsAction(
            actionContainer: try #require(resetButton.superview),
            feedback: masterFeedback,
            in: page.view
        ))

        page.applySecurityStateForTesting(usableState)
        let forceButton = try #require(passwordVaultView(
            identifier: "vault.forceReset.button", in: page.view
        ) as? NSButton)
        forceButton.performClick(nil)
        let forceSheet = try #require(page.forceSheetForTesting)
        forceSheet.setValuesForTesting(new: "new-password", confirmation: "new-password")
        forceSheet.setAcknowledgementForTesting(true)
        forceSheet.submitForTesting()
        let forceFeedback = try #require(passwordVaultView(identifier: "vault.forceReset.feedback", in: page.view))
        page.view.layoutSubtreeIfNeeded()
        #expect(!forceFeedback.isHidden)
        #expect(passwordVaultFeedbackFollowsAction(
            actionContainer: try #require(forceButton.superview),
            feedback: forceFeedback,
            in: page.view
        ))
    }

    @Test
    func retryFeedbackStaysBelowRetryAndInFlightRetryCannotReenterAcrossStateApply() async throws {
        let store = PasswordVaultPreferenceActionStore(state: .unlocked)
        let syncController = PasswordVaultPreferenceRetrySyncController(pendingFailure: .remoteVerificationFailed)
        let defaultsName = "PreferencePaneAlignmentTests.retry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let controller = PasswordVaultUIController(
            store: store,
            syncController: syncController,
            defaults: defaults,
            storeQueue: DispatchQueue(label: defaultsName)
        )
        let page = CPYPasswordVaultPreferenceViewController(controller: controller, localizedString: { $0 })
        page.loadView()
        let pendingState = PasswordVaultSecuritySettingsState(
            vaultState: .unlocked,
            isBusy: false,
            autoLockInterval: 300,
            quickUnlockEnabled: false,
            quickUnlockAvailable: false,
            masterPasswordResetCapability: .preservesData,
            forcedResetPending: true,
            forcedResetPendingFailure: .remoteVerificationFailed
        )
        page.applySecurityStateForTesting(pendingState)
        let retryButton = try #require(passwordVaultView(
            identifier: "vault.forceReset.retry", in: page.view
        ) as? NSButton)

        retryButton.performClick(nil)
        #expect(syncController.retryCallCount == 1)
        #expect(!retryButton.isEnabled)

        page.applySecurityStateForTesting(pendingState)
        retryButton.performClick(nil)
        #expect(syncController.retryCallCount == 1)
        #expect(!retryButton.isEnabled)

        syncController.completeOldestRetry(with: .failure(.remoteWriteFailed))
        #expect(await passwordVaultWaitUntil { retryButton.isEnabled })
        let retryFeedback = try #require(passwordVaultView(
            identifier: "vault.forceReset.retryFeedback", in: page.view
        ))
        let forceFeedback = try #require(passwordVaultView(
            identifier: "vault.forceReset.feedback", in: page.view
        ))
        page.view.layoutSubtreeIfNeeded()
        #expect(!retryFeedback.isHidden)
        #expect(forceFeedback.isHidden)
        #expect(passwordVaultFeedbackFollowsAction(
            actionContainer: try #require(retryButton.superview),
            feedback: retryFeedback,
            in: page.view
        ))

        retryButton.performClick(nil)
        #expect(syncController.retryCallCount == 2)
    }

    @Test
    func localRecoveryHidesRawReasonAndOneDriveRetryWhileItsRetryFailsClosed() async throws {
        let store = PasswordVaultPreferenceActionStore(
            state: .recoveryRequired("forced-reset-cleanup")
        )
        let retryGate = DispatchSemaphore(value: 0)
        defer { retryGate.signal() }
        store.recoveryHandler = {
            retryGate.wait()
            throw PasswordVaultForcedResetError.recoveryRequired
        }
        let syncController = PasswordVaultPreferenceRetrySyncController(
            pendingFailure: .remoteVerificationFailed
        )
        let defaultsName = "PreferencePaneAlignmentTests.local-recovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let controller = PasswordVaultUIController(
            store: store,
            syncController: syncController,
            defaults: defaults,
            storeQueue: DispatchQueue(label: defaultsName)
        )
        let page = CPYPasswordVaultPreferenceViewController(
            controller: controller,
            localizedString: { $0 }
        )
        page.loadView()
        page.applySecurityStateForTesting(.init(
            vaultState: .recoveryRequired("forced-reset-cleanup"),
            isBusy: false,
            autoLockInterval: 300,
            quickUnlockEnabled: true,
            quickUnlockAvailable: true,
            masterPasswordResetCapability: .preservesData,
            forcedResetPending: true,
            forcedResetPendingFailure: .remoteVerificationFailed
        ))

        let visibleCopy = passwordVaultDescendants(in: page.view)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .joined(separator: " ")
        #expect(!visibleCopy.contains("forced-reset-cleanup"))
        #expect(!page.passwordVaultPendingRowVisibleForTesting)
        #expect(!page.passwordVaultRetryVisibleForTesting)
        #expect(!page.passwordVaultResetActionsEnabledForTesting)

        let retryButton = try #require(passwordVaultView(
            identifier: "vault.localRecovery.retry",
            in: page.view
        ) as? NSButton)
        page.view.layoutSubtreeIfNeeded()
        let retryFrame = retryButton.convert(retryButton.bounds, to: page.view)
        let retrySuperview = try #require(retryButton.superview)
        let retryRow = retrySuperview.convert(retrySuperview.bounds, to: page.view)
        #expect(abs(retryFrame.midY - retryRow.midY) < 0.5)
        #expect(retryButton.isEnabled)
        retryButton.performClick(nil)
        #expect(await passwordVaultWaitUntil { store.recoveryCallCount == 1 })
        #expect(controller.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(controller.viewState.isBusy)
        #expect(retryButton.title == "Retrying…")
        #expect(!retryButton.isEnabled)

        retryButton.performClick(nil)
        #expect(store.recoveryCallCount == 1)
        retryGate.signal()

        let feedback = try #require(passwordVaultView(
            identifier: "vault.localRecovery.feedback",
            in: page.view
        ))
        #expect(await passwordVaultWaitUntil { !feedback.isHidden })
        let feedbackText = passwordVaultDescendants(in: feedback)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .joined(separator: " ")
        #expect(feedbackText ==
            "Local recovery is not complete. OneDrive sync remains paused. You can safely try again."
        )
        #expect(store.state == .recoveryRequired("forced-reset-cleanup"))
    }

    @Test
    func localRecoveryRetryBusySnapshotPreservesRecoveryState() async throws {
        let store = PasswordVaultPreferenceActionStore(
            state: .recoveryRequired("forced-reset-cleanup")
        )
        let retryGate = DispatchSemaphore(value: 0)
        defer { retryGate.signal() }
        store.recoveryHandler = {
            retryGate.wait()
            throw PasswordVaultForcedResetError.recoveryRequired
        }
        let queue = DispatchQueue(label: "PreferencePaneAlignmentTests.recovery-busy")
        let controller = PasswordVaultUIController(store: store, storeQueue: queue)
        var didComplete = false

        controller.retryForcedResetRecovery { _ in didComplete = true }

        #expect(controller.viewState.isBusy)
        #expect(controller.viewState.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(controller.state == .recoveryRequired("forced-reset-cleanup"))
        retryGate.signal()
        #expect(await passwordVaultWaitUntil { didComplete })
        #expect(controller.state == .recoveryRequired("forced-reset-cleanup"))
    }

    @Test
    func localRecoverySuccessReportsWhetherThePreviousOrNewVaultWasKept() async throws {
        let scenarios: [(PasswordVaultForcedResetRecoveryResult, String)] = [
            (
                .rolledBack(oldDigest: "old-digest"),
                "Local recovery restored the previous password vault. Password Vault is ready to continue."
            ),
            (
                .committed(newDigest: "new-digest"),
                "Local recovery kept the new password vault. Password Vault is ready to continue."
            )
        ]

        for (result, expectedFeedback) in scenarios {
            let store = PasswordVaultPreferenceActionStore(
                state: .recoveryRequired("forced-reset-cleanup")
            )
            store.recoveryHandler = {
                store.state = .locked
                return result
            }
            let controller = PasswordVaultUIController(
                store: store,
                storeQueue: DispatchQueue(label: "PreferencePaneAlignmentTests.recovery-success")
            )
            let page = CPYPasswordVaultPreferenceViewController(
                controller: controller,
                localizedString: { $0 }
            )
            page.loadView()
            page.applySecurityStateForTesting(.init(
                vaultState: .recoveryRequired("forced-reset-cleanup"),
                isBusy: false,
                autoLockInterval: 300,
                quickUnlockEnabled: true,
                quickUnlockAvailable: true,
                masterPasswordResetCapability: .preservesData,
                forcedResetPending: false,
                forcedResetPendingFailure: nil
            ))
            let retryButton = try #require(passwordVaultView(
                identifier: "vault.localRecovery.retry",
                in: page.view
            ) as? NSButton)
            let feedback = try #require(passwordVaultView(
                identifier: "vault.localRecovery.feedback",
                in: page.view
            ))

            retryButton.performClick(nil)

            #expect(await passwordVaultWaitUntil { !feedback.isHidden })
            let feedbackText = passwordVaultDescendants(in: feedback)
                .compactMap { ($0 as? NSTextField)?.stringValue }
                .joined(separator: " ")
            #expect(feedbackText == expectedFeedback)
            #expect(controller.state == .locked)
        }
    }

    @Test
    func passwordVaultGroupsRemainOneAlignedColumnAtEverySupportedWidth() throws {
        let page = CPYPasswordVaultPreferenceViewController()
        page.loadView()

        for width: CGFloat in [480, 600, 900] {
            page.view.frame = NSRect(x: 0, y: 0, width: width, height: 1_200)
            page.view.needsLayout = true
            page.view.layoutSubtreeIfNeeded()

            #expect(page.adaptiveRowCountForTesting == 1)
            #expect(page.adaptiveItemWidthsForTesting.count == 1)

            let frames = page.passwordVaultGroupFramesForTesting
            #expect(frames.count == 3)
            let first = try #require(frames.first)
            #expect(frames.allSatisfy { abs($0.minX - first.minX) < 0.5 })
            #expect(frames.allSatisfy { abs($0.width - first.width) < 0.5 })
            #expect(frames[0].maxY + 11.5 <= frames[1].minY)
            #expect(frames[1].maxY + 11.5 <= frames[2].minY)
            #expect(abs(frames[1].minY - frames[0].maxY - 12) < 0.5)
            #expect(abs(frames[2].minY - frames[1].maxY - 12) < 0.5)
            #expect(frames.allSatisfy { page.view.bounds.contains($0) })

            #expect(page.passwordVaultActionInsetsForTesting.allSatisfy {
                abs($0.left - 14) < 0.5 && abs($0.right - 14) < 0.5
            })
            let actions = page.passwordVaultActionButtonFramesForTesting
            #expect(actions.count == 2)
            #expect(abs(actions[0].maxX - actions[1].maxX) < 0.5)
            #expect(abs(actions[0].midY - page.passwordVaultActionRowFramesForTesting[0].midY) < 0.5)
            #expect(abs(actions[1].midY - page.passwordVaultActionRowFramesForTesting[1].midY) < 0.5)
        }

        for anchorID in ["vault.autoLock", "vault.systemUnlock", "vault.masterPassword", "vault.forceReset"] {
            #expect(page.revealSetting(anchorID: anchorID, animated: false))
            let frame = try #require(page.passwordVaultAnchorFrameForTesting(anchorID))
            #expect(page.view.bounds.contains(frame))
        }
        #expect(page.passwordVaultFeedbackIdentifiersForTesting == [
            "vault.status.feedback",
            "vault.masterPassword.feedback",
            "vault.forceReset.feedback",
            "vault.forceReset.retryFeedback"
        ])
    }

    @Test
    func passwordVaultLongChinesePendingCopyWrapsWithoutOverlapOrEmptyHoles() throws {
        let page = CPYPasswordVaultPreferenceViewController(
            localizedString: { passwordVaultTask7Chinese[$0] ?? $0 }
        )
        page.loadView()
        page.applySecurityStateForTesting(.init(
            vaultState: .unlocked,
            isBusy: false,
            autoLockInterval: 300,
            quickUnlockEnabled: true,
            quickUnlockAvailable: true,
            masterPasswordResetCapability: .preservesData,
            forcedResetPending: true,
            forcedResetPendingFailure: .remoteVerificationFailed
        ))
        page.view.frame = NSRect(x: 0, y: 0, width: 480, height: 1_400)
        page.view.layoutSubtreeIfNeeded()

        #expect(page.passwordVaultVisibleContentFramesForTesting.allSatisfy { page.view.bounds.contains($0) })
        let visibleFrames = page.passwordVaultVisibleContentFramesForTesting.sorted { $0.minY < $1.minY }
        for pair in zip(visibleFrames, visibleFrames.dropFirst()) {
            #expect(pair.0.maxY <= pair.1.minY + 0.5 || !pair.0.intersects(pair.1))
        }
        #expect(page.passwordVaultPendingRowVisibleForTesting)
        #expect(page.passwordVaultRetryVisibleForTesting)
        #expect(!page.passwordVaultResetActionsEnabledForTesting)
        #expect(page.passwordVaultPendingDetailForTesting == passwordVaultTask7Chinese[
            "OneDrive changed elsewhere. Retry will archive the latest remote encrypted vault before replacing the active vault."
        ])
        #expect(page.passwordVaultMasterFeedbackVisibleForTesting == false)
        #expect(page.passwordVaultForceFeedbackVisibleForTesting == false)
        #expect(page.passwordVaultHiddenOptionalRowsAreCollapsedForTesting)
    }

    @Test
    func renderPasswordVaultTask7VisualEvidence() throws {
        let outputDirectory = URL(fileURLWithPath: "/tmp/pastera-password-vault-task7", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let ordinaryState = PasswordVaultSecuritySettingsState(
            vaultState: .unlocked,
            isBusy: false,
            autoLockInterval: 300,
            quickUnlockEnabled: true,
            quickUnlockAvailable: true,
            masterPasswordResetCapability: .preservesData,
            forcedResetPending: false,
            forcedResetPendingFailure: nil
        )
        let light = CPYPasswordVaultPreferenceViewController()
        try renderPasswordVaultPage(
            light,
            state: ordinaryState,
            width: 480,
            appearance: .aqua,
            to: outputDirectory.appendingPathComponent("password-vault-480-light.png")
        )

        let dark = CPYPasswordVaultPreferenceViewController()
        try renderPasswordVaultPage(
            dark,
            state: ordinaryState,
            width: 900,
            appearance: .darkAqua,
            to: outputDirectory.appendingPathComponent("password-vault-900-dark.png")
        )

        let pendingChinese = CPYPasswordVaultPreferenceViewController(
            localizedString: { passwordVaultTask7Chinese[$0] ?? pasteraPreferenceString($0) }
        )
        try renderPasswordVaultPage(
            pendingChinese,
            state: .init(
                vaultState: .unlocked,
                isBusy: false,
                autoLockInterval: 300,
                quickUnlockEnabled: true,
                quickUnlockAvailable: true,
                masterPasswordResetCapability: .preservesData,
                forcedResetPending: true,
                forcedResetPendingFailure: .remoteVerificationFailed
            ),
            width: 480,
            appearance: .aqua,
            to: outputDirectory.appendingPathComponent("password-vault-480-light-zh-pending.png")
        )
    }

    @Test
    func renderPasswordVaultTask8RecoveryVisualEvidence() throws {
        let outputDirectory = URL(fileURLWithPath: "/tmp/pastera-password-vault-task8", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let recoveryState = PasswordVaultSecuritySettingsState(
            vaultState: .recoveryRequired("forced-reset-cleanup"),
            isBusy: false,
            autoLockInterval: 300,
            quickUnlockEnabled: true,
            quickUnlockAvailable: true,
            masterPasswordResetCapability: .preservesData,
            forcedResetPending: true,
            forcedResetPendingFailure: .remoteVerificationFailed
        )

        try renderPasswordVaultPage(
            CPYPasswordVaultPreferenceViewController(),
            state: recoveryState,
            width: 480,
            appearance: .aqua,
            to: outputDirectory.appendingPathComponent("password-vault-recovery-480-light.png")
        )
        try renderPasswordVaultPage(
            CPYPasswordVaultPreferenceViewController(),
            state: recoveryState,
            width: 900,
            appearance: .darkAqua,
            to: outputDirectory.appendingPathComponent("password-vault-recovery-900-dark.png")
        )
    }

    @Test
    func generalGroupsUseSemanticHeaderIconsAndStableRowRhythm() throws {
        let page = CPYGeneralPreferenceViewController()
        page.loadView()
        page.view.frame = NSRect(x: 0, y: 0, width: 520, height: 900)
        page.view.layoutSubtreeIfNeeded()

        let groups = preferenceGroups(in: page.view)
        #expect(groups.count == 4)
        for group in groups {
            let icons = descendantImageViews(in: group).filter {
                $0.accessibilityIdentifier() == "preference.group.icon"
            }
            let rows = descendantSettingRows(in: group)
            let separators = descendantViews(in: group).filter {
                $0.accessibilityIdentifier() == "preference.group.separator"
            }
            #expect(icons.count == 1)
            #expect(!rows.isEmpty)
            #expect(rows.allSatisfy { $0.frame.height >= 48 })
            #expect(!separators.isEmpty)
            #expect(separators.allSatisfy { ($0.layer?.backgroundColor?.alpha ?? 1) <= 0.15 })
        }
    }

    @Test
    func nativeTask5AnchorsStayInsideTheirPageBounds() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }
        controller.showWindow(nil)

        let anchors: [(PasteraPreferencePaneID, [String])] = [
            (.sync, [
                "sync.oneDriveStatus",
                "sync.rootFolder",
                "sync.passwordVault",
                "sync.fileTypes",
                "sync.actions"
            ]),
            (.softwareUpdate, [
                "softwareUpdate.currentVersion",
                "softwareUpdate.automaticCheck",
                "softwareUpdate.lastCheck"
            ]),
            (.about, ["about.version", "about.github", "about.license"])
        ]
        for (paneID, anchorIDs) in anchors {
            controller.showPreferencePaneForTesting(paneID: paneID)
            let paneBounds = NSRect(
                origin: .zero,
                size: NSSize(
                    width: controller.selectedPaneDocumentWidthForTesting,
                    height: controller.selectedPaneDocumentHeightForTesting
                )
            )
            for anchorID in anchorIDs {
                let frame = try #require(controller.selectedPaneDescendantFrameForTesting(
                    accessibilityIdentifier: anchorID
                ))
                #expect(frame.minX >= paneBounds.minX - 0.5)
                #expect(frame.maxX <= paneBounds.maxX + 0.5)
                #expect(frame.minY >= paneBounds.minY - 0.5)
                #expect(frame.maxY <= paneBounds.maxY + 0.5)
            }
        }
    }

    @Test
    func excludedAppsNativePaneKeepsTitleAndTableInsideContentBounds() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(paneID: .excludedApps)

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let titleFrame = try #require(controller.selectedPaneTextFrameForTesting(
            matching: ["Excluded Apps", "忽略应用"]
        ))
        let tableFrame = try #require(controller.selectedPaneDescendantFrameForTesting(
            accessibilityIdentifier: "exclude.apps.scroll"
        ))
        let paneBounds = NSRect(
            origin: .zero,
            size: NSSize(
                width: controller.selectedPaneDocumentWidthForTesting,
                height: controller.selectedPaneDocumentHeightForTesting
            )
        )

        #expect(titleFrame.minX >= -0.5)
        #expect(titleFrame.maxX <= controller.selectedPaneDocumentWidthForTesting + 0.5)
        #expect(titleFrame.minY >= -0.5)
        #expect(titleFrame.maxY <= controller.selectedPaneDocumentHeightForTesting + 0.5)
        #expect(tableFrame.minX >= paneBounds.minX - 0.5)
        #expect(tableFrame.maxX <= paneBounds.maxX + 0.5)
        #expect(tableFrame.minY >= paneBounds.minY - 0.5)
        #expect(tableFrame.maxY <= paneBounds.maxY + 0.5)
        #expect(tableFrame.width >= controller.selectedPaneDocumentWidthForTesting - 100)
    }

    @Test
    func shortcutsPaneDisplaysHistoryPanelRowsAndAlignsLabelAndRecordColumns() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let textFrames = preferenceTextFieldFrames(in: contentView)
            .filter { $0.frame.minX >= paneMinX }
        let sectionTitles = textFrames.filter {
            [
                "Menu Shortcuts",
                "菜单快捷键",
                "History Panel Shortcuts",
                "历史面板快捷键"
            ].contains($0.text)
        }
        let rowLabels = textFrames.filter {
            [
                "Main",
                "History",
                "Search",
                "Snippets",
                "Password Vault",
                "主体",
                "历史",
                "搜索",
                "片段",
                "密码箱"
            ].contains($0.text)
        }
        let recordFrames = preferenceRecordViewFrames(in: contentView)
            .filter { $0.minX >= paneMinX }
        let menuTitle = try #require(textFrames.first {
            ["Menu Shortcuts", "菜单快捷键"].contains($0.text)
        })
        let historyPanelTitle = try #require(textFrames.first {
            ["History Panel Shortcuts", "历史面板快捷键"].contains($0.text)
        })
        let searchLabel = try #require(rowLabels.first {
            ["Search", "搜索"].contains($0.text)
        })

        #expect(sectionTitles.count == 2)
        #expect(rowLabels.count == 5)
        #expect(recordFrames.count == 5)
        #expect(!textFrames.contains {
            ["Clear History:", "清空历史：", "清除历史："].contains($0.text)
        })
        #expect(abs(menuTitle.frame.minX - historyPanelTitle.frame.minX) <= 1)
        #expect(menuTitle.frame.maxY > historyPanelTitle.frame.maxY)
        #expect(searchLabel.frame.minY >= -0.5)
        #expect(searchLabel.frame.maxY <= controller.selectedPaneDocumentHeightForTesting + 0.5)

        let labelColumns = Set(rowLabels.map { Int(($0.frame.minX / 2).rounded()) })
        let recordColumns = Set(recordFrames.map { Int(($0.minX / 2).rounded()) })
        let paneMaxX = paneFrame.maxX
        #expect(labelColumns.count == 1)
        #expect(recordColumns.count == 1)
        for frame in recordFrames {
            #expect(frame.maxX <= paneMaxX)
        }
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard view.isHidden == false, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, textField.stringValue.isEmpty == false {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceGroups(in view: NSView) -> [PasteraPreferenceGroupView] {
        view.subviews.compactMap { $0 as? PasteraPreferenceGroupView }
            + view.subviews.flatMap { preferenceGroups(in: $0) }
    }

    private func descendantImageViews(in view: NSView) -> [NSImageView] {
        view.subviews.compactMap { $0 as? NSImageView }
            + view.subviews.flatMap { descendantImageViews(in: $0) }
    }

    private func descendantSettingRows(in view: NSView) -> [PasteraPreferenceSettingRowView] {
        view.subviews.compactMap { $0 as? PasteraPreferenceSettingRowView }
            + view.subviews.flatMap { descendantSettingRows(in: $0) }
    }

    private func descendantViews(in view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendantViews(in: $0) }
    }

    private func preferenceTableScrollFrame(in view: NSView, root: NSView? = nil) -> NSRect? {
        let rootView = root ?? view
        if let scrollView = view as? NSScrollView,
           scrollView.documentView is NSTableView {
            return rootView.convert(scrollView.frame, from: scrollView.superview)
        }
        for subview in view.subviews {
            if let frame = preferenceTableScrollFrame(in: subview, root: rootView) {
                return frame
            }
        }
        return nil
    }

    private func preferenceRecordViewFrames(in view: NSView, root: NSView? = nil) -> [NSRect] {
        let rootView = root ?? view
        var values = [NSRect]()
        if String(describing: type(of: view)).contains("RecordView") {
            values.append(rootView.convert(view.frame, from: view.superview))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceRecordViewFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferencePopUpFrames(in view: NSView, root: NSView? = nil) -> [NSRect] {
        let rootView = root ?? view
        var values = [NSRect]()
        if view is NSPopUpButton {
            values.append(rootView.convert(view.frame, from: view.superview))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferencePopUpFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceSwitches(in view: NSView) -> [NSSwitch] {
        var switches = view.subviews.compactMap { $0 as? NSSwitch }
        view.subviews.forEach { switches.append(contentsOf: preferenceSwitches(in: $0)) }
        return switches
    }

    private func preferenceSwitchButtons(in view: NSView, labels: Set<String>) -> [NSButton] {
        preferenceButtons(in: view).filter {
            labels.contains($0.accessibilityLabel() ?? "")
        }
    }
}

@MainActor
@Suite(.serialized)
struct GeneralPreferenceMergedMenuTests {
    @Test
    func generalPaneContainsOnlyApprovedNativeGeneralSettings() throws {
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let paneFrame = controller.selectedPaneFrameInContentViewForTesting
        let paneMinX = paneFrame.minX - 1
        let paneMaxX = paneFrame.maxX + 1
        let allButtonFrames = preferenceButtonFrames(in: contentView)
        let sidebarButtonTitles = allButtonFrames
            .filter { $0.frame.maxX < paneMinX }
            .map(\.title)
        let buttonFrames = allButtonFrames.filter { $0.frame.minX >= paneMinX }
        let textFields = preferenceTextFieldFrames(in: contentView).filter { $0.frame.minX >= paneMinX }
        let launchFrame = try frame(of: [pasteraPreferenceString("Launch on Login")], in: buttonFrames)
        let colorPreviewFrame = try frame(
            of: [pasteraPreferenceString("Show color code preview")],
            in: buttonFrames
        )
        let automaticPasteFrame = try frame(of: [pasteraPreferenceString("Automatic Paste")], in: buttonFrames)
        let automaticPasteInfoFrame = try frame(
            of: [pasteraPreferenceString("Automatic Paste Permission Info")],
            in: buttonFrames
        )
        let remoteFrame = try frame(
            of: [pasteraPreferenceString("Pause shortcuts during remote control")],
            in: buttonFrames
        )
        let opacityFrame = try textFrame(of: [pasteraPreferenceString("Transparency")], in: textFields)
        let menuTitleLengthFrame = try textFrame(
            of: [pasteraPreferenceString("Number of characters in the menu:")],
            in: textFields
        )
        let visibleControlsFrame = [
            launchFrame,
            opacityFrame,
            menuTitleLengthFrame,
            colorPreviewFrame,
            automaticPasteFrame,
            automaticPasteInfoFrame,
            remoteFrame
        ].reduce(NSRect.null) { $0.union($1) }
        #expect(!sidebarButtonTitles.contains { ["Menu", "菜单"].contains($0) })
        #expect(buttonFrames.allSatisfy { !removedButtonTitles.contains($0.title) })
        #expect(textFields.allSatisfy { !removedTextTitles.contains($0.text) })
        #expect(!buttonFrames.contains { ["Clear History", "清除历史", "清空历史"].contains($0.title) })
        #expect(!buttonFrames.contains { ["Place already copied history at the top", "把已经粘贴的历史置顶"].contains($0.title) })
        #expect(!textFields.contains { ["Image/file limit:", "图片/文件上限："].contains($0.text) })
        #expect(!visibleControlsFrame.isNull)
        let generalPage = try #require(
            controller.cachedPreferencePageForTesting(paneID: .general) as? CPYGeneralPreferenceViewController
        )
        #expect((task3MinimumNativePreferenceGroupGap(in: generalPage.view) ?? 0) >= 11.5)
        for frame in [
            launchFrame,
            opacityFrame,
            menuTitleLengthFrame,
            colorPreviewFrame,
            automaticPasteFrame,
            automaticPasteInfoFrame,
            remoteFrame
        ] {
            #expect(frame.minX >= paneMinX)
            #expect(frame.maxX <= paneMaxX)
        }
        #expect(automaticPasteInfoFrame.minX > automaticPasteFrame.minX)
        #expect(abs(automaticPasteInfoFrame.midY - automaticPasteFrame.midY) <= 2)
    }

    private let removedButtonTitles: Set<String> = [
        "Add a menu item to clear clipboard history",
        "在菜单项中添加清空历史",
        "Show alert panel before clear history",
        "清空历史前显示警告面板",
        "Mark menu items with numbers",
        "用数字标记菜单项",
        "Menu items' title starts with 0",
        "菜单项标题从0开始",
        "Display icons in menu items",
        "在菜单项中显示图标",
        "Add key equivalents to numeric keys",
        "添加等效于数字键的按键",
        "Show Image",
        "显示图像",
        "Show tool tip on a menu item",
        "为菜单项显示工具提示"
    ]

    private let removedTextTitles: Set<String> = [
        "Number of items place inline:",
        "不放进文件夹的菜单项个数：",
        "Number of items place inside a folder:",
        "每个文件夹中项的个数：",
        "Width:",
        "宽度：",
        "Height:",
        "高度：",
        "Max length of tool tip string:",
        "工具提示字符串最大长度："
    ]

    private func frame(
        of titles: Set<String>,
        in frames: [(title: String, frame: NSRect)]
    ) throws -> NSRect {
        try #require(frames.first { titles.contains($0.title) }?.frame)
    }

    private func textFrame(
        of titles: Set<String>,
        in frames: [(text: String, frame: NSRect)]
    ) throws -> NSRect {
        try #require(frames.first { titles.contains($0.text) }?.frame)
    }

    private func preferenceButtonFrames(in view: NSView) -> [(title: String, frame: NSRect)] {
        preferenceButtons(in: view).map { button in
            (
                title: button.accessibilityLabel() ?? button.title,
                frame: view.convert(button.frame, from: button.superview)
            )
        }
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard !view.isHidden, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, !textField.stringValue.isEmpty {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceTextFields(in view: NSView) -> [NSTextField] {
        var fields = view.subviews.compactMap { $0 as? NSTextField }
        view.subviews.forEach { fields.append(contentsOf: preferenceTextFields(in: $0)) }
        return fields
    }

}

@MainActor
@Suite(.serialized)
struct SyncPreferenceOneDriveLocationTests { // swiftlint:disable:this type_body_length
    @Test
    func syncPaneHidesLongOneDrivePathAndShowsValidatedStatus() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .appendingPathComponent("OneDrive", isDirectory: true)
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent().deletingLastPathComponent()) }

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: rootURL.deletingLastPathComponent().deletingLastPathComponent(),
                    syncRootURL: rootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(visibleTexts.contains(pasteraPreferenceString("OneDrive Available")))
            #expect(!visibleTexts.contains("已使用 OneDrive 默认同步位置。"))
            #expect(visibleTexts.contains(pasteraPreferenceString("OneDrive Status")))
            #expect(!visibleTexts.contains("可用"))
            #expect(!visibleTexts.contains(where: { $0.contains("Library/CloudStorage") }))
            #expect(preferenceButtons(in: controller.view).contains {
                $0.title == pasteraPreferenceString("Change")
            })
        }
    }

    @Test
    func syncPaneDoesNotRescanDefaultOneDriveLocationWhenAppBecomesActive() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }
        var resolution = SyncDefaultFolderResolution.notFound

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { resolution })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("未检测到 OneDrive"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == nil)

            resolution = .found(SyncDefaultFolderCandidate(
                oneDriveRootURL: oneDriveRootURL,
                syncRootURL: defaultRootURL,
                displayName: "OneDrive",
                isOneDriveBacked: true
            ))
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            controller.view.layoutSubtreeIfNeeded()

            visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("未检测到 OneDrive"))
            #expect(!visibleTexts.contains("OneDrive 可用"))
            #expect(!visibleTexts.contains("已使用 OneDrive 默认同步位置。"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == nil)
            #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
        }
    }

    @Test
    func syncPaneMarksSavedRootUnavailableWithoutRecreatingItWhenAppBecomesActive() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: defaultRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(defaultRootURL.path, forKey: Constants.UserDefaults.syncRootPath)
            defaults.synchronize()

            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: defaultRootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            let window = SyncPreferenceVisibilityWindow()
            window.contentView = controller.view
            window.testIsVisible = true
            defer { window.contentView = nil }
            controller.view.layoutSubtreeIfNeeded()

            var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("OneDrive 可用"))

            try FileManager.default.removeItem(at: defaultRootURL)
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            controller.view.layoutSubtreeIfNeeded()

            visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!visibleTexts.contains("OneDrive 可用"))
            #expect(!visibleTexts.contains("所选 OneDrive 文件夹不可用。"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
            #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
            #expect(preferenceButtons(in: controller.view).first {
                $0.title == pasteraPreferenceString("Show in Finder")
            }?.isEnabled == false)
        }
    }

    @Test
    func syncPanePreservesMissingSavedRootAcrossRepeatedOneDriveLifecycleCycles() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(defaultRootURL.path, forKey: Constants.UserDefaults.syncRootPath)
            defaults.synchronize()

            for _ in 0..<3 {
                try FileManager.default.createDirectory(at: defaultRootURL, withIntermediateDirectories: true)
                var controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                    .found(SyncDefaultFolderCandidate(
                        oneDriveRootURL: oneDriveRootURL,
                        syncRootURL: defaultRootURL,
                        displayName: "OneDrive",
                        isOneDriveBacked: true
                    ))
                })
                controller.loadView()
                controller.viewDidLoad()
                controller.view.layoutSubtreeIfNeeded()
                var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
                #expect(visibleTexts.contains("OneDrive 可用"))
                #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)

                try FileManager.default.removeItem(at: defaultRootURL)
                controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                    .found(SyncDefaultFolderCandidate(
                        oneDriveRootURL: oneDriveRootURL,
                        syncRootURL: defaultRootURL,
                        displayName: "OneDrive",
                        isOneDriveBacked: true
                    ))
                })
                controller.loadView()
                controller.viewDidLoad()
                controller.view.layoutSubtreeIfNeeded()
                visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
                #expect(!visibleTexts.contains("OneDrive 可用"))
                #expect(!visibleTexts.contains("所选 OneDrive 文件夹不可用。"))
                #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
                #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
            }
        }
    }

    @Test
    func syncPaneKeepsValidatedSavedCustomOneDriveLocation() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let customURL = oneDriveRootURL
            .appendingPathComponent("CustomSync", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: customURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(customURL.path, forKey: Constants.UserDefaults.syncRootPath)
            defaults.synchronize()

            let controller = CPYSyncPreferenceViewController(defaultFolderResolver: SyncDefaultFolderResolver(fileManager: .default), defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: defaultRootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == customURL.standardizedFileURL.path)
            #expect(!FileManager.default.fileExists(atPath: defaultRootURL.path))
        }
    }

    @Test
    func syncPaneChangeLocationSavesOnlyValidatedOneDriveFolder() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        let customRootURL = oneDriveRootURL.appendingPathComponent("PasteraCustom", isDirectory: true)
        let invalidRootURL = homeURL.appendingPathComponent("PlainFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: invalidRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            var selectedURL = invalidRootURL
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: {
                    .found(SyncDefaultFolderCandidate(
                        oneDriveRootURL: oneDriveRootURL,
                        syncRootURL: defaultRootURL,
                        displayName: "OneDrive",
                        isOneDriveBacked: true
                    ))
                },
                chooseSyncRoot: { _, _ in selectedURL }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()
            let changeButton = try #require(preferenceButtons(in: controller.view).first { $0.title == "修改" })

            changeButton.performClick(nil)

            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
            #expect(!Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
                .contains("请选择 OneDrive 中可写的文件夹。"))

            selectedURL = customRootURL
            changeButton.performClick(nil)

            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == customRootURL.standardizedFileURL.path)
            let validTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!validTexts.contains("同步位置已更新，并通过 OneDrive 文件夹检查。"))
            #expect(validTexts.contains("OneDrive 可用"))
        }
    }

    @Test
    func syncPaneAutomaticallyUsesPersonalOneDriveWhenMultipleAccountsAreDetected() throws {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personalRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let workRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive - Work", isDirectory: true)
        try FileManager.default.createDirectory(at: personalRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let candidates = [
            SyncDefaultFolderCandidate(
                oneDriveRootURL: personalRootURL,
                syncRootURL: recommendedSyncRootURL(oneDriveRootURL: personalRootURL),
                displayName: "OneDrive",
                isOneDriveBacked: true
            ),
            SyncDefaultFolderCandidate(
                oneDriveRootURL: workRootURL,
                syncRootURL: recommendedSyncRootURL(oneDriveRootURL: workRootURL),
                displayName: "OneDrive - Work",
                isOneDriveBacked: true
            )
        ]

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { .multiple(candidates) })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(!visibleTexts.contains("OneDrive > Pastera > sync"))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(!visibleTexts.contains("找到多个 OneDrive 账号，请选择要使用的 OneDrive 文件夹。"))
            #expect(FileManager.default.fileExists(atPath: recommendedSyncRootURL(oneDriveRootURL: personalRootURL).path))
            #expect(!FileManager.default.fileExists(atPath: recommendedSyncRootURL(oneDriveRootURL: workRootURL).path))
        }
    }

    @Test
    func syncPaneGranularScopeSwitchesWriteTheirDefaultsWithoutAutomaticFlags() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: defaultRootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()
            let historyUploadSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Upload History")
            })
            let historyImportSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Import History")
            })

            historyUploadSwitch.performClick(nil)

            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticEnabled))

            historyImportSwitch.performClick(nil)

            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncAutomaticEnabled))
        }
    }

    @Test
    func syncPaneFileTypeCheckboxesReplaceFileSwitchesAndDeriveFileScopesFromHistoryDirections() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = recommendedSyncRootURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: defaultRootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()
            let labels = Set(preferenceSwitchButtons(in: controller.view).compactMap { $0.accessibilityLabel() })
            #expect(!labels.contains("上传文件"))
            #expect(!labels.contains("同步文件"))
            let fileTypeLabels: Set<String> = [
                pasteraPreferenceString("Images"),
                pasteraPreferenceString("Common Document Types")
            ]
            let fileTypeCheckboxes = preferenceButtons(in: controller.view).filter {
                fileTypeLabels.contains($0.accessibilityLabel() ?? "")
            }
            #expect(fileTypeCheckboxes.count == 2)
            #expect(!preferenceButtons(in: controller.view).contains { $0.accessibilityLabel() == "Finder 文件" })
            #expect(!preferenceButtons(in: controller.view).contains {
                ["PDF", "RTF", "RTFD"].contains($0.accessibilityLabel() ?? "")
            })
            #expect(fileTypeCheckboxes.allSatisfy { $0.state == .off })

            let historyUploadSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Upload History")
            })
            let historyImportSwitch = try #require(preferenceSwitchButtons(in: controller.view).first {
                $0.accessibilityLabel() == pasteraPreferenceString("Import History")
            })
            let commonTextCheckbox = try #require(fileTypeCheckboxes.first {
                $0.accessibilityLabel() == pasteraPreferenceString("Common Document Types")
            })

            historyUploadSwitch.performClick(nil)
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))

            commonTextCheckbox.performClick(nil)

            #expect(commonTextCheckbox.state == .on)
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))

            historyImportSwitch.performClick(nil)
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled))
            #expect(defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))

            commonTextCheckbox.performClick(nil)

            #expect(commonTextCheckbox.state == .off)
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled))
            #expect(!defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled))
        }
    }

    private func cloudStorageURL(homeURL: URL) -> URL {
        homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
    }

    private func recommendedSyncRootURL(oneDriveRootURL: URL) -> URL {
        oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    private func withPreservedSyncDefaults(_ work: () throws -> Void) throws {
        let defaults = AppEnvironment.current.defaults
        let syncKeys = [
            Constants.UserDefaults.syncAutomaticUploadEnabled,
            Constants.UserDefaults.syncAutomaticEnabled,
            Constants.UserDefaults.syncRootPath,
            Constants.UserDefaults.syncHistoryUploadEnabled,
            Constants.UserDefaults.syncHistoryImportEnabled,
            Constants.UserDefaults.syncSnippetUploadEnabled,
            Constants.UserDefaults.syncSnippetImportEnabled,
            Constants.UserDefaults.syncFileUploadEnabled,
            Constants.UserDefaults.syncFileImportEnabled,
            Constants.UserDefaults.syncFileTypes
        ]
        let previousValues = syncKeys.reduce(into: [String: Any]()) { values, key in
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        syncKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()
        defer {
            syncKeys.forEach { key in
                if let value = previousValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.synchronize()
        }
        try work()
    }

    private func preferenceTextFieldFrames(in view: NSView, root: NSView? = nil) -> [(text: String, frame: NSRect)] {
        let rootView = root ?? view
        var values = [(text: String, frame: NSRect)]()
        guard view.isHidden == false, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, textField.stringValue.isEmpty == false {
            values.append((textField.stringValue, rootView.convert(textField.frame, from: textField.superview)))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceSwitches(in view: NSView) -> [NSSwitch] {
        var switches = view.subviews.compactMap { $0 as? NSSwitch }
        view.subviews.forEach { switches.append(contentsOf: preferenceSwitches(in: $0)) }
        return switches
    }

    private func preferenceSwitchButtons(in view: NSView) -> [NSButton] {
        let switchLabels: Set<String> = [
            pasteraPreferenceString("Upload History"),
            pasteraPreferenceString("Import History"),
            pasteraPreferenceString("Upload Snippets"),
            pasteraPreferenceString("Import Snippets")
        ]
        return preferenceButtons(in: view).filter {
            switchLabels.contains($0.accessibilityLabel() ?? "")
        }
    }
}

private final class SyncPreferenceVisibilityWindow: NSWindow {
    var testIsVisible = false

    override var isVisible: Bool {
        testIsVisible
    }
}
