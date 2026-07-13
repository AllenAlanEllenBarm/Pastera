import Foundation

struct ScriptTemplateCatalog {
    let templates: [ScriptTemplate]

    func search(query: String, category: ScriptTemplateCategory) -> [ScriptTemplate] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return templates.filter { template in
            let matchesCategory = category == .all || template.category == category
            guard matchesCategory, !normalizedQuery.isEmpty else { return matchesCategory }
            return ([template.name, template.summary] + template.keywords).contains { value in
                value.localizedCaseInsensitiveContains(normalizedQuery)
            }
        }
    }

    static let `default` = ScriptTemplateCatalog(templates: [
        template("plain-text", "去除格式（纯文本）", "保留剪贴板中的纯文本内容", .text, ["纯文本", "格式"], "return clip.text;"),
        template("uppercase", "转大写", "将英文字符转换为大写", .text, ["uppercase", "大写"], "return clip.text.toUpperCase();"),
        template("lowercase", "转小写", "将英文字符转换为小写", .text, ["lowercase", "小写"], "return clip.text.toLowerCase();"),
        template("format-json", "格式化 JSON", "使用两个空格格式化 JSON", .json, ["JSON", "格式化"], "return JSON.stringify(JSON.parse(clip.text), null, 2);"),
        template("minify-json", "压缩 JSON", "移除 JSON 中多余的空格与换行", .json, ["JSON", "压缩"], "return JSON.stringify(JSON.parse(clip.text));"),
        template("remove-blank-lines", "移除空行", "删除文本中的空白行", .text, ["空行", "清理"], "return clip.text.split('\\n').filter(line => line.trim()).join('\\n');"),
        template("date-to-timestamp", "日期转时间戳", "将可识别日期转换为毫秒时间戳", .text, ["日期", "timestamp"], "const value = Date.parse(clip.text.trim()); if (Number.isNaN(value)) throw new Error('Invalid date'); return String(value);"),
        template("extract-email", "提取邮箱", "从文本中提取电子邮箱地址", .extract, ["邮箱", "email"], "const matches = clip.text.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}/g) || []; return matches.join('\\n');"),
        template("extract-url", "提取 URL", "从文本中提取网页链接", .extract, ["网址", "链接", "URL"], "const matches = clip.text.match(/https?:\\/\\/[^\\s<>\"]+/g) || []; return matches.join('\\n');"),
        template("extract-phone", "提取手机号", "从文本中提取中国大陆手机号", .extract, ["手机", "电话"], "const matches = clip.text.match(/1[3-9]\\d{9}/g) || []; return matches.join('\\n');"),
        template("extract-ip", "提取 IP 地址", "从文本中提取 IPv4 地址", .extract, ["IP", "IPv4"], "const matches = clip.text.match(/\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b/g) || []; return matches.join('\\n');"),
        template("base64-encode", "Base64 编码", "将 UTF-8 文本编码为 Base64", .text, ["Base64", "编码"], "return btoa(unescape(encodeURIComponent(clip.text)));"),
        template("base64-decode", "Base64 解码", "将 Base64 解码为 UTF-8 文本", .text, ["Base64", "解码"], "return decodeURIComponent(escape(atob(clip.text.trim())));"),
    ])

    private static func template(
        _ id: String,
        _ name: String,
        _ summary: String,
        _ category: ScriptTemplateCategory,
        _ keywords: [String],
        _ body: String
    ) -> ScriptTemplate {
        ScriptTemplate(
            id: id,
            name: name,
            summary: summary,
            category: category,
            keywords: keywords,
            code: "function transform(clip) {\n    \(body)\n}"
        )
    }
}
