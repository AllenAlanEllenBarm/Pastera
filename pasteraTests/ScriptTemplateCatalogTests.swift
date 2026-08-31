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

    @Test
    func everyBundledTemplateExecutesWithRepresentativeInput() async {
        let templatesByID = Dictionary(
            uniqueKeysWithValues: ScriptTemplateCatalog.default.templates.map { ($0.id, $0) }
        )
        let coveredTemplateIDs = Set(templateExecutionCases.map(\.id))
        let service = ScriptExecutionService(timeout: 0.5)

        #expect(Set(templatesByID.keys) == coveredTemplateIDs)

        for executionCase in templateExecutionCases {
            guard let template = templatesByID[executionCase.id] else {
                Issue.record("Missing bundled template \(executionCase.id)")
                continue
            }
            let result = await service.execute(
                scripts: [template.makeDraft(now: 100)],
                input: ScriptExecutionInput(
                    text: executionCase.input,
                    sourceAppBundleIdentifier: "com.pastera.tests"
                )
            )

            #expect(
                result == .success(executionCase.expectedOutput),
                "Bundled template \(executionCase.id) returned \(String(describing: result))"
            )
        }
    }
}

private struct TemplateExecutionCase: Sendable {
    let id: String
    let input: String
    let expectedOutput: String
}

private let templateExecutionCases = [
    TemplateExecutionCase(id: "plain-text", input: " Hello 世界 ", expectedOutput: " Hello 世界 "),
    TemplateExecutionCase(id: "uppercase", input: "Hello World", expectedOutput: "HELLO WORLD"),
    TemplateExecutionCase(id: "lowercase", input: "Hello WORLD", expectedOutput: "hello world"),
    TemplateExecutionCase(
        id: "format-json",
        input: #"{"hello":"world","values":[1,2]}"#,
        expectedOutput: """
        {
          "hello": "world",
          "values": [
            1,
            2
          ]
        }
        """
    ),
    TemplateExecutionCase(
        id: "minify-json",
        input: """
        {
          "hello": "world"
        }
        """,
        expectedOutput: #"{"hello":"world"}"#
    ),
    TemplateExecutionCase(
        id: "remove-blank-lines",
        input: "first\n\n \t\nsecond",
        expectedOutput: "first\nsecond"
    ),
    TemplateExecutionCase(
        id: "date-to-timestamp",
        input: "1970-01-01T00:00:01Z",
        expectedOutput: "1000"
    ),
    TemplateExecutionCase(
        id: "extract-email",
        input: "a@example.com and b.test+tag@example.co.uk",
        expectedOutput: "a@example.com\nb.test+tag@example.co.uk"
    ),
    TemplateExecutionCase(
        id: "extract-url",
        input: "Visit https://example.com/a?q=1 then http://test.local/path",
        expectedOutput: "https://example.com/a?q=1\nhttp://test.local/path"
    ),
    TemplateExecutionCase(
        id: "extract-phone",
        input: "Call 13800138000 or 19912345678",
        expectedOutput: "13800138000\n19912345678"
    ),
    TemplateExecutionCase(
        id: "extract-ip",
        input: "IPs 192.168.1.1 and 10.0.0.8",
        expectedOutput: "192.168.1.1\n10.0.0.8"
    ),
    TemplateExecutionCase(
        id: "base64-encode",
        input: "Pastera 世界",
        expectedOutput: "UGFzdGVyYSDkuJbnlYw="
    ),
    TemplateExecutionCase(
        id: "base64-decode",
        input: "UGFzdGVyYSDkuJbnlYw=",
        expectedOutput: "Pastera 世界"
    )
]
