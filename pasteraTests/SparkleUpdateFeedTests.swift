//
//  SparkleUpdateFeedTests.swift
//
//  Clipy
//

import AppKit
import Foundation
import Testing

@Suite(.serialized)
struct SparkleUpdateFeedTests {
    @Test
    func infoPlistUsesRawSparkleAppcastFeed() throws {
        let feedURL = try infoPlistValue(forKey: "SUFeedURL")

        #expect(feedURL == "https://raw.githubusercontent.com/AllenAlanEllenBarm/Pastera/develop/appcast.xml")
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
    func appcastContainsCurrentBetaReleaseItem() throws {
        let appcastURL = projectRoot().appendingPathComponent("appcast.xml")
        let data = try Data(contentsOf: appcastURL)
        let document = try XMLDocument(data: data)
        let root = try #require(document.rootElement())
        let item = try #require(try document.nodes(forXPath: "/rss/channel/item").first as? XMLElement)
        let enclosure = try #require(item.elements(forName: "enclosure").first)

        #expect(root.name == "rss")
        #expect(root.attribute(forName: "version")?.stringValue == "2.0")
        #expect(item.elements(forName: "title").first?.stringValue == "Pastera 1.2.2beta")
        #expect(enclosure.attribute(forName: "url")?.stringValue == "https://github.com/AllenAlanEllenBarm/Pastera/releases/download/v1.2.2-beta/Pastera-1.2.2beta-macOS.zip")
        #expect(enclosure.attribute(forName: "sparkle:version")?.stringValue == "1.2.2beta")
        #expect(enclosure.attribute(forName: "sparkle:shortVersionString")?.stringValue == "1.2.2beta")
        #expect(enclosure.attribute(forName: "type")?.stringValue == "application/octet-stream")
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
