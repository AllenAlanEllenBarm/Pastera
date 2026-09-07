//
//  PasteraPreferenceCatalog.swift
//
//  Pastera
//

import Foundation

enum PasteraPreferencePaneID: String, CaseIterable {
    case general
    case history
    case promptOptimization
    case scripts
    case shortcuts
    case passwordVault
    case excludedApps
    case agentIntegrations
    case sync
    case softwareUpdate
    case about
}

struct PasteraPreferenceSearchItem: Hashable {
    let id: String
    let paneID: PasteraPreferencePaneID
    let sectionID: String
    let anchorID: String
    let title: String
    let subtitle: String
    let keywords: [String]
}

protocol PasteraPreferencePage: AnyObject {
    var paneID: PasteraPreferencePaneID { get }
    var fillsAvailableHeight: Bool { get }

    func revealSetting(anchorID: String, animated: Bool) -> Bool
}

extension PasteraPreferencePage {
    var fillsAvailableHeight: Bool { false }
}

struct PasteraPreferenceCatalogPage: Equatable {
    let paneID: PasteraPreferencePaneID
    let groupTitle: String
    let title: String
    let symbolName: String
    let searchItems: [PasteraPreferenceSearchItem]
}

// swiftlint:disable:next type_body_length
struct PasteraPreferenceCatalog: Equatable {
    let pages: [PasteraPreferenceCatalogPage]

