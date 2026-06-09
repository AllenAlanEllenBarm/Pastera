//
//  CPYWindowAppearance.swift
//
//  Clipy
//

import Cocoa

enum CPYWindowAppearance {
    static let defaultOpacity = 0.94
    static let minimumOpacity = 0.78
    static let maximumOpacity = 1.0
    private static let topNavigationMinimumHeight: CGFloat = 40
    private static let topNavigationMaximumHeight: CGFloat = 90
    private static let topNavigationEdgeTolerance: CGFloat = 1
    private static let managedWindowIdentifier = NSUserInterfaceItemIdentifier("com.pasteraapp.windowAppearance.managed")

    static func normalizedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultOpacity }
        return min(max(value, minimumOpacity), maximumOpacity)
    }

    static func opacity(defaults: UserDefaults = AppEnvironment.current.defaults) -> Double {
        guard let value = defaults.object(forKey: Constants.UserDefaults.windowBackgroundOpacity) as? NSNumber else {
            return defaultOpacity
        }
        return normalizedOpacity(value.doubleValue)
    }

    static func backgroundColor(defaults: UserDefaults = AppEnvironment.current.defaults) -> NSColor {
        PasteraDesignTokens.colors(opacity: CGFloat(opacity(defaults: defaults))).panelBackground
    }

    static func apply(to window: NSWindow?, defaults: UserDefaults = AppEnvironment.current.defaults) {
        guard let window else { return }
        window.identifier = managedWindowIdentifier
        applyAppearance(to: window, defaults: defaults)
    }

    private static func applyAppearance(to window: NSWindow, defaults: UserDefaults) {
        window.isOpaque = false
        window.backgroundColor = backgroundColor(defaults: defaults)
        window.hasShadow = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        applyOpaqueTopNavigationBackgrounds(in: window.contentView)
    }

    static func apply(to view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func applyToVisibleWindows(defaults: UserDefaults = AppEnvironment.current.defaults) {
        NSApp.windows
            .filter { $0.identifier == managedWindowIdentifier && !($0 is NSPanel) }
            .forEach { applyAppearance(to: $0, defaults: defaults) }
    }

    private static func applyOpaqueTopNavigationBackgrounds(in contentView: NSView?) {
        guard let contentView else { return }

        contentView.subviews
            .filter { isTopNavigationView($0, in: contentView) }
            .forEach { view in
                applyOpaqueBackground(to: view)
                applyOpaqueTopNavigationItemBackgrounds(in: view)
            }
    }

    private static func applyOpaqueTopNavigationItemBackgrounds(in navigationView: NSView) {
        navigationView.subviews
            .filter { isTopNavigationItemView($0, in: navigationView) }
            .forEach { applyOpaqueBackground(to: $0) }
    }

    private static func applyOpaqueBackground(to view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.isOpaque = true
    }

    private static func isTopNavigationView(_ view: NSView, in contentView: NSView) -> Bool {
        let height = view.frame.height
        let touchesTopEdge = abs(view.frame.maxY - contentView.bounds.maxY) <= topNavigationEdgeTolerance
        let spansMostOfWidth = view.frame.width >= contentView.bounds.width * 0.5
        return touchesTopEdge
            && spansMostOfWidth
            && height >= topNavigationMinimumHeight
            && height <= topNavigationMaximumHeight
    }

    private static func isTopNavigationItemView(_ view: NSView, in navigationView: NSView) -> Bool {
        let height = view.frame.height
        let touchesTopEdge = abs(view.frame.maxY - navigationView.bounds.maxY) <= topNavigationEdgeTolerance
        let touchesBottomEdge = abs(view.frame.minY - navigationView.bounds.minY) <= topNavigationEdgeTolerance
        let hasNavigationItemWidth = view.frame.width >= 32 && view.frame.width <= 96
        return touchesTopEdge
            && touchesBottomEdge
            && hasNavigationItemWidth
            && height >= topNavigationMinimumHeight
            && height <= topNavigationMaximumHeight
    }
}
