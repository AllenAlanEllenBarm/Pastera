import AppKit

// This native page keeps its compact state machine, manual layout, and actions together.
// swiftlint:disable file_length

enum PasswordVaultCreateStorageMode: String, Equatable {
    case localOnly
    case oneDrive
}

struct MainMenuPasswordVaultSyncDataSource {
    let snapshot: () -> PasswordVaultSyncSnapshot
    let candidates: () -> [SyncDefaultFolderCandidate]
    let enableOneDrive: (
        URL,
        String?,
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void
    let switchToLocalOnly: (
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void
    let retryWithRemotePassword: (
        String,
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void
    let retry: () -> Void
    let startOneDrive: () -> Bool
    let deleteRemoteReplica: (
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void
}

// swiftlint:disable:next type_body_length
final class PasswordVaultSyncView: NSView {
    private enum Metrics {
        static let inset: CGFloat = 12
        static let sectionSpacing: CGFloat = 14
        static let rowHeight: CGFloat = 58
        static let candidateHeight: CGFloat = 42
        static let buttonHeight: CGFloat = 32
        static let minimumHeight: CGFloat = 470
    }

    private let dataSource: MainMenuPasswordVaultSyncDataSource
    private let onContentSizeChange: () -> Void
    private let onRequestRemoteDeletion: () -> Void
    private let onRequestConflictSummary: () -> Void
    private var snapshot: PasswordVaultSyncSnapshot
    private var processStatus: OneDriveProcessStatus
    private var candidates: [SyncDefaultFolderCandidate]
    private var selectedCandidateURL: URL?
    private var isEnabling = false
    private var inlineError: String?

    private let localStatusRow = PasswordVaultSyncStatusRow()
    private let oneDriveStatusRow = PasswordVaultSyncStatusRow()
    private let pendingStatusRow = PasswordVaultSyncStatusRow()
    private let guidanceLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let candidateStack = NSStackView()
    private let primaryButton = NSButton()
    private let secondaryButton = NSButton()
    private let reviewButton = NSButton()
    private let stopButton = NSButton()
    private let deleteButton = NSButton()

    init(
        dataSource: MainMenuPasswordVaultSyncDataSource,
        processStatus: OneDriveProcessStatus,
        onRequestRemoteDeletion: @escaping () -> Void,
        onRequestConflictSummary: @escaping () -> Void,
        onContentSizeChange: @escaping () -> Void
    ) {
        self.dataSource = dataSource
        self.processStatus = processStatus
        self.onRequestRemoteDeletion = onRequestRemoteDeletion
        self.onRequestConflictSummary = onRequestConflictSummary
        self.onContentSizeChange = onContentSizeChange
        snapshot = dataSource.snapshot()
        candidates = dataSource.candidates()
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MainMenuPanelLayout.width,
            height: Self.preferredHeight(candidateCount: candidates.count)
        ))
        setup()
        render()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layoutContent()
    }

    func update(snapshot: PasswordVaultSyncSnapshot, processStatus: OneDriveProcessStatus) {
        let previousCandidateCount = candidates.count
        self.snapshot = snapshot
        self.processStatus = processStatus
        reloadCandidatesPreservingSelection()
        frame.size.height = Self.preferredHeight(candidateCount: candidates.count)
        render()
        if candidates.count != previousCandidateCount {
            onContentSizeChange()
        }
    }

    private func reloadCandidatesPreservingSelection() {
        let availableCandidates = dataSource.candidates()
        let selectedURL = selectedCandidateURL
        candidates = availableCandidates
        if let selectedURL,
           !availableCandidates.contains(where: { $0.syncRootURL == selectedURL }) {
            selectedCandidateURL = nil
        }
    }

    private func setup() {
        wantsLayer = true
        localStatusRow.identifier = NSUserInterfaceItemIdentifier("passwordVaultSyncLocalStatus")
        oneDriveStatusRow.identifier = NSUserInterfaceItemIdentifier("passwordVaultSyncOneDriveStatus")
        pendingStatusRow.identifier = NSUserInterfaceItemIdentifier("passwordVaultSyncPendingStatus")

        guidanceLabel.font = .systemFont(ofSize: 11)
        guidanceLabel.textColor = .secondaryLabelColor
        guidanceLabel.maximumNumberOfLines = 3
        guidanceLabel.identifier = NSUserInterfaceItemIdentifier("passwordVaultSyncGuidance")

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.identifier = NSUserInterfaceItemIdentifier("passwordVaultSyncError")

        candidateStack.orientation = .vertical
        candidateStack.alignment = .leading
        candidateStack.spacing = 6
        candidateStack.identifier = NSUserInterfaceItemIdentifier("passwordVaultSyncCandidates")

        configureButton(
            primaryButton,
            identifier: "passwordVaultSyncPrimaryButton",
            action: #selector(primaryClicked(_:))
        )
        configureButton(
            secondaryButton,
            identifier: "passwordVaultSyncSecondaryButton",
            action: #selector(secondaryClicked(_:))
        )
        secondaryButton.bezelStyle = .inline
        secondaryButton.isBordered = false
        secondaryButton.contentTintColor = .secondaryLabelColor
        configureButton(
            reviewButton,
            identifier: "passwordVaultSyncReviewButton",
            action: #selector(reviewClicked(_:))
        )
        reviewButton.bezelStyle = .inline
        reviewButton.isBordered = false
        reviewButton.contentTintColor = .controlAccentColor
        configureButton(
            stopButton,
            identifier: "passwordVaultSyncStopButton",
            action: #selector(stopClicked(_:))
        )
        stopButton.bezelStyle = .inline
        stopButton.isBordered = false
        stopButton.contentTintColor = .secondaryLabelColor
        configureButton(
            deleteButton,
            identifier: "passwordVaultSyncDeleteButton",
            action: #selector(deleteClicked(_:))
        )
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .systemRed

        [localStatusRow, oneDriveStatusRow, pendingStatusRow, guidanceLabel,
         errorLabel, candidateStack, primaryButton, secondaryButton, reviewButton,
         stopButton, deleteButton].forEach(addSubview)
    }

    private func configureButton(_ button: NSButton, identifier: String, action: Selector) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .large
    }

    private func render() {
        localStatusRow.configure(
            symbolName: snapshot.localVaultAvailable ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
            tintColor: snapshot.localVaultAvailable ? .systemGreen : .systemRed,
            title: snapshot.localVaultAvailable
                ? String(localized: "Saved on This Mac")
                : String(localized: "Local vault is not ready"),
            detail: snapshot.localVaultAvailable
                ? String(localized: "Your encrypted vault remains available without OneDrive.")
                : String(localized: "Restore the local copy before changing sync settings.")
        )
        renderOneDriveStatus()
        renderPendingStatus()
        renderCandidates()
        renderActions()
        errorLabel.stringValue = inlineError ?? ""
        errorLabel.isHidden = inlineError == nil
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func renderOneDriveStatus() {
        let title: String
        let detail: String
        let symbolName: String
        let tintColor: NSColor
        if snapshot.mode == .localOnly {
            title = String(localized: "OneDrive sync is off")
            detail = String(localized: "Nothing is uploaded until you choose to enable sync.")
            symbolName = "cloud"
            tintColor = .secondaryLabelColor
        } else if !processStatus.isRunning {
            title = String(localized: "OneDrive is disconnected")
            detail = String(localized: "Local changes are safe and will wait on this Mac.")
            symbolName = "bolt.slash.fill"
            tintColor = .systemRed
        } else {
            title = oneDrivePhaseTitle
            detail = oneDrivePhaseDetail
            symbolName = oneDrivePhaseSymbol
            tintColor = oneDrivePhaseTint
        }
        oneDriveStatusRow.configure(
            symbolName: symbolName,
            tintColor: tintColor,
            title: title,
            detail: detail
        )
    }

    private func renderPendingStatus() {
        let count = snapshot.pendingChangeCount
        let title = count == 0
            ? String(localized: "No changes waiting")
            : String(format: String(localized: "%lld changes waiting"), Int64(count))
        let detail: String
        if snapshot.conflictCopyCount > 0 {
            detail = String(
                format: String(localized: "%lld conflict copies need review."),
                Int64(snapshot.conflictCopyCount)
            )
        } else if let lastSyncAt = snapshot.lastSyncAt {
            detail = String(
                format: String(localized: "Last synced: %@"),
                Self.dateFormatter.string(from: lastSyncAt)
            )
        } else {
            detail = snapshot.mode == .localOnly
                ? String(localized: "OneDrive has never been enabled for this vault.")
                : String(localized: "The first sync has not finished yet.")
        }
        pendingStatusRow.configure(
            symbolName: snapshot.conflictCopyCount > 0 ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath",
            tintColor: snapshot.conflictCopyCount > 0 ? .systemYellow : .secondaryLabelColor,
            title: title,
            detail: detail
        )
    }

    private func renderCandidates() {
        candidateStack.arrangedSubviews.forEach {
            candidateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard snapshot.mode == .localOnly else {
            candidateStack.isHidden = true
            return
        }
        candidateStack.isHidden = candidates.isEmpty
        candidateStack.frame.size.height = CGFloat(candidates.count) * Metrics.candidateHeight
        if candidates.count == 1, selectedCandidateURL == nil {
            selectedCandidateURL = candidates[0].syncRootURL
        }
        for (index, candidate) in candidates.enumerated() {
            let button = NSButton(
                radioButtonWithTitle: candidate.displayName,
                target: self,
                action: #selector(candidateClicked(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier("passwordVaultSyncCandidate-\(index)")
            button.tag = index
            button.state = candidate.syncRootURL == selectedCandidateURL ? .on : .off
            button.setAccessibilityLabel(String(
                format: String(localized: "Use OneDrive folder: %@"),
                candidate.displayName
            ))
            candidateStack.addArrangedSubview(button)
        }
    }

    private func renderActions() {
        if snapshot.mode == .localOnly {
            guidanceLabel.stringValue = candidates.isEmpty
                ? String(localized: "No OneDrive account folder was found. Install OneDrive or sign in, then try again.")
                : String(localized: "Choose the OneDrive account that should hold the encrypted replica.")
            primaryButton.title = isEnabling
                ? String(localized: "Enabling…")
                : String(localized: "Enable OneDrive Sync")
            primaryButton.isEnabled = !isEnabling && selectedCandidateURL != nil
            primaryButton.isHidden = candidates.isEmpty
            secondaryButton.title = String(localized: "Start OneDrive")
            secondaryButton.isHidden = processStatus.isRunning || processStatus.appURL == nil
            reviewButton.isHidden = true
            stopButton.isHidden = true
            deleteButton.isHidden = true
        } else {
            guidanceLabel.stringValue = guidanceForEnabledMode
            primaryButton.title = String(localized: "Try Again")
            primaryButton.isEnabled = true
            primaryButton.isHidden = isHealthyEnabledState
            secondaryButton.title = String(localized: "Start OneDrive")
            secondaryButton.isHidden = processStatus.isRunning || processStatus.appURL == nil
            reviewButton.title = String(localized: "Review Sync Result")
            reviewButton.isHidden = snapshot.conflictCopyCount == 0
            stopButton.title = String(localized: "Stop Sync, Keep Copies")
            stopButton.isHidden = false
            deleteButton.title = String(localized: "Delete Cloud Copy…")
            deleteButton.isHidden = false
        }
    }

    private var isHealthyEnabledState: Bool {
        guard processStatus.isRunning else { return false }
        return switch snapshot.phase {
        case .synced, .syncing, .conflicts: true
        case .disabled, .disconnected, .waitingForUnlock, .failed: false
        }
    }

    private var guidanceForEnabledMode: String {
        if !processStatus.isRunning {
            return String(localized: "Keep working normally. Pastera will upload queued changes after OneDrive reconnects.")
        }
        switch snapshot.phase {
        case .synced:
            return String(localized: "The encrypted local vault and OneDrive replica are up to date.")
        case .syncing:
            return String(localized: "Pastera is updating the encrypted OneDrive replica.")
        case .conflicts:
            return String(localized: "Your vault stays unlocked. Conflict copies can be reviewed later.")
        case .waitingForUnlock:
            return String(localized: "Unlock the local vault to finish merging remote changes.")
        case .disconnected, .failed:
            return String(localized: "Local changes remain safe. Check OneDrive and try again.")
        case .disabled:
            return String(localized: "OneDrive sync is currently off.")
        }
    }

    private var oneDrivePhaseTitle: String {
        switch snapshot.phase {
        case .synced: String(localized: "OneDrive is connected")
        case .syncing: String(localized: "Syncing with OneDrive")
        case .conflicts: String(localized: "OneDrive sync has conflicts")
        case .waitingForUnlock: String(localized: "Sync is waiting for unlock")
        case .disconnected, .failed: String(localized: "OneDrive sync needs attention")
        case .disabled: String(localized: "OneDrive sync is off")
        }
    }

    private var oneDrivePhaseDetail: String {
        switch snapshot.phase {
        case .syncing(let step): passwordVaultSyncStepTitle(step)
        case .conflicts(let count): String(
            format: String(localized: "%lld conflict copies are available."),
            Int64(count)
        )
        case .waitingForUnlock: String(localized: "Queued changes remain on this Mac.")
        case .disconnected(let failure), .failed(let failure): passwordVaultSyncFailureMessage(failure)
        case .synced: String(localized: "The encrypted replica is up to date.")
        case .disabled: String(localized: "Nothing is uploaded.")
        }
    }

    private var oneDrivePhaseSymbol: String {
        switch snapshot.phase {
        case .synced: "checkmark.icloud.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .conflicts: "exclamationmark.triangle.fill"
        case .waitingForUnlock: "lock.fill"
        case .disconnected, .failed: "exclamationmark.icloud.fill"
        case .disabled: "cloud"
        }
    }

    private var oneDrivePhaseTint: NSColor {
        switch snapshot.phase {
        case .conflicts: .systemYellow
        case .disconnected, .failed: .systemRed
        case .waitingForUnlock: .systemOrange
        case .synced, .syncing: .systemBlue
        case .disabled: .secondaryLabelColor
        }
    }

    private func layoutContent() {
        let inset = Metrics.inset
        let width = max(0, bounds.width - inset * 2)
        var top = bounds.height - inset
        for row in [localStatusRow, oneDriveStatusRow, pendingStatusRow] {
            top -= Metrics.rowHeight
            row.frame = NSRect(x: inset, y: top, width: width, height: Metrics.rowHeight)
            top -= 6
        }
        let candidateHeight = candidateStack.isHidden
            ? CGFloat(0)
            : CGFloat(candidates.count) * Metrics.candidateHeight
        if candidateHeight > 0 {
            top -= candidateHeight
            candidateStack.frame = NSRect(x: inset, y: top, width: width, height: candidateHeight)
            top -= Metrics.sectionSpacing
        }
        if !stopButton.isHidden || !deleteButton.isHidden {
            top -= Metrics.buttonHeight
            let actionWidth = (width - 6) / 2
            stopButton.frame = NSRect(x: inset, y: top, width: actionWidth, height: Metrics.buttonHeight)
            deleteButton.frame = NSRect(
                x: inset + actionWidth + 6,
                y: top,
                width: actionWidth,
                height: Metrics.buttonHeight
            )
            top -= 4
        }
        for button in [reviewButton, primaryButton, secondaryButton] where !button.isHidden {
            top -= Metrics.buttonHeight
            button.frame = NSRect(x: inset, y: top, width: width, height: Metrics.buttonHeight)
            top -= 4
        }
        if !errorLabel.isHidden {
            top -= 30
            errorLabel.frame = NSRect(x: inset, y: top, width: width, height: 30)
            top -= 4
        }
        let guidanceHeight = guidanceLabel.isHidden ? CGFloat(0) : CGFloat(46)
        top -= guidanceHeight
        guidanceLabel.frame = NSRect(x: inset, y: top, width: width, height: guidanceHeight)
    }

    @objc private func candidateClicked(_ sender: NSButton) {
        guard candidates.indices.contains(sender.tag) else { return }
        selectedCandidateURL = candidates[sender.tag].syncRootURL
        inlineError = nil
        render()
    }

    @objc private func primaryClicked(_ sender: NSButton) {
        if snapshot.mode == .oneDrive {
            inlineError = nil
            dataSource.retry()
            render()
            return
        }
        guard let selectedCandidateURL else { return }
        isEnabling = true
        inlineError = nil
        render()
        dataSource.enableOneDrive(selectedCandidateURL, nil) { [weak self] result in
            guard let self else { return }
            self.isEnabling = false
            switch result {
            case .success:
                self.snapshot = self.dataSource.snapshot()
                self.inlineError = nil
            case .failure(let failure):
                self.inlineError = passwordVaultSyncFailureMessage(failure)
            }
            self.render()
        }
    }

    @objc private func secondaryClicked(_ sender: NSButton) {
        guard processStatus.appURL != nil else { return }
        if !dataSource.startOneDrive() {
            inlineError = String(localized: "OneDrive could not be started.")
        }
        render()
    }

    @objc private func reviewClicked(_ sender: NSButton) {
        onRequestConflictSummary()
    }

    @objc private func stopClicked(_ sender: NSButton) {
        inlineError = nil
        stopButton.isEnabled = false
        dataSource.switchToLocalOnly { [weak self] result in
            self?.finishStoppingSync(result)
        }
    }

    private func finishStoppingSync(_ result: Result<Void, PasswordVaultSyncFailure>) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.finishStoppingSync(result) }
            return
        }
        stopButton.isEnabled = true
        switch result {
        case .success:
            snapshot = dataSource.snapshot()
            inlineError = nil
        case .failure(let failure):
            inlineError = passwordVaultSyncFailureMessage(failure)
        }
        render()
        onContentSizeChange()
    }

    @objc private func deleteClicked(_ sender: NSButton) {
        onRequestRemoteDeletion()
    }

    private static func preferredHeight(candidateCount: Int) -> CGFloat {
        Metrics.minimumHeight
            + CGFloat(candidateCount) * Metrics.candidateHeight
            + (candidateCount > 0 ? Metrics.sectionSpacing : 0)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

#if DEBUG
    var candidateTitlesForTesting: [String] { candidates.map(\.displayName) }
    var secondaryButtonIsHiddenForTesting: Bool { secondaryButton.isHidden }
    var statusDetailsWrapForTesting: Bool {
        [localStatusRow, oneDriveStatusRow, pendingStatusRow].allSatisfy(\.allowsDetailWrappingForTesting)
    }

    var controlsDoNotOverlapForTesting: Bool {
        layoutSubtreeIfNeeded()
        let controls = [candidateStack, guidanceLabel, errorLabel, primaryButton, secondaryButton,
                        reviewButton, stopButton, deleteButton]
            .filter { !$0.isHidden }
        for index in controls.indices {
            for comparisonIndex in controls.indices where comparisonIndex > index {
                let intersection = controls[index].frame.intersection(controls[comparisonIndex].frame)
                if intersection.width > 0.5 && intersection.height > 0.5 {
                    return false
                }
            }
        }
        return true
    }

    func selectCandidateForTesting(at index: Int) {
        guard candidates.indices.contains(index) else { return }
        selectedCandidateURL = candidates[index].syncRootURL
        render()
    }

    func performPrimaryActionForTesting() {
        primaryClicked(primaryButton)
    }

    var textValuesForTesting: [String] {
        [
            localStatusRow.titleForTesting,
            localStatusRow.detailForTesting,
            oneDriveStatusRow.titleForTesting,
            oneDriveStatusRow.detailForTesting,
            pendingStatusRow.titleForTesting,
            pendingStatusRow.detailForTesting,
            guidanceLabel.stringValue,
            errorLabel.stringValue
        ].filter { !$0.isEmpty }
    }
#endif
}

enum PasswordVaultInlineActionStyle {
    case primary
    case secondary
    case danger
}

final class PasswordVaultInlineActionView: NSView {
    struct Action {
        let title: String
        let identifier: String
        let style: PasswordVaultInlineActionStyle
        let handler: () -> Void
    }

    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let messageLabels: [NSTextField]
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var actionHandlers = [() -> Void]()
    private var actionButtons = [NSButton]()

    init(
        symbolName: String,
        symbolColor: NSColor,
        title: String,
        messages: [String],
        actions: [Action]
    ) {
        messageLabels = messages.map { NSTextField(wrappingLabelWithString: $0) }
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: 234))
        setup(symbolName: symbolName, symbolColor: symbolColor, title: title, actions: actions)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        let width = max(0, bounds.width - inset * 2)
        symbolView.frame = NSRect(x: inset, y: bounds.height - 40, width: 24, height: 24)
        titleLabel.frame = NSRect(x: 46, y: bounds.height - 44, width: max(0, bounds.width - 60), height: 30)

        let messageHeight: CGFloat = messageLabels.count >= 3 ? 28 : 34
        var top = bounds.height - 52
        for label in messageLabels {
            top -= messageHeight
            label.frame = NSRect(x: inset, y: top, width: width, height: messageHeight - 2)
        }

        var buttonY: CGFloat = 8
        for button in actionButtons.reversed() {
            button.frame = NSRect(x: inset, y: buttonY, width: width, height: 28)
            buttonY += 32
        }
        errorLabel.frame = NSRect(x: inset, y: buttonY + 2, width: width, height: 28)
    }

