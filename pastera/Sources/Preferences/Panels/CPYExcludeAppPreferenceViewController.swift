//
//  CPYExcludeAppPreferenceViewController.swift
//
//  Pastera
//

import AppKit
import UniformTypeIdentifiers

final class CPYExcludeAppPreferenceViewController: PasteraPreferencePageViewController {
    typealias ApplicationURLPicker = () -> [URL]
    typealias ApplicationURLResolver = (String) -> URL?
    typealias ApplicationIconResolver = (URL) -> NSImage

    static let allowedApplicationContentTypes = [UTType.applicationBundle]

    private struct ApplicationDisplayModel {
        let name: String
        let path: String
        let icon: NSImage
    }

    private enum Metrics {
        static let listHeight: CGFloat = 280
        static let rowHeight: CGFloat = 52
        static let iconSize: CGFloat = 32
    }

    private let applicationURLPicker: ApplicationURLPicker
    private let applicationURLResolver: ApplicationURLResolver
    private let applicationIconResolver: ApplicationIconResolver

    private var tableView = ExcludedApplicationsTableView()
    private var scrollView = NSScrollView()
    private var emptyStateLabel = NSTextField(labelWithString: pasteraPreferenceString("No Excluded Applications"))
    private var emptyStateContainer = NSStackView()
    private var deleteButton = NSButton(title: pasteraPreferenceString("Delete"), target: nil, action: nil)
    private var displayModelsByIdentifier = [String: ApplicationDisplayModel]()

    convenience init() {
        self.init(
            applicationURLPicker: Self.pickApplicationURLs,
            applicationURLResolver: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
            applicationIconResolver: { NSWorkspace.shared.icon(forFile: $0.path) }
        )
    }

    init(
        applicationURLPicker: @escaping ApplicationURLPicker,
        applicationURLResolver: @escaping ApplicationURLResolver,
        applicationIconResolver: @escaping ApplicationIconResolver
    ) {
        self.applicationURLPicker = applicationURLPicker
        self.applicationURLResolver = applicationURLResolver
        self.applicationIconResolver = applicationIconResolver
        super.init(paneID: .excludedApps, title: pasteraPreferenceString("Excluded Apps"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        resetViewState()
        super.loadView()
        configureTableView()
        buildApplicationsGroup()
        refreshListState()
    }

    private func resetViewState() {
        displayModelsByIdentifier.removeAll()
        tableView.deleteSelectedRow = nil
        tableView.delegate = nil
        tableView.dataSource = nil
        tableView.tableColumns.forEach(tableView.removeTableColumn)
        removeExistingContent()

        tableView = ExcludedApplicationsTableView()
        scrollView = NSScrollView()
        emptyStateLabel = NSTextField(labelWithString: pasteraPreferenceString("No Excluded Applications"))
        emptyStateContainer = NSStackView()
        deleteButton = NSButton(title: pasteraPreferenceString("Delete"), target: nil, action: nil)
    }

    private func removeExistingContent() {
        contentStack.arrangedSubviews.forEach { arrangedSubview in
            NSLayoutConstraint.deactivate(contentStack.constraints.filter {
                $0.firstItem === arrangedSubview || $0.secondItem === arrangedSubview
            })
            contentStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        if let container = contentStack.superview {
            NSLayoutConstraint.deactivate(container.constraints.filter {
                $0.firstItem === contentStack || $0.secondItem === contentStack
            })
        }
        contentStack.removeFromSuperview()
    }

    private func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("excludedApplication"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("exclude.apps.table")
        tableView.deleteSelectedRow = { [weak self] in
            self?.deleteSelectedApplication() ?? false
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.setAccessibilityIdentifier("exclude.apps.scroll")
    }

    private func buildApplicationsGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Excluded Applications"),
            symbolName: "app.badge",
            accentColor: .systemRed
        )
        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(scrollView)

        emptyStateLabel.font = .systemFont(ofSize: 13)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.setAccessibilityIdentifier("exclude.apps.empty")

        let emptyStateIcon = NSImageView(
            image: NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil) ?? NSImage()
        )
        emptyStateIcon.contentTintColor = .tertiaryLabelColor
        emptyStateIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .light)
        emptyStateIcon.setAccessibilityIdentifier("exclude.apps.empty.icon")

        emptyStateContainer = NSStackView(views: [emptyStateIcon, emptyStateLabel])
        emptyStateContainer.orientation = .vertical
        emptyStateContainer.alignment = .centerX
        emptyStateContainer.spacing = 10
        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(emptyStateContainer)

        NSLayoutConstraint.activate([
            listContainer.heightAnchor.constraint(equalToConstant: Metrics.listHeight),
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            emptyStateIcon.widthAnchor.constraint(equalToConstant: 34),
            emptyStateIcon.heightAnchor.constraint(equalToConstant: 34),
            emptyStateContainer.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor),
            emptyStateContainer.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor),
            emptyStateContainer.leadingAnchor.constraint(
                greaterThanOrEqualTo: listContainer.leadingAnchor,
                constant: 16
            ),
            emptyStateContainer.trailingAnchor.constraint(
                lessThanOrEqualTo: listContainer.trailingAnchor,
                constant: -16
            )
        ])

        group.addContent(listContainer)

        let addButton = NSButton(title: String(localized: "Add"), target: self, action: #selector(addApplications(_:)))
        addButton.bezelStyle = .rounded
        addButton.setAccessibilityIdentifier("exclude.apps.add")

        deleteButton.target = self
        deleteButton.action = #selector(deleteApplication(_:))
        deleteButton.bezelStyle = .rounded
        deleteButton.setAccessibilityIdentifier("exclude.apps.delete")

        let actions = NSStackView(views: [addButton, deleteButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        group.setHeaderAccessory(actions)

        addGroup(group, anchorID: "exclude.apps")
    }

    @objc private func addApplications(_ sender: Any?) {
        let service = AppEnvironment.current.excludeAppService
        var identifiers = Set(service.applications.map(\.identifier))

        for url in applicationURLPicker() {
            guard
                let bundle = Bundle(url: url),
                let infoDictionary = bundle.infoDictionary,
                let appInfo = CPYAppInfo(info: infoDictionary as [String: AnyObject]),
                identifiers.insert(appInfo.identifier).inserted
            else {
                continue
            }
            service.add(with: appInfo)
        }

        reloadApplications()
    }

    @objc private func deleteApplication(_ sender: Any?) {
        if !deleteSelectedApplication() {
            NSSound.beep()
        }
    }

    private func deleteSelectedApplication() -> Bool {
        let service = AppEnvironment.current.excludeAppService
        let selectedRow = tableView.selectedRow
        guard service.applications.indices.contains(selectedRow) else {
            return false
        }

        service.delete(with: selectedRow)
        displayModelsByIdentifier.removeAll()
        tableView.reloadData()

        if !service.applications.isEmpty {
            let nextSelection = min(selectedRow, service.applications.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: nextSelection), byExtendingSelection: false)
        }
        refreshListState()
        return true
    }

    private func reloadApplications() {
        displayModelsByIdentifier.removeAll()
        tableView.reloadData()
        refreshListState()
    }

    private func displayModel(for appInfo: CPYAppInfo) -> ApplicationDisplayModel {
        if let displayModel = displayModelsByIdentifier[appInfo.identifier] {
            return displayModel
        }

        let applicationURL = applicationURLResolver(appInfo.identifier)
        let icon = applicationURL.map(applicationIconResolver)
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage()
        let displayModel = ApplicationDisplayModel(
            name: appInfo.name,
            path: applicationURL?.path ?? pasteraPreferenceString("Application Not Found"),
            icon: icon
        )
        displayModelsByIdentifier[appInfo.identifier] = displayModel
        return displayModel
    }

    private func refreshListState() {
        let isEmpty = AppEnvironment.current.excludeAppService.applications.isEmpty
        scrollView.isHidden = isEmpty
        emptyStateLabel.isHidden = !isEmpty
        emptyStateContainer.isHidden = !isEmpty
        deleteButton.isEnabled = AppEnvironment.current.excludeAppService.applications.indices
            .contains(tableView.selectedRow)
    }

    private static func pickApplicationURLs() -> [URL] {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = allowedApplicationContentTypes
        openPanel.allowsMultipleSelection = true
        openPanel.resolvesAliases = true
        openPanel.prompt = String(localized: "Add")
        openPanel.directoryURL = FileManager.default.urls(
            for: .applicationDirectory,
            in: .localDomainMask
        ).first
        return openPanel.runModal() == .OK ? openPanel.urls : []
    }
}

extension CPYExcludeAppPreferenceViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        AppEnvironment.current.excludeAppService.applications.count
    }
}

extension CPYExcludeAppPreferenceViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let appInfo = AppEnvironment.current.excludeAppService.applications[safe: row] else {
            return nil
        }

        let displayModel = displayModel(for: appInfo)
        let identifier = ExcludedApplicationRowView.reuseIdentifier
        let rowView = tableView.makeView(withIdentifier: identifier, owner: self)
            as? ExcludedApplicationRowView
            ?? ExcludedApplicationRowView(iconSize: Metrics.iconSize)
        rowView.configure(
            name: displayModel.name,
            path: displayModel.path,
            icon: displayModel.icon
        )
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshListState()
    }
}

private final class ExcludedApplicationsTableView: NSTableView {
    var deleteSelectedRow: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasAllowedModifiers = modifiers.isEmpty || modifiers == .function
        guard event.type == .keyDown,
              hasAllowedModifiers,
              event.keyCode == 51 || event.keyCode == 117 else {
            return super.performKeyEquivalent(with: event)
        }

        if deleteSelectedRow?() != true {
            NSSound.beep()
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if performKeyEquivalent(with: event) {
            return
        }
        super.keyDown(with: event)
    }
}

private final class ExcludedApplicationRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("excludedApplicationRow")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    init(iconSize: CGFloat) {
        super.init(frame: .zero)
        identifier = Self.reuseIdentifier

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail

        pathLabel.font = .systemFont(ofSize: 11.5)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        let labels = NSStackView(views: [nameLabel, pathLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labels)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(name: String, path: String, icon: NSImage) {
        nameLabel.stringValue = name
        pathLabel.stringValue = path
        iconView.image = icon
    }
}
