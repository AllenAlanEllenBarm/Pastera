import AppKit

@MainActor
final class ScriptTemplateMarketViewController: NSViewController, NSSearchFieldDelegate {
    private let catalog: ScriptTemplateCatalog
    private let onSelect: (ScriptTemplate) -> Void
    private let searchField = NSSearchField()
    private let categoryControl = NSSegmentedControl()
    private let listStack = NSStackView()
    private let documentView = PasteraPreferenceFlippedView()
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
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let header = makeHeader()
        let controls = makeControls()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 10
        listStack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 18, right: 18)
        listStack.translatesAutoresizingMaskIntoConstraints = true
        listStack.autoresizingMask = [.width]
        documentView.frame = NSRect(x: 0, y: 0, width: 760, height: 2_000)
        listStack.frame = NSRect(x: 0, y: 0, width: 760, height: 2_000)
        documentView.addSubview(listStack)
        scroll.documentView = documentView
        root.addSubview(header)
        root.addSubview(controls)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 760),
            root.heightAnchor.constraint(equalToConstant: 650),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 78),
            controls.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
        reloadTemplates()
    }

    private func makeHeader() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: pasteraScriptString("Script Templates", "脚本模板"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let subtitle = NSTextField(labelWithString: pasteraScriptString("Choose a bundled template to create a script.", "选择预设模板快速创建脚本"))
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        let done = NSButton(title: pasteraScriptString("Done", "完成"), target: self, action: #selector(done))
        done.bezelStyle = .rounded
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)
        view.addSubview(subtitle)
        view.addSubview(done)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            done.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func makeControls() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = pasteraScriptString("Search templates", "搜索模板名称或用途")
        searchField.delegate = self
        categoryControl.segmentCount = ScriptTemplateCategory.allCases.count
        for (index, category) in ScriptTemplateCategory.allCases.enumerated() {
            categoryControl.setLabel(category.title, forSegment: index)
        }
        categoryControl.selectedSegment = 0
        categoryControl.target = self
        categoryControl.action = #selector(filterChanged)
        stack.addArrangedSubview(searchField)
        stack.addArrangedSubview(categoryControl)
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        return stack
    }

    private func reloadTemplates() {
        let categories = ScriptTemplateCategory.allCases
        let category = categories.indices.contains(categoryControl.selectedSegment)
            ? categories[categoryControl.selectedSegment]
            : .all
        visibleTemplates = catalog.search(query: searchField.stringValue, category: category)
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if visibleTemplates.isEmpty {
            let empty = NSTextField(labelWithString: pasteraScriptString("No matching templates.", "没有匹配的模板"))
            empty.textColor = .secondaryLabelColor
            listStack.addArrangedSubview(empty)
        } else {
            visibleTemplates.forEach {
                let card = makeTemplateCard($0)
                listStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: listStack.widthAnchor, constant: -36).isActive = true
            }
        }
        listStack.layoutSubtreeIfNeeded()
        listStack.frame.size = NSSize(width: 760, height: max(1, listStack.fittingSize.height))
        documentView.frame.size = NSSize(
            width: 760,
            height: max(1, listStack.fittingSize.height)
        )
    }

    private func makeTemplateCard(_ template: ScriptTemplate) -> NSView {
        let card = NSStackView()
        card.orientation = .horizontal
        card.alignment = .centerY
        card.spacing = 14
        card.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let title = NSTextField(labelWithString: template.name)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let summary = NSTextField(labelWithString: template.summary)
        summary.textColor = .secondaryLabelColor
        let preview = NSTextField(labelWithString: template.code.split(separator: "\n").dropFirst().first.map(String.init) ?? "")
        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.textColor = .tertiaryLabelColor
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(summary)
        labels.addArrangedSubview(preview)
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(addTemplate(_:)))
        add.bezelStyle = .circular
        add.identifier = NSUserInterfaceItemIdentifier(template.id)
        add.setAccessibilityLabel(pasteraPreferenceString("Add \(template.name) template"))
        card.addArrangedSubview(labels)
        card.addArrangedSubview(add)
        labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 590).isActive = true
        return card
    }

    func controlTextDidChange(_ notification: Notification) { reloadTemplates() }
    @objc private func filterChanged() { reloadTemplates() }
    @objc private func done() { dismiss(self) }

    @objc private func addTemplate(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let template = visibleTemplates.first(where: { $0.id == id }) else { return }
        onSelect(template)
    }

    var visibleTemplateIDsForTesting: [String] { visibleTemplates.map(\.id) }
    func searchForTesting(_ query: String) { searchField.stringValue = query; reloadTemplates() }
    func selectTemplateForTesting(id: String) {
        guard let template = visibleTemplates.first(where: { $0.id == id }) else { return }
        onSelect(template)
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