    func setError(_ message: String?) {
        errorLabel.stringValue = message ?? ""
        errorLabel.isHidden = message == nil
        setAccessibilityHelp(message ?? "")
    }

    private func setup(
        symbolName: String,
        symbolColor: NSColor,
        title: String,
        actions: [Action]
    ) {
        wantsLayer = true
        symbolView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.contentTintColor = symbolColor
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        messageLabels.forEach {
            $0.font = .systemFont(ofSize: 10.5)
            $0.textColor = .secondaryLabelColor
            $0.maximumNumberOfLines = 3
            $0.lineBreakMode = .byWordWrapping
        }
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isHidden = true
        [symbolView, titleLabel].forEach(addSubview)
        messageLabels.forEach(addSubview)
        addSubview(errorLabel)

        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.title, target: self, action: #selector(actionClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action.identifier)
            button.tag = index
            button.controlSize = .large
            button.setAccessibilityLabel(action.title)
            switch action.style {
            case .primary:
                button.bezelStyle = .rounded
                button.keyEquivalent = "\r"
            case .secondary:
                button.bezelStyle = .inline
                button.isBordered = false
                button.contentTintColor = .secondaryLabelColor
            case .danger:
                button.bezelStyle = .rounded
                button.contentTintColor = .systemRed
                button.attributedTitle = NSAttributedString(
                    string: action.title,
                    attributes: [
                        .foregroundColor: NSColor.systemRed,
                        .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                    ]
                )
            }
            actionButtons.append(button)
            actionHandlers.append(action.handler)
            addSubview(button)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }

