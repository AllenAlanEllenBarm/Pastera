//
//  CPYWindowAppearanceTests.swift
//
//  Clipy
//

import Cocoa
import Testing
@testable import Pastera

@Suite
struct CPYWindowAppearanceTests {
    @Test
    func normalizedOpacityClampsToSupportedRange() {
        #expect(CPYWindowAppearance.normalizedOpacity(0.1) == CPYWindowAppearance.minimumOpacity)
        #expect(CPYWindowAppearance.normalizedOpacity(0.5) == 0.5)
        #expect(CPYWindowAppearance.normalizedOpacity(2.0) == CPYWindowAppearance.maximumOpacity)
    }

    @Test
    func normalizedOpacityUsesDefaultForNonFiniteValues() {
        #expect(CPYWindowAppearance.normalizedOpacity(.nan) == CPYWindowAppearance.defaultOpacity)
        #expect(CPYWindowAppearance.normalizedOpacity(.infinity) == CPYWindowAppearance.defaultOpacity)
    }

    @Test
    func opacityUsesDefaultWhenPreferenceIsMissing() throws {
        let suiteName = "CPYWindowAppearanceTests.default.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(CPYWindowAppearance.opacity(defaults: defaults) == CPYWindowAppearance.defaultOpacity)
    }

    @Test
    func opacityReadsAndClampsStoredPreference() throws {
        let suiteName = "CPYWindowAppearanceTests.stored.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(0.2, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        #expect(CPYWindowAppearance.opacity(defaults: defaults) == CPYWindowAppearance.minimumOpacity)

        defaults.set(0.72, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        #expect(CPYWindowAppearance.opacity(defaults: defaults) == 0.72)
    }

    @Test @MainActor
    func applyingWindowAppearancePreservesTitlebarTransparency() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = false
        CPYWindowAppearance.apply(to: window)
        #expect(window.titlebarAppearsTransparent == false)

        window.titlebarAppearsTransparent = true
        CPYWindowAppearance.apply(to: window)
        #expect(window.titlebarAppearsTransparent == true)
    }

    @Test @MainActor
    func applyingWindowAppearanceKeepsTopNavigationBackgroundOpaque() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let paneView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 184))
        let navigationView = NSView(frame: NSRect(x: 0, y: 184, width: 320, height: 56))
        contentView.addSubview(paneView)
        contentView.addSubview(navigationView)
        window.contentView = contentView

        CPYWindowAppearance.apply(to: window)

        #expect(contentView.layer?.backgroundColor == NSColor.clear.cgColor)
        #expect(paneView.layer?.backgroundColor == nil)
        #expect(navigationView.layer?.backgroundColor?.alpha == 1)
    }

    @Test @MainActor
    func applyingWindowAppearanceKeepsTopNavigationItemBackgroundsOpaque() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let navigationView = NSView(frame: NSRect(x: 0, y: 184, width: 320, height: 56))
        let navigationItemView = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 56))
        navigationView.addSubview(navigationItemView)
        contentView.addSubview(navigationView)
        window.contentView = contentView

        CPYWindowAppearance.apply(to: window)

        #expect(navigationView.layer?.backgroundColor?.alpha == 1)
        #expect(navigationItemView.layer?.backgroundColor?.alpha == 1)
    }

    @Test @MainActor
    func applyToVisibleWindowsOnlyUpdatesManagedClipyWindows() throws {
        let suiteName = "CPYWindowAppearanceTests.visible.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let managedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let unmanagedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer {
            managedWindow.close()
            unmanagedWindow.close()
        }

        defaults.set(0.9, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        CPYWindowAppearance.apply(to: managedWindow, defaults: defaults)
        unmanagedWindow.backgroundColor = .systemRed
        unmanagedWindow.isOpaque = true
        managedWindow.orderFront(nil)
        unmanagedWindow.orderFront(nil)

        defaults.set(0.45, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        CPYWindowAppearance.applyToVisibleWindows(defaults: defaults)

        #expect(managedWindow.backgroundColor.alphaComponent == 0.45)
        #expect(unmanagedWindow.backgroundColor == .systemRed)
        #expect(unmanagedWindow.isOpaque)
    }

    @Test @MainActor
    func generalPreferenceOpacityControlDoesNotShiftExistingPaneContent() {
        let controller = CPYGeneralPreferenceViewController(
            nibName: "CPYGeneralPreferenceViewController",
            bundle: nil
        )

        let paneView = controller.view
        let textFieldMaxY = paneView.subviews
            .compactMap { $0 as? NSTextField }
            .map(\.frame.maxY)
            .max()

        #expect(Int(paneView.frame.height.rounded()) == 259)
        #expect(Int((textFieldMaxY ?? 0).rounded()) == 247)
    }

}
