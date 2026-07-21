//
//  PasteraUpdaterFacade.swift
//
//  Pastera
//

import Combine
import Sparkle

@MainActor
protocol PasteraUpdaterFacade: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    var lastUpdateCheckDate: Date? { get }
    var canCheckForUpdates: Bool { get }
    var stateChanges: AnyPublisher<Void, Never> { get }

    func checkForUpdates()
}

@MainActor
final class PasteraSparkleUpdaterFacade: PasteraUpdaterFacade {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { updater.updateCheckInterval }
        set { updater.updateCheckInterval = newValue }
    }

    var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var stateChanges: AnyPublisher<Void, Never> {
        Publishers.Merge(
            updater.publisher(for: \.lastUpdateCheckDate).map { _ in () },
            updater.publisher(for: \.canCheckForUpdates).map { _ in () }
        )
        .eraseToAnyPublisher()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