    @objc private func actionClicked(_ sender: NSButton) {
        guard actionHandlers.indices.contains(sender.tag) else { return }
        actionHandlers[sender.tag]()
    }

#if DEBUG
    var textValuesForTesting: [String] {
        [titleLabel.stringValue]
            + messageLabels.map(\.stringValue)
            + [errorLabel.stringValue].filter { !$0.isEmpty }
    }
#endif
}

final class PasswordVaultRemoteCredentialsView: NSView {
    private let titleLabel = NSTextField(wrappingLabelWithString: String(localized: "Unlock the OneDrive Copy"))
    private let messageLabel = NSTextField(wrappingLabelWithString: String(
        localized: "Your local vault is already unlocked. Enter the OneDrive copy's master password for this merge only."
    ))
    private let fieldLabel = NSTextField(labelWithString: String(localized: "OneDrive Vault Master Password"))
    private let secureField = NSSecureTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let submitButton = NSButton()
    private let onSubmit: (String) -> Void

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: 234))
        setup()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        let width = max(0, bounds.width - inset * 2)
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 38, width: width, height: 26)
        messageLabel.frame = NSRect(x: inset, y: bounds.height - 88, width: width, height: 42)
        fieldLabel.frame = NSRect(x: inset, y: bounds.height - 110, width: width, height: 16)
        secureField.frame = NSRect(x: inset, y: bounds.height - 142, width: width, height: 26)
        errorLabel.frame = NSRect(x: inset, y: 46, width: width, height: 30)
        submitButton.frame = NSRect(x: inset, y: 8, width: width, height: 30)
    }

    func clearSecret() {
        secureField.stringValue = ""
    }

    func setError(_ message: String?) {
        errorLabel.stringValue = message ?? ""
        errorLabel.isHidden = message == nil
        setAccessibilityHelp(message ?? "")
    }

    func submit() {
        let password = secureField.stringValue
        clearSecret()
        guard !password.isEmpty else {
            setError(String(localized: "Enter the OneDrive vault master password."))
            return
        }
        setError(nil)
        onSubmit(password)
    }

    private func setup() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        messageLabel.font = .systemFont(ofSize: 10.5)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 3
        fieldLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        secureField.identifier = NSUserInterfaceItemIdentifier("passwordVaultRemoteMasterPasswordField")
        secureField.setAccessibilityLabel(String(localized: "OneDrive Vault Master Password"))
        secureField.target = self
        secureField.action = #selector(submitClicked(_:))
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        submitButton.title = String(localized: "Unlock and Merge")
        submitButton.identifier = NSUserInterfaceItemIdentifier("passwordVaultRemoteCredentialSubmit")
        submitButton.bezelStyle = .rounded
        submitButton.controlSize = .large
        submitButton.target = self
        submitButton.action = #selector(submitClicked(_:))
        submitButton.keyEquivalent = "\r"
        submitButton.setAccessibilityLabel(String(localized: "Unlock the OneDrive copy and merge"))
        [titleLabel, messageLabel, fieldLabel, secureField, errorLabel, submitButton].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "OneDrive copy credentials"))
    }

    @objc private func submitClicked(_ sender: Any?) {
        submit()
    }

