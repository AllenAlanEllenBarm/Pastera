import AppKit

@MainActor
final class ScriptTemplateMarketViewController: NSViewController, NSSearchFieldDelegate {
    private enum Metrics {
        static let minimumWidth: CGFloat = 560
        static let idealWidth: CGFloat = 760
        static let minimumHeight: CGFloat = 460
        static let idealHeight: CGFloat = 650
    }

    private let catalog: ScriptTemplateCatalog
    private let onSelect: (ScriptTemplate) -> Void
    private let searchField = NSSearchField()
    private let categoryControl = NSSegmentedControl()
    private let listStack = NSStackView()
    private weak var sheetScaffold: PasteraPreferenceSheetScaffold?
    private var visibleTemplates = [ScriptTemplate]()

    init(
        catalog: ScriptTemplateCatalog = .default,
        onSelect: @escaping (ScriptTemplate) -> Void
    ) {
        self.catalog = catalog
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let scaffold = PasteraPreferenceSheetScaffold(
            title: pasteraScriptString("Script Templates", "脚本模板"),
            subtitle: pasteraScriptString(
                "Choose a bundled starting point, then review it before saving.",
                "选择内置模板作为起点，保存前仍可继续编辑"
            ),
            minimumSize: NSSize(width: Metrics.minimumWidth, height: Metrics.minimumHeight),
            idealSize: NSSize(width: Metrics.idealWidth, height: Metrics.idealHeight)
        )
        sheetScaffold = scaffold

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.addArrangedSubview(makeControls())
        content.addArrangedSubview(makeTemplateList())
        content.arrangedSubviews.forEach {
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        scaffold.addBodyView(content)

        let doneButton = NSButton(
            title: pasteraScriptString("Done", "完成"),
            target: self,
            action: #selector(done)
        )
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\u{1b}"
        scaffold.setFooterActions(trailing: [doneButton])

        view = scaffold
        reloadTemplates()
        scaffold.layoutSubtreeIfNeeded()
    }

    private func makeControls() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        searchField.placeholderString = pasteraScriptString(
            "Search by name or purpose",
            "搜索模板名称或用途"
        )
        searchField.delegate = self
        searchField.setAccessibilityLabel(pasteraScriptString("Search Templates", "搜索脚本模板"))

        categoryControl.segmentCount = ScriptTemplateCategory.allCases.count
        for (index, category) in ScriptTemplateCategory.allCases.enumerated() {
            categoryControl.setLabel(category.title, forSegment: index)
        }
        categoryControl.selectedSegment = 0
        categoryControl.target = self
        categoryControl.action = #selector(filterChanged)
        categoryControl.setAccessibilityLabel(pasteraScriptString("Template Category", "模板分类"))

        stack.addArrangedSubview(searchField)
        stack.addArrangedSubview(categoryControl)
        searchField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        categoryControl.setContentHuggingPriority(.required, for: .horizontal)
        return stack
    }

    private func makeTemplateList() -> NSView {
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 0
        return listStack
    }

    private func reloadTemplates() {
        let categories = ScriptTemplateCategory.allCases
        let category = categories.indices.contains(categoryControl.selectedSegment)
            ? categories[categoryControl.selectedSegment]
            : .all
        visibleTemplates = catalog.search(query: searchField.stringValue, category: category)
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if visibleTemplates.isEmpty {
            let empty = PasteraPreferenceEmptyStateView(
                symbolName: "magnifyingglass",
                title: pasteraScriptString("No matching templates", "没有匹配的模板"),
                message: pasteraScriptString(
                    "Try another keyword or category.",
                    "请尝试其他关键词或分类"
                ),
                minimumHeight: 132
            )
            listStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        } else {
            for (index, template) in visibleTemplates.enumerated() {
                let row = makeTemplateRow(template)
                listStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
                guard index < visibleTemplates.count - 1 else { continue }
                let separator = NSBox()
                separator.boxType = .separator
                listStack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            }
        }
        sheetScaffold?.needsLayout = true
        sheetScaffold?.layoutSubtreeIfNeeded()
    }

    private func makeTemplateRow(_ template: ScriptTemplate) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 10, left: 4, bottom: 10, right: 4)
        row.identifier = NSUserInterfaceItemIdentifier("script.template.row.\(template.id)")
        row.setAccessibilityIdentifier("script.template.row.\(template.id)")
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let titleLabel = NSTextField(labelWithString: template.name)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let summaryLabel = NSTextField(wrappingLabelWithString: template.summary)
        summaryLabel.font = .systemFont(ofSize: 11.5)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.maximumNumberOfLines = 2
        let previewLabel = NSTextField(
            labelWithString: template.code
                .split(separator: "\n")
                .dropFirst()
                .first
                .map(String.init) ?? ""
        )
        previewLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        previewLabel.textColor = .tertiaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(summaryLabel)
        labels.addArrangedSubview(previewLabel)

        let addButton = NSButton(
            title: pasteraScriptString("Add", "添加"),
            target: self,
            action: #selector(addTemplate(_:))
        )
        addButton.bezelStyle = .rounded
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.identifier = NSUserInterfaceItemIdentifier("script.template.add.\(template.id)")
        addButton.setAccessibilityLabel(
            pasteraScriptString("Add \(template.name) Template", "添加模板 \(template.name)")
        )

        row.addArrangedSubview(labels)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(addButton)
        labels.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addButton.setContentHuggingPriority(.required, for: .horizontal)
        addButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    func controlTextDidChange(_ notification: Notification) {
        reloadTemplates()
    }

    @objc private func filterChanged() {
        reloadTemplates()
    }

    @objc private func done() {
        dismissScriptSheet(self)
    }

    @objc private func addTemplate(_ sender: NSButton) {
        guard let rawIdentifier = sender.identifier?.rawValue,
              let id = rawIdentifier.split(separator: ".").last.map(String.init),
              let template = visibleTemplates.first(where: { $0.id == id }) else { return }
        onSelect(template)
        dismissScriptSheet(self)
    }

    var visibleTemplateIDsForTesting: [String] {
        visibleTemplates.map(\.id)
    }

    func searchForTesting(_ query: String) {
        searchField.stringValue = query
        reloadTemplates()
    }

    func selectTemplateForTesting(id: String) {
        guard let template = visibleTemplates.first(where: { $0.id == id }) else { return }
        onSelect(template)
    }

    var minimumSheetWidthForTesting: CGFloat { Metrics.minimumWidth }
    var usesFlexibleTemplateRowsForTesting: Bool {
        sheetScaffold?.documentView.autoresizingMask.contains(.width) == true
    }
}

private extension ScriptTemplateCategory {
    var title: String {
        switch self {
        case .all: return pasteraScriptString("All", "全部")
        case .text: return pasteraScriptString("Text", "文本")
        case .json: return "JSON"
        case .extract: return pasteraScriptString("Extract", "提取")
        }
    }
}
