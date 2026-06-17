//
//  ReleasePackagingConfigurationTests.swift
//
//  Pastera
//
//  Created by Codex on 2026/06/15.
//

import Foundation
import Testing

struct ReleasePackagingConfigurationTests {
    @Test
    func adHocSigningConfigurationDoesNotOverrideRelease() throws {
        let adHoc = try projectText("Configurations/CodeSigning-AdHoc.xcconfig")

        #expect(!adHoc.contains("CODE_SIGN_IDENTITY[config=Release] = -"))
        #expect(!adHoc.contains("PROVISIONING_PROFILE_SPECIFIER[config=Release] ="))
        #expect(!adHoc.contains("\nDEVELOPMENT_TEAM =\n"))
    }

    @Test
    func releaseSigningConfigurationEnablesDistributionRequirements() throws {
        let signing = try projectText("Configurations/CodeSigning.xcconfig")

        #expect(signing.contains("CODE_SIGN_IDENTITY[config=Release] = Developer ID Application"))
        #expect(signing.contains("ENABLE_HARDENED_RUNTIME[config=Release] = YES"))
        #expect(signing.contains("OTHER_CODE_SIGN_FLAGS[config=Release] = --timestamp"))
    }

    @Test
    func releasePackagingScriptCreatesSignedNotarizedDmg() throws {
        let script = try projectText("script/package_release_dmg.sh")

        #expect(script.contains("hdiutil create"))
        #expect(script.contains("notarytool submit"))
        #expect(script.contains("stapler staple"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("spctl -a -vv"))
        #expect(script.contains("ln -s /Applications"))
        #expect(script.contains("-target \"${APP_TARGET}\""))
    }

    @Test
    func releasePackagingScriptSupportsLocalAdHocDryRun() throws {
        let script = try projectText("script/package_release_dmg.sh")

        #expect(script.contains("DEVELOPER_ID_APPLICATION is required unless --skip-notarization is passed."))
        #expect(script.contains("CODE_SIGNING_ALLOWED=NO"))
        #expect(script.contains("/usr/bin/codesign --force --deep --sign -"))
    }

    @Test
    func releasePackageEntryPointRunsDmgPackagingAndOptionalAppcastUpdate() throws {
        let script = try projectText("script/package_release.sh")

        #expect(script.contains("script/package_release_dmg.sh"))
        #expect(script.contains("script/update_appcast_for_dmg.sh"))
        #expect(script.contains("--update-appcast"))
        #expect(script.contains("--skip-notarization"))
    }

    @Test
    func appcastUpdateScriptSignsDmgForSparkle() throws {
        let script = try projectText("script/update_appcast_for_dmg.sh")

        #expect(script.contains("sign_update"))
        #expect(script.contains("sparkle:edSignature"))
        #expect(script.contains("application/x-apple-diskimage"))
    }

    @Test
    func releaseWorkflowPublishesDmgAsset() throws {
        let workflow = try projectText(".github/workflows/release-dmg.yml")

        #expect(workflow.contains("script/package_release_dmg.sh"))
        #expect(workflow.contains("script/update_appcast_for_dmg.sh"))
        #expect(workflow.contains("gh release upload"))
        #expect(workflow.contains("Pastera-${{ inputs.version }}-macOS.dmg"))
        #expect(!workflow.contains("- name: Update appcast for DMG"))

        let uploadRange = try #require(workflow.range(of: "gh release upload"))
        let appcastRange = try #require(workflow.range(of: "script/update_appcast_for_dmg.sh"))
        #expect(uploadRange.lowerBound < appcastRange.lowerBound)
    }

    private func projectText(_ path: String) throws -> String {
        let url = projectRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
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
