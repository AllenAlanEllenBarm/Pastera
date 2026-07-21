//
//  CPYAboutPreferenceViewController.swift
//
//  Pastera
//

import AppKit

@MainActor
final class CPYAboutPreferenceViewController: PasteraPreferencePageViewController {
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
    private let applicationIconProvider: (Bundle) -> NSImage
    private let openURL: (URL) -> Void

    init(
        bundle: Bundle = .main,
        applicationIconProvider: @escaping (Bundle) -> NSImage = {
            PasteraAppIconProvider.applicationIcon(bundle: $0)
        },
        openURL: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        self.bundle = bundle
        self.applicationIconProvider = applicationIconProvider
        self.openURL = openURL
        super.init(paneID: .about, title: pasteraPreferenceString("About Pastera"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        resetContent()
        super.loadView()
        buildApplicationGroup()
        buildLinksGroup()
        buildLicenseGroup()
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

    @objc func openLink(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let link = Link.allCases.first(where: { $0.identifier == identifier }),
              let url = URL(string: link.rawValue) else { return }
        openURL(url)
    }
}
