//
//  CPYPreferencesWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/25.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class CPYPreferencesWindowController: NSWindowController {
    static let sharedController = CPYPreferencesWindowController()

    private enum Pane: Int, CaseIterable {
        case general
        case menu
        case type
        case exclude
        case shortcuts
        case updates
        case beta

        var title: String {
            switch self {
            case .general:
                return String(localized: "General")
            case .menu:
                return String(localized: "Menu")
            case .type:
                return String(localized: "Types")
            case .exclude:
                return String(localized: "Exclude")
            case .shortcuts:
                return String(localized: "Shortcuts")
            case .updates:
                return String(localized: "Update")
            case .beta:
                return String(localized: "Beta")
            }
        }

        var symbolName: String {
            switch self {
            case .general:
                return "switch.2"
            case .menu:
                return "list.bullet"
            case .type:
                return "doc"
            case .exclude:
                return "nosign"
            case .shortcuts:
                return "command"
            case .updates:
                return "arrow.triangle.2.circlepath"
            case .beta:
                return "testtube.2"
            }
        }
    }

    private enum Metrics {
        static let sidebarWidth: CGFloat = 132
        static let sidebarInset: CGFloat = 10
        static let paneInset: CGFloat = 18
        static let minimumWidth: CGFloat = 620
        static let minimumHeight: CGFloat = 360
        static let maximumPaneWidth: CGFloat = 700
    }

    private let rootView = NSView()
    private let sidebarView = NSView()
    private let sidebarStack = NSStackView()
    private let separatorView = NSView()
    private let paneContainerView = NSView()
    private var sidebarButtons = [PasteraPreferenceSidebarButton]()
    private let viewController: [NSViewController] = [
        CPYGeneralPreferenceViewController(nibName: "CPYGeneralPreferenceViewController", bundle: nil),
        NSViewController(nibName: "CPYMenuPreferenceViewController", bundle: nil),
        CPYTypePreferenceViewController(nibName: "CPYTypePreferenceViewController", bundle: nil),
        CPYExcludeAppPreferenceViewController(nibName: "CPYExcludeAppPreferenceViewController", bundle: nil),
        CPYShortcutsPreferenceViewController(nibName: "CPYShortcutsPreferenceViewController", bundle: nil),
        CPYUpdatesPreferenceViewController(nibName: "CPYUpdatesPreferenceViewController", bundle: nil),
        CPYBetaPreferenceViewController(nibName: "CPYBetaPreferenceViewController", bundle: nil)
    ]
    private var selectedView: NSView?
    private var selectedTabIndex = -1
    private var paneSizes = [Int: NSSize]()
    private var didPreloadPaneViews = false
    private var defaultsObserver: NSObjectProtocol?
    private var hasShownWindow = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Pastera - Settings")
        window.minSize = NSSize(width: Metrics.minimumWidth, height: Metrics.minimumHeight)
        super.init(window: window)
        window.delegate = self
        setupContent()
        installOpacityObserver()
        preloadPaneViews()
        switchView(Pane.general.rawValue)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if !hasShownWindow {
            window?.center()
            hasShownWindow = true
        }
        CPYWindowAppearance.apply(to: window)
        window?.makeKeyAndOrderFront(self)
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }
}

extension CPYPreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let viewController = viewController[Pane.type.rawValue] as? CPYTypePreferenceViewController {
            AppEnvironment.current.defaults.set(viewController.storeTypes, forKey: Constants.UserDefaults.storeTypes)
            AppEnvironment.current.defaults.synchronize()
        }
        if let window = window, !window.makeFirstResponder(window) {
            window.endEditing(for: nil)
        }
        NSApp.deactivate()
    }
}

