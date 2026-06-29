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
    @objc var filePreviewTypes: NSMutableDictionary!
    private var contentTypeButtons = [NSButton]()
    private var filePreviewButtons = [NSButton]()
    private weak var titleLabel: NSTextField?
    private weak var contentSectionView: PasteraSettingsSectionView?
    private weak var filePreviewTitleLabel: NSTextField?
    private weak var filePreviewSectionView: PasteraSettingsSectionView?

    private enum Layout {
        static let width: CGFloat = 450
        static let titleHeight: CGFloat = 22
        static let titleToSectionSpacing: CGFloat = 12
        static let sectionGap: CGFloat = 14
        static let sectionTitleHeight: CGFloat = 18
        static let sectionTitleToSectionSpacing: CGFloat = 8
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
            titleHeight
                + titleToSectionSpacing
                + sectionHeight(rowCount: 7)
                + sectionGap
                + sectionTitleHeight
                + sectionTitleToSectionSpacing
                + sectionHeight(rowCount: 2)
        }
    }

    private struct TypeOption {
        let key: String
        let title: String
    }

    private let typeOptions: [TypeOption] = [
        TypeOption(key: PasteboardAvailableType.string.rawValue, title: "文本"),
        TypeOption(key: PasteboardAvailableType.rtf.rawValue, title: "富文本"),
        TypeOption(key: PasteboardAvailableType.rtfd.rawValue, title: "富文本附件"),
        TypeOption(key: PasteboardAvailableType.pdf.rawValue, title: "文档"),
        TypeOption(key: PasteboardAvailableType.filenames.rawValue, title: "文件"),
        TypeOption(key: PasteboardAvailableType.url.rawValue, title: "链接"),
        TypeOption(key: PasteboardAvailableType.tiff.rawValue, title: "图片内容")
    ]

    private let filePreviewOptions: [TypeOption] = [
        TypeOption(key: PasteraFilePreviewKind.image.rawValue, title: "图片"),
        TypeOption(key: PasteraFilePreviewKind.commonText.rawValue, title: "常用文本文件类型")
    ]

    // MARK: - Initialize
    override func loadView() {
        loadStoreTypes()
        loadFilePreviewTypes()
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

    private func loadFilePreviewTypes() {
        if let dictionary = AppEnvironment.current.defaults.object(
            forKey: Constants.UserDefaults.filePreviewTypes
        ) as? [String: Any] {
            filePreviewTypes = NSMutableDictionary(dictionary: dictionary)
        } else {
            filePreviewTypes = NSMutableDictionary(dictionary: PasteraFilePreviewKind.defaultStates())
        }
    }

    private func makeView() -> NSView {
        let host = PasteraSettingsPaneHost(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))

        let titleLabel = NSTextField(labelWithString: "选择要保存在历史中的内容")
        self.titleLabel = titleLabel
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        host.addSubview(titleLabel)

        let contentSection = PasteraSettingsSectionView(frame: NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.sectionHeight(rowCount: typeOptions.count)
        ))
        contentSectionView = contentSection
        host.addSubview(contentSection)

        typeOptions.enumerated().forEach { index, option in
            let row = makeRow(in: contentSection, rowCount: typeOptions.count, index: index, width: Layout.width)
            let button = makeCheckbox(option: option, rowSize: row.frame.size)
            row.addSubview(button)
            contentSection.addSubview(row)
            contentTypeButtons.append(button)
        }

        let filePreviewTitleLabel = NSTextField(labelWithString: "文件预览")
        self.filePreviewTitleLabel = filePreviewTitleLabel
        filePreviewTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        filePreviewTitleLabel.textColor = .secondaryLabelColor
        filePreviewTitleLabel.lineBreakMode = .byTruncatingTail
        host.addSubview(filePreviewTitleLabel)

        let filePreviewSection = PasteraSettingsSectionView(frame: NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.sectionHeight(rowCount: filePreviewOptions.count)
        ))
        filePreviewSectionView = filePreviewSection
        host.addSubview(filePreviewSection)

        filePreviewOptions.enumerated().forEach { index, option in
            let row = makeRow(
                in: filePreviewSection,
                rowCount: filePreviewOptions.count,
                index: index,
                width: Layout.width
            )
            let button = makeFilePreviewCheckbox(option: option, rowSize: row.frame.size)
            row.addSubview(button)
            filePreviewSection.addSubview(row)
            filePreviewButtons.append(button)
        }

        updateFilePreviewButtonStates()
        layoutContent(width: Layout.width)
        return host
    }

    private func layoutContent(width: CGFloat) {
        let contentSectionHeight = Layout.sectionHeight(rowCount: typeOptions.count)
        let filePreviewSectionHeight = Layout.sectionHeight(rowCount: filePreviewOptions.count)
        titleLabel?.frame = NSRect(
            x: 0,
            y: Layout.height - Layout.titleHeight,
            width: width,
            height: Layout.titleHeight
        )
        contentSectionView?.frame = NSRect(
            x: 0,
            y: Layout.height - Layout.titleHeight - Layout.titleToSectionSpacing - contentSectionHeight,
            width: width,
            height: contentSectionHeight
        )
        filePreviewTitleLabel?.frame = NSRect(
            x: 0,
            y: filePreviewSectionHeight + Layout.sectionTitleToSectionSpacing,
            width: width,
            height: Layout.sectionTitleHeight
        )
        filePreviewSectionView?.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: filePreviewSectionHeight
        )
        layoutRows(in: contentSectionView, rowCount: typeOptions.count, width: width, buttons: contentTypeButtons)
        layoutRows(
            in: filePreviewSectionView,
            rowCount: filePreviewOptions.count,
            width: width,
            buttons: filePreviewButtons
        )
    }

    private func makeRow(in section: NSView, rowCount: Int, index: Int, width: CGFloat) -> PasteraSettingsRowView {
        let rowY = Layout.sectionHeight(rowCount: rowCount)
            - Layout.sectionInsetY
            - Layout.rowHeight
            - CGFloat(index) * (Layout.rowHeight + Layout.rowSpacing)
        return PasteraSettingsRowView(frame: NSRect(
            x: Layout.sectionInsetX,
            y: rowY,
            width: width - Layout.sectionInsetX * 2,
            height: Layout.rowHeight
        ))
    }

    private func layoutRows(
        in section: PasteraSettingsSectionView?,
        rowCount: Int,
        width: CGFloat,
        buttons: [NSButton]
    ) {
        guard let section else { return }
        let rows = section.subviews.compactMap { $0 as? PasteraSettingsRowView }
        rows.enumerated().forEach { index, row in
            row.frame = makeRow(in: section, rowCount: rowCount, index: index, width: width).frame
            buttons[safe: index]?.frame = NSRect(origin: .zero, size: row.frame.size)
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

    private func makeFilePreviewCheckbox(option: TypeOption, rowSize: NSSize) -> NSButton {
        let button = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(filePreviewCheckboxChanged(_:)))
        button.frame = NSRect(origin: .zero, size: rowSize)
        button.identifier = NSUserInterfaceItemIdentifier(option.key)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.state = isFilePreviewEnabled(option.key) ? .on : .off
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

    private func isFilePreviewEnabled(_ key: String) -> Bool {
        guard let value = filePreviewTypes[key] else { return true }
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
        updateFilePreviewButtonStates()
    }

    @objc private func filePreviewCheckboxChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        filePreviewTypes[key] = NSNumber(value: sender.state == .on)
    }

    private func updateFilePreviewButtonStates() {
        let filesEnabled = isTypeEnabled(PasteboardAvailableType.filenames.rawValue)
        filePreviewButtons.forEach { $0.isEnabled = filesEnabled }
    }

    private func refreshAppearance() {
        PasteraSemanticViewStyler.apply(to: view, appearance: view.effectiveAppearance)
        (view as? PasteraSettingsPaneHost)?.refreshAppearance()
    }

}
