import Darwin
import Foundation
import PasteraAgentProtocol
import Testing
@testable import Pastera

@Suite("Vault agent integration installer", .serialized)
// swiftlint:disable:next type_body_length
struct VaultAgentIntegrationInstallerTests {
    @Test("Codex install uses the official argument array only once")
    func codexInstallIsIdempotent() throws {
        let fixture = try InstallerFixture()

        _ = try fixture.installer().install(host: .codex)
        _ = try fixture.installer().install(host: .codex)

        #expect(fixture.runner.invocations == [
            .init(
                executableURL: fixture.codexURL,
                arguments: [
                    "mcp", "add", "pastera-vault", "--",
                    fixture.codexHelperURL.path
                ]
            )
        ])
    }

    @Test("foreign and changed MCP registrations are preserved as conflicts")
    func foreignMCPRegistrationsArePreserved() throws {
        do {
            let fixture = try InstallerFixture()
            let foreign = VaultAgentHostRegistration(
                command: fixture.codexHelperURL.path,
                arguments: [],
                userScoped: true,
                hasAdditionalConfiguration: true
            )
            fixture.runner.registrations[fixture.codexURL] = foreign

            #expect(throws: VaultAgentInstallerError.installationConflict) {
                _ = try fixture.installer().install(host: .codex)
            }

            #expect(fixture.runner.invocations.isEmpty)
            #expect(fixture.runner.registrations[fixture.codexURL] == foreign)
            #expect(!FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
        }
        do {
            let fixture = try InstallerFixture()
            let installer = fixture.installer()
            _ = try installer.install(host: .codex)
            let foreign = VaultAgentHostRegistration(
                command: "/usr/local/bin/replacement-mcp",
                arguments: [],
                userScoped: true
            )
            fixture.runner.registrations[fixture.codexURL] = foreign

            #expect(throws: VaultAgentInstallerError.installationConflict) {
                _ = try installer.uninstall(host: .codex)
            }

            #expect(fixture.runner.invocations.count == 1)
            #expect(fixture.runner.registrations[fixture.codexURL] == foreign)
            #expect(FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
        }
    }

    @Test("missing owned registration is not reported as installed or silently recreated")
    func missingOwnedRegistrationIsAConflict() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        _ = try installer.install(host: .codex)
        fixture.runner.registrations[fixture.codexURL] = nil

        let status = try installer.status(host: .codex)
        #expect(status.hosts.first?.mcpInstalled == false)
        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try installer.install(host: .codex)
        }
        #expect(fixture.runner.invocations.count == 1)
    }

    @Test("a user-modified installed Skill is preserved as a conflict")
    func userModifiedSkillIsPreserved() throws {
        let fixture = try InstallerFixture()
        _ = try fixture.installer().install(host: .codex)
        let installedSkill = fixture.userRootURL
            .appendingPathComponent(".agents/skills/pastera-vault/SKILL.md")
        let userText = "user-owned edit\n"
        try Data(userText.utf8).write(to: installedSkill)

        #expect(throws: VaultAgentInstallerError.userModifiedSkill) {
            _ = try fixture.installer().install(host: .codex)
        }
        #expect(try String(contentsOf: installedSkill, encoding: .utf8) == userText)
        #expect(fixture.runner.invocations.count == 1)
    }

    @Test("Claude snippets are exact and Codex exposes no permission mutation")
    func permissionCapabilitiesAreNarrow() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        let metadata = try installer.permissionSnippet(for: .claude, scope: .metadataOnly)
        let all = try installer.permissionSnippet(for: .claude, scope: .allCurrentPasteraTools)

        #expect(metadata.allowedTools == [
            "mcp__pastera-vault__vault_get",
            "mcp__pastera-vault__vault_search",
            "mcp__pastera-vault__vault_status"
        ])
        #expect(all.allowedTools == [
            "mcp__pastera-vault__vault_get",
            "mcp__pastera-vault__vault_paste",
            "mcp__pastera-vault__vault_prepare_exec",
            "mcp__pastera-vault__vault_search",
            "mcp__pastera-vault__vault_status"
        ])
        #expect(!metadata.serialized.contains("*"))
        #expect(!all.serialized.contains("mcp__pastera-vault\""))
        #expect(installer.supportedPermissionScopes(for: .codex).isEmpty)
        #expect(installer.configurationMutations(for: .codex).isEmpty)
        #expect(throws: VaultAgentInstallerError.hostManagedUnsupported) {
            _ = try installer.permissionSnippet(for: .codex, scope: .metadataOnly)
        }
    }

    @Test("owned Codex and Claude installs uninstall exactly once and preserve unrelated Skills")
    func uninstallIsOwnedAndIdempotent() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        let unrelatedSkill = fixture.userRootURL
            .appendingPathComponent(".agents/skills/unrelated/SKILL.md")
        try FileManager.default.createDirectory(
            at: unrelatedSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("unrelated\n".utf8).write(to: unrelatedSkill)

        _ = try installer.install(host: .codex)
        _ = try installer.install(host: .claude)
        _ = try installer.uninstall(host: .codex)
        _ = try installer.uninstall(host: .codex)
        _ = try installer.uninstall(host: .claude)
        _ = try installer.uninstall(host: .claude)

        #expect(fixture.runner.invocations == [
            .init(
                executableURL: fixture.codexURL,
                arguments: ["mcp", "add", "pastera-vault", "--", fixture.codexHelperURL.path]
            ),
            .init(
                executableURL: fixture.claudeURL,
                arguments: [
                    "mcp", "add", "--transport", "stdio", "--scope", "user",
                    "pastera-vault", "--", fixture.claudeHelperURL.path
                ]
            ),
            .init(
                executableURL: fixture.codexURL,
                arguments: ["mcp", "remove", "pastera-vault"]
            ),
            .init(
                executableURL: fixture.claudeURL,
                arguments: ["mcp", "remove", "pastera-vault"]
            )
        ])
        #expect(!FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.claudeSkillURL.path))
        #expect(try String(contentsOf: unrelatedSkill, encoding: .utf8) == "unrelated\n")
    }

    @Test("uninstall preserves a user-modified Skill without invoking host removal")
    func uninstallPreservesModifiedSkill() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        _ = try installer.install(host: .codex)
        let userText = "user-owned edit\n"
        try Data(userText.utf8).write(to: fixture.codexSkillURL)

        #expect(throws: VaultAgentInstallerError.userModifiedSkill) {
            _ = try installer.uninstall(host: .codex)
        }

        #expect(try String(contentsOf: fixture.codexSkillURL, encoding: .utf8) == userText)
        #expect(fixture.runner.invocations.count == 1)
    }

    @Test("uninstall preserves extra user files inside an owned Skill directory")
    func uninstallPreservesExtraSkillFiles() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        _ = try installer.install(host: .codex)
        let extra = fixture.codexSkillURL.deletingLastPathComponent()
            .appendingPathComponent("user-note.md")
        try Data("user-owned\n".utf8).write(to: extra)

        #expect(throws: VaultAgentInstallerError.userModifiedSkill) {
            _ = try installer.uninstall(host: .codex)
        }

        #expect(try String(contentsOf: extra, encoding: .utf8) == "user-owned\n")
        #expect(fixture.runner.invocations.count == 1)
    }

    @Test("a post-add local commit failure removes the host registration and staged ownership")
    func postAddFailureIsCompensated() throws {
        let fixture = try InstallerFixture()
        fixture.runner.handler = { _, arguments in
            guard arguments.prefix(2) == ["mcp", "add"] else { return 0 }
            try FileManager.default.createDirectory(
                at: fixture.codexSkillURL.deletingLastPathComponent(),
                withIntermediateDirectories: false
            )
            return 0
        }

        #expect(throws: (any Error).self) {
            _ = try fixture.installer().install(host: .codex)
        }

        #expect(fixture.runner.invocations.map(\.arguments) == [
            ["mcp", "add", "pastera-vault", "--", fixture.codexHelperURL.path],
            ["mcp", "remove", "pastera-vault"]
        ])
        #expect(!FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.manifestURL.path))
    }

    @Test("an installed Skill symlink is rejected without host removal")
    func installedSkillSymlinkFailsSafely() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        _ = try installer.install(host: .codex)
        try FileManager.default.removeItem(at: fixture.codexSkillURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.codexSkillURL,
            withDestinationURL: fixture.sourceSkillURL.appendingPathComponent("SKILL.md")
        )

        #expect(throws: VaultAgentInstallerError.userModifiedSkill) {
            _ = try installer.uninstall(host: .codex)
        }

        #expect(fixture.runner.invocations.count == 1)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.codexSkillURL.path)
                == fixture.sourceSkillURL.appendingPathComponent("SKILL.md").path)
    }

    @Test("a manifest symlink is rejected before any ownership mutation")
    func manifestSymlinkFailsSafely() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        _ = try installer.install(host: .codex)
        let backup = fixture.rootURL.appendingPathComponent("manifest-backup.json")
        try FileManager.default.copyItem(at: fixture.manifestURL, to: backup)
        try FileManager.default.removeItem(at: fixture.manifestURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.manifestURL,
            withDestinationURL: backup
        )

        #expect(throws: VaultAgentInstallerError.manifestCorrupt) {
            _ = try installer.uninstall(host: .codex)
        }

        #expect(fixture.runner.invocations.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
    }

    @Test("CLI symlink install is owned, idempotent, PATH-only advisory, and mode-safe")
    func cliSymlinkLifecycleIsOwned() throws {
        let fixture = try InstallerFixture()
        let skillParent = fixture.codexSkillURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: skillParent,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: skillParent.path
        )
        let zprofile = fixture.userRootURL.appendingPathComponent(".zprofile")
        try Data("user profile\n".utf8).write(to: zprofile)
        let installer = fixture.installer(environmentPath: "/usr/bin:/bin")

        let installed = try installer.installCLI()
        let repeated = try installer.installCLI()
        _ = try installer.install(host: .codex)

        #expect(installed == repeated)
        #expect(installed.installed)
        #expect(installed.executablePath == fixture.cliLinkURL.path)
        #expect(installed.pathHint == "Add ~/.local/bin to PATH to run pastera from a shell.")
        #expect(try FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.cliLinkURL.path
        ) == fixture.cliHelperURL.path)
        #expect(try String(contentsOf: zprofile, encoding: .utf8) == "user profile\n")
        #expect(try fixture.permissions(of: skillParent) == 0o755)
        #expect(try fixture.permissions(of: fixture.manifestURL) == 0o600)
        #expect(try fixture.permissions(of: fixture.manifestURL.deletingLastPathComponent()) == 0o700)
        let manifestText = try String(contentsOf: fixture.manifestURL, encoding: .utf8)
        #expect(!manifestText.contains(fixture.rootURL.path))
        #expect(!manifestText.localizedCaseInsensitiveContains("password"))

        let removed = try installer.uninstallCLI()
        let repeatedRemoval = try installer.uninstallCLI()
        #expect(!removed.installed)
        #expect(removed == repeatedRemoval)
        #expect(lstatExists(fixture.cliLinkURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.cliHelperURL.path))
    }

    @Test("CLI install and uninstall preserve non-owned or modified links")
    func cliConflictsArePreserved() throws {
        let fixture = try InstallerFixture()
        try FileManager.default.createDirectory(
            at: fixture.cliLinkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.cliLinkURL,
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/false")
        )
        let installer = fixture.installer(environmentPath: fixture.cliLinkURL
            .deletingLastPathComponent().path)

        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try installer.installCLI()
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.cliLinkURL.path
        ) == "/usr/bin/false")

        try FileManager.default.removeItem(at: fixture.cliLinkURL)
        _ = try installer.installCLI()
        try FileManager.default.removeItem(at: fixture.cliLinkURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.cliLinkURL,
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/true")
        )

        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try installer.uninstallCLI()
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.cliLinkURL.path
        ) == "/usr/bin/true")
    }

    @Test("explicit Claude permission apply preserves JSON and owns only newly added rules")
    func claudePermissionApplyAndRemoveAreOwned() throws {
        let fixture = try InstallerFixture()
        try fixture.writeClaudeSettings([
            "theme": "dark",
            "unknown": ["nested": true],
            "permissions": [
                "allow": [
                    "Bash(git status)",
                    "mcp__pastera-vault__vault_status"
                ],
                "deny": ["Read(.env)"]
            ]
        ])
        let installer = fixture.installer(permissionDisposition: .userRulesAllowed)
        _ = try installer.install(host: .claude)

        let applied = try installer.applyClaudePermissionScope(.metadataOnly)
        let repeated = try installer.applyClaudePermissionScope(.metadataOnly)
        let status = try installer.claudePermissionStatus()

        #expect(applied.addedRules == [
            "mcp__pastera-vault__vault_get",
            "mcp__pastera-vault__vault_search"
        ])
        #expect(!applied.unchanged)
        #expect(repeated.addedRules.isEmpty)
        #expect(repeated.unchanged)
        #expect(status.policyDisposition == .userRulesAllowed)
        #expect(status.ownedRules == applied.addedRules)
        let afterApply = try fixture.readClaudeSettings()
        #expect(afterApply["theme"] as? String == "dark")
        #expect((afterApply["unknown"] as? [String: Bool])?["nested"] == true)
        let appliedPermissions = try #require(afterApply["permissions"] as? [String: Any])
        #expect(appliedPermissions["deny"] as? [String] == ["Read(.env)"])
        #expect(appliedPermissions["allow"] as? [String] == [
            "Bash(git status)",
            "mcp__pastera-vault__vault_status",
            "mcp__pastera-vault__vault_get",
            "mcp__pastera-vault__vault_search"
        ])

        let removed = try installer.removeOwnedClaudePermissionRules()
        #expect(removed.removedRules == applied.addedRules)
        #expect(!removed.unchanged)
        let afterRemove = try fixture.readClaudeSettings()
        let removedPermissions = try #require(afterRemove["permissions"] as? [String: Any])
        #expect(removedPermissions["allow"] as? [String] == [
            "Bash(git status)",
            "mcp__pastera-vault__vault_status"
        ])
        #expect(fixture.runner.invocations.map(\.arguments).filter { $0 == ["doctor"] }.count == 2)
    }

    @Test("Claude settings above one MiB use the same bounded CAS path")
    func largeClaudeSettingsUseTheSameCASBound() throws {
        let fixture = try InstallerFixture()
        let preserved = String(repeating: "x", count: 1_100_000)
        try fixture.writeClaudeSettings(["preserved": preserved])
        let installer = fixture.installer(permissionDisposition: .userRulesAllowed)
        _ = try installer.install(host: .claude)

        _ = try installer.applyClaudePermissionScope(.metadataOnly)

        #expect(try fixture.readClaudeSettings()["preserved"] as? String == preserved)
    }

    @Test("managed or unknown Claude policy fails closed without changing settings")
    func claudeManagedPolicyFailsClosed() throws {
        for disposition in [
            VaultAgentManagedPermissionDisposition.managedRulesOnly,
            .unknown
        ] {
            let fixture = try InstallerFixture()
            try fixture.writeClaudeSettings(["theme": "dark"])
            let original = try Data(contentsOf: fixture.claudeSettingsURL)
            let installer = fixture.installer(permissionDisposition: disposition)
            _ = try installer.install(host: .claude)

            #expect(throws: VaultAgentInstallerError.managedPolicyRestricted) {
                _ = try installer.applyClaudePermissionScope(.metadataOnly)
            }

            #expect(try Data(contentsOf: fixture.claudeSettingsURL) == original)
            #expect(fixture.runner.invocations.map(\.arguments).filter { $0 == ["doctor"] }.isEmpty)
        }
    }

    @Test("managed policy uncertainty never blocks removal of owned Claude rules")
    func claudeOwnedRulesCanAlwaysBeRemoved() throws {
        for disposition in [
            VaultAgentManagedPermissionDisposition.managedRulesOnly,
            .unknown
        ] {
            let fixture = try InstallerFixture()
            try fixture.writeClaudeSettings(["theme": "dark"])
            let allowed = fixture.installer(permissionDisposition: .userRulesAllowed)
            _ = try allowed.install(host: .claude)
            _ = try allowed.applyClaudePermissionScope(.metadataOnly)

            let restricted = fixture.installer(permissionDisposition: disposition)
            let removed = try restricted.removeOwnedClaudePermissionRules()

            #expect(removed.removedRules == [
                "mcp__pastera-vault__vault_get",
                "mcp__pastera-vault__vault_search",
                "mcp__pastera-vault__vault_status"
            ])
            #expect(try restricted.claudePermissionStatus().ownedRules.isEmpty)
        }
    }

    @Test("MCP install and uninstall never change Claude permission settings")
    func hostLifecycleDoesNotChangePermissions() throws {
        let fixture = try InstallerFixture()
        try fixture.writeClaudeSettings([
            "permissions": ["allow": ["Bash(git status)"]],
            "theme": "dark"
        ])
        let original = try Data(contentsOf: fixture.claudeSettingsURL)
        let installer = fixture.installer(permissionDisposition: .userRulesAllowed)

        _ = try installer.install(host: .claude)
        _ = try installer.uninstall(host: .claude)

        #expect(try Data(contentsOf: fixture.claudeSettingsURL) == original)
        #expect(fixture.runner.invocations.map(\.arguments).filter { $0 == ["doctor"] }.isEmpty)
    }

    @Test("invalid and symlinked Claude settings fail before doctor or writes")
    func unsafeClaudeSettingsFailClosed() throws {
        do {
            let fixture = try InstallerFixture()
            try FileManager.default.createDirectory(
                at: fixture.claudeSettingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("not-json".utf8).write(to: fixture.claudeSettingsURL)
            let installer = fixture.installer(permissionDisposition: .userRulesAllowed)
            _ = try installer.install(host: .claude)
            #expect(throws: VaultAgentInstallerError.installationConflict) {
                _ = try installer.applyClaudePermissionScope(.metadataOnly)
            }
            #expect(try String(contentsOf: fixture.claudeSettingsURL, encoding: .utf8)
                    == "not-json")
        }
        do {
            let fixture = try InstallerFixture()
            let external = fixture.rootURL.appendingPathComponent("external-settings.json")
            try Data("{}".utf8).write(to: external)
            try FileManager.default.createDirectory(
                at: fixture.claudeSettingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: fixture.claudeSettingsURL,
                withDestinationURL: external
            )
            let installer = fixture.installer(permissionDisposition: .userRulesAllowed)
            _ = try installer.install(host: .claude)
            #expect(throws: VaultAgentInstallerError.installationConflict) {
                _ = try installer.applyClaudePermissionScope(.metadataOnly)
            }
            #expect(try String(contentsOf: external, encoding: .utf8) == "{}")
        }
    }

    @Test("Claude settings races and doctor failures preserve or restore the original")
    func claudePermissionTransactionsRollBack() throws {
        do {
            let fixture = try InstallerFixture()
            try fixture.writeClaudeSettings(["theme": "before"])
            let installer = fixture.installer(
                atomicWriteInterposer: { url, phase in
                    guard url == fixture.claudeSettingsURL, phase == .beforeSwap else { return }
                    try fixture.writeClaudeSettings(["theme": "concurrent"])
                },
                permissionDisposition: .userRulesAllowed
            )
            _ = try installer.install(host: .claude)
            #expect(throws: VaultAgentInstallerError.installationConflict) {
                _ = try installer.applyClaudePermissionScope(.metadataOnly)
            }
            #expect(try fixture.readClaudeSettings()["theme"] as? String == "concurrent")
        }
        do {
            let fixture = try InstallerFixture()
            try fixture.writeClaudeSettings(["theme": "before"])
            let original = try Data(contentsOf: fixture.claudeSettingsURL)
            let installer = fixture.installer(permissionDisposition: .userRulesAllowed)
            _ = try installer.install(host: .claude)
            var sawPrivateBackup = false
            fixture.runner.handler = { _, arguments in
                guard arguments == ["doctor"] else { return 0 }
                sawPrivateBackup = try fixture.hasPrivateClaudeBackup()
                return 9
            }

            #expect(throws: VaultAgentInstallerError.commandFailed(9)) {
                _ = try installer.applyClaudePermissionScope(.metadataOnly)
            }

            #expect(sawPrivateBackup)
            #expect(try Data(contentsOf: fixture.claudeSettingsURL) == original)
            #expect(try installer.claudePermissionStatus().ownedRules.isEmpty)
        }
        do {
            let fixture = try InstallerFixture()
            try fixture.writeClaudeSettings(["theme": "before"])
            let installer = fixture.installer(permissionDisposition: .userRulesAllowed)
            _ = try installer.install(host: .claude)
            fixture.runner.handler = { _, arguments in
                guard arguments == ["doctor"] else { return 0 }
                var concurrent = try fixture.readClaudeSettings()
                concurrent["theme"] = "concurrent"
                try fixture.writeClaudeSettings(concurrent)
                return 9
            }

            #expect(throws: VaultAgentInstallerError.commandFailed(9)) {
                _ = try installer.applyClaudePermissionScope(.allCurrentPasteraTools)
            }

            let preserved = try fixture.readClaudeSettings()
            #expect(preserved["theme"] as? String == "concurrent")
            let permissions = try #require(preserved["permissions"] as? [String: Any])
            #expect((permissions["allow"] as? [String])?.isEmpty == true)
            #expect(try installer.claudePermissionStatus().ownedRules.isEmpty)
        }
    }

    @Test("CAS rollback never overwrites a write that arrives after the first swap")
    func atomicRollbackPreservesLateConcurrentWrite() throws {
        let fixture = try InstallerFixture()
        try fixture.writeClaudeSettings(["theme": "initial"])
        let installer = fixture.installer(
            atomicWriteInterposer: { url, phase in
                guard url == fixture.claudeSettingsURL else { return }
                switch phase {
                case .beforeSwap:
                    try fixture.writeClaudeSettings(["theme": "before-swap"])
                case .beforeConflictRollback:
                    try fixture.writeClaudeSettings(["theme": "after-swap"])
                case .afterSwapBeforeSync:
                    break
                case .afterRollbackTargetQuarantined:
                    break
                }
            },
            permissionDisposition: .userRulesAllowed
        )
        _ = try installer.install(host: .claude)

        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try installer.applyClaudePermissionScope(.metadataOnly)
        }

        #expect(try fixture.readClaudeSettings()["theme"] as? String == "after-swap")
    }

    @Test("CAS rollback preserves writes racing after its target quarantine")
    func atomicRollbackQuarantineRacePreservesAllUserData() throws {
        let fixture = try InstallerFixture()
        try fixture.writeClaudeSettings(["theme": "initial"])
        let installer = fixture.installer(
            atomicWriteInterposer: { url, phase in
                guard url == fixture.claudeSettingsURL else { return }
                if phase == .beforeSwap {
                    try fixture.writeClaudeSettings(["theme": "before-swap"])
                } else if phase == .afterRollbackTargetQuarantined {
                    try fixture.writeClaudeSettings(["theme": "late-write"])
                }
            },
            permissionDisposition: .userRulesAllowed
        )
        _ = try installer.install(host: .claude)

        #expect(throws: VaultAgentInstallerError.rollbackFailed) {
            _ = try installer.applyClaudePermissionScope(.metadataOnly)
        }

        #expect(try fixture.readClaudeSettings()["theme"] as? String == "late-write")
        let preservedTemporaryFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.claudeSettingsURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".pastera-write-") }
        #expect(!preservedTemporaryFiles.isEmpty)
        #expect(try preservedTemporaryFiles.contains { url in
            let object = try #require(JSONSerialization.jsonObject(
                with: Data(contentsOf: url)
            ) as? [String: Any])
            return object["theme"] as? String == "before-swap"
        })
    }

    @Test("a failed uninstall manifest commit restores host registration and Skill")
    func uninstallCommitFailureRollsBack() throws {
        let fixture = try InstallerFixture()
        let initial = fixture.installer()
        _ = try initial.install(host: .codex)
        let manifestBefore = try Data(contentsOf: fixture.manifestURL)
        var shouldFail = true
        let failing = fixture.installer(atomicWriteInterposer: { url, phase in
            if shouldFail, url == fixture.manifestURL, phase == .beforeSwap {
                shouldFail = false
                throw InstallerProbeError.injectedFailure
            }
        })

        #expect(throws: InstallerProbeError.injectedFailure) {
            _ = try failing.uninstall(host: .codex)
        }

        #expect(fixture.runner.invocations.map(\.arguments) == [
            ["mcp", "add", "pastera-vault", "--", fixture.codexHelperURL.path],
            ["mcp", "remove", "pastera-vault"],
            ["mcp", "add", "pastera-vault", "--", fixture.codexHelperURL.path]
        ])
        #expect(FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
        #expect(try Data(contentsOf: fixture.manifestURL) == manifestBefore)
    }

    @Test("a post-swap manifest failure restores the prior manifest and external state")
    func postSwapManifestFailureRollsBack() throws {
        do {
            let fixture = try InstallerFixture()
            let initial = fixture.installer()
            _ = try initial.install(host: .codex)
            let manifestBefore = try Data(contentsOf: fixture.manifestURL)
            var shouldFail = true
            let failing = fixture.installer(atomicWriteInterposer: { url, phase in
                if shouldFail, url == fixture.manifestURL, phase == .afterSwapBeforeSync {
                    shouldFail = false
                    throw InstallerProbeError.injectedFailure
                }
            })

            #expect(throws: InstallerProbeError.injectedFailure) {
                _ = try failing.uninstall(host: .codex)
            }

            #expect(try Data(contentsOf: fixture.manifestURL) == manifestBefore)
            #expect(FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
            #expect(fixture.runner.registrations[fixture.codexURL]?.command
                    == fixture.codexHelperURL.path)
        }
        do {
            let fixture = try InstallerFixture()
            var shouldFail = true
            let failing = fixture.installer(atomicWriteInterposer: { url, phase in
                if shouldFail, url == fixture.manifestURL, phase == .afterSwapBeforeSync {
                    shouldFail = false
                    throw InstallerProbeError.injectedFailure
                }
            })

            #expect(throws: InstallerProbeError.injectedFailure) {
                _ = try failing.install(host: .codex)
            }

            #expect(!FileManager.default.fileExists(atPath: fixture.manifestURL.path))
            #expect(!FileManager.default.fileExists(atPath: fixture.codexSkillURL.path))
            #expect(fixture.runner.registrations[fixture.codexURL] == nil)
        }
    }
    @Test("service status is ordered, scoped, non-throwing for missing hosts, and authorization-aware")
    func statusIsNarrowAndReadOnly() throws {
        let fixture = try InstallerFixture()
        let idleExpiry = Date(timeIntervalSince1970: 1_700_000_100)
        let hardExpiry = Date(timeIntervalSince1970: 1_700_000_200)
        fixture.authorizationStatuses[.codex] = .init(
            authorized: true,
            idleExpiresAt: idleExpiry,
            hardExpiresAt: hardExpiry
        )
        try FileManager.default.removeItem(at: fixture.claudeURL)
        let service: VaultAgentIntegrationServicing = fixture.installer()

        let all = try service.status(host: nil)
        let codex = try #require(all.hosts.first)
        let claude = try #require(all.hosts.last)
        #expect(all.hosts.map { $0.host.rawValue } == ["codex", "claude"])
        #expect(codex.hostDetected)
        #expect(codex.hostExecutablePath == fixture.codexURL.path)
        #expect(codex.authorized)
        #expect(codex.idleExpiresAt == idleExpiry)
        #expect(codex.hardExpiresAt == hardExpiry)
        #expect(!claude.hostDetected)
        #expect(claude.hostExecutablePath == nil)
        #expect(!claude.authorized)
        #expect(fixture.authorizationRequests == [.codex, .claude])

        fixture.authorizationRequests.removeAll()
        let single = try service.status(host: .codex)
        #expect(single.hosts.map { $0.host.rawValue } == ["codex"])
        #expect(fixture.authorizationRequests == [.codex])
    }

    @Test("install and uninstall still reject an unverifiable host")
    func mutationsRequireVerifiedHost() throws {
        let fixture = try InstallerFixture()
        try FileManager.default.removeItem(at: fixture.codexURL)
        let service: VaultAgentIntegrationServicing = fixture.installer()

        #expect(throws: VaultAgentInstallerError.invalidHost) {
            _ = try service.install(host: .codex)
        }
        #expect(throws: VaultAgentInstallerError.invalidHost) {
            _ = try service.uninstall(host: .codex)
        }
        #expect(fixture.runner.invocations.isEmpty)
    }

    @Test("a symlink candidate records and invokes the canonical host identity")
    func symlinkCandidateUsesCanonicalIdentity() throws {
        let fixture = try InstallerFixture()
        let symlink = fixture.rootURL.appendingPathComponent("bin/codex")
        try FileManager.default.createDirectory(
            at: symlink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: fixture.codexURL)
        let installer = fixture.installer(hostCandidates: [
            .init(host: .codex, urls: [symlink]),
            .init(host: .claude, urls: [fixture.claudeURL])
        ])
        let provider: VaultAgentHostIdentityProviding = installer

        _ = try installer.install(host: .codex)
        let identity = try #require(provider.installedHostIdentity(for: .codex))

        #expect(fixture.runner.invocations.first?.executableURL == fixture.codexURL)
        #expect(identity.client == .codex)
        #expect(identity.canonicalPath == fixture.codexURL.path)
        #expect(identity.designatedRequirement
                == "identifier com.openai.codex and anchor apple generic")
        #expect(identity.cdHash == Data([0x11]))
        #expect(!identity.isAdHoc)
        #expect(provider.installedHostIdentity(for: .cli) == nil)
    }

    @Test("incomplete stable and ad-hoc signatures fail closed")
    func incompleteSignaturesFailClosed() throws {
        let invalidSignatures: [VaultAgentInstallerCodeSignature] = [
            .init(
                identifier: "",
                designatedRequirement: "requirement",
                teamID: "TEAM",
                cdHash: Data([0x01]),
                isAdHoc: false
            ),
            .init(
                identifier: "identifier",
                designatedRequirement: "",
                teamID: "TEAM",
                cdHash: Data([0x01]),
                isAdHoc: false
            ),
            .init(
                identifier: "identifier",
                designatedRequirement: "requirement",
                teamID: nil,
                cdHash: Data([0x01]),
                isAdHoc: false
            ),
            .init(
                identifier: "identifier",
                designatedRequirement: "requirement",
                teamID: nil,
                cdHash: nil,
                isAdHoc: true
            )
        ]

        for signature in invalidSignatures {
            let fixture = try InstallerFixture()
            fixture.signingInspector.signatures[fixture.codexURL.path] = signature
            #expect(throws: VaultAgentInstallerError.invalidSignature) {
                _ = try fixture.installer().install(host: .codex)
            }
            #expect(fixture.runner.invocations.isEmpty)
        }
    }

    @Test("path, signature, and ad-hoc cdhash changes conflict without a second command")
    func changedInstalledIdentityConflicts() throws {
        try expectPathChangeConflict()
        try expectRequirementChangeConflict()
        try expectAdHocCDHashChangeConflict()
    }

    @Test("stable Host and owned Skill updates refresh in place without a second registration")
    func stableOwnedUpdatesAreInPlace() throws {
        let fixture = try InstallerFixture()
        let installer = fixture.installer()
        _ = try installer.install(host: .codex)
        fixture.signingInspector.signatures[fixture.codexURL.path] = .init(
            identifier: fixture.codexSignature.identifier,
            designatedRequirement: fixture.codexSignature.designatedRequirement,
            teamID: fixture.codexSignature.teamID,
            cdHash: Data([0x99]),
            isAdHoc: false
        )
        try fixture.updateSourceSkill("# updated workflow\n")

        _ = try installer.install(host: .codex)
        let provider: VaultAgentHostIdentityProviding = installer
        let identity = try #require(provider.installedHostIdentity(for: .codex))

        #expect(identity.cdHash == Data([0x99]))
        #expect(try String(contentsOf: fixture.codexSkillURL, encoding: .utf8)
                == "# updated workflow\n")
        #expect(fixture.runner.invocations.count == 1)
    }

    @Test("system signing inspection fails closed and command execution is bounded")
    func systemAdaptersAreFailClosedAndBounded() throws {
        let fixture = try InstallerFixture()
        let inspector = VaultAgentSystemInstallerCodeSigningInspector()
        #expect(throws: VaultAgentInstallerError.invalidSignature) {
            _ = try inspector.inspect(executableURL: fixture.codexURL)
        }

        let runner = VaultAgentSystemHostCommandRunner(timeout: 0.05)
        #expect(throws: VaultAgentInstallerError.commandLaunchFailed) {
            _ = try runner.run(
                executableURL: fixture.rootURL.appendingPathComponent("missing-command"),
                arguments: []
            )
        }
        #expect(try runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: []
        ) == 1)
        let startedAt = Date()
        #expect(throws: VaultAgentInstallerError.commandTimedOut) {
            _ = try runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"]
            )
        }
        #expect(Date().timeIntervalSince(startedAt) < 2)

        let hardKillRunner = VaultAgentSystemHostCommandRunner(
            timeout: 0.2,
            terminationGracePeriod: 0.05
        )
        let hardKillStartedAt = Date()
        #expect(throws: VaultAgentInstallerError.commandTimedOut) {
            _ = try hardKillRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                arguments: ["-e", "$SIG{TERM} = 'IGNORE'; sleep 5"]
            )
        }
        #expect(Date().timeIntervalSince(hardKillStartedAt) < 2)
    }

    @Test("system registration inspection accepts only bounded official Host output")
    func systemRegistrationInspectionIsStrict() throws {
        let fixture = try InstallerFixture()
        let runner = VaultAgentSystemHostCommandRunner(timeout: 1)
        let script = fixture.rootURL.appendingPathComponent("registration-probe")

        try fixture.writeExecutableScript(
            """
            #!/bin/sh
            printf '%s\\n' '{"transport":{"type":"stdio","command":"\(fixture.codexHelperURL.path)","args":[]}}'
            """,
            to: script
        )
        #expect(try runner.registration(executableURL: script, host: .codex) == .init(
            command: fixture.codexHelperURL.path,
            arguments: [],
            userScoped: true
        ))

        try fixture.writeExecutableScript(
            """
            #!/bin/sh
            printf '%s\\n' '{"transport":{"type":"stdio","command":"\(fixture.codexHelperURL.path)","args":[],"env":{"USER_VALUE":"redacted"}}}'
            """,
            to: script
        )
        #expect(try runner.registration(
            executableURL: script,
            host: .codex
        )?.hasAdditionalConfiguration == true)

        try fixture.writeExecutableScript(
            """
            #!/bin/sh
            printf 'pastera-vault:\\n  Scope: User config\\n  Type: stdio\\n  Command: \(fixture.claudeHelperURL.path)\\n  Args:\\n  Environment:\\n'
            """,
            to: script
        )
        #expect(try runner.registration(executableURL: script, host: .claude) == .init(
            command: fixture.claudeHelperURL.path,
            arguments: [],
            userScoped: true
        ))

        try fixture.writeExecutableScript(
            """
            #!/bin/sh
            printf 'pastera-vault:\\n  Scope: User config\\n  Type: stdio\\n  Command: \(fixture.claudeHelperURL.path)\\n  Args:\\n  Environment:\\n    TOKEN=redacted\\n'
            """,
            to: script
        )
        #expect(try runner.registration(
            executableURL: script,
            host: .claude
        )?.hasAdditionalConfiguration == true)

        try fixture.writeExecutableScript(
            """
            #!/bin/sh
            printf '%s\\n' "Error: No MCP server named 'pastera-vault' found." >&2
            exit 1
            """,
            to: script
        )
        #expect(try runner.registration(executableURL: script, host: .codex) == nil)

        try fixture.writeExecutableScript("#!/bin/sh\nprintf 'unexpected\\n'\n", to: script)
        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try runner.registration(executableURL: script, host: .codex)
        }
    }

    private func expectPathChangeConflict() throws {
        let fixture = try InstallerFixture()
        _ = try fixture.installer().install(host: .codex)
        let movedHost = fixture.rootURL.appendingPathComponent("Applications/Codex2")
        try fixture.makeExecutable(movedHost)
        fixture.signingInspector.signatures[movedHost.path] = fixture.codexSignature
        let changed = fixture.installer(hostCandidates: [
            .init(host: .codex, urls: [movedHost]),
            .init(host: .claude, urls: [fixture.claudeURL])
        ])

        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try changed.install(host: .codex)
        }
        #expect(fixture.runner.invocations.count == 1)
    }

    private func expectRequirementChangeConflict() throws {
        let fixture = try InstallerFixture()
        _ = try fixture.installer().install(host: .codex)
        fixture.signingInspector.signatures[fixture.codexURL.path] = .init(
            identifier: fixture.codexSignature.identifier,
            designatedRequirement: "changed requirement",
            teamID: fixture.codexSignature.teamID,
            cdHash: fixture.codexSignature.cdHash,
            isAdHoc: false
        )

        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try fixture.installer().install(host: .codex)
        }
        #expect(fixture.runner.invocations.count == 1)
    }

    private func expectAdHocCDHashChangeConflict() throws {
        let fixture = try InstallerFixture()
        fixture.signingInspector.signatures[fixture.codexURL.path] = .init(
            identifier: fixture.codexSignature.identifier,
            designatedRequirement: fixture.codexSignature.designatedRequirement,
            teamID: nil,
            cdHash: Data([0xA1]),
            isAdHoc: true
        )
        _ = try fixture.installer().install(host: .codex)
        fixture.signingInspector.signatures[fixture.codexURL.path] = .init(
            identifier: fixture.codexSignature.identifier,
            designatedRequirement: fixture.codexSignature.designatedRequirement,
            teamID: nil,
            cdHash: Data([0xA2]),
            isAdHoc: true
        )

        #expect(throws: VaultAgentInstallerError.installationConflict) {
            _ = try fixture.installer().install(host: .codex)
        }
        #expect(fixture.runner.invocations.count == 1)
    }
}

