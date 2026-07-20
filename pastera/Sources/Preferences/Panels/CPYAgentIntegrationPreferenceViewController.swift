import AppKit
import PasteraAgentProtocol

// The page keeps its fixed three-row rendering and action routing in one controller.
// swiftlint:disable file_length
// swiftlint:disable:next type_name type_body_length
final class CPYAgentIntegrationPreferenceViewController: PasteraPreferencePageViewController {
    struct RowSnapshot: Equatable {
        let showsIdleExpiry: Bool
        let showsHardExpiry: Bool
        let showsLastSensitiveUse: Bool
        let primaryAction: VaultAgentPreferencePrimaryAction
        let primaryActionCount: Int
        let showsSecondaryUninstall: Bool
    }

    private enum Text {
        static let title = pasteraPreferenceString("Agent Integrations")
        static let clients = pasteraPreferenceString("Password Vault Clients")
        static let codex = pasteraPreferenceString("Codex")
        static let claude = pasteraPreferenceString("Claude Code")
        static let cli = pasteraPreferenceString("Pastera CLI")
        static let audit = pasteraPreferenceString("Recent Agent Activity")
        static let permissions = pasteraPreferenceString("Claude Tool Approvals")
        static let install = pasteraPreferenceString("Install")
        static let update = pasteraPreferenceString("Update")
        static let authorize = pasteraPreferenceString("Authorize")
        static let reauthorize = pasteraPreferenceString("Reauthorize")
        static let revoke = pasteraPreferenceString("Revoke")
        static let uninstall = pasteraPreferenceString("Uninstall")
        static let previewReadOnly = pasteraPreferenceString("Preview Read-only")
        static let copy = pasteraPreferenceString("Copy Config")
        static let allowReadOnly = pasteraPreferenceString("Allow Read-only")
        static let allowSensitive = pasteraPreferenceString("Allow Sensitive")
        static let remove = pasteraPreferenceString("Remove Rules")
        static let busy = pasteraPreferenceString("Working…")
        static let unavailable = pasteraPreferenceString("Unavailable")
        static let installed = pasteraPreferenceString("Installed")
        static let notInstalled = pasteraPreferenceString("Not Installed")
        static let authorized = pasteraPreferenceString("Authorized")
        static let notAuthorized = pasteraPreferenceString("Not Authorized")
        static let expired = pasteraPreferenceString("Expired")
        static let revoked = pasteraPreferenceString("Revoked")
        static let identityChanged = pasteraPreferenceString("Identity Changed")
        static let never = pasteraPreferenceString("Never")
        static let noActivity = pasteraPreferenceString("No recent agent activity.")
        static let codexManaged = pasteraPreferenceString("Tool approvals are managed by Codex.")
        static let permissionUnavailable = pasteraPreferenceString("Automatic apply is unavailable; copying remains available.")
        static let authorizationLifetime = pasteraPreferenceString("7 idle days · 30 days total")
        static let unattendedRisk = pasteraPreferenceString("Unattended automation can expose secrets to client commands.")
        static let agentScope = pasteraPreferenceString("Metadata, paste, and controlled injection")
        static let cliScope = pasteraPreferenceString("Metadata, paste, copy, and controlled injection")
    }

    private final class ClientRowView: NSView {
        let client: VaultAgentClientKind
        let actionButton = NSButton()
        let uninstallButton = NSButton(title: Text.uninstall, target: nil, action: nil)
        let stateLabel = NSTextField(labelWithString: "")
        let detailLabel = NSTextField(wrappingLabelWithString: "")

        init(client: VaultAgentClientKind, title: String) {
            self.client = client
            super.init(frame: .zero)

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
            stateLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
            stateLabel.textColor = .secondaryLabelColor
            detailLabel.font = .systemFont(ofSize: 10.5)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.maximumNumberOfLines = 7

            let labels = NSStackView(views: [titleLabel, stateLabel, detailLabel])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 2
            labels.translatesAutoresizingMaskIntoConstraints = false

            actionButton.bezelStyle = .rounded
            actionButton.controlSize = .small
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
            uninstallButton.bezelStyle = .roundRect
            uninstallButton.controlSize = .mini
            uninstallButton.translatesAutoresizingMaskIntoConstraints = false
            let buttons = NSStackView(views: [uninstallButton, actionButton])
            buttons.orientation = .horizontal
            buttons.alignment = .centerY
            buttons.spacing = 6
            buttons.translatesAutoresizingMaskIntoConstraints = false

            addSubview(labels)
            addSubview(buttons)
            labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            NSLayoutConstraint.activate([
                labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                labels.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
                labels.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
                labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -12),
                buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
                heightAnchor.constraint(greaterThanOrEqualToConstant: 108)
            ])
            setAccessibilityIdentifier("agents.\(client.rawValue).row")
        }

