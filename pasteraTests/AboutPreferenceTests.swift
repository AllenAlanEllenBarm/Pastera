//
//  AboutPreferenceTests.swift
//
//  Pastera
//

import AppKit
import Foundation
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct AboutPreferenceTests {
    @Test
    func aboutPaneShowsBundleMetadataApplicationIconAndMITLicense() throws {
        let bundle = try makeBundle(version: "9.8.7", build: "654")
        let icon = NSImage(size: NSSize(width: 96, height: 96))
        var iconBundle: Bundle?
        let controller = CPYAboutPreferenceViewController(
            bundle: bundle,
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
        #expect(!controller.revealSetting(anchorID: "about.sparkle", animated: false))
        #expect(view(in: controller.view, identifier: "softwareUpdate.checkNow") == nil)
        #expect(view(in: controller.view, identifier: "softwareUpdate.automaticChecks") == nil)
    }

    @Test
    func aboutLinksOpenOnlyTheApprovedExactURLs() throws {
        var openedURLs = [URL]()
        let controller = CPYAboutPreferenceViewController(
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
