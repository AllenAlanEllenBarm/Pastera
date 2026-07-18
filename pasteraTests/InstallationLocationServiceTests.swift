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
    func enablingLaunchAtLoginRegistersMainAppService() throws {
        var registerCount = 0
        var unregisterCount = 0
        let controller = LaunchAtLoginController(
            register: { registerCount += 1 },
            unregister: { unregisterCount += 1 }
        )

        try controller.setEnabled(true)

        #expect(registerCount == 1)
        #expect(unregisterCount == 0)
    }

    @Test
    func disablingLaunchAtLoginUnregistersMainAppService() throws {
        var registerCount = 0
        var unregisterCount = 0
        let controller = LaunchAtLoginController(
            register: { registerCount += 1 },
            unregister: { unregisterCount += 1 }
        )

        try controller.setEnabled(false)

        #expect(registerCount == 0)
        #expect(unregisterCount == 1)
    }

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
