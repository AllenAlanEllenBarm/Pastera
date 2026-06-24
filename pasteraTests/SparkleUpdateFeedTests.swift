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

    @Test
    func manualUpdateCheckUsesSparkleWithoutGitHubDownloadFallback() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent("pastera/Sources/Preferences/Panels/CPYUpdatesPreferenceViewController.swift"),
            encoding: .utf8
        )

        #expect(source.contains("updaterController?.checkForUpdates(sender)"))
        #expect(!source.contains("PasteraGitHubReleaseUpdateChecker"))
        #expect(!source.contains("api.github.com/repos/pastera-app/Pastera/releases"))
        #expect(!source.contains("NSWorkspace.shared.open"))
        #expect(!source.contains("Open the GitHub release page to download this version."))
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
