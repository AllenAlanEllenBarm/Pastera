//
//  CPYAboutPreferenceViewController.swift
//
//  Pastera
//

import AppKit
import Combine
import Sparkle

@MainActor
protocol PasteraUpdaterFacade: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    var lastUpdateCheckDate: Date? { get }
    var canCheckForUpdates: Bool { get }
    var stateChanges: AnyPublisher<Void, Never> { get }

    func checkForUpdates()
}

@MainActor
private final class PasteraSparkleUpdaterFacade: PasteraUpdaterFacade {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { updater.updateCheckInterval }
        set { updater.updateCheckInterval = newValue }
    }

    var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var stateChanges: AnyPublisher<Void, Never> {
        Publishers.Merge(
            updater.publisher(for: \.lastUpdateCheckDate).map { _ in () },
            updater.publisher(for: \.canCheckForUpdates).map { _ in () }
        )
        .eraseToAnyPublisher()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

@MainActor
final class CPYAboutPreferenceViewController: PasteraPreferencePageViewController {
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

    private enum Link: String, CaseIterable {
        case repository = "https://github.com/pastera-app/Pastera"
        case releases = "https://github.com/pastera-app/Pastera/releases"
        case issues = "https://github.com/pastera-app/Pastera/issues"
        case license = "https://github.com/pastera-app/Pastera/blob/develop/LICENSE"

        var identifier: String {
            switch self {
            case .repository: return "about.repositoryLink"
            case .releases: return "about.releasesLink"
            case .issues: return "about.issuesLink"
            case .license: return "about.licenseLink"
            }
        }

        var title: String {
            switch self {
            case .repository: return pasteraPreferenceString("Repository")
            case .releases: return pasteraPreferenceString("Releases")
            case .issues: return pasteraPreferenceString("Issues")
            case .license: return pasteraPreferenceString("View License")
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
    private var updaterStatusContainer = NSStackView()

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
        super.init(paneID: .about, title: pasteraPreferenceString("About Pastera"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        cancellables.removeAll()
        updater = nil
        resetContent()
        super.loadView()
        resetControls()
        buildApplicationGroup()
        buildLinksGroup()
        buildLicenseGroup()
        buildUpdatesGroup()
        connectUpdater()
    }
}

private extension CPYAboutPreferenceViewController {
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
        automaticCheckButton.setAccessibilityIdentifier("about.automaticUpdates")
        automaticCheckButton.setAccessibilityLabel(pasteraPreferenceString("Automatically Check for Updates"))

        intervalButton = NSPopUpButton(frame: .zero, pullsDown: false)
        UpdateInterval.allCases.forEach {
            intervalButton.menu?.addItem(withTitle: $0.title, action: nil, keyEquivalent: "")
            intervalButton.lastItem?.tag = $0.rawValue
        }
        intervalButton.target = self
        intervalButton.action = #selector(updateIntervalChanged(_:))
        intervalButton.setAccessibilityIdentifier("about.updateInterval")
        intervalButton.setAccessibilityLabel(pasteraPreferenceString("Check Frequency"))

        lastCheckField = NSTextField(labelWithString: "")
        lastCheckField.setAccessibilityIdentifier("about.lastCheck")
        lastCheckField.setAccessibilityLabel(pasteraPreferenceString("Last Check"))
        lastCheckField.alignment = .right
        lastCheckField.formatter = makeDateFormatter()

        checkNowButton = NSButton(
            title: pasteraPreferenceString("Check Now"),
            target: self,
            action: #selector(checkForUpdates)
        )
        checkNowButton.bezelStyle = .rounded
        checkNowButton.setAccessibilityIdentifier("about.checkNow")
        checkNowButton.setAccessibilityLabel(pasteraPreferenceString("Check for Updates Now"))

        updaterStatusContainer = NSStackView()
        updaterStatusContainer.orientation = .vertical
        updaterStatusContainer.alignment = .trailing
    }

    func buildApplicationGroup() {
        let iconView = NSImageView(image: applicationIconProvider(bundle))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityIdentifier("about.applicationIcon")
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
        let buildLabel = NSTextField(labelWithString: String(
            format: pasteraPreferenceString("Build %@"),
            build
        ))
        buildLabel.textColor = .secondaryLabelColor
        let metadataStack = NSStackView(views: [versionLabel, buildLabel])
        metadataStack.orientation = .vertical
        metadataStack.alignment = .trailing
        metadataStack.spacing = 4
        let identityStack = NSStackView(views: [metadataStack, iconView])
        identityStack.orientation = .horizontal
        identityStack.alignment = .centerY
        identityStack.spacing = 14

        let row = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Pastera"),
            control: identityStack
        )
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Application"),
            symbolName: "app",
            accentColor: .systemBlue
        )
        group.addRow(row)
        addGroup(group)
        registerAnchor("about.version", view: row)
    }

    func buildLinksGroup() {
        let buttons = [Link.repository, .releases, .issues].map(makeLinkButton)
        let controls = NSStackView(views: buttons)
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        let row = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("GitHub"),
            subtitle: pasteraPreferenceString("Source code, releases, and issue tracking."),
            control: controls
        )
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Project Links"),
            symbolName: "link",
            accentColor: .systemTeal
        )
        group.addRow(row)
        addGroup(group)
        registerAnchor("about.github", view: row)
    }

    func buildLicenseGroup() {
        let row = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("MIT License"),
            subtitle: pasteraPreferenceString("Pastera is distributed under the MIT License."),
            control: makeLinkButton(.license)
        )
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("License"),
            symbolName: "checkmark.seal",
            accentColor: .systemIndigo
        )
        group.addRow(row)
        addGroup(group)
        registerAnchor("about.license", view: row)
    }

    func buildUpdatesGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Software Updates"),
            symbolName: "arrow.triangle.2.circlepath",
            accentColor: .systemBlue
        )
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Automatically Check for Updates"),
            control: automaticCheckButton
        ))
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Check Frequency"),
            control: intervalButton
        ))
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Last Check"),
            control: lastCheckField
        ))
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Check for Updates"),
            control: checkNowButton
        ))
        group.addRow(PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Update Status"),
            control: updaterStatusContainer
        ))
        addGroup(group, anchorID: "about.sparkle")
    }

    private func makeLinkButton(_ link: Link) -> NSButton {
        let button = NSButton(title: link.title, target: self, action: #selector(openLink(_:)))
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        button.font = font
        button.attributedTitle = NSAttributedString(
            string: link.title,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.linkColor
            ]
        )
        button.identifier = NSUserInterfaceItemIdentifier(link.identifier)
        button.setAccessibilityIdentifier(link.identifier)
        button.setAccessibilityLabel(link.title)
        button.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        return button
    }

    func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