private final class InstallerFixture {
    let rootURL: URL
    let userRootURL: URL
    let sourceSkillURL: URL
    let applicationURL: URL
    let codexURL: URL
    let codexHelperURL: URL
    let claudeURL: URL
    let claudeHelperURL: URL
    let cliHelperURL: URL
    let runner = InstallerCommandRunnerProbe()
    let signingInspector = InstallerSigningInspectorProbe()
    var authorizationStatuses: [VaultAgentClientKind: VaultAgentInstallerAuthorizationStatus] = [:]
    var authorizationRequests: [VaultAgentClientKind] = []

    var codexSignature: VaultAgentInstallerCodeSignature {
        .init(
            identifier: "com.openai.codex",
            designatedRequirement: "identifier com.openai.codex and anchor apple generic",
            teamID: "2DC432GLL2",
            cdHash: Data([0x11]),
            isAdHoc: false
        )
    }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraInstallerTests-\(UUID().uuidString)")
        userRootURL = rootURL.appendingPathComponent("user")
        sourceSkillURL = rootURL.appendingPathComponent("source/pastera-vault")
        applicationURL = rootURL.appendingPathComponent("Pastera.app")
        codexURL = rootURL.appendingPathComponent("Applications/Codex.app/Contents/MacOS/Codex")
        codexHelperURL = applicationURL
            .appendingPathComponent("Contents/Helpers/PasteraCodexMCP")
        claudeURL = rootURL.appendingPathComponent("Applications/Claude.app/Contents/MacOS/Claude")
        claudeHelperURL = applicationURL
            .appendingPathComponent("Contents/Helpers/PasteraClaudeMCP")
        cliHelperURL = applicationURL.appendingPathComponent("Contents/Helpers/pastera")