#if DEBUG
    var secretValueForTesting: String { secureField.stringValue }
    var textValuesForTesting: [String] {
        [titleLabel.stringValue, messageLabel.stringValue, fieldLabel.stringValue, errorLabel.stringValue]
            .filter { !$0.isEmpty }
    }

    func setSecretForTesting(_ value: String) {
        secureField.stringValue = value
    }
#endif
}

private final class PasswordVaultSyncStatusRow: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: 2, y: bounds.height - 24, width: 18, height: 18)
        let textX: CGFloat = 28
        let textWidth = max(0, bounds.width - textX)
        titleLabel.frame = NSRect(x: textX, y: bounds.height - 21, width: textWidth, height: 17)
        detailLabel.frame = NSRect(x: textX, y: 2, width: textWidth, height: 31)
    }

    func configure(symbolName: String, tintColor: NSColor, title: String, detail: String) {
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        imageView.contentTintColor = tintColor
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        setAccessibilityElement(true)
        setAccessibilityLabel("\(title). \(detail)")
    }

    private func setup() {
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        imageView.imageScaling = .scaleProportionallyDown
        [imageView, titleLabel, detailLabel].forEach(addSubview)
    }

#if DEBUG
    var titleForTesting: String { titleLabel.stringValue }
    var detailForTesting: String { detailLabel.stringValue }
    var allowsDetailWrappingForTesting: Bool {
        detailLabel.maximumNumberOfLines == 2 && detailLabel.lineBreakMode == .byWordWrapping
    }