private extension CPYAboutPreferenceViewController {
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
        automaticCheckButton.isEnabled = canCheck
        intervalButton.isEnabled = canCheck && automaticCheckButton.state == .on
        checkNowButton.isEnabled = canCheck

        if let lastCheckDate = updater?.lastUpdateCheckDate {
            lastCheckField.objectValue = lastCheckDate
        } else {
            lastCheckField.objectValue = nil
            lastCheckField.stringValue = pasteraPreferenceString("Never Checked")
        }

        let statusText = updater == nil
            ? pasteraPreferenceString("Sparkle Update Service Unavailable")
            : canCheck
                ? pasteraPreferenceString("Sparkle Update Service Available")
                : pasteraPreferenceString("Sparkle Cannot Check for Updates")
        replaceUpdaterStatus(text: statusText, canCheck: canCheck)
    }

    func replaceUpdaterStatus(text: String, canCheck: Bool) {
        updaterStatusContainer.arrangedSubviews.forEach {
            updaterStatusContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let status = PasteraPreferenceStatusView(
            text: text,
            style: canCheck ? .success : .warning
        )
        status.setAccessibilityIdentifier("about.updaterStatus")
        updaterStatusContainer.addArrangedSubview(status)
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
        guard updater?.canCheckForUpdates == true else { return }
        updater?.checkForUpdates()
    }

    @objc func openLink(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let link = Link.allCases.first(where: { $0.identifier == identifier }),
              let url = URL(string: link.rawValue) else { return }
        openURL(url)
    }
}
