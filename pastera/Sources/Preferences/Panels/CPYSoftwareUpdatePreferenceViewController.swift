//
//  CPYSoftwareUpdatePreferenceViewController.swift
//
//  Pastera
//

import AppKit
import Combine

@MainActor
final class CPYSoftwareUpdatePreferenceViewController: PasteraPreferencePageViewController {
    private enum UpdateInterval: Int, CaseIterable {
        case daily = 86_400
        case weekly = 604_800
        case monthly = 2_592_000

        var title: String {
            switch self {
            case .daily: return pasteraPreferenceString("Daily")
            case .weekly: return pasteraPreferenceString("Weekly")
            case .monthly: return pasteraPreferenceString("Monthly")
            }
        }
    }

    private let bundle: Bundle
    private let defaults: UserDefaults
    private let updaterProvider: @MainActor () -> (any PasteraUpdaterFacade)?
    private let applicationIconProvider: (Bundle) -> NSImage
    private let openURL: (URL) -> Void

    private var updater: (any PasteraUpdaterFacade)?
    private var cancellables = Set<AnyCancellable>()
    private var automaticCheckButton = NSButton()
    private var intervalButton = NSPopUpButton()
    private var lastCheckField = NSTextField()
    private var checkNowButton = NSButton()
    private var statusContainer = NSStackView()
    private var manualCheckInFlight = false
    private var observedBusySinceManualCheck = false
    private var lastCheckDateWhenManualCheckStarted: Date?

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = AppEnvironment.current.defaults,
        updaterProvider: @escaping @MainActor () -> (any PasteraUpdaterFacade)? = {
            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let updater = appDelegate.updaterController?.updater else { return nil }
            return PasteraSparkleUpdaterFacade(updater: updater)
        },
        applicationIconProvider: @escaping (Bundle) -> NSImage = {
            PasteraAppIconProvider.applicationIcon(bundle: $0)
        },
        openURL: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        self.bundle = bundle
        self.defaults = defaults
        self.updaterProvider = updaterProvider
        self.applicationIconProvider = applicationIconProvider
        self.openURL = openURL
        super.init(paneID: .softwareUpdate, title: pasteraPreferenceString("Software Update"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        cancellables.removeAll()
        updater = nil
        manualCheckInFlight = false
        observedBusySinceManualCheck = false
        lastCheckDateWhenManualCheckStarted = nil
        resetContent()
        super.loadView()
        resetControls()
        buildCurrentVersionGroup()
        buildAutomaticChecksGroup()
        buildUpdateHistoryGroup()
        connectUpdater()
    }
}

private extension CPYSoftwareUpdatePreferenceViewController {
    func resetContent() {
        contentStack.arrangedSubviews.forEach { arrangedSubview in
            contentStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        contentStack.removeFromSuperview()
    }

    func resetControls() {
        automaticCheckButton = NSButton(
            checkboxWithTitle: "",
            target: self,
            action: #selector(automaticCheckChanged(_:))
        )
        automaticCheckButton.setAccessibilityIdentifier("softwareUpdate.automaticChecks")
        automaticCheckButton.setAccessibilityLabel(pasteraPreferenceString("Automatically Check for Updates"))

        intervalButton = NSPopUpButton(frame: .zero, pullsDown: false)
        UpdateInterval.allCases.forEach { interval in
            intervalButton.menu?.addItem(withTitle: interval.title, action: nil, keyEquivalent: "")
            intervalButton.lastItem?.tag = interval.rawValue
        }
        intervalButton.target = self
        intervalButton.action = #selector(updateIntervalChanged(_:))
        intervalButton.setAccessibilityIdentifier("softwareUpdate.checkInterval")
        intervalButton.setAccessibilityLabel(pasteraPreferenceString("Check Frequency"))

        lastCheckField = NSTextField(labelWithString: "")
        lastCheckField.alignment = .right
        lastCheckField.formatter = makeDateFormatter()
        lastCheckField.setAccessibilityIdentifier("softwareUpdate.lastCheckValue")
        lastCheckField.setAccessibilityLabel(pasteraPreferenceString("Last Check"))

        checkNowButton = NSButton(
            title: pasteraPreferenceString("Check for Updates…"),
            target: self,
            action: #selector(checkForUpdates)
        )
        checkNowButton.bezelStyle = .rounded
        checkNowButton.setAccessibilityIdentifier("softwareUpdate.checkNow")
        checkNowButton.setAccessibilityLabel(pasteraPreferenceString("Check for Updates"))

        statusContainer = NSStackView()
        statusContainer.orientation = .vertical
        statusContainer.alignment = .trailing
    }

    func buildCurrentVersionGroup() {
        let iconView = NSImageView(image: applicationIconProvider(bundle))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityIdentifier("softwareUpdate.applicationIcon")
        iconView.setAccessibilityLabel(pasteraPreferenceString("Pastera Application Icon"))
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72)
        ])

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let versionLabel = NSTextField(labelWithString: String(
            format: pasteraPreferenceString("Version %@"),
            version
        ))
        versionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let buildLabel = NSTextField(labelWithString: String(
            format: pasteraPreferenceString("Build %@"),
            build
        ))
        buildLabel.textColor = .secondaryLabelColor

        let metadata = NSStackView(views: [versionLabel, buildLabel])
        metadata.orientation = .vertical
        metadata.alignment = .trailing
        metadata.spacing = 4
        let identity = NSStackView(views: [metadata, iconView])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 12