private extension CPYPreferencesWindowController {
    func setupContent() {
        guard let window else { return }
        let tokens = PasteraDesignTokens.colors()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        window.contentView = rootView

        sidebarView.wantsLayer = true
        sidebarView.layer?.backgroundColor = tokens.surface.cgColor
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = tokens.separator.cgColor
        paneContainerView.wantsLayer = true
        paneContainerView.layer?.backgroundColor = NSColor.clear.cgColor

        sidebarStack.orientation = .vertical
        sidebarStack.spacing = 4
        sidebarStack.alignment = .leading
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false

        [sidebarView, separatorView, paneContainerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview($0)
        }
        sidebarView.addSubview(sidebarStack)

        Pane.allCases.forEach { pane in
            let button = PasteraPreferenceSidebarButton(title: pane.title, symbolName: pane.symbolName)
            button.tag = pane.rawValue
            button.target = self
            button.action = #selector(sidebarButtonTapped(_:))
            sidebarButtons.append(button)
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth - Metrics.sidebarInset * 2).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }

        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: Metrics.sidebarInset),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -Metrics.sidebarInset),
            sidebarStack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 14),

            separatorView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            separatorView.topAnchor.constraint(equalTo: rootView.topAnchor),
            separatorView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: PasteraDesignTokens.Metrics.hairlineWidth),

            paneContainerView.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor),
            paneContainerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            paneContainerView.topAnchor.constraint(equalTo: rootView.topAnchor),
            paneContainerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    @objc func sidebarButtonTapped(_ sender: PasteraPreferenceSidebarButton) {
        switchView(sender.tag)
    }

    func switchView(_ index: Int) {
        guard viewController.indices.contains(index), index != selectedTabIndex else { return }
        let newView = viewController[index].view
        let paneSize = paneSizes[index] ?? newView.frame.size
        CPYWindowAppearance.apply(to: newView)

        selectedView?.removeFromSuperview()
        newView.translatesAutoresizingMaskIntoConstraints = false
        paneContainerView.addSubview(newView)

        NSLayoutConstraint.activate([
            newView.leadingAnchor.constraint(equalTo: paneContainerView.leadingAnchor, constant: Metrics.paneInset),
            newView.trailingAnchor.constraint(lessThanOrEqualTo: paneContainerView.trailingAnchor, constant: -Metrics.paneInset),
            newView.topAnchor.constraint(equalTo: paneContainerView.topAnchor, constant: Metrics.paneInset),
            newView.widthAnchor.constraint(equalToConstant: min(paneSize.width, Metrics.maximumPaneWidth)),
            newView.heightAnchor.constraint(equalToConstant: paneSize.height)
        ])

        selectedView = newView
        selectedTabIndex = index
        updateSidebarSelection(index)
        resizeWindow(for: paneSize)
        CPYWindowAppearance.apply(to: window)
    }

    func updateSidebarSelection(_ index: Int) {
        sidebarButtons.forEach { $0.isSelected = $0.tag == index }
    }

    func resizeWindow(for paneSize: NSSize) {
        guard let window else { return }
        let contentWidth = max(
            Metrics.minimumWidth,
            Metrics.sidebarWidth + Metrics.paneInset * 2 + min(paneSize.width, Metrics.maximumPaneWidth)
        )
        let contentHeight = max(Metrics.minimumHeight, paneSize.height + Metrics.paneInset * 2)
        let oldFrame = window.frame
        var newFrame = window.frameRect(forContentRect: NSRect(
            origin: .zero,
            size: NSSize(width: contentWidth, height: contentHeight)
        ))
        newFrame.origin = oldFrame.origin
        newFrame.origin.y += oldFrame.height - newFrame.height
        window.setFrame(newFrame, display: true)
    }

    func preloadPaneViews() {
        guard !didPreloadPaneViews else { return }
        didPreloadPaneViews = true
        viewController.enumerated().forEach { index, viewController in
            let paneView = viewController.view
            CPYWindowAppearance.apply(to: paneView)
            paneSizes[index] = paneView.frame.size
        }
    }

    func installOpacityObserver() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: AppEnvironment.current.defaults,
            queue: .main
        ) { [weak self] _ in
            CPYWindowAppearance.apply(to: self?.window)
            self?.refreshBackgroundColors()
        }
    }

    func refreshBackgroundColors() {
        let tokens = PasteraDesignTokens.colors()
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        sidebarView.layer?.backgroundColor = tokens.surface.cgColor
        separatorView.layer?.backgroundColor = tokens.separator.cgColor
        sidebarButtons.forEach { $0.refreshAppearance() }
    }
}

private final class PasteraPreferenceSidebarButton: NSButton {
    var isSelected = false {
        didSet {
            refreshAppearance()
        }
    }

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshAppearance()
    }

    func refreshAppearance() {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        } else if isHovered {
            layer?.backgroundColor = PasteraDesignTokens.colors().hoveredRow.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        let textColor: NSColor = isSelected ? .controlAccentColor : .labelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium),
                .foregroundColor: textColor
            ]
        )
    }

    private func setup() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        imagePosition = .imageLeading
        alignment = .left
        font = .systemFont(ofSize: 13, weight: .medium)
        setAccessibilityLabel(title)
        refreshAppearance()
    }
}
