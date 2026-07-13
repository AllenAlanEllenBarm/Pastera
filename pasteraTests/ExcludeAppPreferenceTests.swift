//
//  ExcludeAppPreferenceTests.swift
//
//  Pastera
//

import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Pastera

@MainActor
@Suite(.serialized)
struct ExcludeAppPreferenceTests {
    @Test
    func emptyPageOwnsExactAnchorAndShowsSafeDisabledDeleteState() throws {
        let context = try makeContext(applications: [])
        defer { context.cleanup() }
        let controller = makeController()
        _ = controller.view

        let table = try excludeTable(in: controller.view)
        let emptyState = try excludeView(in: controller.view, identifier: "exclude.apps.empty")
        let emptyStateIcon = try excludeView(in: controller.view, identifier: "exclude.apps.empty.icon")
        let deleteButton = try excludeButton(in: controller.view, identifier: "exclude.apps.delete")
        let buttons = excludeSubviews(in: controller.view).compactMap { $0 as? NSButton }

        #expect(controller.paneID == .excludedApps)
        #expect(controller.revealSetting(anchorID: "exclude.apps", animated: false))
        #expect(table.numberOfRows == 0)
        #expect(!emptyState.isHidden)
        #expect(!emptyStateIcon.isHidden)
        #expect(!deleteButton.isEnabled)
        #expect(buttons.filter { $0.title == pasteraPreferenceString("Add") }.count == 1)
        #expect(buttons.filter { $0.title == pasteraPreferenceString("Delete") }.count == 1)
    }

