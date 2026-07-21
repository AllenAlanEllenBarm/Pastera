//
//  SoftwareUpdatePreferenceTests.swift
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
struct SoftwareUpdatePreferenceTests {
    @Test
    func paneShowsBundleMetadataIconAndReleaseHistoryLink() throws {
        let bundle = try makeBundle(version: "9.8.7", build: "654")
        let defaults = makeDefaults()
        let updater = SoftwareUpdateFakeUpdater()
        let icon = NSImage(size: NSSize(width: 96, height: 96))
        var iconBundle: Bundle?
        var openedURLs = [URL]()
        let controller = CPYSoftwareUpdatePreferenceViewController(
            bundle: bundle,
            defaults: defaults,
            updaterProvider: { updater },
            applicationIconProvider: {
                iconBundle = $0
                return icon
            },
            openURL: { openedURLs.append($0) }
        )

        _ = controller.view

        let texts = Set(textFields(in: controller.view).map(\.stringValue))
        let iconView = try #require(
            view(in: controller.view, identifier: "softwareUpdate.applicationIcon") as? NSImageView
        )
        let releasesButton = try #require(
            view(in: controller.view, identifier: "softwareUpdate.releasesLink") as? NSButton
        )

        #expect(controller.paneID == .softwareUpdate)
        #expect(iconBundle === bundle)
        #expect(iconView.image === icon)
        #expect(texts.contains("版本 9.8.7"))
        #expect(texts.contains("构建 654"))
        #expect(controller.revealSetting(anchorID: "softwareUpdate.currentVersion", animated: false))
        #expect(controller.revealSetting(anchorID: "softwareUpdate.automaticCheck", animated: false))
        #expect(controller.revealSetting(anchorID: "softwareUpdate.lastCheck", animated: false))

        releasesButton.performClick(nil)
        #expect(openedURLs.map(\.absoluteString) == [
            "https://github.com/pastera-app/Pastera/releases"
        ])
    }

    @Test
    func registeredDefaultsEnableDailyAutomaticChecks() throws {
        let defaults = makeDefaults()
        let updater = SoftwareUpdateFakeUpdater(
            automaticallyChecksForUpdates: false,
            updateCheckInterval: 2_592_000
        )
        let controller = makeController(defaults: defaults, updater: updater)

        _ = controller.view

        let automaticButton = try #require(
            view(in: controller.view, identifier: "softwareUpdate.automaticChecks") as? NSButton
        )
        let intervalButton = try #require(
            view(in: controller.view, identifier: "softwareUpdate.checkInterval") as? NSPopUpButton
        )

        #expect(automaticButton.state == .on)
        #expect(intervalButton.selectedTag() == 86_400)
        #expect(updater.automaticallyChecksForUpdates)
        #expect(updater.updateCheckInterval == 86_400)
    }

    @Test
    func disablingAutomaticChecksKeepsManualCheckAvailable() throws {
        let defaults = makeDefaults()
        let updater = SoftwareUpdateFakeUpdater()
        let controller = makeController(defaults: defaults, updater: updater)
        _ = controller.view

        let automaticButton = try #require(
            view(in: controller.view, identifier: "softwareUpdate.automaticChecks") as? NSButton
        )
        let intervalButton = try #require(
            view(in: controller.view, identifier: "softwareUpdate.checkInterval") as? NSPopUpButton
        )
        let checkNowButton = try #require(
            view(in: controller.view, identifier: "softwareUpdate.checkNow") as? NSButton
        )

        automaticButton.performClick(nil)

        #expect(!defaults.bool(forKey: Constants.Update.enableAutomaticCheck))
        #expect(!updater.automaticallyChecksForUpdates)
        #expect(!intervalButton.isEnabled)
        #expect(checkNowButton.isEnabled)
    }

    @Test
    func manualCheckRunsOnceAndReflectsCheckingStateUntilUpdaterRecovers() throws {
        let updater = SoftwareUpdateFakeUpdater()
        let controller = makeController(defaults: makeDefaults(), updater: updater)
        _ = controller.view

        let checkNowButton = try #require(
            view(in: controller.view, identifier: "softwareUpdate.checkNow") as? NSButton
        )
        checkNowButton.performClick(nil)

        #expect(updater.checkForUpdatesCount == 1)
        #expect(!checkNowButton.isEnabled)
        #expect(checkNowButton.title == pasteraPreferenceString("Checking for Updates…"))

        checkNowButton.performClick(nil)
        #expect(updater.checkForUpdatesCount == 1)

        let date = Date(timeIntervalSince1970: 1_750_000_000)
        updater.lastUpdateCheckDate = date
        updater.canCheckForUpdates = true
        updater.sendStateChange()

        let lastCheck = try #require(
            view(in: controller.view, identifier: "softwareUpdate.lastCheckValue") as? NSTextField
        )
        #expect(checkNowButton.isEnabled)
        #expect(checkNowButton.title == pasteraPreferenceString("Check for Updates…"))
        #expect(lastCheck.objectValue as? Date == date)
    }

    @Test
    func missingUpdaterDisablesControlsAndUsesUserFacingStatus() throws {
        let controller = CPYSoftwareUpdatePreferenceViewController(
            defaults: makeDefaults(),
            updaterProvider: { nil },
            openURL: { _ in }
        )
        _ = controller.view

        let status = try #require(
            view(in: controller.view, identifier: "softwareUpdate.status") as? PasteraPreferenceStatusView
        )
        #expect(status.accessibilityLabel() == pasteraPreferenceString("Temporarily Unable to Check for Updates"))
        #expect(updateControls(in: controller.view).allSatisfy { !$0.isEnabled })
    }

    @Test
    func reloadingViewKeepsOneUpdaterObservationAndOneControlSet() {
        let updater = SoftwareUpdateFakeUpdater()
        let controller = makeController(defaults: makeDefaults(), updater: updater)

        controller.loadView()
        controller.loadView()

        #expect(updater.activeSubscriptionCount == 1)
        #expect(updateControls(in: controller.view).count == 3)
        #expect(views(in: controller.view, identifier: "softwareUpdate.status").count == 1)
    }

    @Test
    func softwareUpdateSourceUsesSparkleWithoutSilentDownloadOrGitHubFallback() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent(
                "pastera/Sources/Preferences/Panels/CPYSoftwareUpdatePreferenceViewController.swift"
            ),
            encoding: .utf8
        )
        let aboutSource = try String(
            contentsOf: projectRoot().appendingPathComponent(
                "pastera/Sources/Preferences/Panels/CPYAboutPreferenceViewController.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("updater?.checkForUpdates()"))
        #expect(!source.contains("automaticallyDownloadsUpdates"))
        #expect(!source.contains("api.github.com/repos/pastera-app/Pastera/releases"))
        #expect(!aboutSource.contains("import Sparkle"))
        #expect(!aboutSource.contains("PasteraUpdaterFacade"))
    }

    private func makeController(
        defaults: UserDefaults,
        updater: SoftwareUpdateFakeUpdater
    ) -> CPYSoftwareUpdatePreferenceViewController {
        CPYSoftwareUpdatePreferenceViewController(
            defaults: defaults,
            updaterProvider: { updater },
            openURL: { _ in }
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SoftwareUpdatePreferenceTests.\(UUID().uuidString)"
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
            .appendingPathComponent("SoftwareUpdatePreferenceTests-\(UUID().uuidString).bundle", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: NSDictionary = [
            "CFBundleIdentifier": "com.pastera.tests.software-update.\(UUID().uuidString)",
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
        [
            "softwareUpdate.automaticChecks",
            "softwareUpdate.checkInterval",
            "softwareUpdate.checkNow"
        ].compactMap { view(in: root, identifier: $0) as? NSControl }
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

    private func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("pastera.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

@MainActor
private final class SoftwareUpdateFakeUpdater: PasteraUpdaterFacade {
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
        canCheckForUpdates = false
        stateSubject.send()
    }

    func sendStateChange() {
        stateSubject.send()
    }
}
