//
//  InstallationLocationServiceTests.swift
//
//  Pastera
//
//  Created by Codex on 2026/06/15.
//

import Foundation
import Testing
@testable import Pastera

struct InstallationLocationServiceTests {
    @Test
    func applicationsFolderDoesNotNeedMoveRecommendation() {
        let service = InstallationLocationService(homeDirectory: URL(fileURLWithPath: "/Users/alice"))
        let appURL = URL(fileURLWithPath: "/Applications/Pastera.app")

        #expect(service.status(for: appURL) == .applications)
        #expect(!service.shouldRecommendMoveToApplications(for: appURL))
    }

    @Test
    func mountedDiskImageNeedsMoveRecommendation() {
        let service = InstallationLocationService(homeDirectory: URL(fileURLWithPath: "/Users/alice"))
        let appURL = URL(fileURLWithPath: "/Volumes/Pastera/Pastera.app")

        #expect(service.status(for: appURL) == .mountedDiskImage)
        #expect(service.shouldRecommendMoveToApplications(for: appURL))
    }

    @Test
    func downloadsFolderNeedsMoveRecommendation() {
        let service = InstallationLocationService(homeDirectory: URL(fileURLWithPath: "/Users/alice"))
        let appURL = URL(fileURLWithPath: "/Users/alice/Downloads/Pastera.app")

        #expect(service.status(for: appURL) == .downloads)
        #expect(service.shouldRecommendMoveToApplications(for: appURL))
    }

    @Test
    func appTranslocationNeedsMoveRecommendation() {
        let service = InstallationLocationService(homeDirectory: URL(fileURLWithPath: "/Users/alice"))
        let appURL = URL(fileURLWithPath: "/private/var/folders/ab/cd/T/AppTranslocation/123/d/Pastera.app")

        #expect(service.status(for: appURL) == .appTranslocation)
        #expect(service.shouldRecommendMoveToApplications(for: appURL))
    }
}