#endif
}

private func passwordVaultSyncStepTitle(_ step: PasswordVaultSyncStep) -> String {
    switch step {
    case .checking: String(localized: "Checking OneDrive")
    case .downloading: String(localized: "Downloading encrypted replica")
    case .merging: String(localized: "Merging vault changes")
    case .savingLocal: String(localized: "Saving the local vault")
    case .uploading: String(localized: "Uploading encrypted replica")
    case .verifying: String(localized: "Verifying OneDrive copy")
    }
}

func passwordVaultSyncFailureMessage(_ failure: PasswordVaultSyncFailure) -> String {
    switch failure {
    case .oneDriveNotInstalled: String(localized: "OneDrive is not installed.")
    case .oneDriveNotRunning: String(localized: "OneDrive is not running.")
    case .folderUnavailable: String(localized: "The selected OneDrive folder is unavailable.")
    case .folderNotWritable: String(localized: "The selected OneDrive folder is read-only.")
    case .remoteUnavailable: String(localized: "The OneDrive replica is temporarily unavailable.")
    case .remoteCorrupted: String(localized: "The OneDrive replica cannot be read safely.")
    case .remoteCredentialsRequired: String(localized: "The OneDrive replica uses a different master password.")
    case .remoteWriteFailed: String(localized: "The encrypted replica could not be saved to OneDrive.")
    case .remoteVerificationFailed: String(localized: "The saved OneDrive replica could not be verified.")
    }
}

// swiftlint:enable file_length
