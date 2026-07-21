//
//  PreferenceSearchTests.swift
//
//  Pastera
//

import Foundation
import Testing
@testable import Pastera

// The fixed preference catalog assertions intentionally remain together.
// swiftlint:disable:next type_body_length
struct PreferenceSearchTests {
    private let catalog = PasteraPreferenceCatalog.default

    private final class StubPreferencePage: PasteraPreferencePage {
        let paneID: PasteraPreferencePaneID
        private(set) var revealedAnchors: [(String, Bool)] = []

        init(paneID: PasteraPreferencePaneID) {
            self.paneID = paneID
        }

        func revealSetting(anchorID: String, animated: Bool) -> Bool {
            revealedAnchors.append((anchorID, animated))
            return anchorID == "stub.anchor"
        }
    }

    @Test
    func preferenceSearchFindsPromptOptimization() throws {
        let item = try #require(catalog.pages.flatMap(\.searchItems).first {
            $0.id == "scripts.promptOptimization"
        })

        #expect(item.paneID == .scripts)
        #expect(item.anchorID == "scripts.promptOptimization")
        #expect(item.keywords.contains("OpenAI"))
        #expect(item.keywords.contains("Ollama"))
        #expect(PasteraPreferenceSearch(catalog: catalog).search("美化").contains { page in
            page.paneID == .scripts && page.searchItems.contains(item)
        })
    }

    @Test
    func paneIDDefinesExactFixedCases() {
        #expect(PasteraPreferencePaneID.allCases == [
            .general,
            .history,
            .scripts,
            .shortcuts,
            .excludedApps,
            .agentIntegrations,
            .sync,
            .softwareUpdate,
            .about
        ])
        #expect(PasteraPreferencePaneID.allCases.map(\.rawValue) == [
            "general",
            "history",
            "scripts",
            "shortcuts",
            "excludedApps",
            "agentIntegrations",
            "sync",
            "softwareUpdate",
            "about"
        ])
    }

    @Test
    func protocolContractSupportsClassBackedPages() {
        let page = StubPreferencePage(paneID: .sync)

        #expect(page.paneID == .sync)
        #expect(page.revealSetting(anchorID: "stub.anchor", animated: true))
        #expect(page.revealedAnchors.map(\.0) == ["stub.anchor"])
        #expect(page.revealedAnchors.map(\.1) == [true])
    }

    @Test
    func catalogDefinesFixedPageOrderGroupsIconsAndItemOwnership() {
        let pages = catalog.pages

        #expect(pages.map(\.paneID) == [
            .general,
            .history,
            .scripts,
            .shortcuts,
            .excludedApps,
            .agentIntegrations,
            .sync,
            .softwareUpdate,
            .about
        ])
        #expect(pages.map(\.groupTitle) == [
            pasteraPreferenceString("Usage Preferences"),
            pasteraPreferenceString("Usage Preferences"),
            pasteraPreferenceString("Usage Preferences"),
            pasteraPreferenceString("Usage Preferences"),
            pasteraPreferenceString("Usage Preferences"),
            pasteraPreferenceString("Services & Support"),
            pasteraPreferenceString("Services & Support"),
            pasteraPreferenceString("Services & Support"),
            pasteraPreferenceString("Services & Support")
        ])
        #expect(pages.map(\.title) == [
            pasteraPreferenceString("General"),
            pasteraPreferenceString("History & Preview"),
            pasteraPreferenceString("Scripts"),
            pasteraPreferenceString("Shortcuts"),
            pasteraPreferenceString("Excluded Apps"),
            pasteraPreferenceString("Agent Integrations"),
            pasteraPreferenceString("Sync"),
            pasteraPreferenceString("Software Update"),
            pasteraPreferenceString("About Pastera")
        ])
        #expect(pages.map(\.symbolName) == [
            "gearshape",
            "clock.arrow.circlepath",
            "curlybraces.square",
            "keyboard",
            "app.badge.checkmark",
            "terminal",
            "icloud",
            "arrow.triangle.2.circlepath",
            "info.circle"
        ])

        for page in pages {
            for item in page.searchItems {
                #expect(!item.id.isEmpty)
                #expect(item.paneID == page.paneID)
                #expect(!item.sectionID.isEmpty)
                #expect(!item.anchorID.isEmpty)
                #expect(!item.title.isEmpty)
                #expect(!item.subtitle.isEmpty)
            }
        }
    }

    @Test
    func catalogItemsHaveStableUniqueIDsAndUniqueAnchors() {
        let items = catalog.pages.flatMap(\.searchItems)
        let itemIDs = items.map(\.id)
        let anchorIDs = items.map(\.anchorID)

        #expect(!items.isEmpty)
        #expect(Set(itemIDs).count == itemIDs.count)
        #expect(Set(anchorIDs).count == anchorIDs.count)
    }

    @Test
    func searchPrefersTitleMatchesBeforeSubtitleAndKeywords() throws {
        let results = PasteraPreferenceSearch(catalog: catalog).search("onedrive")
        let syncPage = try #require(results.first { $0.paneID == .sync })

        #expect(Array(syncPage.searchItems.prefix(2).map(\.title)) == [
            pasteraPreferenceString("OneDrive Status"),
            pasteraPreferenceString("Sync Location")
        ])
    }

    @Test
    func searchGroupsMatchesByPageAndRanksItemsByRelevance() {
        let results = PasteraPreferenceSearch(catalog: catalog).search("shortcut")

        #expect(results.map(\.paneID) == [.general, .scripts, .shortcuts])
        #expect(results[0].searchItems.map(\.title) == [
            pasteraPreferenceString("Pause Shortcuts During Remote Control")
        ])
        #expect(results[1].searchItems.map(\.title) == [
            pasteraPreferenceString("Manual Script Shortcut")
        ])
        #expect(results[2].searchItems.map(\.title) == [
            pasteraPreferenceString("History Panel Shortcuts"),
            pasteraPreferenceString("Menu Shortcuts")
        ])
    }

    @Test
    func searchSupportsCaseInsensitiveDiacriticInsensitiveAndChineseQueries() {
        let search = PasteraPreferenceSearch(catalog: catalog)
        let diacriticCatalog = PasteraPreferenceCatalog(
            pages: [
                PasteraPreferenceCatalogPage(
                    paneID: .history,
                    groupTitle: "使用偏好",
                    title: "历史与预览",
                    symbolName: "clock.arrow.circlepath",
                    searchItems: [
                        PasteraPreferenceSearchItem(
                            id: "history.preview.resumeOnly",
                            paneID: .history,
                            sectionID: "history.preview",
                            anchorID: "history.preview.resumeOnly",
                            title: "Résumé",
                            subtitle: "仅限重音文本",
                            keywords: []
                        ),
                        PasteraPreferenceSearchItem(
                            id: "history.preview.chinese",
                            paneID: .history,
                            sectionID: "history.preview",
                            anchorID: "history.preview.chinese",
                            title: "文件预览类型",
                            subtitle: "控制文件内容的预览方式。",
                            keywords: []
                        )
                    ]
                )
            ]
        )
        let diacriticSearch = PasteraPreferenceSearch(catalog: diacriticCatalog)

        let oneDriveResults = search.search("ONEDRIVE")
        let previewResults = diacriticSearch.search("resume")
        let chineseResults = diacriticSearch.search("预览")

        #expect(oneDriveResults.contains(where: { page in
            page.paneID == .sync && page.searchItems.contains(where: {
                $0.title == pasteraPreferenceString("OneDrive Status")
            })
        }))
        #expect(previewResults.contains(where: { page in
            page.paneID == .history && page.searchItems.contains(where: { $0.title == "Résumé" })
        }))
        #expect(chineseResults.contains(where: { page in
            page.paneID == .history && page.searchItems.contains(where: { $0.title == "文件预览类型" })
        }))
    }

    @Test
    func imageCountAliasFindsTheImageHistoryLimit() throws {
        let results = PasteraPreferenceSearch(catalog: catalog).search("图片数量")
        let historyPage = try #require(results.first { $0.paneID == .history })

        #expect(historyPage.searchItems.map(\.id) == ["history.imageLimit"])
        #expect(historyPage.searchItems.first?.anchorID == "history.imageLimit")
    }

    @Test
    func searchDoesNotFallbackToPageTitleWithoutItemMatch() {
        let pageOnlyCatalog = PasteraPreferenceCatalog(
            pages: [
                PasteraPreferenceCatalogPage(
                    paneID: .about,
                    groupTitle: "Group",
                    title: "Container-Only Token",
                    symbolName: "info.circle",
                    searchItems: [
                        PasteraPreferenceSearchItem(
                            id: "about.item",
                            paneID: .about,
                            sectionID: "about.section",
                            anchorID: "about.anchor",
                            title: "Unrelated Item",
                            subtitle: "Different description",
                            keywords: []
                        )
                    ]
                )
            ]
        )
        let results = PasteraPreferenceSearch(catalog: pageOnlyCatalog).search("Container-Only Token")

        #expect(results.isEmpty)
    }

    @Test
    func searchReturnsNoResultsForEmptyOrUnknownQueries() {
        let search = PasteraPreferenceSearch(catalog: catalog)

        #expect(search.search("").isEmpty)
        #expect(search.search("   ").isEmpty)
        #expect(search.search("zz-not-found-zz").isEmpty)
    }

    @Test
    func preferenceStringCatalogProvidesEverySupportedLocalization() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repositoryURL
            .appendingPathComponent("pastera/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let document = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(document["sourceLanguage"] as? String == "en")

        let strings = try #require(document["strings"] as? [String: Any])
        let sourcePaths = preferenceSourcePaths.map { repositoryURL.appendingPathComponent($0) }
        let preferenceKeys = try localizationKeys(in: sourcePaths)
        #expect(preferenceKeys.count >= 100)

        let supportedLanguages = ["en", "de", "it", "ja", "zh-Hans"]
        for key in preferenceKeys {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in supportedLanguages {
                let localization = try #require(localizations[language] as? [String: Any])
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
                let value = try #require(stringUnit["value"] as? String)
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }

        let semanticTranslations: [String: [String: String]] = [
            "History Panel Shortcuts": [
                "de": "Kurzbefehle für Verlaufsfenster",
                "it": "Scorciatoie del pannello cronologia",
                "ja": "履歴パネルのショートカット",
                "zh-Hans": "历史面板快捷键"
            ],
            "Releases": [
                "de": "Versionen",
                "it": "Versioni",
                "ja": "リリース",
                "zh-Hans": "版本发布"
            ],
            "Issues": [
                "de": "Probleme",
                "it": "Segnalazioni",
                "ja": "問題",
                "zh-Hans": "问题反馈"
            ],
            "Menu Shortcuts": [
                "de": "Menü-Kurzbefehle",
                "it": "Scorciatoie del menu",
                "ja": "メニューのショートカット",
                "zh-Hans": "菜单快捷键"
            ],
            "Previous Page": [
                "de": "Vorherige Seite",
                "it": "Pagina precedente",
                "ja": "前のページ",
                "zh-Hans": "上一页"
            ],
            "Next Page": [
                "de": "Nächste Seite",
                "it": "Pagina successiva",
                "ja": "次のページ",
                "zh-Hans": "下一页"
            ],
            "Search": [
                "de": "Suchen",
                "it": "Cerca",
                "ja": "検索",
                "zh-Hans": "搜索"
            ],
            "Transparency": [
                "de": "Transparenz",
                "it": "Trasparenza",
                "ja": "透明度",
                "zh-Hans": "透明度"
            ]
        ]
        for (key, expectedValues) in semanticTranslations {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for (language, expectedValue) in expectedValues {
                let localization = try #require(localizations[language] as? [String: Any])
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
                #expect(stringUnit["value"] as? String == expectedValue)
            }
        }
    }

    @Test
    func nativePreferenceSourcesDoNotConstructVisibleControlsFromLiterals() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let visibleLiteralPattern = try NSRegularExpression(
            pattern: #"(?:title|labelWithString|checkboxWithTitle|text|setAccessibilityLabel)\s*:\s*\"(?!\")[^\"]+\""#
        )

        for relativePath in preferenceSourcePaths {
            let source = try String(
                contentsOf: repositoryURL.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            let range = NSRange(source.startIndex..., in: source)
            #expect(
                visibleLiteralPattern.firstMatch(in: source, range: range) == nil,
                "Visible string literal remains in \(relativePath)"
            )
        }
    }

    @Test
    func legacyPreferencePagesAndResourcesAreAbsent() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: repositoryURL.appendingPathComponent("pastera.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let preferencesURL = repositoryURL.appendingPathComponent("pastera/Sources/Preferences")
        let sourceFiles = try FileManager.default.subpathsOfDirectory(atPath: preferencesURL.path)
            .filter { $0.hasSuffix(".swift") }
        let preferenceSources = try sourceFiles.map {
            try String(contentsOf: preferencesURL.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")

        let legacyTypeController = ["CPY", "Type", "PreferenceViewController"].joined()
        let legacyUpdatesController = ["CPY", "Updates", "PreferenceViewController"].joined()
        let legacyAlignment = ["PasteraPreferencePane", "AlignmentAdapter"].joined()
        let legacyNormalizer = ["PasteraPreferencePane", "LayoutNormalizer"].joined()
        let legacyAdapter = ["Pastera", "LegacyPreferencePageAdapter"].joined()
        for token in [
            legacyTypeController,
            legacyUpdatesController,
            legacyAlignment,
            legacyNormalizer,
            legacyAdapter
        ] {
            #expect(!project.contains(token))
            #expect(!preferenceSources.contains(token))
        }

        let removedResourceNames = [
            ["CPYPreferencesWindowController", "xib"].joined(separator: "."),
            ["CPYGeneralPreferenceViewController", "xib"].joined(separator: "."),
            ["CPYExcludeAppPreferenceViewController", "xib"].joined(separator: "."),
            ["CPYShortcutsPreferenceViewController", "xib"].joined(separator: "."),
            [legacyTypeController, "xib"].joined(separator: "."),
            [legacyUpdatesController, "xib"].joined(separator: ".")
        ]
        for resourceName in removedResourceNames {
            #expect(!project.contains(resourceName))
            let matches = try FileManager.default.subpathsOfDirectory(atPath: preferencesURL.path)
                .filter { $0.hasSuffix(resourceName) }
            #expect(matches.isEmpty)
        }
    }

    private var preferenceSourcePaths: [String] {
        [
            "pastera/Sources/Preferences/PasteraPreferenceCatalog.swift",
            "pastera/Sources/Preferences/PasteraPreferenceSearchResultsViewController.swift",
            "pastera/Sources/Preferences/CPYPreferencesWindowController.swift",
            "pastera/Sources/Preferences/Panels/CPYGeneralPreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/CPYHistoryPreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/CPYExcludeAppPreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/CPYAgentIntegrationPreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/CPYSoftwareUpdatePreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/CPYAboutPreferenceViewController.swift",
            "pastera/Sources/Preferences/Panels/PasteraOneDriveStatusBadge.swift"
        ]
    }

    private func localizationKeys(in sourceURLs: [URL]) throws -> Set<String> {
        let patterns = [
            #"(?:pasteraPreferenceString|localizedGeneralPreferenceString)\(\s*\"([^\"]+)\""#,
            #"String\(localized:\s*\"([^\"]+)\""#
        ]
        let expressions = try patterns.map { try NSRegularExpression(pattern: $0) }
        var keys = Set<String>()

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let sourceRange = NSRange(source.startIndex..., in: source)
            for expression in expressions {
                for match in expression.matches(in: source, range: sourceRange) {
                    guard
                        let range = Range(match.range(at: 1), in: source)
                    else { continue }
                    keys.insert(String(source[range]))
                }
            }
        }
        return keys
    }
}