        try FileManager.default.createDirectory(
            at: userRootURL,
            withIntermediateDirectories: true
        )
        try writeSkillFixture()
        try makeExecutable(codexURL)
        try makeExecutable(codexHelperURL)
        try makeExecutable(claudeURL)
        try makeExecutable(claudeHelperURL)
        try makeExecutable(cliHelperURL)
        signingInspector.signatures[codexURL.resolvingSymlinksInPath().path] = codexSignature
        signingInspector.signatures[codexHelperURL.path] = .init(
            identifier: "com.pastera-app.PasteraCodexMCP",
            designatedRequirement: "identifier com.pastera-app.PasteraCodexMCP",
            teamID: nil,
            cdHash: Data([0x22]),
            isAdHoc: true
        )
        signingInspector.signatures[claudeURL.path] = .init(
            identifier: "com.anthropic.claudefordesktop",
            designatedRequirement: "identifier com.anthropic.claudefordesktop and anchor apple generic",
            teamID: "MLY3R8VXP8",
            cdHash: Data([0x33]),
            isAdHoc: false
        )
        signingInspector.signatures[claudeHelperURL.path] = .init(
            identifier: "com.pastera-app.PasteraClaudeMCP",
            designatedRequirement: "identifier com.pastera-app.PasteraClaudeMCP",
            teamID: nil,
            cdHash: Data([0x44]),
            isAdHoc: true
        )
        signingInspector.signatures[cliHelperURL.path] = .init(
            identifier: "com.pastera-app.pastera",
            designatedRequirement: "identifier com.pastera-app.pastera",
            teamID: nil,
            cdHash: Data([0x55]),
            isAdHoc: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func installer(
        hostCandidates: [VaultAgentHostCandidate]? = nil,
        environmentPath: String = "/usr/bin:/bin:/usr/sbin:/sbin",
        atomicWriteInterposer: @escaping (
            URL,
            VaultAgentAtomicWritePhase
        ) throws -> Void = { _, _ in },
        permissionDisposition: VaultAgentManagedPermissionDisposition = .unknown
    ) -> VaultAgentIntegrationInstaller {
        VaultAgentIntegrationInstaller(
            sourceSkillURL: sourceSkillURL,
            applicationURL: applicationURL,
            userRootURL: userRootURL,
            hostCandidates: hostCandidates ?? [
                .init(host: .codex, urls: [codexURL]),
                .init(host: .claude, urls: [claudeURL])
            ],
            currentUID: getuid(),
            signingInspector: signingInspector,
            commandRunner: runner,
            installationVersion: "1",
            environmentPathProvider: { environmentPath },
            atomicWriteInterposer: atomicWriteInterposer,
            managedPermissionDispositionProvider: { permissionDisposition },
            authorizationStatusProvider: { [weak self] client in
                guard let self else { return .unauthorized }
                self.authorizationRequests.append(client)
                return self.authorizationStatuses[client] ?? .unauthorized
            }
        )
    }

    var codexSkillURL: URL {
        userRootURL.appendingPathComponent(".agents/skills/pastera-vault/SKILL.md")
    }

    var claudeSkillURL: URL {
        userRootURL.appendingPathComponent(".claude/skills/pastera-vault/SKILL.md")
    }

    var manifestURL: URL {
        userRootURL.appendingPathComponent(
            "Library/Application Support/Pastera/Agent/v1/install-manifest.json"
        )
    }

    var cliLinkURL: URL {
        userRootURL.appendingPathComponent(".local/bin/pastera")
    }

    var claudeSettingsURL: URL {
        userRootURL.appendingPathComponent(".claude/settings.json")
    }

    func writeClaudeSettings(_ object: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: claudeSettingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: claudeSettingsURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: claudeSettingsURL.path
        )
    }

