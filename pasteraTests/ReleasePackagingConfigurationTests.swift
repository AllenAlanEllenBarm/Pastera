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
    func releasePackagingScriptIncludesInstallGuide() throws {
        let script = try projectText("script/package_release_dmg.sh")

        #expect(script.contains("prepare_install_guide_assets"))
        #expect(script.contains("configure_dmg_window"))
        #expect(script.contains("render_dmg_install_guide.swift"))
        #expect(script.contains(".background"))
        #expect(script.contains("pastera-dmg-guide.png"))
        #expect(script.contains("bounds of container window of volumeRoot to {120, 120, 980, 660}"))
        #expect(script.contains("icon size of icon view options of container window of volumeRoot to 96"))
        #expect(script.contains("position of item \"Pastera.app\" of volumeRoot to {210, 285}"))
        #expect(script.contains("position of item \"Applications\" of volumeRoot to {650, 285}"))
        #expect(script.contains("position of item \"Open Privacy & Security.webloc\" of volumeRoot to {430, 430}"))
        #expect(script.contains("Pastera 安装说明.txt"))
        #expect(script.contains("Open Privacy & Security.webloc"))
        #expect(script.contains("Open Anyway"))
        #expect(script.contains("Control-click"))
        #expect(script.contains("Privacy & Security"))
        #expect(script.contains("Accessibility"))
    }

    @Test
    func releasePackagingScriptCreatesSignedNotarizedPkg() throws {
        let script = try projectText("script/package_release_pkg.sh")

        #expect(script.contains("DEVELOPER_ID_APPLICATION"))
        #expect(script.contains("DEVELOPER_ID_INSTALLER"))
        #expect(script.contains("NOTARY_KEYCHAIN_PROFILE"))
        #expect(script.contains("pkgbuild"))
        #expect(script.contains("productbuild"))
        #expect(script.contains("productsign"))
        #expect(script.contains("notarytool submit"))
        #expect(script.contains("stapler validate"))
        #expect(script.contains("spctl -a -vv -t install"))
        #expect(script.contains("--skip-notarization"))
        #expect(script.contains("postinstall"))
        #expect(script.contains("installer-resources"))
        #expect(script.contains("Pastera-${VERSION}-macOS.pkg"))
        #expect(script.contains("--pastera-open-setup-guide"))
    }

    @Test
    func installerQuitsRunningPasteraBeforeReplacingApp() throws {
        let packageScript = try projectText("script/package_release_pkg.sh")
        let preinstall = try projectText("script/installer-resources/pkg/scripts/preinstall")
        let processHelper = try projectText("script/pastera_process.sh")
        let localInstall = try projectText("script/install_local.sh")

        #expect(packageScript.contains("${RESOURCES_DIR}/scripts/preinstall"))
        #expect(packageScript.contains("pastera_process.sh"))
        #expect(preinstall.contains("quit_running_pastera"))
        #expect(processHelper.contains("osascript"))
        #expect(processHelper.contains("pkill -TERM -x"))
        #expect(processHelper.contains("pkill -KILL -x"))
        #expect(processHelper.contains("launchctl asuser"))
        #expect(localInstall.contains("script/pastera_process.sh"))
        #expect(localInstall.contains("quit_running_pastera"))
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
    func homebrewCaskInstallsReleaseDmg() throws {
        let cask = try projectText("Casks/pastera.rb")

        #expect(cask.contains("cask \"pastera\" do"))
        #expect(cask.contains("version \"2.0.1-beta\""))
        #expect(cask.contains("sha256 \"0fc376493894760197ffb4f45536588216107ce36be174bf205da0cfc45dceac\""))
        #expect(cask.contains("https://github.com/pastera-app/Pastera/releases/download/v#{version}/Pastera-#{version}-macOS.dmg"))
        #expect(cask.contains("app \"Pastera.app\""))
        #expect(cask.contains("uninstall quit: \"com.pastera-app.Pastera\""))
        #expect(cask.contains("zap trash:"))
        #expect(cask.contains("Automatic Paste"))
        #expect(!cask.contains("pkg \""))
        #expect(!cask.contains(".pkg"))
    }

    @Test
    func homebrewCaskUpdateScriptRefreshesDmgMetadata() throws {
        let script = try projectText("script/update_homebrew_cask.sh")

        #expect(script.contains("Casks/pastera.rb"))
        #expect(script.contains("shasum -a 256"))
        #expect(script.contains("Pastera-${VERSION}-macOS.dmg"))
        #expect(script.contains("https://github.com/pastera-app/Pastera/releases/download/${TAG}/Pastera-${VERSION}-macOS.dmg"))
        #expect(script.contains("PASTERA_CASK_VERSION=\"${VERSION}\""))
        #expect(script.contains("PASTERA_CASK_SHA256=\"${SHA256}\""))
        #expect(script.contains("s/version \"[^\"]+\"/version \"$version\"/"))
        #expect(script.contains("s/sha256 \"[^\"]+\"/sha256 \"$sha256\"/"))
        #expect(script.contains("--check-url"))
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

    @Test
    func releaseWorkflowPublishesPkgAssetWithoutRemovingDmgWorkflow() throws {
        let workflow = try projectText(".github/workflows/release-pkg.yml")

        #expect(workflow.contains("Build signed notarized PKG"))
        #expect(workflow.contains("script/package_release_pkg.sh"))
        #expect(workflow.contains("DEVELOPER_ID_APPLICATION"))
        #expect(workflow.contains("DEVELOPER_ID_INSTALLER"))
        #expect(workflow.contains("NOTARY_KEYCHAIN_PROFILE"))
        #expect(workflow.contains("gh release upload"))
        #expect(workflow.contains("Pastera-${{ inputs.version }}-macOS.pkg"))
        #expect(!workflow.contains("script/update_appcast_for_dmg.sh"))

        _ = try projectText(".github/workflows/release-dmg.yml")
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
