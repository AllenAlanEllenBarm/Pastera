import AppKit
// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
final class PromptOptimizationPreferenceSection: NSStackView {
    private let settingsStore: any PromptOptimizationSettingsStoring
    private let apiKeyStore: any PromptOptimizationAPIKeyStoring
    nonisolated(unsafe) private let optimizationService: any PromptOptimizationServicing
    private let endpointPolicy: PromptOptimizationEndpointPolicy
    private let confirmationRunner: (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult

    private let providerPopup = NSPopUpButton()
    private let availabilityLabel = NSTextField(wrappingLabelWithString: "")
    private let remoteStack = NSStackView()
    private let profilePopup = NSPopUpButton()
    private let profileNameField = NSTextField()
    private let addProfileButton = NSButton()
    private let deleteProfileButton = NSButton()
    private let presetPopup = NSPopUpButton()
    private let applyPresetDefaultsButton = NSButton()
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let apiKeyStatusLabel = NSTextField(labelWithString: "")
    private let allowsInsecureHTTPSwitch = NSSwitch()
    private let validationLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton()
    private let saveAPIKeyButton = NSButton()
    private let removeAPIKeyButton = NSButton()
    private let testButton = NSButton()
    private let progressIndicator = NSProgressIndicator()

    private var profileDraft: PromptOptimizationRemoteProfileDraft
    private var connectionTask: Task<Void, Never>?
    private var progressWorkItem: DispatchWorkItem?
    private weak var observedWindow: NSWindow?
    private var windowWillCloseObserver: NSObjectProtocol?
    private var isTestingConnection = false
    var onContentSizeChange: (() -> Void)?

    init(
        settingsStore: any PromptOptimizationSettingsStoring,
        apiKeyStore: any PromptOptimizationAPIKeyStoring,
        optimizationService: any PromptOptimizationServicing,
        endpointPolicy: PromptOptimizationEndpointPolicy = PromptOptimizationEndpointPolicy(),
        confirmationRunner: @escaping (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult = {
            PasteraConfirmationController.runModal(options: $0, sourceWindow: $1)
        }
    ) {
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.optimizationService = optimizationService
        self.endpointPolicy = endpointPolicy
        self.confirmationRunner = confirmationRunner
        self.profileDraft = PromptOptimizationRemoteProfileDraft(settings: settingsStore.load())
        super.init(frame: .zero)
        configureCard()
        loadSettingsIntoControls()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let windowWillCloseObserver {
            NotificationCenter.default.removeObserver(windowWillCloseObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else {
            observeWindowWillClose()
            return
        }
        removeWindowWillCloseObserver()
        cancelConnectionTest()
    }

    private func observeWindowWillClose() {
        guard let window else { return }
        guard observedWindow !== window else { return }
        removeWindowWillCloseObserver()
        observedWindow = window
        windowWillCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelConnectionTest()
            }
        }
    }

    private func removeWindowWillCloseObserver() {
        if let windowWillCloseObserver {
            NotificationCenter.default.removeObserver(windowWillCloseObserver)
        }
        windowWillCloseObserver = nil
        observedWindow = nil
    }

    private func cancelConnectionTest() {
        progressWorkItem?.cancel()
        progressWorkItem = nil
        connectionTask?.cancel()
        connectionTask = nil
        progressIndicator.stopAnimation(nil)
        isTestingConnection = false
        testButton.isEnabled = true
    }

    private func configureCard() {
        orientation = .vertical
        alignment = .leading
        spacing = 12
        edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.34).cgColor
        layer?.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor

        let header = makeHeader()
        addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: widthAnchor, constant: -32).isActive = true

        configureProviderControls()
        let providerRow = makeLabeledControl(
            label: promptPreferenceString("Processing", "处理方式"),
            control: providerPopup
        )
        addArrangedSubview(providerRow)
        providerRow.widthAnchor.constraint(equalTo: widthAnchor, constant: -32).isActive = true

        availabilityLabel.font = .systemFont(ofSize: 12)
        availabilityLabel.textColor = .secondaryLabelColor
        availabilityLabel.maximumNumberOfLines = 2
        addArrangedSubview(availabilityLabel)
        availabilityLabel.widthAnchor.constraint(equalTo: widthAnchor, constant: -32).isActive = true

        configureRemoteControls()
        addArrangedSubview(remoteStack)
        remoteStack.widthAnchor.constraint(equalTo: widthAnchor, constant: -32).isActive = true

        validationLabel.font = .systemFont(ofSize: 12)
        validationLabel.textColor = .systemRed
        validationLabel.isHidden = true
        addArrangedSubview(validationLabel)

        let actions = NSStackView(views: [saveButton, progressIndicator, testButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        addArrangedSubview(actions)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalTo: widthAnchor, constant: -32).isActive = true
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView(image: NSImage(
            systemSymbolName: "wand.and.stars",
            accessibilityDescription: promptPreferenceString("Prompt Optimization", "提示词优化")
        ) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let title = NSTextField(labelWithString: promptPreferenceString("Prompt Optimization", "提示词优化"))
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: promptPreferenceString(
            "Improve history drafts locally for free, or use your own compatible model.",
            "默认在本机免费处理，也可使用你自己的兼容模型。"
        ))
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let header = NSStackView(views: [icon, labels])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return header
    }

    private func configureProviderControls() {
        providerPopup.addItem(withTitle: promptPreferenceString("Automatic — Free", "免费自动"))
        providerPopup.lastItem?.representedObject = PromptOptimizationProviderSelection.automaticFree.rawValue
        providerPopup.addItem(withTitle: promptPreferenceString(
            "OpenAI-compatible — Custom provider",
            "OpenAI 兼容 — 自备服务"
        ))
        providerPopup.lastItem?.representedObject = PromptOptimizationProviderSelection.openAICompatible.rawValue
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))
        providerPopup.setAccessibilityLabel(promptPreferenceString("Processing provider", "提示词处理方式"))

