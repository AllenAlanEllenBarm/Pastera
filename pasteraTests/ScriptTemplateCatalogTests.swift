import Testing
@testable import Pastera

struct ScriptTemplateCatalogTests {
    @Test
    func catalogContainsRequiredOfflineTemplates() {
        #expect(Set(ScriptTemplateCatalog.default.templates.map(\.id)) == [
            "plain-text", "uppercase", "lowercase", "format-json", "minify-json",
            "remove-blank-lines", "date-to-timestamp", "extract-email", "extract-url",
            "extract-phone", "extract-ip", "base64-encode", "base64-decode"
        ])
    }

    @Test
    func templateSearchMatchesNameAndCategory() {
        let catalog = ScriptTemplateCatalog.default

        #expect(catalog.search(query: "JSON", category: .all).map(\.id) == [
            "format-json", "minify-json"
        ])
        #expect(catalog.search(query: "", category: .extract).allSatisfy { template in
            template.category == .extract
        })
    }

    @Test
    func templateDraftGetsFreshIdentity() throws {
        let template = try #require(ScriptTemplateCatalog.default.templates.first)

        #expect(template.makeDraft(now: 100).id != template.makeDraft(now: 100).id)
    }
}