        required init?(coder: NSCoder) {
            nil
        }
    }

    private let runtime: VaultAgentPreferenceRuntimeServicing
    private let notificationCenter: NotificationCenter
    private let sensitiveConfirmation: (() -> Bool)?
    private let copyText: (String) -> Void
    private var snapshot = VaultAgentPreferenceSnapshot(
        clients: Dictionary(uniqueKeysWithValues: VaultAgentClientKind.allCases.map {
            ($0, VaultAgentPreferenceClientSnapshot.unavailable(client: $0))
        }),
        claudePermission: .unavailable,
        audit: []
    )
    private var clientRows = [VaultAgentClientKind: ClientRowView]()
    private var inFlightClients = Set<VaultAgentClientKind>()
    private var clientErrors = [VaultAgentClientKind: Error]()
    private var permissionInFlight = false
    private var permissionError: Error?
    private var pageError: Error?
    private var metadataPreview: VaultAgentPermissionSnippet?
    private var stateObserver: NSObjectProtocol?
    private var isPageVisible = false
    private var snapshotRefreshInFlight = false
    private var snapshotRefreshDirty = true
    private var clientGroup: PasteraPreferenceGroupView?
    private let permissionStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let previewReadOnlyButton = NSButton(title: Text.previewReadOnly, target: nil, action: nil)
    private let auditLabel = NSTextField(wrappingLabelWithString: "")
    private let copyPermissionButton = NSButton(title: Text.copy, target: nil, action: nil)
    private let applyReadOnlyButton = NSButton(title: Text.allowReadOnly, target: nil, action: nil)
    private let applySensitiveButton = NSButton(title: Text.allowSensitive, target: nil, action: nil)
    private let removePermissionButton = NSButton(title: Text.remove, target: nil, action: nil)

    init(
        runtime: VaultAgentPreferenceRuntimeServicing = VaultAgentPreferenceRuntimeProvider.runtime,
        confirmSensitivePermission: (() -> Bool)? = nil,
        notificationCenter: NotificationCenter = .default,
        copyText: @escaping (String) -> Void = { value in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    ) {
        self.runtime = runtime
        self.notificationCenter = notificationCenter
        self.sensitiveConfirmation = confirmSensitivePermission
        self.copyText = copyText
        super.init(paneID: .agentIntegrations, title: Text.title)
        stateObserver = notificationCenter.addObserver(
            forName: .vaultAgentPreferenceStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.snapshotStateDidChange()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let stateObserver { notificationCenter.removeObserver(stateObserver) }
    }

    override func loadView() {
        clientRows.removeAll()
        super.loadView()
        buildPage()
        requestSnapshotRefresh(allowWhileHidden: true)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isPageVisible = true
        if !snapshotRefreshInFlight {
            snapshotRefreshDirty = true
        }
        requestSnapshotRefresh()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        isPageVisible = false
    }

    private func buildPage() {
        let clients = PasteraPreferenceGroupView(
            title: Text.clients,
            symbolName: "terminal",
            accentColor: .systemBlue
        )
        clientGroup = clients
        for client in VaultAgentClientKind.allCases {
            let row = ClientRowView(client: client, title: title(for: client))
            row.actionButton.tag = tag(for: client)
            row.actionButton.target = self
            row.actionButton.action = #selector(primaryActionTapped(_:))
            row.uninstallButton.tag = tag(for: client)
            row.uninstallButton.target = self
            row.uninstallButton.action = #selector(uninstallActionTapped(_:))
            clientRows[client] = row
            clients.addContent(row)
            registerAnchor("agents.\(client.rawValue)", view: row)
        }
        clients.addContent(makePermissionControls())
        addGroup(clients, anchorID: "agents.authorization")

        let auditGroup = PasteraPreferenceGroupView(
            title: Text.audit,
            symbolName: "clock",
            accentColor: .systemPurple
        )
        auditLabel.font = .systemFont(ofSize: 11.5)
        auditLabel.textColor = .secondaryLabelColor
        auditLabel.maximumNumberOfLines = 5
        let auditContainer = inset(auditLabel)
        auditGroup.addContent(auditContainer)
        addGroup(auditGroup)
    }

    private func makePermissionControls() -> NSView {
        permissionStatusLabel.font = .systemFont(ofSize: 11.5)
        permissionStatusLabel.textColor = .secondaryLabelColor
        permissionStatusLabel.maximumNumberOfLines = 3

        let firstLine = NSStackView(views: [
            previewReadOnlyButton,
            copyPermissionButton,
            applyReadOnlyButton
        ])
        let secondLine = NSStackView(views: [applySensitiveButton, removePermissionButton])
        for line in [firstLine, secondLine] {
            line.orientation = .horizontal
            line.alignment = .centerY
            line.spacing = 8
        }
        let buttons = NSStackView(views: [firstLine, secondLine])
        buttons.orientation = .vertical
        buttons.alignment = .trailing
        buttons.spacing = 6
        let labels = NSStackView(views: [
            NSTextField(labelWithString: Text.permissions),
            permissionStatusLabel
        ])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.arrangedSubviews.first?.setAccessibilityIdentifier("agents.claude.permissions.title")

        let row = NSStackView(views: [labels, buttons])
        row.orientation = .vertical
        row.alignment = .leading
        row.distribution = .fill
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        labels.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor).isActive = true
        buttons.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor).isActive = true
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true

        previewReadOnlyButton.target = self
        previewReadOnlyButton.action = #selector(previewClaudeReadOnlyPermission)
        copyPermissionButton.target = self
        copyPermissionButton.action = #selector(copyClaudePermission)
        applyReadOnlyButton.target = self
        applyReadOnlyButton.action = #selector(applyClaudeReadOnlyPermission)
        applySensitiveButton.target = self
        applySensitiveButton.action = #selector(applyClaudeSensitivePermission)
        removePermissionButton.target = self
        removePermissionButton.action = #selector(removeClaudePermission)
        [
            previewReadOnlyButton,
            copyPermissionButton,
            applyReadOnlyButton,
            applySensitiveButton,
            removePermissionButton
        ].forEach {
            $0.controlSize = .small
            $0.bezelStyle = .rounded
        }
        return row
    }

    private func inset(_ content: NSView) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        return container
    }

    private func snapshotStateDidChange() {
        snapshotRefreshDirty = true
        requestSnapshotRefresh()
    }

    private func requestSnapshotRefresh(allowWhileHidden: Bool = false) {
        guard snapshotRefreshDirty,
              !snapshotRefreshInFlight,
              isPageVisible || allowWhileHidden else { return }
        snapshotRefreshDirty = false
        snapshotRefreshInFlight = true
        runtime.loadSnapshot { [weak self] result in
            self?.onMain {
                guard let self else { return }
                self.snapshotRefreshInFlight = false
                self.consume(result)
                if self.isPageVisible, self.snapshotRefreshDirty {
                    self.requestSnapshotRefresh()
                }
            }
        }
    }

    private func consume(_ result: Result<VaultAgentPreferenceSnapshot, Error>) {
        switch result {
        case let .success(snapshot):
            self.snapshot = snapshot
            pageError = nil
            updateRows()
        case let .failure(error):
            pageError = error
            updateRows()
        }
    }

    private func updateRows() {
        for client in VaultAgentClientKind.allCases {
            guard let row = clientRows[client] else { continue }
            let state = snapshot.clients[client] ?? .unavailable(client: client)
            row.stateLabel.stringValue = stateText(state, error: clientErrors[client])
            row.detailLabel.stringValue = detailText(state)
            let busy = inFlightClients.contains(client)
            row.actionButton.title = busy ? Text.busy : actionTitle(state.primaryAction)
            row.actionButton.isEnabled = !busy
            row.actionButton.setAccessibilityLabel(row.actionButton.title)
            row.uninstallButton.isHidden = !state.installed ||
                state.authorization == .authorized ||
                state.primaryAction == .uninstall
            row.uninstallButton.isEnabled = !busy
        }
        updatePermissionControls()
        updateAudit()
        invalidateContentSize()
    }

    private func updatePermissionControls() {
        let permission = snapshot.claudePermission
        let claudeInstalled = snapshot.clients[.claude]?.installed == true
        let hasMetadataPreview = metadataPreview?.exactlyMatches(scope: .metadataOnly) == true
        previewReadOnlyButton.isEnabled = claudeInstalled && !permissionInFlight
        copyPermissionButton.isEnabled = claudeInstalled && hasMetadataPreview && !permissionInFlight
        applyReadOnlyButton.isEnabled = claudeInstalled &&
            hasMetadataPreview && permission.canApplyAutomatically && !permissionInFlight
        applySensitiveButton.isEnabled = claudeInstalled && permission.canApplyAutomatically && !permissionInFlight
        removePermissionButton.isEnabled = permission.canRemoveOwnedRules && !permissionInFlight
        if let error = permissionError {
            permissionStatusLabel.stringValue = error.localizedDescription
        } else if let metadataPreview {
            permissionStatusLabel.stringValue = metadataPreview.allowedTools.joined(separator: ", ")
        } else if permission.canApplyAutomatically {
            permissionStatusLabel.stringValue = permission.ownedRules.isEmpty
                ? pasteraPreferenceString("No Pastera-owned approval rules.")
                : String(
                    format: pasteraPreferenceString("%d Pastera-owned approval rules."),
                    permission.ownedRules.count
                )
        } else {
            permissionStatusLabel.stringValue = Text.permissionUnavailable
        }
    }

    private func updateAudit() {
        if let pageError {
            auditLabel.stringValue = String(
                format: pasteraPreferenceString("Unable to refresh: %@"),
                pageError.localizedDescription
            )
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let values = snapshot.audit.prefix(5).map {
            let result = $0.result?.rawValue ?? "ok"
            return "\(formatter.string(from: $0.timestamp)) · \($0.action.rawValue) · \(result)"
        }
        auditLabel.stringValue = values.isEmpty ? Text.noActivity : values.joined(separator: "\n")
    }

    @objc private func primaryActionTapped(_ sender: NSButton) {
        guard let client = client(for: sender.tag),
              let state = snapshot.clients[client],
              !inFlightClients.contains(client) else { return }
        let action: VaultAgentPreferenceAction
        switch state.primaryAction {
        case .install, .update: action = .install(client)
        case .authorize, .reauthorize: action = .authorize(client)
        case .revoke: action = .revoke(client)
        case .uninstall: action = .uninstall(client)
        }
        performClientAction(action, client: client)
    }

    @objc private func uninstallActionTapped(_ sender: NSButton) {
        guard let client = client(for: sender.tag),
              snapshot.clients[client]?.installed == true,
              snapshot.clients[client]?.authorization != .authorized,
              !inFlightClients.contains(client) else { return }
        performClientAction(.uninstall(client), client: client)
    }

    private func performClientAction(
        _ action: VaultAgentPreferenceAction,
        client: VaultAgentClientKind
    ) {
        inFlightClients.insert(client)
        clientErrors.removeValue(forKey: client)
        updateRows()
        runtime.perform(action) { [weak self] result in
            self?.onMain {
                guard let self else { return }
                self.inFlightClients.remove(client)
                switch result {
                case let .success(snapshot):
                    self.snapshot = snapshot
                    self.clientErrors.removeValue(forKey: client)
                    if client == .claude, case .uninstall = action { self.metadataPreview = nil }
                case let .failure(error):
                    self.clientErrors[client] = error
                }
                self.updateRows()
            }
        }
    }

    @objc private func previewClaudeReadOnlyPermission() {
        permissionError = nil
        requestSnippet(.metadataOnly) { [weak self] snippet in
            guard let self else { return }
            guard snippet.exactlyMatches(scope: .metadataOnly) else {
                permissionError = VaultAgentErrorCode.invalidRequest
                metadataPreview = nil
                updatePermissionControls()
                return
            }
            metadataPreview = snippet
            updatePermissionControls()
        }
    }

    @objc private func copyClaudePermission() {
        guard let metadataPreview else { return }
        copyText(metadataPreview.serialized)
    }

    @objc private func applyClaudeReadOnlyPermission() {
        guard metadataPreview?.exactlyMatches(scope: .metadataOnly) == true else { return }
        performPermission(.applyClaudePermission(.metadataOnly))
    }

    @objc private func applyClaudeSensitivePermission() {
        applyClaudePermission(.allCurrentPasteraTools)
    }

    @objc private func removeClaudePermission() {
        performPermission(.removeClaudePermission)
    }

    private func applyClaudePermission(_ scope: VaultAgentHostPermissionScope) {
        requestSnippet(scope) { [weak self] snippet in
            guard let self else { return }
            if scope == .allCurrentPasteraTools, !confirmSensitive(snippet) { return }
            performPermission(.applyClaudePermission(scope))
        }
    }

    private func requestSnippet(
        _ scope: VaultAgentHostPermissionScope,
        completion: @escaping (VaultAgentPermissionSnippet) -> Void
    ) {
        guard !permissionInFlight else { return }
        permissionInFlight = true
        permissionError = nil
        updatePermissionControls()
        runtime.claudePermissionSnippet(scope: scope) { [weak self] result in
            self?.onMain {
                self?.permissionInFlight = false
                switch result {
                case let .success(snippet):
                    self?.permissionError = nil
                    self?.updatePermissionControls()
                    completion(snippet)
                case let .failure(error):
                    self?.permissionError = error
                    self?.updatePermissionControls()
                }
            }
        }
    }

    private func performPermission(_ action: VaultAgentPreferenceAction) {
        guard !permissionInFlight else { return }
        permissionInFlight = true
        permissionError = nil
        updatePermissionControls()
        runtime.perform(action) { [weak self] result in
            self?.onMain {
                guard let self else { return }
                self.permissionInFlight = false
                switch result {
                case let .success(snapshot):
                    self.snapshot = snapshot
                    self.permissionError = nil
                case let .failure(error):
                    self.permissionError = error
                }
                self.updateRows()
            }
        }
    }

    private func confirmSensitive(_ snippet: VaultAgentPermissionSnippet) -> Bool {
        if let sensitiveConfirmation { return sensitiveConfirmation() }
        let alert = NSAlert()
        alert.messageText = pasteraPreferenceString("Allow sensitive password actions?")
        alert.informativeText = String(
            format: pasteraPreferenceString("Claude will be allowed to call these tools without another tool prompt: %@"),
            snippet.allowedTools.joined(separator: ", ")
        )
        alert.addButton(withTitle: pasteraPreferenceString("Allow"))
        alert.addButton(withTitle: pasteraPreferenceString("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func stateText(
        _ state: VaultAgentPreferenceClientSnapshot,
        error: Error?
    ) -> String {
        if let error { return error.localizedDescription }
        let install = state.installed ? Text.installed : Text.notInstalled
        let authorization: String
        switch state.authorization {
        case .missing: authorization = Text.notAuthorized
        case .authorized: authorization = Text.authorized
        case .expired: authorization = Text.expired
        case .revoked: authorization = Text.revoked
        case .identityChanged: authorization = Text.identityChanged
        case .unavailable: authorization = Text.unavailable
        }
        return "\(install) · \(authorization)"
    }

    private func detailText(_ state: VaultAgentPreferenceClientSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let host = state.hostPathSummary ?? Text.unavailable
        let last = state.lastSensitiveUseAt.map(formatter.string) ?? Text.never
        var details = [String(format: pasteraPreferenceString("Host: %@"), host)]
        if let hint = state.installationHint {
            details.append(String(format: pasteraPreferenceString("PATH: %@"), hint))
        }
        if state.authorization == .authorized {
            let idle = state.idleExpiresAt.map(formatter.string) ?? Text.never
            let hard = state.hardExpiresAt.map(formatter.string) ?? Text.never
            details.append(String(format: pasteraPreferenceString("Idle: %@ · Hard: %@"), idle, hard))
            details.append(String(format: pasteraPreferenceString("Last sensitive use: %@"), last))
        } else if state.authorization != .unavailable {
            details.append(state.client == .cli ? Text.cliScope : Text.agentScope)
            details.append(Text.authorizationLifetime)
            details.append(Text.unattendedRisk)
        }
        if state.client == .codex { details.append(Text.codexManaged) }
        return details.joined(separator: "\n")
    }

    private func actionTitle(_ action: VaultAgentPreferencePrimaryAction) -> String {
        switch action {
        case .install: Text.install
        case .update: Text.update
        case .authorize: Text.authorize
        case .reauthorize: Text.reauthorize
        case .revoke: Text.revoke
        case .uninstall: Text.uninstall
        }
    }

    private func title(for client: VaultAgentClientKind) -> String {
        switch client {
        case .codex: Text.codex
        case .claude: Text.claude
        case .cli: Text.cli
        }
    }

    private func tag(for client: VaultAgentClientKind) -> Int {
        switch client {
        case .codex: 0
        case .claude: 1
        case .cli: 2
        }
    }

    private func client(for tag: Int) -> VaultAgentClientKind? {
        switch tag {
        case 0: .codex
        case 1: .claude
        case 2: .cli
        default: nil
        }
    }

    private func onMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread { operation() } else { DispatchQueue.main.async(execute: operation) }
    }
}

#if DEBUG
extension CPYAgentIntegrationPreferenceViewController {
    func rowSnapshotForTesting(_ client: VaultAgentClientKind) -> RowSnapshot? {
        guard clientRows[client] != nil else { return nil }
        let state = snapshot.clients[client] ?? .unavailable(client: client)
        return .init(
            showsIdleExpiry: state.idleExpiresAt != nil,
            showsHardExpiry: state.hardExpiresAt != nil,
            showsLastSensitiveUse: state.lastSensitiveUseAt != nil,
            primaryAction: state.primaryAction,
            primaryActionCount: 1,
            showsSecondaryUninstall: state.installed &&
                state.authorization != .authorized &&
                state.primaryAction != .uninstall
        )
    }

    var clientRowCountForTesting: Int { clientRows.count }
    var clientGroupCountForTesting: Int { clientGroup == nil ? 0 : 1 }
    var maximumClientRowWidthForTesting: CGFloat { clientRows.values.map(\.frame.width).max() ?? 0 }
    var primaryActionCenterYOffsetsForTesting: [CGFloat] {
        clientRows.values.map { row in
            row.actionButton.convert(row.actionButton.bounds, to: row).midY - row.bounds.midY
        }
    }

    func permissionControlsFitForTesting(width: CGFloat) -> Bool {
        view.layoutSubtreeIfNeeded()
        return [
            previewReadOnlyButton,
            copyPermissionButton,
            applyReadOnlyButton,
            applySensitiveButton,
            removePermissionButton
        ].allSatisfy { button in
            let frame = button.convert(button.bounds, to: view)
            return frame.minX >= 0 && frame.maxX <= width
        }
    }

    var codexApprovalManagedByHostForTesting: Bool { Text.codexManaged == pasteraPreferenceString("Tool approvals are managed by Codex.") }
    var codexHasPermissionControlForTesting: Bool { false }
    var metadataApplyEnabledForTesting: Bool { applyReadOnlyButton.isEnabled }
    var copyPermissionEnabledForTesting: Bool { copyPermissionButton.isEnabled }
    var permissionPreviewForTesting: String { metadataPreview?.allowedTools.joined(separator: ", ") ?? "" }
    var permissionErrorForTesting: String { permissionError?.localizedDescription ?? "" }
    var pageErrorForTesting: String { pageError?.localizedDescription ?? "" }

    func clientErrorForTesting(_ client: VaultAgentClientKind) -> String {
        clientErrors[client]?.localizedDescription ?? ""
    }

    func clientDetailForTesting(_ client: VaultAgentClientKind) -> String {
        clientRows[client]?.detailLabel.stringValue ?? ""
    }

    func triggerPrimaryActionForTesting(_ client: VaultAgentClientKind) {
        guard let button = clientRows[client]?.actionButton else { return }
        primaryActionTapped(button)
    }

    func triggerSecondaryUninstallForTesting(_ client: VaultAgentClientKind) {
        guard let button = clientRows[client]?.uninstallButton else { return }
        uninstallActionTapped(button)
    }

    func previewClaudeMetadataForTesting() {
        previewClaudeReadOnlyPermission()
    }

    func copyClaudePermissionForTesting() {
        copyClaudePermission()
    }

    func applyClaudeMetadataPermissionForTesting() {
        applyClaudeReadOnlyPermission()
    }

    func applyClaudePermissionForTesting(_ scope: VaultAgentHostPermissionScope) {
        applyClaudePermission(scope)
    }
}
#endif