        saveButton.title = promptPreferenceString("Save Settings", "保存设置")
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveSettings(_:))

        testButton.title = promptPreferenceString("Test Connection", "测试连接")
        testButton.bezelStyle = .rounded
        testButton.target = self
        testButton.action = #selector(testConnection(_:))

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
    }

    private func configureRemoteControls() {
        remoteStack.orientation = .vertical
        remoteStack.alignment = .leading
        remoteStack.spacing = 10

        profilePopup.target = self
        profilePopup.action = #selector(profileChanged(_:))
        profilePopup.setAccessibilityLabel(promptPreferenceString("Model profile", "模型配置"))
        profilePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addProfileButton.title = promptPreferenceString("Add", "添加")
        addProfileButton.target = self
        addProfileButton.action = #selector(addProfile(_:))
        addProfileButton.setAccessibilityLabel(promptPreferenceString("Add model profile", "添加模型配置"))
        deleteProfileButton.title = promptPreferenceString("Delete", "删除")
        deleteProfileButton.target = self
        deleteProfileButton.action = #selector(deleteProfile(_:))
        deleteProfileButton.setAccessibilityLabel(promptPreferenceString("Delete model profile", "删除模型配置"))
        let profileActions = NSStackView(views: [profilePopup, addProfileButton, deleteProfileButton])
        profileActions.orientation = .horizontal
        profileActions.alignment = .centerY
        profileActions.spacing = 8
        remoteStack.addArrangedSubview(makeLabeledControl(
            label: promptPreferenceString("Model profile", "模型配置"),
            control: profileActions
        ))

        profileNameField.setAccessibilityLabel(promptPreferenceString("Profile name", "配置名称"))
        remoteStack.addArrangedSubview(makeLabeledControl(
            label: promptPreferenceString("Profile name", "配置名称"),
            control: profileNameField
        ))

        OpenAICompatiblePreset.allCases.forEach { preset in
            presetPopup.addItem(withTitle: preset.displayName)
            presetPopup.lastItem?.representedObject = preset.rawValue
        }
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        presetPopup.setAccessibilityLabel(promptPreferenceString("Provider preset", "服务预设"))
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        applyPresetDefaultsButton.title = promptPreferenceString("Apply Preset Defaults", "应用预设默认值")
        applyPresetDefaultsButton.target = self
        applyPresetDefaultsButton.action = #selector(applyPresetDefaults(_:))
        applyPresetDefaultsButton.setAccessibilityLabel(promptPreferenceString(
            "Apply preset defaults",
            "应用预设默认值"
        ))
        let presetActions = NSStackView(views: [presetPopup, applyPresetDefaultsButton])
        presetActions.orientation = .horizontal
        presetActions.alignment = .centerY
        presetActions.spacing = 8
        remoteStack.addArrangedSubview(makeLabeledControl(
            label: promptPreferenceString("Provider preset", "服务预设"),
            control: presetActions
        ))

        baseURLField.placeholderString = "https://api.example.com/v1"
        baseURLField.setAccessibilityLabel(promptPreferenceString("Compatible API base URL", "兼容 API 基础地址"))
        remoteStack.addArrangedSubview(makeLabeledControl(
            label: promptPreferenceString("Base URL", "基础地址"),
            control: baseURLField
        ))

        modelField.placeholderString = promptPreferenceString("Required, for example gpt-4.1-mini", "必填，例如 gpt-4.1-mini")
        modelField.setAccessibilityLabel(promptPreferenceString("Model", "模型"))
        remoteStack.addArrangedSubview(makeLabeledControl(
            label: promptPreferenceString("Model", "模型"),
            control: modelField
        ))

        configureAPIKeyControls()
        let credentialStack = NSStackView()
        credentialStack.orientation = .vertical
        credentialStack.alignment = .leading
        credentialStack.spacing = 6
        credentialStack.addArrangedSubview(apiKeyField)
        let credentialActions = NSStackView(views: [saveAPIKeyButton, removeAPIKeyButton, apiKeyStatusLabel])
        credentialActions.orientation = .horizontal
        credentialActions.alignment = .centerY
        credentialActions.spacing = 8
        credentialStack.addArrangedSubview(credentialActions)
        remoteStack.addArrangedSubview(makeLabeledControl(
            label: promptPreferenceString("API Key — stored in Keychain", "API Key — 存储于钥匙串"),
            control: credentialStack
        ))

        allowsInsecureHTTPSwitch.target = self
        allowsInsecureHTTPSwitch.action = #selector(insecureHTTPChanged(_:))
        let insecureRow = NSStackView(views: [allowsInsecureHTTPSwitch, NSTextField(wrappingLabelWithString: promptPreferenceString(
            "Allow non-loopback HTTP. Prompt text and credentials may be exposed.",
            "允许非回环 HTTP；提示词和凭据可能被暴露。"
        ))])
        insecureRow.orientation = .horizontal
        insecureRow.alignment = .top
        insecureRow.spacing = 8
        remoteStack.addArrangedSubview(insecureRow)

        let testNotice = NSTextField(wrappingLabelWithString: promptPreferenceString(
            "Connection testing sends only fixed probe text and may incur provider charges.",
            "连接测试只发送固定探针文本，但仍可能产生服务费用。"
        ))
        testNotice.font = .systemFont(ofSize: 11)
        testNotice.textColor = .secondaryLabelColor
        testNotice.maximumNumberOfLines = 2
        remoteStack.addArrangedSubview(testNotice)

        remoteStack.arrangedSubviews.forEach {
            $0.widthAnchor.constraint(equalTo: remoteStack.widthAnchor).isActive = true
        }
    }

    private func configureAPIKeyControls() {
        apiKeyField.placeholderString = promptPreferenceString(
            "Enter a new key; the saved value is never shown",
            "输入新密钥；已保存值不会显示"
        )
        apiKeyField.setAccessibilityLabel(promptPreferenceString("API Key", "API Key"))
        saveAPIKeyButton.title = promptPreferenceString("Save Key", "保存密钥")
        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey(_:))
        removeAPIKeyButton.title = promptPreferenceString("Remove", "移除")
        removeAPIKeyButton.target = self
        removeAPIKeyButton.action = #selector(removeAPIKey(_:))
        apiKeyStatusLabel.font = .systemFont(ofSize: 11)
        apiKeyStatusLabel.textColor = .secondaryLabelColor
    }

    private func makeLabeledControl(label: String, control: NSView) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12, weight: .medium)
        let stack = NSStackView(views: [labelView, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func loadSettingsIntoControls() {
        selectProvider(profileDraft.settings.provider)
        loadSelectedProfileIntoControls()
        refreshProviderVisibility()
        if migrateLegacyAPIKeyIfNeeded() {
            refreshCredentialStatus()
        }
    }

    private func loadSelectedProfileIntoControls(clearsAPIKey: Bool = true) {
        refreshProfilePopup()
        guard let profile = profileDraft.selectedProfile else { return }
        profileNameField.stringValue = profile.displayName
        selectPreset(profile.preset)
        baseURLField.stringValue = profile.baseURL
        modelField.stringValue = profile.model
        allowsInsecureHTTPSwitch.state = profile.allowsInsecureHTTP ? .on : .off
        if clearsAPIKey {
            apiKeyField.stringValue = ""
        }
        refreshCredentialStatus()
        onContentSizeChange?()
    }

    private func refreshProfilePopup() {
        profilePopup.removeAllItems()
        for profile in profileDraft.settings.remoteProfiles {
            profilePopup.addItem(withTitle: profile.displayName)
            profilePopup.lastItem?.representedObject = profile.id.uuidString
        }
        if let selectedIndex = profilePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == profileDraft.selectedProfileID.uuidString
        }) {
            profilePopup.selectItem(at: selectedIndex)
        }
    }

    private func stageCurrentControls() {
        if let provider = selectedProvider {
            profileDraft.setProvider(provider)
        }
        profileDraft.updateSelected(
            displayName: profileNameField.stringValue,
            preset: selectedPreset ?? profileDraft.selectedProfile?.preset ?? .custom,
            baseURL: baseURLField.stringValue,
            model: modelField.stringValue,
            allowsInsecureHTTP: allowsInsecureHTTPSwitch.state == .on
        )
    }

    private func switchToProfile(id profileID: UUID) {
        stageCurrentControls()
        profileDraft.selectProfile(id: profileID)
        clearProfileTransientState()
        loadSelectedProfileIntoControls()
    }

    @discardableResult
    private func addProfile(preset: OpenAICompatiblePreset, id: UUID) -> UUID {
        stageCurrentControls()
        let profileID = profileDraft.addProfile(preset: preset, id: id)
        clearProfileTransientState()
        loadSelectedProfileIntoControls()
        return profileID
    }

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        clearMessages()
        refreshProviderVisibility()
    }

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        guard let rawID = sender.selectedItem?.representedObject as? String,
              let profileID = UUID(uuidString: rawID) else { return }
        switchToProfile(id: profileID)
    }

    @objc private func addProfile(_ sender: NSButton) {
        _ = addProfile(preset: .custom, id: UUID())
    }

    @objc private func deleteProfile(_ sender: NSButton) {
        let confirmation = confirmationRunner(
            PasteraConfirmationOptions(
                title: promptPreferenceString("Delete this model profile?", "删除此模型配置？"),
                message: promptPreferenceString(
                    "Its saved API Key will also be removed from Keychain.",
                    "其保存的 API Key 也会从钥匙串中移除。"
                ),
                confirmTitle: promptPreferenceString("Delete", "删除"),
                cancelTitle: promptPreferenceString("Cancel", "取消"),
                symbolName: "trash"
            ),
            window
        )
        deleteSelectedProfile(confirmation: confirmation)
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        clearMessages()
    }

    @objc private func applyPresetDefaults(_ sender: NSButton) {
        stageCurrentControls()
        profileDraft.applyPresetDefaults()
        clearMessages()
        loadSelectedProfileIntoControls(clearsAPIKey: false)
    }

    @objc private func insecureHTTPChanged(_ sender: NSSwitch) {
        clearMessages()
    }

    @objc private func saveSettings(_ sender: NSButton) {
        guard persistSettings(), savePendingAPIKeyIfNeeded() else { return }
        setStatus(promptPreferenceString("Prompt optimization settings saved.", "提示词优化设置已保存。"), announces: true)
    }

    @objc private func saveAPIKey(_ sender: NSButton) {
        _ = saveAPIKeyFromControls()
    }

    private func saveAPIKeyFromControls() -> Bool {
        clearMessages()
        guard profileDraft.isPersisted(profileDraft.selectedProfileID) else {
            setError(promptPreferenceString(
                "Save Settings before saving a key for this profile.",
                "请先保存设置，再为此配置保存密钥。"
            ))
            return false
        }
        let value = apiKeyField.stringValue
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showValidation(promptPreferenceString("Enter an API Key before saving.", "请输入 API Key 后再保存。"))
            return false
        }
        if savePendingAPIKeyIfNeeded() {
            setStatus(promptPreferenceString("API Key saved securely.", "API Key 已安全保存。"), announces: true)
            return true
        }
        return false
    }

    @objc private func removeAPIKey(_ sender: NSButton) {
        let result = confirmationRunner(
            PasteraConfirmationOptions(
                title: promptPreferenceString("Remove saved API Key?", "移除已保存的 API Key？"),
                message: promptPreferenceString(
                    "Remote optimization may stop working until a new key is saved.",
                    "保存新密钥前，远端提示词优化可能无法使用。"
                ),
                confirmTitle: promptPreferenceString("Remove", "移除"),
                cancelTitle: promptPreferenceString("Cancel", "取消"),
                symbolName: "lock.shield"
            ),
            window
        )
        guard result.confirmed else { return }
        do {
            try settingsStore.migrateLegacyAPIKeyIfNeeded(using: apiKeyStore)
            try apiKeyStore.delete(for: profileDraft.selectedProfileID)
            refreshCredentialStatus()
            setStatus(promptPreferenceString("Saved API Key removed.", "已移除保存的 API Key。"), announces: true)
        } catch {
            setError(promptPreferenceString("Unable to remove the API Key.", "无法移除 API Key。"))
        }
    }

    private func deleteSelectedProfile(confirmation: PasteraConfirmationResult) {
        stageCurrentControls()
        guard confirmation.confirmed, let profileID = profileDraft.selectedProfile?.id else { return }
        do {
            if profileDraft.isPersisted(profileID) {
                try apiKeyStore.delete(for: profileID)
            }
            profileDraft.removeOrResetSelectedProfile()
            settingsStore.save(profileDraft.snapshot())
            profileDraft.markSaved()
            loadSelectedProfileIntoControls()
        } catch {
            setError(promptPreferenceString(
                "Unable to remove this model profile.",
                "无法移除此模型配置。"
            ))
        }
    }

    @objc private func testConnection(_ sender: NSButton) {
        guard !isTestingConnection,
              persistSettings(),
              savePendingAPIKeyIfNeeded() else { return }
        isTestingConnection = true
        testButton.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""
        scheduleProgressIndicator()
        connectionTask = Task { [weak self] in
            guard let self else { return }
            await runConnectionTest(allowsConsentRetry: true)
        }
    }

    private func runConnectionTest(allowsConsentRetry: Bool) async {
        let result = await performConnectionTest()
        guard !Task.isCancelled else { return }
        switch result {
        case .success:
            finishConnectionTest()
            setStatus(promptPreferenceString("Connection successful.", "连接成功。"), announces: true)
        case let .failure(.originNotConfirmed(origin)) where allowsConsentRetry:
            let confirmation = confirmationRunner(
                PasteraConfirmationOptions(
                    title: promptPreferenceString("Connect to \(origin)?", "连接到 \(origin)？"),
                    message: promptPreferenceString(
                        "The test sends fixed probe text only and may incur provider charges.",
                        "测试只发送固定探针文本，但仍可能产生服务费用。"
                    ),
                    confirmTitle: promptPreferenceString("Continue", "继续"),
                    cancelTitle: promptPreferenceString("Cancel", "取消"),
                    symbolName: "network"
                ),
                window
            )
            guard confirmation.confirmed else {
                finishConnectionTest()
                setStatus(promptPreferenceString("Connection test cancelled.", "已取消连接测试。"), announces: true)
                return
            }
            optimizationService.confirmRemoteOrigin(origin)
            profileDraft.confirmRemoteOrigin(origin)
            await runConnectionTest(allowsConsentRetry: false)
        case let .failure(error):
            finishConnectionTest()
            setError(connectionErrorMessage(error))
        }
    }

    nonisolated private func performConnectionTest() async -> Result<Void, PromptOptimizationError> {
        await optimizationService.testRemoteConnection()
    }

    private func persistSettings() -> Bool {
        clearMessages()
        guard let provider = selectedProvider else { return false }
        stageCurrentControls()
        profileDraft.setProvider(provider)
        guard normalizeAndValidateProfiles() else { return false }
        settingsStore.save(profileDraft.snapshot())
        profileDraft.markSaved()
        loadSelectedProfileIntoControls(clearsAPIKey: false)
        refreshProviderVisibility()
        return true
    }

    private func normalizeAndValidateProfiles() -> Bool {
        let selectedID = profileDraft.selectedProfileID
        var normalizedNames: Set<String> = []
        for profile in profileDraft.settings.remoteProfiles {
            let validationChangedProfile = profile.id != selectedID
            let displayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
            profileDraft.selectProfile(id: profile.id)
            profileDraft.updateSelected(
                displayName: displayName,
                preset: profile.preset,
                baseURL: baseURL,
                model: model,
                allowsInsecureHTTP: profile.allowsInsecureHTTP
            )
            guard !displayName.isEmpty else {
                loadSelectedProfileIntoControls(clearsAPIKey: validationChangedProfile)
                showValidation(promptPreferenceString("Profile name is required.", "配置名称为必填项。"))
                window?.makeFirstResponder(profileNameField)
                return false
            }
            guard normalizedNames.insert(displayName.lowercased()).inserted else {
                loadSelectedProfileIntoControls(clearsAPIKey: validationChangedProfile)
                showValidation(promptPreferenceString("Profile names must be unique.", "配置名称不能重复。"))
                window?.makeFirstResponder(profileNameField)
                return false
            }
            guard !model.isEmpty else {
                loadSelectedProfileIntoControls(clearsAPIKey: validationChangedProfile)
                showValidation(promptPreferenceString("Model is required.", "模型为必填项。"))
                window?.makeFirstResponder(modelField)
                return false
            }
            do {
                _ = try endpointPolicy.validate(PromptOptimizationRemoteConfiguration(
                    preset: profile.preset,
                    baseURL: baseURL,
                    model: model,
                    allowsInsecureHTTP: profile.allowsInsecureHTTP
                ))
            } catch PromptOptimizationError.insecureEndpoint {
                loadSelectedProfileIntoControls(clearsAPIKey: validationChangedProfile)
                showValidation(promptPreferenceString(
                    "Use HTTPS, a loopback address, or explicitly allow insecure HTTP.",
                    "请使用 HTTPS、回环地址，或显式允许不安全 HTTP。"
                ))
                window?.makeFirstResponder(baseURLField)
                return false
            } catch {
                loadSelectedProfileIntoControls(clearsAPIKey: validationChangedProfile)
                showValidation(promptPreferenceString("Enter a valid Base URL.", "请输入有效的基础地址。"))
                window?.makeFirstResponder(baseURLField)
                return false
            }
        }
        profileDraft.selectProfile(id: selectedID)
        return true
    }

    private func savePendingAPIKeyIfNeeded() -> Bool {
        let value = apiKeyField.stringValue
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        do {
            try settingsStore.migrateLegacyAPIKeyIfNeeded(using: apiKeyStore)
            try apiKeyStore.save(value, for: profileDraft.selectedProfileID)
            apiKeyField.stringValue = ""
            refreshCredentialStatus()
            return true
        } catch {
            setError(promptPreferenceString("Unable to save the API Key.", "无法保存 API Key。"))
            return false
        }
    }

    private func refreshProviderVisibility() {
        let usesRemote = selectedProvider == .openAICompatible
        remoteStack.isHidden = !usesRemote
        testButton.isHidden = !usesRemote
        if usesRemote {
            availabilityLabel.stringValue = promptPreferenceString(
                "Uses your configured provider. Prompt text leaves this Mac only after confirmation.",
                "使用你配置的服务；确认后提示词才会离开本机。"
            )
        } else {
            switch optimizationService.availability {
            case .available:
                availabilityLabel.stringValue = promptPreferenceString(
                    "Free. Apple on-device intelligence is ready for typo and semantic optimization.",
                    "免费；Apple 设备端智能已就绪，可进行错别字与语义优化。"
                )
            case .unavailable:
                availabilityLabel.stringValue = promptPreferenceString(
                    "Apple on-device intelligence is unavailable. Local formatting cannot check typos or meaning; configure a compatible model for semantic optimization.",
                    "Apple 设备端智能当前不可用。本地整理无法检查错别字或语义；如需语义优化，请配置兼容模型。"
                )
            }
        }
        onContentSizeChange?()
    }

    private func refreshCredentialStatus() {
        let profileID = profileDraft.selectedProfileID
        saveAPIKeyButton.isEnabled = profileDraft.isPersisted(profileID)
        do {
            let containsAPIKey = try apiKeyStore.containsAPIKey(for: profileID)
            apiKeyStatusLabel.stringValue = containsAPIKey
                ? promptPreferenceString("Saved in Keychain", "已保存至钥匙串")
                : promptPreferenceString("No key saved", "未保存密钥")
            removeAPIKeyButton.isEnabled = containsAPIKey
        } catch {
            apiKeyStatusLabel.stringValue = promptPreferenceString("Keychain unavailable", "钥匙串不可用")
            removeAPIKeyButton.isEnabled = false
        }
    }

    private func clearProfileTransientState() {
        cancelConnectionTest()
        apiKeyField.stringValue = ""
        clearMessages()
    }

    private func migrateLegacyAPIKeyIfNeeded() -> Bool {
        do {
            try settingsStore.migrateLegacyAPIKeyIfNeeded(using: apiKeyStore)
            return true
        } catch {
            setError(promptPreferenceString("Unable to access the API Key.", "无法访问 API Key。"))
            apiKeyStatusLabel.stringValue = ""
            removeAPIKeyButton.isEnabled = false
            return false
        }
    }

    private func scheduleProgressIndicator() {
        progressWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isTestingConnection else { return }
            self.progressIndicator.startAnimation(nil)
            self.statusLabel.stringValue = promptPreferenceString("Testing connection...", "正在测试连接...")
        }
        progressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func finishConnectionTest() {
        progressWorkItem?.cancel()
        progressWorkItem = nil
        progressIndicator.stopAnimation(nil)
        connectionTask = nil
        isTestingConnection = false
        testButton.isEnabled = true
        window?.makeFirstResponder(testButton)
    }

    private func clearMessages() {
        validationLabel.stringValue = ""
        validationLabel.isHidden = true
        statusLabel.stringValue = ""
        statusLabel.textColor = .secondaryLabelColor
    }

    private func showValidation(_ message: String) {
        validationLabel.stringValue = message
        validationLabel.isHidden = false
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    private func setStatus(_ message: String, announces: Bool) {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = message
        guard announces else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    private func setError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    private func connectionErrorMessage(_ error: PromptOptimizationError) -> String {
        switch error {
        case .unauthorized, .missingAPIKey, .keychainUnavailable:
            return promptPreferenceString("Authentication failed. Check the saved API Key.", "认证失败，请检查已保存的 API Key。")
        case .rateLimited:
            return promptPreferenceString("The provider is rate limited. Try again later.", "服务请求过于频繁，请稍后重试。")
        case .requestTimedOut:
            return promptPreferenceString("The connection timed out.", "连接超时。")
        case .originNotConfirmed:
            return promptPreferenceString("The provider origin was not confirmed.", "尚未确认此服务来源。")
        default:
            return promptPreferenceString("Unable to connect with the current settings.", "无法使用当前设置连接。")
        }
    }

    private var selectedProvider: PromptOptimizationProviderSelection? {
        PromptOptimizationProviderSelection(
            rawValue: providerPopup.selectedItem?.representedObject as? String ?? ""
        )
    }

    private var selectedPreset: OpenAICompatiblePreset? {
        OpenAICompatiblePreset(rawValue: presetPopup.selectedItem?.representedObject as? String ?? "")
    }

    private func selectProvider(_ provider: PromptOptimizationProviderSelection) {
        providerPopup.selectItem(at: PromptOptimizationProviderSelection.allCases.firstIndex(of: provider) ?? 0)
    }

    private func selectPreset(_ preset: OpenAICompatiblePreset) {
        presetPopup.selectItem(at: OpenAICompatiblePreset.allCases.firstIndex(of: preset) ?? 0)
    }

    var showsRemoteFieldsForTesting: Bool { !remoteStack.isHidden }
    var providerForTesting: PromptOptimizationProviderSelection? { selectedProvider }
    var presetForTesting: OpenAICompatiblePreset? { selectedPreset }
    var baseURLForTesting: String { baseURLField.stringValue }
    var modelForTesting: String { modelField.stringValue }
    var profileNameForTesting: String { profileNameField.stringValue }
    var activeProfileIDForTesting: UUID { profileDraft.selectedProfileID }
    var saveAPIKeyEnabledForTesting: Bool { saveAPIKeyButton.isEnabled }
    var modelValidationForTesting: String? { validationLabel.isHidden ? nil : validationLabel.stringValue }
    var credentialStatusForTesting: String { apiKeyStatusLabel.stringValue }
    var statusForTesting: String { statusLabel.stringValue }
    var connectionNoticeForTesting: String {
        remoteStack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.last ?? ""
    }

    func selectProviderForTesting(_ provider: PromptOptimizationProviderSelection) {
        selectProvider(provider)
        providerChanged(providerPopup)
    }

    func selectPresetForTesting(_ preset: OpenAICompatiblePreset) {
        selectPreset(preset)
        presetChanged(presetPopup)
    }

    func selectProfileForTesting(_ profileID: UUID) {
        switchToProfile(id: profileID)
    }

    @discardableResult
    func addProfileForTesting(preset: OpenAICompatiblePreset) -> UUID {
        addProfile(preset: preset, id: UUID())
    }

    func setProfileFieldsForTesting(name: String, baseURL: String, model: String) {
        profileNameField.stringValue = name
        baseURLField.stringValue = baseURL
        modelField.stringValue = model
    }

    func applyPresetDefaultsForTesting() {
        applyPresetDefaults(applyPresetDefaultsButton)
    }

    func deleteSelectedProfileForTesting(confirmed: Bool) {
        deleteSelectedProfile(confirmation: PasteraConfirmationResult(
            confirmed: confirmed,
            suppressionChecked: false
        ))
    }

    func setRemoteFieldsForTesting(baseURL: String, model: String) {
        baseURLField.stringValue = baseURL
        modelField.stringValue = model
    }

    func setAPIKeyForTesting(_ apiKey: String) {
        apiKeyField.stringValue = apiKey
    }

    @discardableResult
    func saveAPIKeyForTesting() -> Bool {
        saveAPIKeyFromControls()
    }

    @discardableResult
    func saveSettingsForTesting() -> Bool {
        persistSettings() && savePendingAPIKeyIfNeeded()
    }

    func testConnectionForTesting() async {
        guard persistSettings(), savePendingAPIKeyIfNeeded() else { return }
        isTestingConnection = true
        testButton.isEnabled = false
        await runConnectionTest(allowsConsentRetry: true)
    }
}

private extension OpenAICompatiblePreset {
    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .custom: return promptPreferenceString("Custom", "自定义")
        }
    }
}

private func promptPreferenceString(_ english: String, _ simplifiedChinese: String) -> String {
    pasteraScriptString(english, simplifiedChinese)
}
