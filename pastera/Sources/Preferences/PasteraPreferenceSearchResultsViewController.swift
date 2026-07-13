//
//  PasteraPreferenceSearchResultsViewController.swift
//
//  Pastera
//

import AppKit

// swiftlint:disable:next type_name
final class PasteraPreferenceSearchResultsViewController: NSViewController {
    var onActivate: ((PasteraPreferenceSearchItem) -> Void)?

    private let documentView = PasteraPreferenceFlippedView()
    private let resultsStack = NSStackView()
    private var resultItems = [PasteraPreferenceSearchItem]()

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView

        documentView.translatesAutoresizingMaskIntoConstraints = false
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 6
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(resultsStack)

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            resultsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            resultsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            resultsStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            resultsStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -24)
        ])
        view = scrollView
    }

    func updateResults(_ pages: [PasteraPreferenceCatalogPage]) {
        _ = view
        resultsStack.arrangedSubviews.forEach {
            resultsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        resultItems = pages.flatMap(\.searchItems)

        guard !pages.isEmpty else {
            let emptyLabel = NSTextField(labelWithString: pasteraPreferenceString("No Settings Found"))
            emptyLabel.textColor = .secondaryLabelColor
            resultsStack.addArrangedSubview(emptyLabel)
            return
        }

        for page in pages {
            let groupLabel = NSTextField(labelWithString: page.title)
            groupLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            groupLabel.textColor = .secondaryLabelColor
            resultsStack.addArrangedSubview(groupLabel)

            for item in page.searchItems {
                let button = PasteraPreferenceSearchResultButton(item: item)
                button.target = self
                button.action = #selector(resultButtonTapped(_:))
                resultsStack.addArrangedSubview(button)
                button.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
            }
        }
    }

    func activateFirstResult() -> Bool {
        guard let item = resultItems.first else { return false }
        onActivate?(item)
        return true
    }

    @objc private func resultButtonTapped(_ sender: PasteraPreferenceSearchResultButton) {
        onActivate?(sender.item)
    }
}

private final class PasteraPreferenceSearchResultButton: NSButton {
    let item: PasteraPreferenceSearchItem

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    init(item: PasteraPreferenceSearchItem) {
        self.item = item
        super.init(frame: .zero)
        title = item.title
        image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: item.title)
        imagePosition = .imageTrailing
        alignment = .left
        isBordered = false
        font = .systemFont(ofSize: 13, weight: .medium)
        setAccessibilityLabel("\(item.title)，\(item.subtitle)")
    }

    required init?(coder: NSCoder) {
        nil
    }
}
