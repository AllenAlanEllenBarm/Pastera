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
        static let minimumHeight: CGFloat = 378
    }

    private let dataSource: MainMenuPasswordVaultSyncDataSource
    private let onContentSizeChange: () -> Void
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

    init(
        dataSource: MainMenuPasswordVaultSyncDataSource,
        processStatus: OneDriveProcessStatus,
        onContentSizeChange: @escaping () -> Void
    ) {
        self.dataSource = dataSource
        self.processStatus = processStatus
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

        [localStatusRow, oneDriveStatusRow, pendingStatusRow, guidanceLabel,
         errorLabel, candidateStack, primaryButton, secondaryButton].forEach(addSubview)
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
        } else {
            guidanceLabel.stringValue = guidanceForEnabledMode
            primaryButton.title = String(localized: "Try Again")
            primaryButton.isEnabled = true
            primaryButton.isHidden = isHealthyEnabledState
            secondaryButton.title = String(localized: "Start OneDrive")
            secondaryButton.isHidden = processStatus.isRunning || processStatus.appURL == nil
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
        let guidanceHeight = guidanceLabel.isHidden ? CGFloat(0) : CGFloat(46)
        top -= guidanceHeight
        guidanceLabel.frame = NSRect(x: inset, y: top, width: width, height: guidanceHeight)
        if !errorLabel.isHidden {
            top -= 34
            errorLabel.frame = NSRect(x: inset, y: top, width: width, height: 30)
        }
        secondaryButton.frame = NSRect(x: inset, y: 8, width: width, height: Metrics.buttonHeight)
        let primaryY: CGFloat = secondaryButton.isHidden ? 16 : 48
        primaryButton.frame = NSRect(x: inset, y: primaryY, width: width, height: Metrics.buttonHeight)
        let visibleButtonTop = [primaryButton, secondaryButton]
            .filter { !$0.isHidden }
            .map(\.frame.maxY)
            .max() ?? 8
        if !errorLabel.isHidden {
            errorLabel.frame = NSRect(x: inset, y: visibleButtonTop + 8, width: width, height: 30)
        }
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
        let controls = [candidateStack, guidanceLabel, errorLabel, primaryButton, secondaryButton]
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
