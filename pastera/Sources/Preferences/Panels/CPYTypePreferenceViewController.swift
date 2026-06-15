//
//  CPYTypePreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

class CPYTypePreferenceViewController: NSViewController {

    // MARK: - Properties
    @objc var storeTypes: NSMutableDictionary!
    private var typeButtons = [NSButton]()
    private weak var titleLabel: NSTextField?
    private weak var sectionView: PasteraSettingsSectionView?
    private var rowViews = [PasteraSettingsRowView]()

    private enum Layout {
        static let width: CGFloat = 450
        static let titleHeight: CGFloat = 22
        static let titleToSectionSpacing: CGFloat = 12
        static let sectionInsetX: CGFloat = 14
        static let sectionInsetY: CGFloat = 14
        static let rowHeight: CGFloat = 22
        static let rowSpacing: CGFloat = 6

        static func sectionHeight(rowCount: Int) -> CGFloat {
            sectionInsetY * 2
                + CGFloat(rowCount) * rowHeight
                + CGFloat(max(rowCount - 1, 0)) * rowSpacing
        }

        static var height: CGFloat {
            titleHeight + titleToSectionSpacing + sectionHeight(rowCount: 7)
        }
    }

    private struct TypeOption {
        let key: String
        let title: String
    }

    private let typeOptions: [TypeOption] = [
        TypeOption(key: PasteboardAvailableType.string.rawValue, title: "Plain Text"),
        TypeOption(key: PasteboardAvailableType.rtf.rawValue, title: "Rich Text Format (RTF)"),
        TypeOption(key: PasteboardAvailableType.rtfd.rawValue, title: "Rich Text Format Directory (RTFD)"),
        TypeOption(key: PasteboardAvailableType.pdf.rawValue, title: "PDF"),
        TypeOption(key: PasteboardAvailableType.filenames.rawValue, title: "Filenames"),
        TypeOption(key: PasteboardAvailableType.url.rawValue, title: "URL"),
        TypeOption(key: PasteboardAvailableType.tiff.rawValue, title: "TIFF Image")
    ]

    // MARK: - Initialize
    override func loadView() {
        loadStoreTypes()
        view = makeView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshAppearance()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutContent(width: max(Layout.width, view.bounds.width))
    }

    private func loadStoreTypes() {
        if let dictionary = AppEnvironment.current.defaults.object(forKey: Constants.UserDefaults.storeTypes) as? [String: Any] {
            storeTypes = NSMutableDictionary(dictionary: dictionary)
        } else {
            storeTypes = NSMutableDictionary()
        }
    }

    private func makeView() -> NSView {
        let host = PasteraSettingsPaneHost(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))

        let titleLabel = NSTextField(labelWithString: "Select clipboard types to store:")
        self.titleLabel = titleLabel
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        host.addSubview(titleLabel)

        let section = PasteraSettingsSectionView(frame: NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.sectionHeight(rowCount: typeOptions.count)
        ))
        sectionView = section
        host.addSubview(section)

        typeOptions.enumerated().forEach { index, option in
            let rowY = Layout.sectionHeight(rowCount: typeOptions.count)
                - Layout.sectionInsetY
                - Layout.rowHeight
                - CGFloat(index) * (Layout.rowHeight + Layout.rowSpacing)
            let row = PasteraSettingsRowView(frame: NSRect(
                x: Layout.sectionInsetX,
                y: rowY,
                width: Layout.width - Layout.sectionInsetX * 2,
                height: Layout.rowHeight
            ))
            let button = makeCheckbox(option: option, rowSize: row.frame.size)
            row.addSubview(button)
            section.addSubview(row)
            rowViews.append(row)
            typeButtons.append(button)
        }

        layoutContent(width: Layout.width)
        return host
    }

    private func layoutContent(width: CGFloat) {
        let sectionHeight = Layout.sectionHeight(rowCount: typeOptions.count)
        titleLabel?.frame = NSRect(
            x: 0,
            y: Layout.height - Layout.titleHeight,
            width: width,
            height: Layout.titleHeight
        )
        sectionView?.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: sectionHeight
        )
        rowViews.enumerated().forEach { index, row in
            let rowY = sectionHeight
                - Layout.sectionInsetY
                - Layout.rowHeight
                - CGFloat(index) * (Layout.rowHeight + Layout.rowSpacing)
            row.frame = NSRect(
                x: Layout.sectionInsetX,
                y: rowY,
                width: width - Layout.sectionInsetX * 2,
                height: Layout.rowHeight
            )
            typeButtons[safe: index]?.frame = NSRect(origin: .zero, size: row.frame.size)
        }
    }

    private func makeCheckbox(option: TypeOption, rowSize: NSSize) -> NSButton {
        let button = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(typeCheckboxChanged(_:)))
        button.frame = NSRect(origin: .zero, size: rowSize)
        button.identifier = NSUserInterfaceItemIdentifier(option.key)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.state = isTypeEnabled(option.key) ? .on : .off
        button.setAccessibilityLabel(option.title)
        return button
    }

    private func isTypeEnabled(_ key: String) -> Bool {
        guard let value = storeTypes[key] else { return true }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let bool = value as? Bool {
            return bool
        }
        return true
    }

    @objc private func typeCheckboxChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        storeTypes[key] = NSNumber(value: sender.state == .on)
    }

    private func refreshAppearance() {
        PasteraSemanticViewStyler.apply(to: view, appearance: view.effectiveAppearance)
        (view as? PasteraSettingsPaneHost)?.refreshAppearance()
    }

}