    @Test
    func rowUsesInjectedWorkspacePathAndIconResolution() throws {
        let appInfo = try makeAppInfo(identifier: "com.example.editor", name: "Example Editor")
        let context = try makeContext(applications: [appInfo])
        defer { context.cleanup() }
        let appURL = URL(fileURLWithPath: "/Applications/Example Editor.app")
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        var resolvedIdentifiers = [String]()
        var iconURLs = [URL]()
        let controller = CPYExcludeAppPreferenceViewController(
            applicationURLPicker: { [] },
            applicationURLResolver: { identifier in
                resolvedIdentifiers.append(identifier)
                return appURL
            },
            applicationIconResolver: { url in
                iconURLs.append(url)
                return icon
            }
        )
        _ = controller.view

        let table = try excludeTable(in: controller.view)
        let rowView = try #require(controller.tableView(
            table,
            viewFor: table.tableColumns.first,
            row: 0
        ))
        let labels = excludeSubviews(in: rowView).compactMap { $0 as? NSTextField }.map(\.stringValue)
        let image = excludeSubviews(in: rowView).compactMap { $0 as? NSImageView }.first?.image

        #expect(labels.contains("Example Editor"))
        #expect(labels.contains("/Applications/Example Editor.app"))
        #expect(image === icon)
        #expect(resolvedIdentifiers == ["com.example.editor"])
        #expect(iconURLs == [appURL])
    }

    @Test
    func repeatedRowRequestsResolvePathAndIconOnlyOncePerBundleIdentifier() throws {
        let appInfo = try makeAppInfo(identifier: "com.example.editor", name: "Example Editor")
        let context = try makeContext(applications: [appInfo])
        defer { context.cleanup() }
        let appURL = URL(fileURLWithPath: "/Applications/Example Editor.app")
        var urlResolutionCount = 0
        var iconResolutionCount = 0
        let controller = CPYExcludeAppPreferenceViewController(
            applicationURLPicker: { [] },
            applicationURLResolver: { _ in
                urlResolutionCount += 1
                return appURL
            },
            applicationIconResolver: { _ in
                iconResolutionCount += 1
                return NSImage()
            }
        )
        _ = controller.view
        let table = try excludeTable(in: controller.view)

        _ = controller.tableView(table, viewFor: table.tableColumns.first, row: 0)
        let countsAfterFirstRequest = (urlResolutionCount, iconResolutionCount)
        _ = controller.tableView(table, viewFor: table.tableColumns.first, row: 0)

        #expect(urlResolutionCount == countsAfterFirstRequest.0)
        #expect(iconResolutionCount == countsAfterFirstRequest.1)
    }

    @Test
    func reusableRowCellReconfiguresNamePathAndIconWithoutStaleContent() throws {
        let first = try makeAppInfo(identifier: "com.example.first", name: "First App")
        let second = try makeAppInfo(identifier: "com.example.second", name: "Second App")
        let context = try makeContext(applications: [first, second])
        defer { context.cleanup() }
        let firstURL = URL(fileURLWithPath: "/Applications/First App.app")
        let secondURL = URL(fileURLWithPath: "/Applications/Second App.app")
        let firstIcon = NSImage(size: NSSize(width: 32, height: 32))
        let secondIcon = NSImage(size: NSSize(width: 24, height: 24))
        let controller = CPYExcludeAppPreferenceViewController(
            applicationURLPicker: { [] },
            applicationURLResolver: { identifier in
                identifier == first.identifier ? firstURL : secondURL
            },
            applicationIconResolver: { url in
                url == firstURL ? firstIcon : secondIcon
            }
        )
        _ = controller.view
        let table = ReusingExcludeTableView()

        let firstCell = try #require(controller.tableView(table, viewFor: nil, row: 0))
        table.reusableView = firstCell
        let secondCell = try #require(controller.tableView(table, viewFor: nil, row: 1))
        let labels = excludeSubviews(in: secondCell)
            .compactMap { $0 as? NSTextField }
            .map(\.stringValue)
        let image = excludeSubviews(in: secondCell).compactMap { $0 as? NSImageView }.first?.image

        #expect(table.makeViewCallCount == 2)
        #expect(secondCell === firstCell)
        #expect(labels.contains("Second App"))
        #expect(labels.contains("/Applications/Second App.app"))
        #expect(!labels.contains("First App"))
        #expect(!labels.contains("/Applications/First App.app"))
        #expect(image === secondIcon)
    }

    @Test
    func addUsesInjectedMultiplePickerAndDoesNotDuplicateApplications() throws {
        let context = try makeContext(applications: [])
        defer { context.cleanup() }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExcludeAppPreferenceTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let firstURL = try makeApplicationBundle(
            in: temporaryDirectory,
            identifier: "com.example.first",
            name: "First App"
        )
        let secondURL = try makeApplicationBundle(
            in: temporaryDirectory,
            identifier: "com.example.second",
            name: "Second App"
        )
        var pickerCallCount = 0
        let controller = CPYExcludeAppPreferenceViewController(
            applicationURLPicker: {
                pickerCallCount += 1
                return [firstURL, firstURL, secondURL]
            },
            applicationURLResolver: { identifier in
                identifier == "com.example.first" ? firstURL : secondURL
            },
            applicationIconResolver: { _ in NSImage() }
        )
        _ = controller.view

        try excludeButton(in: controller.view, identifier: "exclude.apps.add").performClick(nil)

        #expect(pickerCallCount == 1)
        #expect(context.service.applications.count == 2)
        #expect(Set(context.service.applications.map(\.identifier)) == [
            "com.example.first",
            "com.example.second"
        ])
        #expect(try persistedApplications(in: context.defaults).count == 2)
        #expect(try excludeTable(in: controller.view).numberOfRows == 2)
        #expect(try excludeView(in: controller.view, identifier: "exclude.apps.empty").isHidden)
    }

    @Test
    func selectedDeleteAndBackspacePersistWhileDeleteWithoutSelectionIsSafe() throws {
        let first = try makeAppInfo(identifier: "com.example.first", name: "First App")
        let second = try makeAppInfo(identifier: "com.example.second", name: "Second App")
        let context = try makeContext(applications: [first, second])
        defer { context.cleanup() }
        let controller = makeController()
        _ = controller.view
        let table = try excludeTable(in: controller.view)
        let deleteButton = try excludeButton(in: controller.view, identifier: "exclude.apps.delete")

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.tableViewSelectionDidChange(Notification(
            name: NSTableView.selectionDidChangeNotification,
            object: table
        ))
        #expect(deleteButton.isEnabled)
        deleteButton.performClick(nil)

        #expect(context.service.applications.map(\.identifier) == ["com.example.second"])
        #expect(try persistedApplications(in: context.defaults).map(\.identifier) == ["com.example.second"])

        table.deselectAll(nil)
        controller.tableViewSelectionDidChange(Notification(
            name: NSTableView.selectionDidChangeNotification,
            object: table
        ))
        let deleteEvent = try makeKeyEvent(keyCode: 117, characters: "\u{7f}")
        #expect(table.performKeyEquivalent(with: deleteEvent))
        #expect(context.service.applications.count == 1)

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.tableViewSelectionDidChange(Notification(
            name: NSTableView.selectionDidChangeNotification,
            object: table
        ))
        let backspaceEvent = try makeKeyEvent(keyCode: 51, characters: "\u{8}")
        #expect(table.performKeyEquivalent(with: backspaceEvent))
        #expect(context.service.applications.isEmpty)
        #expect(try persistedApplications(in: context.defaults).isEmpty)
        #expect(try excludeView(in: controller.view, identifier: "exclude.apps.empty").isHidden == false)
    }

    @Test
    func forwardDeleteAllowsFunctionAndRejectsCommandOptionControlAndShift() throws {
        let first = try makeAppInfo(identifier: "com.example.first", name: "First App")
        let second = try makeAppInfo(identifier: "com.example.second", name: "Second App")
        let context = try makeContext(applications: [first, second])
        defer { context.cleanup() }
        let controller = makeController()
        _ = controller.view
        let table = try excludeTable(in: controller.view)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        for modifier in [
            NSEvent.ModifierFlags.command,
            .option,
            .control,
            .shift
        ] {
            let event = try makeKeyEvent(
                keyCode: 117,
                characters: "\u{7f}",
                modifierFlags: modifier
            )
            #expect(!table.performKeyEquivalent(with: event))
            #expect(context.service.applications.count == 2)
        }

        let functionDelete = try makeKeyEvent(
            keyCode: 117,
            characters: "\u{7f}",
            modifierFlags: .function
        )
        #expect(table.performKeyEquivalent(with: functionDelete))
        #expect(context.service.applications.map(\.identifier) == ["com.example.second"])

        let unmodifiedDelete = try makeKeyEvent(keyCode: 117, characters: "\u{7f}")
        #expect(table.performKeyEquivalent(with: unmodifiedDelete))
        #expect(context.service.applications.isEmpty)
    }

    @Test
    func preferencesWindowRoutesForwardDeleteToSelectedExcludedApplication() throws {
        let appInfo = try makeAppInfo(identifier: "com.example.editor", name: "Example Editor")
        let context = try makeContext(applications: [appInfo])
        defer { context.cleanup() }
        let controller = CPYPreferencesWindowController()
        defer { controller.close() }
        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(paneID: .excludedApps)

        let contentView = try #require(controller.window?.contentView)
        let table = try excludeTable(in: contentView)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(controller.window?.makeFirstResponder(table) == true)
        let functionDelete = try makeKeyEvent(
            keyCode: 117,
            characters: "\u{7f}",
            modifierFlags: .function
        )

        #expect(!controller.handlePreferenceKeyboardEventForTesting(functionDelete))
        #expect(controller.window?.performKeyEquivalent(with: functionDelete) == true)
        #expect(context.service.applications.isEmpty)
        #expect(try persistedApplications(in: context.defaults).isEmpty)
    }

    @Test
    func repeatedLoadViewRebuildsOneTableAndActionsWithoutStaleBindings() throws {
        let appInfo = try makeAppInfo(identifier: "com.example.editor", name: "Example Editor")
        let context = try makeContext(applications: [appInfo])
        defer { context.cleanup() }
        let controller = makeController()
        _ = controller.view
        let firstTable = try excludeTable(in: controller.view)

        controller.loadView()
        let secondTable = try excludeTable(in: controller.view)
        controller.loadView()
        let currentView = controller.view
        let currentTable = try excludeTable(in: currentView)
        let currentViews = excludeSubviews(in: currentView)

        #expect(firstTable !== secondTable)
        #expect(secondTable !== currentTable)
        #expect(!firstTable.isDescendant(of: currentView))
        #expect(!secondTable.isDescendant(of: currentView))
        #expect(firstTable.delegate == nil)
        #expect(firstTable.dataSource == nil)
        #expect(firstTable.tableColumns.isEmpty)
        #expect(secondTable.delegate == nil)
        #expect(secondTable.dataSource == nil)
        #expect(secondTable.tableColumns.isEmpty)
        #expect(currentViews.compactMap { $0 as? PasteraPreferenceGroupView }.count == 1)
        #expect(currentViews.compactMap { $0 as? NSTableView }.count == 1)
        #expect(currentTable.tableColumns.count == 1)
        #expect(currentViews.compactMap { $0 as? NSButton }
            .filter { $0.title == pasteraPreferenceString("Add") }.count == 1)
        #expect(currentViews.compactMap { $0 as? NSButton }
            .filter { $0.title == pasteraPreferenceString("Delete") }.count == 1)
        #expect(currentViews.filter {
            $0.accessibilityIdentifier() == "exclude.apps.empty"
        }.count == 1)
        let currentDeleteButton = try excludeButton(
            in: currentView,
            identifier: "exclude.apps.delete"
        )
        #expect(!currentDeleteButton.isEnabled)
    }

    @Test
    func openPanelUsesOnlyApplicationBundleContentType() {
        #expect(CPYExcludeAppPreferenceViewController.allowedApplicationContentTypes == [
            UTType.applicationBundle
        ])
    }
}

