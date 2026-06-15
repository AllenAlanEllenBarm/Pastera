//
//  CPYWindowAppearance.swift
//
//  Clipy
//

import Cocoa

enum CPYWindowAppearance {
    static let opacityDidChangeNotification = Notification.Name("com.pasteraapp.windowAppearance.opacityDidChange")
    static let defaultOpacity = 0.94
    static let minimumOpacity = 0.0
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

    static func setOpacity(_ value: Double, defaults: UserDefaults = AppEnvironment.current.defaults) {
        let opacity = normalizedOpacity(value)
        defaults.set(opacity, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        defaults.synchronize()
        applyToVisibleWindows(defaults: defaults)
        NotificationCenter.default.post(
            name: opacityDidChangeNotification,
            object: defaults,
            userInfo: ["opacity": opacity]
        )
    }

    static func backgroundColor(
        for appearance: NSAppearance? = nil,
        defaults: UserDefaults = AppEnvironment.current.defaults
    ) -> NSColor {
        PasteraDesignTokens.colors(
            for: appearance,
            opacity: CGFloat(opacity(defaults: defaults))
        ).panelBackground
    }

    static func backgroundColor(defaults: UserDefaults = AppEnvironment.current.defaults) -> NSColor {
        backgroundColor(for: nil, defaults: defaults)
    }

    static func surfaceColor(
        for appearance: NSAppearance? = nil,
        defaults: UserDefaults = AppEnvironment.current.defaults
    ) -> NSColor {
        PasteraDesignTokens.colors(
            for: appearance,
            opacity: CGFloat(opacity(defaults: defaults))
        ).surface
    }

    static func apply(to window: NSWindow?, defaults: UserDefaults = AppEnvironment.current.defaults) {
        guard let window else { return }
        window.identifier = managedWindowIdentifier
        applyAppearance(to: window, defaults: defaults)
    }

    private static func applyAppearance(to window: NSWindow, defaults: UserDefaults) {
        let appearance = window.effectiveAppearance
        let colors = PasteraDesignTokens.colors(
            for: appearance,
            opacity: CGFloat(opacity(defaults: defaults))
        )
        let isFloatingPanel = window is NSPanel
        let targetBackgroundColor = colors.panelBackground

        window.isOpaque = false
        window.backgroundColor = targetBackgroundColor
        window.hasShadow = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = isFloatingPanel
            ? NSColor.clear.cgColor
            : targetBackgroundColor.cgColor
        window.contentView?.layer?.isOpaque = false
        applyOpaqueTopNavigationBackgrounds(in: window.contentView, backgroundColor: colors.surface)
    }

    static func apply(to view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func applyToVisibleWindows(defaults: UserDefaults = AppEnvironment.current.defaults) {
        NSApp.windows
            .filter { $0.identifier == managedWindowIdentifier }
            .forEach { applyAppearance(to: $0, defaults: defaults) }
    }

    private static func applyOpaqueTopNavigationBackgrounds(in contentView: NSView?, backgroundColor: NSColor) {
        guard let contentView else { return }

        contentView.subviews
            .filter { isTopNavigationView($0, in: contentView) }
            .forEach { view in
                applyOpaqueBackground(to: view, backgroundColor: backgroundColor)
                applyOpaqueTopNavigationItemBackgrounds(in: view, backgroundColor: backgroundColor)
            }
    }

    private static func applyOpaqueTopNavigationItemBackgrounds(in navigationView: NSView, backgroundColor: NSColor) {
        navigationView.subviews
            .filter { isTopNavigationItemView($0, in: navigationView) }
            .forEach { applyOpaqueBackground(to: $0, backgroundColor: backgroundColor) }
    }

    private static func applyOpaqueBackground(to view: NSView, backgroundColor: NSColor) {
        view.wantsLayer = true
        view.layer?.backgroundColor = backgroundColor.cgColor
        view.layer?.isOpaque = false
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