    func readClaudeSettings() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: claudeSettingsURL)
        ) as? [String: Any])
    }

    func hasPrivateClaudeBackup() throws -> Bool {
        let backupDirectory = userRootURL.appendingPathComponent(
            "Library/Application Support/Pastera/Agent/v1/backups"
        )
        let names = try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)
        guard let name = names.first(where: { $0.hasPrefix("claude-settings-") }) else {
            return false
        }
        return try permissions(of: backupDirectory.appendingPathComponent(name)) == 0o600
    }

    func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func writeSkillFixture() throws {
        let files = [
            ("SKILL.md", "---\nname: pastera-vault\ndescription: fixture\n---\n"),
            ("references/tool-contract.md", "# Tool contract\n"),
            ("references/security-boundary.md", "# Security boundary\n"),
            ("agents/openai.yaml", "interface:\n  display_name: \"Pastera Vault\"\n")
        ]
        for (relativePath, contents) in files {
            let url = sourceSkillURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }
    }

    func updateSourceSkill(_ contents: String) throws {
        try Data(contents.utf8).write(
            to: sourceSkillURL.appendingPathComponent("SKILL.md"),
            options: .atomic
        )
    }

    func makeExecutable(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xCA, 0xFE]).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func writeExecutableScript(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}

private struct InstallerCommandInvocation: Equatable {
    let executableURL: URL
    let arguments: [String]
}

