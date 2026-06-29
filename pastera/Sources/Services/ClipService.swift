//
//  ClipService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Dependencies
import Foundation
import PINCache
import RxSwift
import RxCocoa

final class ClipService {

    // MARK: - Properties
    fileprivate var cachedChangeCount = BehaviorRelay<Int>(value: 0)
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .utility)
    fileprivate let lock = NSRecursiveLock(name: "com.pastera-app.Pastera.ClipUpdatable")
    fileprivate var disposeBag = DisposeBag()

    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository

    // MARK: - Clips
    func startMonitoring() {
        disposeBag = DisposeBag()
        // Pasteboard observe timer
        Observable<Int>.interval(.milliseconds(750), scheduler: scheduler)
            .map { _ in NSPasteboard.general.changeCount }
            .withLatestFrom(cachedChangeCount.asObservable()) { ($0, $1) }
            .filter { $0 != $1 }
            .subscribe(onNext: { [weak self] changeCount, _ in
                guard self?.create() == true else { return }
                self?.cachedChangeCount.accept(changeCount)
            })
            .disposed(by: disposeBag)
        // Store types
        AppEnvironment.current.defaults.rx
            .observe([String: NSNumber].self, Constants.UserDefaults.storeTypes)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.storeTypes = $0
            })
            .disposed(by: disposeBag)
    }

    func clearAll() {
        pasteboardHistoryRepository.deleteAll()
        // Clear legacy Realm-backed history caches used through v1.2.1.
        PINCache.shared.removeAllObjects()
        try? FileManager.default.removeItem(atPath: CPYUtilities.applicationSupportFolder())
    }

    func delete(with history: PasteboardHistory) {
        pasteboardHistoryRepository.deleteHistory(id: history.id)
    }

    func incrementChangeCount() {
        cachedChangeCount.accept(cachedChangeCount.value + 1)
    }

}

// MARK: - Create Clip
extension ClipService {
    @discardableResult
    fileprivate func create(from pasteboard: NSPasteboard = .general) -> Bool {
        lock.lock(); defer { lock.unlock() }

        // Pasteboard types
        let pasteboardTypes = pasteboard.pasteboardItems?.flatMap { $0.types } ?? []
        guard !pasteboardTypes.isEmpty else { return false }
        let types = PasteboardAvailableType.availableTypes(
            from: pasteboardTypes,
            storeAvailableTypes: storeTypes.filter { $0.value.boolValue }.compactMap { PasteboardAvailableType(rawValue: $0.key) }
        )
        guard !types.isEmpty else { return true }

        // Excluded application
        guard !AppEnvironment.current.excludeAppService.frontProcessIsExcludedApplication() else { return true }
        // Special applications
        guard !AppEnvironment.current.excludeAppService.copiedProcessIsExcludedApplications(pasteboard: pasteboard) else { return true }

        guard let content = PasteboardContent(pasteboard: pasteboard, types: types) else { return false }
        return save(content)
    }

    func create(with image: NSImage) {
        lock.lock(); defer { lock.unlock() }

        guard let content = PasteboardContent(image: image) else { return }
        save(content, allowDuplicateContent: true)
    }

    func createScreenshot(from url: URL) {
        lock.lock(); defer { lock.unlock() }

        guard let content = PasteboardContent(imageFileURL: url) else { return }
        save(content, allowDuplicateContent: true)
    }

    @discardableResult
    private func save(_ content: PasteboardContent, allowDuplicateContent: Bool = false) -> Bool {
        // Copy already copied history
        let isCopySameHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory)
        let historyID = PasteboardHistory.ID(rawValue: content.hash)
        if !allowDuplicateContent, pasteboardHistoryRepository.fetchHistory(id: historyID) != nil, !isCopySameHistory { return true }

        // Don't save empty string history
        if content.isOnlyStringType && content.stringValue.isEmpty { return true }

        // Overwrite same history
        let isOverwriteHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
        let savedHash = (isOverwriteHistory && !allowDuplicateContent) ? content.hash : UUID().uuidString

        let unixTime = Int(Date().timeIntervalSince1970)
        pasteboardHistoryRepository.save(id: .init(rawValue: savedHash), content: content, updateAt: unixTime)
        pasteboardHistoryRepository.pruneHistories(settings: HistoryRetentionSettings.current())
        return true
    }
}

#if DEBUG
extension ClipService {
    func setStoreTypesForTesting(_ storeTypes: [String: NSNumber]) {
        self.storeTypes = storeTypes
    }

    @discardableResult
    func createForTesting(from pasteboard: NSPasteboard) -> Bool {
        create(from: pasteboard)
    }
}
#endif
