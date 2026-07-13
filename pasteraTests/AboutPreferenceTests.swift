//
//  AboutPreferenceTests.swift
//
//  Pastera
//

import AppKit
import Combine
import Foundation
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct AboutPreferenceTests {
    @Test
    func aboutPaneShowsBundleMetadataApplicationIconAndMITLicense() throws {
        let bundle = try makeBundle(version: "9.8.7", build: "654")
        let defaults = makeDefaults()
        let icon = NSImage(size: NSSize(width: 96, height: 96))
        var iconBundle: Bundle?
        let controller = CPYAboutPreferenceViewController(
            bundle: bundle,
            defaults: defaults,
            updaterProvider: { FakeUpdater() },
            applicationIconProvider: {
                iconBundle = $0
                return icon
            },
            openURL: { _ in }
        )

        _ = controller.view

        let texts = Set(textFields(in: controller.view).map(\.stringValue))
        let iconView = try #require(view(in: controller.view, identifier: "about.applicationIcon") as? NSImageView)
        #expect(controller.paneID == .about)
        #expect(iconBundle === bundle)
        #expect(iconView.image === icon)
        #expect(texts.contains("Pastera"))
        #expect(texts.contains("版本 9.8.7"))
        #expect(texts.contains("构建 654"))
        #expect(texts.contains(pasteraPreferenceString("MIT License")))
        #expect(controller.revealSetting(anchorID: "about.version", animated: false))
        #expect(controller.revealSetting(anchorID: "about.github", animated: false))
        #expect(controller.revealSetting(anchorID: "about.license", animated: false))
        #expect(controller.revealSetting(anchorID: "about.sparkle", animated: false))
    }

    @Test
    func aboutLinksOpenOnlyTheApprovedExactURLs() throws {
        let defaults = makeDefaults()
        var openedURLs = [URL]()
        let controller = CPYAboutPreferenceViewController(
            defaults: defaults,
            updaterProvider: { FakeUpdater() },
            openURL: { openedURLs.append($0) }
        )
        _ = controller.view

        let linkTitles = Dictionary(uniqueKeysWithValues: [
            "about.releasesLink",
            "about.issuesLink"
        ].compactMap { identifier -> (String, String)? in
            guard let button = view(in: controller.view, identifier: identifier) as? NSButton else { return nil }
            return (identifier, button.title)
        })

        #expect(linkTitles["about.releasesLink"] == pasteraPreferenceString("Releases"))
        #expect(linkTitles["about.issuesLink"] == pasteraPreferenceString("Issues"))

        for identifier in [
            "about.repositoryLink",
            "about.releasesLink",
            "about.issuesLink",
            "about.licenseLink"
        ] {
            let button = try #require(view(in: controller.view, identifier: identifier) as? NSButton)
            #expect(!button.isBordered)
            #expect(button.contentTintColor == .linkColor)
            #expect(
                button.attributedTitle.attribute(
                    .foregroundColor,
                    at: 0,
                    effectiveRange: nil
                ) as? NSColor == .linkColor
            )
            button.performClick(nil)
        }

        #expect(openedURLs.map(\.absoluteString) == [
            "https://github.com/pastera-app/Pastera",
            "https://github.com/pastera-app/Pastera/releases",
            "https://github.com/pastera-app/Pastera/issues",
            "https://github.com/pastera-app/Pastera/blob/develop/LICENSE"
        ])
    }

    @Test
    func hostedAboutLinksKeepSemanticLinkStyling() throws {
        let controller = CPYPreferencesWindowController(
            frameAutosaveName: "AboutPreferenceTests.Hosted.\(UUID().uuidString)",
            reduceMotion: { true },
            deactivateApplication: {}
        )
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(paneID: .about)
        let page = try #require(
            controller.cachedPreferencePageForTesting(paneID: .about) as? CPYAboutPreferenceViewController
        )

        for identifier in [
            "about.repositoryLink",
            "about.releasesLink",
            "about.issuesLink",
            "about.licenseLink"
        ] {
            let button = try #require(view(in: page.view, identifier: identifier) as? NSButton)
            #expect(button.contentTintColor == .linkColor)
            #expect(
                button.attributedTitle.attribute(
                    .foregroundColor,
                    at: 0,
                    effectiveRange: nil
                ) as? NSColor == .linkColor
            )
        }
    }

    @Test
    func updateControlsUseExistingDefaultsAndMutateTheLiveUpdaterImmediately() throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: Constants.Update.enableAutomaticCheck)
        defaults.set(86_400, forKey: Constants.Update.checkInterval)
        let updater = FakeUpdater(
            automaticallyChecksForUpdates: true,
            updateCheckInterval: 2_592_000,
            canCheckForUpdates: true
        )
        let controller = CPYAboutPreferenceViewController(
            defaults: defaults,
            updaterProvider: { updater },
            openURL: { _ in }
        )
        _ = controller.view

        let automaticButton = try #require(
            view(in: controller.view, identifier: "about.automaticUpdates") as? NSButton
        )
        let intervalButton = try #require(
            view(in: controller.view, identifier: "about.updateInterval") as? NSPopUpButton
        )
        let checkNowButton = try #require(
            view(in: controller.view, identifier: "about.checkNow") as? NSButton
        )

        #expect(automaticButton.state == .off)
        #expect(intervalButton.selectedTag() == 86_400)
        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(updater.updateCheckInterval == 86_400)

        automaticButton.performClick(nil)
        #expect(defaults.bool(forKey: Constants.Update.enableAutomaticCheck))
        #expect(updater.automaticallyChecksForUpdates)

        intervalButton.selectItem(withTag: 604_800)
        intervalButton.sendAction(intervalButton.action, to: intervalButton.target)
        #expect(defaults.integer(forKey: Constants.Update.checkInterval) == 604_800)
        #expect(updater.updateCheckInterval == 604_800)

        checkNowButton.performClick(nil)
        #expect(updater.checkForUpdatesCount == 1)
    }

    @Test
    func updaterStateRefreshesLastCheckAndDisablesControlsWhenCheckingBecomesUnavailable() throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: Constants.Update.enableAutomaticCheck)
        defaults.set(604_800, forKey: Constants.Update.checkInterval)
        let updater = FakeUpdater(canCheckForUpdates: true)
        let controller = CPYAboutPreferenceViewController(
            defaults: defaults,
            updaterProvider: { updater },
            openURL: { _ in }
        )
        _ = controller.view

        let date = Date(timeIntervalSince1970: 1_750_000_000)
        updater.lastUpdateCheckDate = date
        updater.canCheckForUpdates = false
        updater.sendStateChange()

        let status = try #require(
            view(in: controller.view, identifier: "about.updaterStatus") as? PasteraPreferenceStatusView
        )
        let lastCheck = try #require(
            view(in: controller.view, identifier: "about.lastCheck") as? NSTextField
        )
        #expect(status.accessibilityLabel() == pasteraPreferenceString("Sparkle Cannot Check for Updates"))
        #expect(lastCheck.objectValue as? Date == date)
        #expect(updateControls(in: controller.view).allSatisfy { !$0.isEnabled })
    }

    @Test
    func missingUpdaterDisablesControlsAndShowsVisibleStatus() throws {
        let controller = CPYAboutPreferenceViewController(
            defaults: makeDefaults(),
            updaterProvider: { nil },
            openURL: { _ in }
        )
        _ = controller.view

        let status = try #require(
            view(in: controller.view, identifier: "about.updaterStatus") as? PasteraPreferenceStatusView
        )
        #expect(status.accessibilityLabel() == pasteraPreferenceString("Sparkle Update Service Unavailable"))
        #expect(updateControls(in: controller.view).allSatisfy { !$0.isEnabled })
    }

    @Test
    func reloadingViewKeepsOneUpdaterObservationAndOneControlSet() {
        let updater = FakeUpdater(canCheckForUpdates: true)
        let controller = CPYAboutPreferenceViewController(
            defaults: makeDefaults(),
            updaterProvider: { updater },
            openURL: { _ in }
        )

        controller.loadView()
        controller.loadView()

        #expect(updater.activeSubscriptionCount == 1)
        #expect(updateControls(in: controller.view).count == 3)
        #expect(views(in: controller.view, identifier: "about.updaterStatus").count == 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AboutPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.register(defaults: [
            Constants.Update.enableAutomaticCheck: true,
            Constants.Update.checkInterval: 86_400
        ])
        return defaults
    }

    private func makeBundle(version: String, build: String) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AboutPreferenceTests-\(UUID().uuidString).bundle", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: NSDictionary = [
            "CFBundleIdentifier": "com.pastera.tests.about.\(UUID().uuidString)",
            "CFBundleName": "Pastera",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build
        ]
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        #expect(info.write(to: infoURL, atomically: true))
        return try #require(Bundle(url: bundleURL))
    }

    private func updateControls(in root: NSView) -> [NSControl] {
        ["about.automaticUpdates", "about.updateInterval", "about.checkNow"].compactMap {
            view(in: root, identifier: $0) as? NSControl
        }
    }

    private func view(in root: NSView, identifier: String) -> NSView? {
        views(in: root, identifier: identifier).first
    }

    private func views(in root: NSView, identifier: String) -> [NSView] {
        var matches = root.accessibilityIdentifier() == identifier ? [root] : []
        root.subviews.forEach { matches.append(contentsOf: views(in: $0, identifier: identifier)) }
        return matches
    }

    private func textFields(in root: NSView) -> [NSTextField] {
        var fields = root.subviews.compactMap { $0 as? NSTextField }
        root.subviews.forEach { fields.append(contentsOf: textFields(in: $0)) }
        return fields
    }
}

