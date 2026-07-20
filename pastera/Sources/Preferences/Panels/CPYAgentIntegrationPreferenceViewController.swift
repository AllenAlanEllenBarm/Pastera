import AppKit
import PasteraAgentProtocol

// The page keeps its fixed three-row rendering and action routing in one controller.
// swiftlint:disable:next type_name type_body_length
final class CPYAgentIntegrationPreferenceViewController: PasteraPreferencePageViewController {
    struct RowSnapshot: Equatable {
        let showsIdleExpiry: Bool
        let showsHardExpiry: Bool
        let showsLastSensitiveUse: Bool
        let primaryAction: VaultAgentPreferencePrimaryAction
        let primaryActionCount: Int
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
    }

    private final class ClientRowView: NSView {
        let client: VaultAgentClientKind
        let actionButton = NSButton()
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
            detailLabel.maximumNumberOfLines = 4

            let labels = NSStackView(views: [titleLabel, stateLabel, detailLabel])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 2
            labels.translatesAutoresizingMaskIntoConstraints = false

            actionButton.bezelStyle = .rounded
            actionButton.controlSize = .small
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

            addSubview(labels)
            addSubview(actionButton)
            labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            NSLayoutConstraint.activate([
                labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                labels.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
                labels.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
                labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),
                actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                heightAnchor.constraint(greaterThanOrEqualToConstant: 88)
            ])
            setAccessibilityIdentifier("agents.\(client.rawValue).row")
        }

        required init?(coder: NSCoder) {
            nil
        }
    }

    private let runtime: VaultAgentPreferenceRuntimeServicing
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
    private var permissionInFlight = false
    private var clientGroup: PasteraPreferenceGroupView?
    private let permissionStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let auditLabel = NSTextField(wrappingLabelWithString: "")
    private let copyPermissionButton = NSButton(title: Text.copy, target: nil, action: nil)
    private let applyReadOnlyButton = NSButton(title: Text.allowReadOnly, target: nil, action: nil)
    private let applySensitiveButton = NSButton(title: Text.allowSensitive, target: nil, action: nil)
    private let removePermissionButton = NSButton(title: Text.remove, target: nil, action: nil)

    init(
        runtime: VaultAgentPreferenceRuntimeServicing = VaultAgentPreferenceRuntimeProvider.runtime,
        confirmSensitivePermission: (() -> Bool)? = nil,
        copyText: @escaping (String) -> Void = { value in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    ) {
        self.runtime = runtime
        self.sensitiveConfirmation = confirmSensitivePermission
        self.copyText = copyText
        super.init(paneID: .agentIntegrations, title: Text.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        clientRows.removeAll()
        super.loadView()
        buildPage()
        refresh()
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

        let firstLine = NSStackView(views: [copyPermissionButton, applyReadOnlyButton])
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
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        copyPermissionButton.target = self
        copyPermissionButton.action = #selector(copyClaudePermission)
        applyReadOnlyButton.target = self
        applyReadOnlyButton.action = #selector(applyClaudeReadOnlyPermission)
        applySensitiveButton.target = self
        applySensitiveButton.action = #selector(applyClaudeSensitivePermission)
        removePermissionButton.target = self
        removePermissionButton.action = #selector(removeClaudePermission)
        [copyPermissionButton, applyReadOnlyButton, applySensitiveButton, removePermissionButton].forEach {
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

    private func refresh() {
        runtime.loadSnapshot { [weak self] result in
            self?.onMain { self?.consume(result) }
        }
    }

    private func consume(_ result: Result<VaultAgentPreferenceSnapshot, Error>) {
        switch result {
        case let .success(snapshot):
            self.snapshot = snapshot
            updateRows(error: nil)
        case let .failure(error):
            updateRows(error: error)
        }
    }

    private func updateRows(error: Error?) {
        for client in VaultAgentClientKind.allCases {
            guard let row = clientRows[client] else { continue }
            let state = snapshot.clients[client] ?? .unavailable(client: client)
            row.stateLabel.stringValue = stateText(state, error: error)
            row.detailLabel.stringValue = detailText(state)
            let busy = inFlightClients.contains(client)
            row.actionButton.title = busy ? Text.busy : actionTitle(state.primaryAction)
            row.actionButton.isEnabled = !busy
            row.actionButton.setAccessibilityLabel(row.actionButton.title)
        }
        updatePermissionControls(error: error)
        updateAudit()
        invalidateContentSize()
    }

    private func updatePermissionControls(error: Error?) {
        let permission = snapshot.claudePermission
        let claudeInstalled = snapshot.clients[.claude]?.installed == true
        copyPermissionButton.isEnabled = claudeInstalled && !permissionInFlight
        applyReadOnlyButton.isEnabled = claudeInstalled && permission.canApplyAutomatically && !permissionInFlight
        applySensitiveButton.isEnabled = claudeInstalled && permission.canApplyAutomatically && !permissionInFlight
        removePermissionButton.isEnabled = permission.canRemoveOwnedRules && !permissionInFlight
        if let error {
            permissionStatusLabel.stringValue = error.localizedDescription
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
        inFlightClients.insert(client)
        updateRows(error: nil)
        runtime.perform(action) { [weak self] result in
            self?.onMain {
                self?.inFlightClients.remove(client)
                self?.consume(result)
            }
        }
    }

    @objc private func copyClaudePermission() {
        requestSnippet(.metadataOnly) { [copyText] snippet in copyText(snippet.serialized) }
    }

    @objc private func applyClaudeReadOnlyPermission() {
        applyClaudePermission(.metadataOnly)
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
        updatePermissionControls(error: nil)
        runtime.claudePermissionSnippet(scope: scope) { [weak self] result in
            self?.onMain {
                self?.permissionInFlight = false
                switch result {
                case let .success(snippet):
                    self?.permissionStatusLabel.stringValue = snippet.allowedTools.joined(separator: ", ")
                    completion(snippet)
                case let .failure(error):
                    self?.updatePermissionControls(error: error)
                }
            }
        }
    }

    private func performPermission(_ action: VaultAgentPreferenceAction) {
        guard !permissionInFlight else { return }
        permissionInFlight = true
        updatePermissionControls(error: nil)
        runtime.perform(action) { [weak self] result in
            self?.onMain {
                self?.permissionInFlight = false
                self?.consume(result)
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
        let idle = state.idleExpiresAt.map(formatter.string) ?? Text.never
        let hard = state.hardExpiresAt.map(formatter.string) ?? Text.never
        let last = state.lastSensitiveUseAt.map(formatter.string) ?? Text.never
        var details = [
            String(format: pasteraPreferenceString("Host: %@"), host),
            String(format: pasteraPreferenceString("Idle: %@ · Hard: %@"), idle, hard),
            String(format: pasteraPreferenceString("Last sensitive use: %@"), last)
        ]
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
            primaryActionCount: 1
        )
    }

    var clientRowCountForTesting: Int { clientRows.count }
    var clientGroupCountForTesting: Int { clientGroup == nil ? 0 : 1 }
    var maximumClientRowWidthForTesting: CGFloat { clientRows.values.map(\.frame.width).max() ?? 0 }
    var primaryActionCenterYOffsetsForTesting: [CGFloat] {
        clientRows.values.map { $0.actionButton.frame.midY - $0.bounds.midY }
    }
    var codexApprovalManagedByHostForTesting: Bool { Text.codexManaged == pasteraPreferenceString("Tool approvals are managed by Codex.") }
    var codexHasPermissionControlForTesting: Bool { false }

    func applyClaudePermissionForTesting(_ scope: VaultAgentHostPermissionScope) {
        applyClaudePermission(scope)
    }
}
#endif
