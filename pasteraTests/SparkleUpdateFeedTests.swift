//
//  SparkleUpdateFeedTests.swift
//
//  Clipy
//

import AppKit
import Foundation
import Testing
@testable import Pastera

@Suite(.serialized)
struct SparkleUpdateFeedTests {
    @Test
    func infoPlistUsesRawSparkleAppcastFeed() throws {
        let feedURL = try infoPlistValue(forKey: "SUFeedURL")

        #expect(feedURL == "https://raw.githubusercontent.com/pastera-app/Pastera/develop/appcast.xml")
        #expect(!feedURL.hasSuffix("/releases"))
    }

    @Test
    func sourceInfoPlistDeclaresAppIcon() throws {
        #expect(try infoPlistValue(forKey: "CFBundleIconFile") == "AppIcon")
        #expect(try infoPlistValue(forKey: "CFBundleIconName") == "AppIcon")
    }

    @Test
    func legacyClipyLogoAssetIsReplaced() throws {
        let root = projectRoot()
        let legacyLogoPath = root.appendingPathComponent("Resources/clipy_logo.png").path
        let pasteraLogoPath = root.appendingPathComponent("Resources/pastera_logo.png").path

        #expect(!FileManager.default.fileExists(atPath: legacyLogoPath))
        #expect(FileManager.default.fileExists(atPath: pasteraLogoPath))
    }

    @Test
    func appIconAssetsPreserveTransparentEdges() throws {
        let iconURL = projectRoot().appendingPathComponent("pastera/Resources/Assets.xcassets/AppIcon.appiconset/512@2x.png")
        let data = try Data(contentsOf: iconURL)
        let image = try #require(NSBitmapImageRep(data: data))

        #expect(image.pixelsWide == 1024)
        #expect(image.pixelsHigh == 1024)
        #expect(image.hasAlpha)
    }

    @Test
    func appcastContainsParseableReleaseItem() throws {
        let appcastURL = projectRoot().appendingPathComponent("appcast.xml")
        let data = try Data(contentsOf: appcastURL)
        let document = try XMLDocument(data: data)
        let root = try #require(document.rootElement())
        let item = try #require(try document.nodes(forXPath: "/rss/channel/item").first as? XMLElement)
        let enclosure = try #require(item.elements(forName: "enclosure").first)

        #expect(root.name == "rss")
        #expect(root.attribute(forName: "version")?.stringValue == "2.0")
        #expect(item.elements(forName: "title").first?.stringValue?.hasPrefix("Pastera ") == true)
        #expect(item.elements(forName: "link").first?.stringValue?.hasPrefix("https://github.com/pastera-app/Pastera/releases/tag/") == true)
        #expect(enclosure.attribute(forName: "url")?.stringValue?.hasPrefix("https://github.com/pastera-app/Pastera/releases/download/") == true)
        #expect(enclosure.attribute(forName: "sparkle:version")?.stringValue?.isEmpty == false)
        #expect(enclosure.attribute(forName: "sparkle:shortVersionString")?.stringValue?.isEmpty == false)
        #expect(enclosure.attribute(forName: "type")?.stringValue?.isEmpty == false)
    }

    private func infoPlistValue(forKey key: String) throws -> String {
        let plistURL = projectRoot().appendingPathComponent("pastera/Supporting Files/Info.plist")
        let plist = try #require(NSDictionary(contentsOf: plistURL) as? [String: Any])
        return try #require(plist[key] as? String)
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

@Suite
struct PasteraGitHubReleaseUpdateCheckerTests {
    @Test
    func detectsNewerGitHubReleaseWhenSparkleAppcastIsStale() throws {
        let checker = PasteraGitHubReleaseUpdateChecker()
        let update = try #require(try checker.availableUpdate(
            currentVersion: "1.2.2beta",
            from: releasesJSON([
                release(tag: "v2.0.1-beta", asset: "Pastera-2.0.1-beta-macOS.dmg"),
                release(tag: "v1.2.2-beta", asset: "Pastera-1.2.2beta-macOS.zip")
            ])
        ))

        #expect(update.version == "2.0.1-beta")
        #expect(update.releasePageURL.absoluteString == "https://github.com/pastera-app/Pastera/releases/tag/v2.0.1-beta")
        #expect(update.assetURL?.absoluteString == "https://github.com/pastera-app/Pastera/releases/download/v2.0.1-beta/Pastera-2.0.1-beta-macOS.dmg")
    }

    @Test
    func ignoresDraftsAndDoesNotOfferOlderReleases() throws {
        let checker = PasteraGitHubReleaseUpdateChecker()
        let update = try checker.availableUpdate(
            currentVersion: "2.0.1-beta",
            from: releasesJSON([
                release(tag: "v3.0.0-beta", asset: "Pastera-3.0.0-beta-macOS.dmg", draft: true),
                release(tag: "v1.2.2-beta", asset: "Pastera-1.2.2beta-macOS.dmg")
            ])
        )

        #expect(update == nil)
    }

    @Test
    func stillReportsLatestReleaseWhenNoUpdateIsAvailable() throws {
        let checker = PasteraGitHubReleaseUpdateChecker()
        let data = try releasesJSON([
            release(tag: "v2.0.1-beta", asset: "Pastera-2.0.1-beta-macOS.dmg")
        ])

        #expect(try checker.availableUpdate(currentVersion: "2.0.1-beta", from: data) == nil)
        #expect(try checker.latestRelease(from: data)?.version == "2.0.1-beta")
    }

    @Test
    func comparesReleaseVersionForManualUpdateChecks() {
        let checker = PasteraGitHubReleaseUpdateChecker()

        #expect(checker.isUpdateAvailable(currentVersion: "1.2.2beta", releaseVersion: "2.0.1-beta"))
        #expect(!checker.isUpdateAvailable(currentVersion: "2.0.1-beta", releaseVersion: "2.0.1-beta"))
        #expect(!checker.isUpdateAvailable(currentVersion: "2.0.1", releaseVersion: "2.0.1-beta"))
    }

    @Test
    func prefersDmgAssetForManualDownloads() throws {
        let checker = PasteraGitHubReleaseUpdateChecker()
        let update = try #require(try checker.availableUpdate(
            currentVersion: "1.2.2beta",
            from: releasesJSON([
                release(
                    tag: "v2.0.1-beta",
                    assets: [
                        "Pastera-2.0.1-beta-macOS.zip",
                        "Pastera-2.0.1-beta-macOS.dmg"
                    ]
                )
            ])
        ))

        #expect(update.assetURL?.lastPathComponent == "Pastera-2.0.1-beta-macOS.dmg")
    }

    @Test
    func comparesExistingBetaVersionSpellings() {
        #expect(PasteraReleaseVersion("2.0.1-beta") > PasteraReleaseVersion("1.2.2beta"))
        #expect(PasteraReleaseVersion("2.0.1") > PasteraReleaseVersion("2.0.1-beta"))
        #expect(!(PasteraReleaseVersion("v1.2.2-beta") > PasteraReleaseVersion("1.2.2beta")))
    }

    private func release(tag: String, asset: String, draft: Bool = false) -> [String: Any] {
        release(tag: tag, assets: [asset], draft: draft)
    }

    private func release(tag: String, assets: [String], draft: Bool = false) -> [String: Any] {
        [
            "tag_name": tag,
            "html_url": "https://github.com/pastera-app/Pastera/releases/tag/\(tag)",
            "draft": draft,
            "assets": assets.map {
                [
                    "name": $0,
                    "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/\(tag)/\($0)"
                ]
            }
        ]
    }

    private func releasesJSON(_ releases: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: releases)
    }
}