private extension ExcludeAppPreferenceTests {
    private func makeController() -> CPYExcludeAppPreferenceViewController {
        CPYExcludeAppPreferenceViewController(
            applicationURLPicker: { [] },
            applicationURLResolver: { _ in nil },
            applicationIconResolver: { _ in NSImage() }
        )
    }

    private func makeContext(applications: [CPYAppInfo]) throws -> ExcludeAppPreferenceTestContext {
        let suiteName = "ExcludeAppPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let service = ExcludeAppService(applications: applications)
        AppEnvironment.push(excludeAppService: service, defaults: defaults)
        return ExcludeAppPreferenceTestContext(
            service: service,
            defaults: defaults,
            cleanup: {
                _ = AppEnvironment.popLast()
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }

    private func makeAppInfo(identifier: String, name: String) throws -> CPYAppInfo {
        try #require(CPYAppInfo(info: [
            kCFBundleIdentifierKey as String: identifier as NSString,
            kCFBundleNameKey as String: name as NSString
        ]))
    }

    private func makeApplicationBundle(in rootURL: URL, identifier: String, name: String) throws -> URL {
        let applicationURL = rootURL.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let propertyList: [String: Any] = [
            kCFBundleIdentifierKey as String: identifier,
            kCFBundleNameKey as String: name,
            kCFBundleExecutableKey as String: name
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return applicationURL
    }

    private func persistedApplications(in defaults: UserDefaults) throws -> [CPYAppInfo] {
        let data = try #require(defaults.data(forKey: Constants.UserDefaults.excludeApplications))
        return try #require(NSKeyedUnarchiver.unarchiveObject(with: data) as? [CPYAppInfo])
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

private final class ReusingExcludeTableView: NSTableView {
    var reusableView: NSView?
    private(set) var makeViewCallCount = 0

    override func makeView(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        owner: Any?
    ) -> NSView? {
        makeViewCallCount += 1
        return reusableView
    }
}

private struct ExcludeAppPreferenceTestContext {
    let service: ExcludeAppService
    let defaults: UserDefaults
    let cleanup: () -> Void
}

private func excludeTable(in view: NSView) throws -> NSTableView {
    try #require(excludeSubviews(in: view).compactMap { $0 as? NSTableView }.first {
        $0.accessibilityIdentifier() == "exclude.apps.table"
    })
}

private func excludeButton(in view: NSView, identifier: String) throws -> NSButton {
    try #require(excludeSubviews(in: view).compactMap { $0 as? NSButton }.first {
        $0.accessibilityIdentifier() == identifier
    })
}

private func excludeView(in view: NSView, identifier: String) throws -> NSView {
    try #require(excludeSubviews(in: view).first { $0.accessibilityIdentifier() == identifier })
}

private func excludeSubviews(in view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + excludeSubviews(in: $0) }
}
