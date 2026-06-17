//
//  InstallationLocationService.swift
//
//  Pastera
//
//  Created by Codex on 2026/06/15.
//

import Cocoa
import Foundation

final class InstallationLocationService {
    enum Status: Equatable {
        case applications
        case mountedDiskImage
        case downloads
        case appTranslocation
        case outsideApplications
    }

    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    func status(for appURL: URL = Bundle.main.bundleURL) -> Status {
        let path = normalizedPath(appURL)
        let homePath = normalizedPath(homeDirectory)

        if path == "/Applications/Pastera.app" || path.hasPrefix("/Applications/") {
            return .applications
        }

        if path.hasPrefix("/Volumes/") {
            return .mountedDiskImage
        }

        if path.contains("/AppTranslocation/") {
            return .appTranslocation
        }

        if path == "\(homePath)/Downloads/Pastera.app" || path.hasPrefix("\(homePath)/Downloads/") {
            return .downloads
        }

        return .outsideApplications
    }

    func shouldRecommendMoveToApplications(for appURL: URL = Bundle.main.bundleURL) -> Bool {
        return status(for: appURL) != .applications
    }

    func showMoveToApplicationsAlertIfNeeded(appURL: URL = Bundle.main.bundleURL) {
        guard shouldRecommendMoveToApplications(for: appURL) else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Pastera to Applications")
        alert.informativeText = String(localized: "To keep Accessibility permissions stable, move Pastera.app to the Applications folder before enabling Accessibility.")
        alert.addButton(withTitle: String(localized: "Open Applications"))
        alert.addButton(withTitle: String(localized: "Continue"))
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
    }

    private func normalizedPath(_ url: URL) -> String {
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