@MainActor
private final class FakeUpdater: PasteraUpdaterFacade {
    var automaticallyChecksForUpdates: Bool
    var updateCheckInterval: TimeInterval
    var lastUpdateCheckDate: Date?
    var canCheckForUpdates: Bool
    private(set) var checkForUpdatesCount = 0
    private(set) var activeSubscriptionCount = 0

    private let stateSubject = PassthroughSubject<Void, Never>()

    var stateChanges: AnyPublisher<Void, Never> {
        stateSubject
            .handleEvents(
                receiveSubscription: { [weak self] _ in self?.activeSubscriptionCount += 1 },
                receiveCancel: { [weak self] in self?.activeSubscriptionCount -= 1 }
            )
            .eraseToAnyPublisher()
    }

    init(
        automaticallyChecksForUpdates: Bool = true,
        updateCheckInterval: TimeInterval = 86_400,
        lastUpdateCheckDate: Date? = nil,
        canCheckForUpdates: Bool = true
    ) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.updateCheckInterval = updateCheckInterval
        self.lastUpdateCheckDate = lastUpdateCheckDate
        self.canCheckForUpdates = canCheckForUpdates
    }

    func checkForUpdates() {
        checkForUpdatesCount += 1
    }

    func sendStateChange() {
        stateSubject.send()
    }
}