        let versionRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Pastera"),
            control: identity,
            minimumHeight: 72
        )
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Current Version"),
            symbolName: "app.badge",
            accentColor: .systemBlue
        )
        group.addRow(versionRow)
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Check for Updates"),
            subtitle: pasteraPreferenceString("Review an available update before downloading and installing it."),
            control: checkNowButton
        ))
        addGroup(group)
        registerAnchor("softwareUpdate.currentVersion", view: versionRow)
    }

    func buildAutomaticChecksGroup() {
        let automaticRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Automatically Check for Updates"),
            subtitle: pasteraPreferenceString("Notify you when a new version is available."),
            control: automaticCheckButton
        )
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Automatic Updates"),
            symbolName: "clock.arrow.circlepath",
            accentColor: .systemTeal
        )
        group.addRow(automaticRow)
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Check Frequency"),
            control: intervalButton
        ))
        addGroup(group)
        registerAnchor("softwareUpdate.automaticCheck", view: automaticRow)
    }

    func buildUpdateHistoryGroup() {
        let lastCheckRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Last Check"),
            control: lastCheckField
        )
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Update History"),
            symbolName: "clock",
            accentColor: .systemIndigo
        )
        group.addRow(lastCheckRow)
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Release Notes"),
            control: makeReleasesButton()
        ))
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Update Status"),
            control: statusContainer
        ))
        addGroup(group)
        registerAnchor("softwareUpdate.lastCheck", view: lastCheckRow)
    }

    func makeReleasesButton() -> NSButton {
        let title = pasteraPreferenceString("View Release History")
        let button = NSButton(title: title, target: self, action: #selector(openReleases))
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        button.font = font
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: font, .foregroundColor: NSColor.linkColor]
        )
        button.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.setAccessibilityIdentifier("softwareUpdate.releasesLink")
        button.setAccessibilityLabel(title)
        return button
    }

    func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

private extension CPYSoftwareUpdatePreferenceViewController {
    func connectUpdater() {
        updater = updaterProvider()
        applyStoredPreferencesToUpdater()
        updater?.stateChanges
            .sink { [weak self] in
                self?.refreshUpdaterState()
            }
            .store(in: &cancellables)
        refreshUpdaterState()
    }

    func applyStoredPreferencesToUpdater() {
        let automaticallyChecks = defaults.bool(forKey: Constants.Update.enableAutomaticCheck)
        let interval = normalizedInterval(defaults.integer(forKey: Constants.Update.checkInterval))
        automaticCheckButton.state = automaticallyChecks ? .on : .off
        intervalButton.selectItem(withTag: interval.rawValue)
        updater?.automaticallyChecksForUpdates = automaticallyChecks
        updater?.updateCheckInterval = TimeInterval(interval.rawValue)
    }

    func refreshUpdaterState() {
        let canCheck = updater?.canCheckForUpdates == true
        if manualCheckInFlight {
            if !canCheck {
                observedBusySinceManualCheck = true
            }
            let lastCheckChanged = updater?.lastUpdateCheckDate != lastCheckDateWhenManualCheckStarted
            if lastCheckChanged || (observedBusySinceManualCheck && canCheck) {
                manualCheckInFlight = false
                observedBusySinceManualCheck = false
            }
        }

        automaticCheckButton.isEnabled = updater != nil
        intervalButton.isEnabled = updater != nil && automaticCheckButton.state == .on
        checkNowButton.isEnabled = canCheck && !manualCheckInFlight
        checkNowButton.title = manualCheckInFlight
            ? pasteraPreferenceString("Checking for Updates…")
            : pasteraPreferenceString("Check for Updates…")

        if let lastCheckDate = updater?.lastUpdateCheckDate {
            lastCheckField.objectValue = lastCheckDate
        } else {
            lastCheckField.objectValue = nil
            lastCheckField.stringValue = pasteraPreferenceString("Never Checked")
        }

        let statusText: String
        let statusStyle: PasteraPreferenceStatusView.Style
        if updater == nil || (!canCheck && !manualCheckInFlight) {
            statusText = pasteraPreferenceString("Temporarily Unable to Check for Updates")
            statusStyle = .warning
        } else if manualCheckInFlight {
            statusText = pasteraPreferenceString("Checking for Updates…")
            statusStyle = .neutral
        } else {
            statusText = pasteraPreferenceString("Ready to Check for Updates")
            statusStyle = .success
        }
        replaceStatus(text: statusText, style: statusStyle)
    }

    func replaceStatus(text: String, style: PasteraPreferenceStatusView.Style) {
        statusContainer.arrangedSubviews.forEach {
            statusContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let status = PasteraPreferenceStatusView(text: text, style: style)
        status.setAccessibilityIdentifier("softwareUpdate.status")
        statusContainer.addArrangedSubview(status)
        invalidateContentSize()
    }

    private func normalizedInterval(_ value: Int) -> UpdateInterval {
        UpdateInterval(rawValue: value) ?? .daily
    }

    @objc func automaticCheckChanged(_ sender: NSButton) {
        let isEnabled = sender.state == .on
        defaults.set(isEnabled, forKey: Constants.Update.enableAutomaticCheck)
        updater?.automaticallyChecksForUpdates = isEnabled
        refreshUpdaterState()
    }

    @objc func updateIntervalChanged(_ sender: NSPopUpButton) {
        guard let interval = UpdateInterval(rawValue: sender.selectedTag()) else { return }
        defaults.set(interval.rawValue, forKey: Constants.Update.checkInterval)
        updater?.updateCheckInterval = TimeInterval(interval.rawValue)
    }

    @objc func checkForUpdates() {
        guard updater?.canCheckForUpdates == true, !manualCheckInFlight else { return }
        manualCheckInFlight = true
        observedBusySinceManualCheck = false
        lastCheckDateWhenManualCheckStarted = updater?.lastUpdateCheckDate
        refreshUpdaterState()
        updater?.checkForUpdates()
    }

    @objc func openReleases() {
        guard let url = URL(string: "https://github.com/pastera-app/Pastera/releases") else { return }
        openURL(url)
    }
}
