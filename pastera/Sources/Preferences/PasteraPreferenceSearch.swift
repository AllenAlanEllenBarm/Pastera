//
//  PasteraPreferenceSearch.swift
//
//  Pastera
//

import Foundation

struct PasteraPreferenceSearch {
    let catalog: PasteraPreferenceCatalog

    init(catalog: PasteraPreferenceCatalog = .default) {
        self.catalog = catalog
    }

    func search(_ rawQuery: String) -> [PasteraPreferenceCatalogPage] {
        let query = normalized(rawQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return catalog.pages.compactMap { page in
            let rankedItems = page.searchItems.enumerated().compactMap { index, item -> (Int, Int, PasteraPreferenceSearchItem)? in
                guard let score = score(for: query, item: item) else {
                    return nil
                }
                return (score, index, item)
            }

            guard !rankedItems.isEmpty else {
                return nil
            }

            let sortedItems = rankedItems
                .sorted { lhs, rhs in
                    if lhs.0 != rhs.0 {
                        return lhs.0 > rhs.0
                    }
                    return lhs.1 < rhs.1
                }
                .map(\.2)

            return PasteraPreferenceCatalogPage(
                paneID: page.paneID,
                groupTitle: page.groupTitle,
                title: page.title,
                symbolName: page.symbolName,
                searchItems: sortedItems
            )
        }
    }
}

private extension PasteraPreferenceSearch {
    var normalizationLocale: Locale {
        Locale(identifier: "en_US_POSIX")
    }

    func score(for query: String, item: PasteraPreferenceSearchItem) -> Int? {
        let titleScore = matchScore(query: query, text: item.title, base: 300) ?? 0
        let subtitleScore = matchScore(query: query, text: item.subtitle, base: 200) ?? 0
        let keywordScore = item.keywords
            .compactMap { matchScore(query: query, text: $0, base: 100) }
            .max() ?? 0

        let bestScore = max(titleScore, subtitleScore, keywordScore)
        return bestScore == 0 ? nil : bestScore
    }

    func matchScore(query: String, text: String, base: Int) -> Int? {
        let candidate = normalized(text)
        guard !candidate.isEmpty, candidate.contains(query) else {
            return nil
        }
        if candidate == query {
            return base + 40
        }
        if candidate.hasPrefix(query) {
            return base + 20
        }
        return base
    }

    func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: normalizationLocale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