    static let `default` = PasteraPreferenceCatalog(
        pages: [
            PasteraPreferenceCatalogPage(
                paneID: .general,
                groupTitle: pasteraPreferenceString("Usage Preferences"),
                title: pasteraPreferenceString("General"),
                symbolName: "gearshape",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "general.launchAtLogin",
                        paneID: .general,
                        sectionID: "general.behavior",
                        anchorID: "general.launchAtLogin",
                        title: pasteraPreferenceString("Launch at Login"),
                        subtitle: pasteraPreferenceString("Start automatically after login."),
                        keywords: ["launch", "login", "startup"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "general.windowOpacity",
                        paneID: .general,
                        sectionID: "general.appearance",
                        anchorID: "general.windowOpacity",
                        title: pasteraPreferenceString("Menu Transparency"),
                        subtitle: pasteraPreferenceString(
                            "Adjust the transparency of the main menu and settings window."
                        ),
                        keywords: ["opacity", "transparency", "alpha"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "general.titleLength",
                        paneID: .general,
                        sectionID: "general.appearance",
                        anchorID: "general.titleLength",
                        title: pasteraPreferenceString("Menu Title Length"),
                        subtitle: pasteraPreferenceString(
                            "Limit the displayed length of history titles in the main menu."
                        ),
                        keywords: ["title", "length", "truncate"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "general.colorPreview",
                        paneID: .general,
                        sectionID: "general.appearance",
                        anchorID: "general.colorPreview",
                        title: pasteraPreferenceString("Color Preview"),
                        subtitle: pasteraPreferenceString(
                            "Control whether color content shows a preview swatch."
                        ),
                        keywords: ["color", "preview", "swatch"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "general.autoPaste",
                        paneID: .general,
                        sectionID: "general.behavior",
                        anchorID: "general.autoPaste",
                        title: pasteraPreferenceString("Automatic Paste"),
                        subtitle: pasteraPreferenceString(
                            "Paste immediately after choosing a history item."
                        ),
                        keywords: ["auto paste", "paste", "accessibility"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "general.pauseHotkeys",
                        paneID: .general,
                        sectionID: "general.behavior",
                        anchorID: "general.pauseHotkeys",
                        title: pasteraPreferenceString("Pause Shortcuts During Remote Control"),
                        subtitle: pasteraPreferenceString(
                            "Temporarily pause shortcuts during remote-control sessions."
                        ),
                        keywords: ["remote", "shortcut", "hotkey"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .history,
                groupTitle: pasteraPreferenceString("Usage Preferences"),
                title: pasteraPreferenceString("History & Preview"),
                symbolName: "clock.arrow.circlepath",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "history.imageLimit",
                        paneID: .history,
                        sectionID: "history.capacity",
                        anchorID: "history.imageLimit",
                        title: pasteraPreferenceString("Image History Limit"),
                        subtitle: pasteraPreferenceString(
                            "Limit the number of image items kept in history."
                        ),
                        keywords: [
                            "image limit",
                            "history images",
                            pasteraPreferenceString("Image Count")
                        ]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "history.fileLimit",
                        paneID: .history,
                        sectionID: "history.capacity",
                        anchorID: "history.fileLimit",
                        title: pasteraPreferenceString("File History Limit"),
                        subtitle: pasteraPreferenceString(
                            "Limit the number of file items kept in history."
                        ),
                        keywords: ["file limit", "history files"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "history.duplicatePolicy",
                        paneID: .history,
                        sectionID: "history.content",
                        anchorID: "history.duplicatePolicy",
                        title: pasteraPreferenceString("Duplicate Policy"),
                        subtitle: pasteraPreferenceString(
                            "Control how repeated clipboard content is retained."
                        ),
                        keywords: ["duplicate", "dedupe", "repeat"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "history.savedTypes",
                        paneID: .history,
                        sectionID: "history.content",
                        anchorID: "history.savedTypes",
                        title: pasteraPreferenceString("Stored Types"),
                        subtitle: pasteraPreferenceString(
                            "Choose which content types are saved in history."
                        ),
                        keywords: ["types", "store types", "history types"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "history.previewTypes",
                        paneID: .history,
                        sectionID: "history.preview",
                        anchorID: "history.previewTypes",
                        title: pasteraPreferenceString("File Preview Types"),
                        subtitle: pasteraPreferenceString(
                            "Control previews for file and media content."
                        ),
                        keywords: ["preview", "prévisualisation"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "history.clearAll",
                        paneID: .history,
                        sectionID: "history.danger",
                        anchorID: "history.clearAll",
                        title: pasteraPreferenceString("Clear History"),
                        subtitle: pasteraPreferenceString("Delete all history stored on this device."),
                        keywords: ["clear", "delete history", "danger"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .promptOptimization,
                groupTitle: pasteraPreferenceString("Usage Preferences"),
                title: pasteraScriptString("Prompt Optimization", "提示词优化"),
                symbolName: "wand.and.stars",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "promptOptimization.configuration",
                        paneID: .promptOptimization,
                        sectionID: "promptOptimization.configuration",
                        anchorID: "promptOptimization.configuration",
                        title: pasteraScriptString("Prompt Optimization", "提示词优化"),
                        subtitle: pasteraScriptString(
                            "Improve history prompts locally or with your own compatible model.",
                            "在本机或通过自备兼容模型美化历史提示词。"
                        ),
                        keywords: [
                            "prompt", "optimization", "优化", "美化", "model",
                            "OpenAI", "Gemini", "Ollama", "LM Studio"
                        ]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .scripts,
                groupTitle: pasteraPreferenceString("Usage Preferences"),
                title: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "脚本" : pasteraPreferenceString("Scripts"),
                symbolName: "curlybraces.square",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "scripts.list",
                        paneID: .scripts,
                        sectionID: "scripts.list",
                        anchorID: "scripts.list",
                        title: pasteraPreferenceString("Script Transforms"),
                        subtitle: pasteraPreferenceString("Transform plain-text clipboard content with local JavaScript."),
                        keywords: ["script", "javascript", "transform", "clipboard"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "scripts.shortcut",
                        paneID: .scripts,
                        sectionID: "scripts.shortcut",
                        anchorID: "scripts.shortcut",
                        title: pasteraPreferenceString("Manual Script Shortcut"),
                        subtitle: pasteraPreferenceString("Run enabled manual scripts on the current clipboard."),
                        keywords: ["script", "manual", "shortcut", "hotkey"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "scripts.test",
                        paneID: .scripts,
                        sectionID: "scripts.test",
                        anchorID: "scripts.test",
                        title: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "测试脚本" : "Test Script",
                        subtitle: Locale.preferredLanguages.first?.hasPrefix("zh") == true
                            ? "使用示例文本预览已保存脚本的输出。"
                            : "Preview a saved script with sample text.",
                        keywords: ["script", "test", "preview", "output"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .shortcuts,
                groupTitle: pasteraPreferenceString("Usage Preferences"),
                title: pasteraPreferenceString("Shortcuts"),
                symbolName: "keyboard",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "shortcuts.menu",
                        paneID: .shortcuts,
                        sectionID: "shortcuts.menu",
                        anchorID: "shortcuts.menu",
                        title: pasteraPreferenceString("Menu Shortcuts"),
                        subtitle: pasteraPreferenceString(
                            "Configure shortcuts for opening and switching the main menu."
                        ),
                        keywords: ["menu shortcut", "keyboard", "hotkey"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "shortcuts.historyPanel",
                        paneID: .shortcuts,
                        sectionID: "shortcuts.historyPanel",
                        anchorID: "shortcuts.historyPanel",
                        title: pasteraPreferenceString("History Panel Shortcuts"),
                        subtitle: pasteraPreferenceString(
                            "Configure search, paging, and switching shortcuts for the history panel."
                        ),
                        keywords: ["history panel", "shortcut", "keyboard"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .passwordVault,
                groupTitle: pasteraPreferenceString("Usage Preferences"),
                title: pasteraPreferenceString("Password Vault"),
                symbolName: "lock.shield",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "vault.autoLock",
                        paneID: .passwordVault,
                        sectionID: "vault.locking",
                        anchorID: "vault.autoLock",
                        title: pasteraPreferenceString("Automatic Lock"),
                        subtitle: pasteraPreferenceString(
                            "Lock the password vault automatically after a period of inactivity."
                        ),
                        keywords: ["vault", "password vault", "auto lock", "自动锁定", "密码箱"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "vault.systemUnlock",
                        paneID: .passwordVault,
                        sectionID: "vault.locking",
                        anchorID: "vault.systemUnlock",
                        title: pasteraPreferenceString("System Unlock"),
                        subtitle: pasteraPreferenceString(
                            "Use Touch ID, Apple Watch, or the Mac login password to unlock on this Mac."
                        ),
                        keywords: [
                            "vault", "system unlock", "Mac password", "login password",
                            "Mac 登录密码", "系统解锁", "密码箱"
                        ]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "vault.masterPassword",
                        paneID: .passwordVault,
                        sectionID: "vault.masterPassword",
                        anchorID: "vault.masterPassword",
                        title: pasteraPreferenceString("Reset Master Password"),
                        subtitle: pasteraPreferenceString(
                            "Reset the master password after this Mac authenticates you."
                        ),
                        keywords: [
                            "vault", "master password", "reset password", "forgot password",
                            "忘记密码", "重置密码", "主密码", "密码箱"
                        ]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "vault.forceReset",
                        paneID: .passwordVault,
                        sectionID: "vault.recovery",
                        anchorID: "vault.forceReset",
                        title: pasteraPreferenceString("Force Reset Password Vault"),
                        subtitle: pasteraPreferenceString(
                            "Create a new empty vault while retaining one latest encrypted archive."
                        ),
                        keywords: [
                            "vault", "force reset", "forgot password", "强制重置", "忘记密码", "密码箱"
                        ]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .excludedApps,
                groupTitle: pasteraPreferenceString("Usage Preferences"),
                title: pasteraPreferenceString("Excluded Apps"),
                symbolName: "app.badge.checkmark",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "excludedApps.list",
                        paneID: .excludedApps,
                        sectionID: "excludedApps.rules",
                        anchorID: "exclude.apps",
                        title: pasteraPreferenceString("Excluded Applications List"),
                        subtitle: pasteraPreferenceString(
                            "Disable clipboard recording for selected applications."
                        ),
                        keywords: ["exclude", "ignored apps", "blacklist"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .agentIntegrations,
                groupTitle: pasteraPreferenceString("Services & Support"),
                title: pasteraPreferenceString("Agent Integrations"),
                symbolName: "terminal",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "agents.codex",
                        paneID: .agentIntegrations,
                        sectionID: "agents.clients",
                        anchorID: "agents.codex",
                        title: pasteraPreferenceString("Codex Integration"),
                        subtitle: pasteraPreferenceString("Install and authorize the password vault tools for Codex."),
                        keywords: ["codex", "mcp", "agent"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "agents.claude",
                        paneID: .agentIntegrations,
                        sectionID: "agents.clients",
                        anchorID: "agents.claude",
                        title: pasteraPreferenceString("Claude Code Integration"),
                        subtitle: pasteraPreferenceString("Install and authorize the password vault tools for Claude Code."),
                        keywords: ["claude", "mcp", "agent"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "agents.cli",
                        paneID: .agentIntegrations,
                        sectionID: "agents.clients",
                        anchorID: "agents.cli",
                        title: pasteraPreferenceString("Pastera CLI"),
                        subtitle: pasteraPreferenceString("Install and authorize the local password vault command line tool."),
                        keywords: ["cli", "terminal", "command line"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "agents.authorization",
                        paneID: .agentIntegrations,
                        sectionID: "agents.authorization",
                        anchorID: "agents.authorization",
                        title: pasteraPreferenceString("Agent Authorization"),
                        subtitle: pasteraPreferenceString("Review the idle and hard expiration boundaries for each client."),
                        keywords: ["authorization", "expiry", "grant"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .sync,
                groupTitle: pasteraPreferenceString("Services & Support"),
                title: pasteraPreferenceString("Sync"),
                symbolName: "icloud",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "sync.oneDriveStatus",
                        paneID: .sync,
                        sectionID: "sync.account",
                        anchorID: "sync.oneDriveStatus",
                        title: pasteraPreferenceString("OneDrive Status"),
                        subtitle: pasteraPreferenceString(
                            "Show availability and current authorization status."
                        ),
                        keywords: ["onedrive", "status", "cloud"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "sync.rootFolder",
                        paneID: .sync,
                        sectionID: "sync.account",
                        anchorID: "sync.rootFolder",
                        title: pasteraPreferenceString("Sync Location"),
                        subtitle: pasteraPreferenceString("Choose the OneDrive folder used for sync."),
                        keywords: ["sync folder", "sync root", "cloud folder"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "sync.fileTypes",
                        paneID: .sync,
                        sectionID: "sync.scope",
                        anchorID: "sync.fileTypes",
                        title: pasteraPreferenceString("File Type Sync"),
                        subtitle: pasteraPreferenceString(
                            "Control which history content types participate in sync."
                        ),
                        keywords: ["sync types", "history sync", "snippet sync"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "sync.actions",
                        paneID: .sync,
                        sectionID: "sync.actions",
                        anchorID: "sync.actions",
                        title: pasteraPreferenceString("Manual Sync and Transfer Directions"),
                        subtitle: pasteraPreferenceString(
                            "Run sync now and control upload and import separately."
                        ),
                        keywords: ["manual sync", "upload", "import"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .softwareUpdate,
                groupTitle: pasteraPreferenceString("Services & Support"),
                title: pasteraPreferenceString("Software Update"),
                symbolName: "arrow.triangle.2.circlepath",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "softwareUpdate.checkNow",
                        paneID: .softwareUpdate,
                        sectionID: "softwareUpdate.currentVersion",
                        anchorID: "softwareUpdate.currentVersion",
                        title: pasteraPreferenceString("Current Version"),
                        subtitle: pasteraPreferenceString("Show the installed version and check for updates."),
                        keywords: [
                            "version", "build", "update", "software update",
                            "check for updates", "更新", "检查更新"
                        ]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "softwareUpdate.automaticCheck",
                        paneID: .softwareUpdate,
                        sectionID: "softwareUpdate.automaticCheck",
                        anchorID: "softwareUpdate.automaticCheck",
                        title: pasteraPreferenceString("Automatically Check for Updates"),
                        subtitle: pasteraPreferenceString("Choose whether and how often Pastera checks for updates."),
                        keywords: [
                            "automatic update", "frequency", "daily", "自动更新", "自动检查更新"
                        ]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "softwareUpdate.lastCheck",
                        paneID: .softwareUpdate,
                        sectionID: "softwareUpdate.lastCheck",
                        anchorID: "softwareUpdate.lastCheck",
                        title: pasteraPreferenceString("Last Check"),
                        subtitle: pasteraPreferenceString("Review the last check time and release history."),
                        keywords: ["last check", "release notes", "update history"]
                    )
                ]
            ),
            PasteraPreferenceCatalogPage(
                paneID: .about,
                groupTitle: pasteraPreferenceString("Services & Support"),
                title: pasteraPreferenceString("About Pastera"),
                symbolName: "info.circle",
                searchItems: [
                    PasteraPreferenceSearchItem(
                        id: "about.version",
                        paneID: .about,
                        sectionID: "about.app",
                        anchorID: "about.version",
                        title: pasteraPreferenceString("Application Icon and Version"),
                        subtitle: pasteraPreferenceString(
                            "Show the application icon, version, and build number."
                        ),
                        keywords: ["version", "build", "about"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "about.github",
                        paneID: .about,
                        sectionID: "about.links",
                        anchorID: "about.github",
                        title: pasteraPreferenceString("GitHub"),
                        subtitle: pasteraPreferenceString("Open the project repository."),
                        keywords: ["repository", "source", "website"]
                    ),
                    PasteraPreferenceSearchItem(
                        id: "about.license",
                        paneID: .about,
                        sectionID: "about.license",
                        anchorID: "about.license",
                        title: pasteraPreferenceString("MIT License"),
                        subtitle: pasteraPreferenceString("View application license information."),
                        keywords: ["license", "legal"]
                    )
                ]
            )
        ]
    )
}
