//
//  PasteraAppIconProvider.swift
//
//  Clipy
//

import Cocoa

enum PasteraAppIconProvider {

    @MainActor
    static func installApplicationIcon(bundle: Bundle = .main) {
        installApplicationIcon(on: NSApplication.shared, bundle: bundle)
    }

    @MainActor
    static func installApplicationIcon(on application: NSApplication, bundle: Bundle = .main) {
        application.applicationIconImage = applicationIcon(bundle: bundle)
    }

    static func applicationIcon(bundle: Bundle = .main) -> NSImage {
        if let image = appIconFromBundle(bundle: bundle) {
            return image
        }

        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 64, height: 64))
    }

    static func appIconFromBundle(bundle: Bundle = .main) -> NSImage? {
        guard let iconURL = bundle.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            return nil
        }

        image.isTemplate = false
        return image
    }

}