private final class InstallerCommandRunnerProbe: VaultAgentHostCommandRunning {
    var invocations: [InstallerCommandInvocation] = []
    var registrations: [URL: VaultAgentHostRegistration] = [:]
    var handler: ((URL, [String]) throws -> Int32)?

    func run(executableURL: URL, arguments: [String]) throws -> Int32 {
        invocations.append(.init(executableURL: executableURL, arguments: arguments))
        let exitCode = try handler?(executableURL, arguments) ?? 0
        guard exitCode == 0 else { return exitCode }
        if arguments.prefix(2) == ["mcp", "add"],
           let separator = arguments.lastIndex(of: "--"),
           separator + 1 < arguments.count {
            registrations[executableURL] = .init(
                command: arguments[separator + 1],
                arguments: Array(arguments.dropFirst(separator + 2)),
                userScoped: true
            )
        } else if arguments == ["mcp", "remove", "pastera-vault"] {
            registrations[executableURL] = nil
        }
        return exitCode
    }

    func registration(
        executableURL: URL,
        host: VaultAgentHostKind
    ) throws -> VaultAgentHostRegistration? {
        registrations[executableURL]
    }
}

private final class InstallerSigningInspectorProbe: VaultAgentInstallerCodeSigningInspecting {
    var signatures: [String: VaultAgentInstallerCodeSignature] = [:]

    func inspect(executableURL: URL) throws -> VaultAgentInstallerCodeSignature {
        guard let signature = signatures[executableURL.path] else {
            throw InstallerProbeError.missingSignature
        }
        return signature
    }
}

private enum InstallerProbeError: Error {
    case missingSignature
    case injectedFailure
}

private func lstatExists(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0
}
// swiftlint:disable:this file_length
