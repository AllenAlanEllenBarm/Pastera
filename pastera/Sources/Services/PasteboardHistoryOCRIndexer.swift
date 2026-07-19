//
//  PasteboardHistoryOCRIndexer.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/07/08.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import Combine
import CryptoKit
import Dependencies
import ImageIO
import Vision

protocol PasteboardImageTextRecognizing {
    func recognizeText(in imageData: Data) throws -> String
}

protocol PasteboardHistoryOCRIndexing {
    func enqueueIndexing(historyID: PasteboardHistory.ID)
    func backfillMissingImageOCR(limit: Int)
    func recognizeText(
        historyID: PasteboardHistory.ID,
        content: PasteboardContent
    ) async -> Result<String, PasteboardHistoryOCRRecognitionError>
}

extension PasteboardHistoryOCRIndexing {
    func recognizeText(
        historyID _: PasteboardHistory.ID,
        content _: PasteboardContent
    ) async -> Result<String, PasteboardHistoryOCRRecognitionError> {
        .failure(.unsupportedImageSource)
    }
}

enum PasteboardHistoryOCRRecognitionError: Error, Equatable {
    case unsupportedImageSource
    case recognitionFailed
}

enum PasteboardHistoryOCRTextLimits {
    static let maxRecognizedTextLength = 16 * 1024

    static func normalized(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count > maxRecognizedTextLength else { return trimmedText }
        return String(trimmedText.prefix(maxRecognizedTextLength))
    }
}

enum PasteboardHistoryOCRActivity: Equatable {
    case idle
    case indexing(remaining: Int)
    case completed(processed: Int, skipped: Int)
}

struct PasteboardHistoryOCRImageSource: Equatable {
    let data: Data
    let sourceHash: String
}

final class PasteboardHistoryOCRIndexer: PasteboardHistoryOCRIndexing {
    typealias Scheduler = (@escaping () -> Void) -> Void

    static let shared = PasteboardHistoryOCRIndexer()
    static let maxSourceImageBytes = 12 * 1024 * 1024
    static let activityDidChangeNotification = Notification.Name("PasteraOCRActivityDidChange")

    private static let queue = DispatchQueue(label: "com.pastera-app.Pastera.ocr-indexer", qos: .utility)

    private let repository: any PasteboardHistoryRepositoryProtocol
    private let recognizer: any PasteboardImageTextRecognizing
    private let scheduler: Scheduler
    private let now: () -> Int
    private var isPumpScheduled = false
    private var processedCount = 0
    private var skippedCount = 0
    private var activityGeneration = 0

    init(
        repository: any PasteboardHistoryRepositoryProtocol = PasteboardHistoryRepository(),
        recognizer: any PasteboardImageTextRecognizing = VisionPasteboardImageTextRecognizer(),
        scheduler: @escaping Scheduler = { work in PasteboardHistoryOCRIndexer.queue.async { work() } },
        now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }
    ) {
        self.repository = repository
        self.recognizer = recognizer
        self.scheduler = scheduler
        self.now = now
    }

    func enqueueIndexing(historyID: PasteboardHistory.ID) {
        scheduler { [weak self] in
            guard let self else { return }
            repository.enqueueOCRJob(historyID: historyID, priority: 1, enqueuedAt: now())
            schedulePumpIfNeeded()
        }
    }

    func backfillMissingImageOCR(limit: Int) {
        guard limit > 0 else { return }
        scheduler { [weak self] in
            self?.startBackfill(limit: limit)
        }
    }

    private func startBackfill(limit: Int) {
        guard !isPumpScheduled else { return }
        let candidateIDs = repository.fetchOCRIndexingCandidateIDs(limit: limit)
        guard !candidateIDs.isEmpty else { return }
        for (offset, historyID) in candidateIDs.enumerated() {
            repository.enqueueOCRJob(historyID: historyID, priority: 0, enqueuedAt: now() - offset)
        }
        schedulePumpIfNeeded()
    }

    private func schedulePumpIfNeeded() {
        guard !isPumpScheduled else { return }
        isPumpScheduled = true
        publish(.indexing(remaining: repository.countOCRJobs()))
        processNextJob()
    }

    private func processNextJob() {
        guard let historyID = repository.fetchNextOCRJobID() else {
            isPumpScheduled = false
            let completed = PasteboardHistoryOCRActivity.completed(
                processed: processedCount,
                skipped: skippedCount
            )
            processedCount = 0
            skippedCount = 0
            publish(completed)
            return
        }

        var succeeded = false
        autoreleasepool {
            if let content = repository.fetchContent(id: historyID) {
                succeeded = Self.index(
                    historyID: historyID,
                    content: content,
                    repository: repository,
                    recognizer: recognizer,
                    now: now
                )
            } else {
                succeeded = true
            }
            repository.deleteOCRJob(historyID: historyID)
        }
        if succeeded { processedCount += 1 } else { skippedCount += 1 }
        publish(.indexing(remaining: repository.countOCRJobs()))

        scheduler { [weak self] in
            self?.processNextJob()
        }
    }

    func recognizeText(
        historyID: PasteboardHistory.ID,
        content: PasteboardContent
    ) async -> Result<String, PasteboardHistoryOCRRecognitionError> {
        guard let source = Self.imageSource(from: content) else {
            return .failure(.unsupportedImageSource)
        }
        if let existingText = repository.fetchOCRText(historyID: historyID),
           existingText.sourceHash == source.sourceHash {
            return .success(existingText.recognizedText)
        }
        if let existingText = repository.fetchOCRText(sourceHash: source.sourceHash) {
            _ = repository.upsertOCRText(
                historyID: historyID,
                sourceHash: source.sourceHash,
                recognizedText: existingText.recognizedText,
                updatedAt: now()
            )
            return .success(existingText.recognizedText)
        }
        return await withCheckedContinuation { continuation in
            scheduler { [repository, recognizer, now] in
                do {
                    let text = PasteboardHistoryOCRTextLimits.normalized(
                        try recognizer.recognizeText(in: source.data)
                    )
                    _ = repository.upsertOCRText(
                        historyID: historyID,
                        sourceHash: source.sourceHash,
                        recognizedText: text,
                        updatedAt: now()
                    )
                    continuation.resume(returning: .success(text))
                } catch {
                    continuation.resume(returning: .failure(.recognitionFailed))
                }
            }
        }
    }

    static func imageSource(from content: PasteboardContent) -> PasteboardHistoryOCRImageSource? {
        if let asset = content.assets.first(where: { $0.type.isClipyImageType }),
           asset.data.count <= maxSourceImageBytes,
           canCreateImage(from: asset.data) {
            return PasteboardHistoryOCRImageSource(
                data: asset.data,
                sourceHash: sourceHash(kind: asset.type.rawValue, data: asset.data)
            )
        }

        guard let imageURL = content.assets
            .filter({ $0.type == .fileURL })
            .compactMap({ URL(dataRepresentation: $0.data, relativeTo: nil) })
            .first(where: { PasteraFileTypeClassifier.kind(for: $0) == .image }),
            isFileSizeWithinSourceLimit(imageURL),
            let imageData = try? Data(contentsOf: imageURL),
            imageData.count <= maxSourceImageBytes,
            canCreateImage(from: imageData) else {
            return nil
        }
        return PasteboardHistoryOCRImageSource(
            data: imageData,
            sourceHash: sourceHash(kind: imageURL.path, data: imageData)
        )
    }

    @discardableResult
    private static func index(
        historyID: PasteboardHistory.ID,
        content: PasteboardContent,
        repository: any PasteboardHistoryRepositoryProtocol,
        recognizer: any PasteboardImageTextRecognizing,
        now: () -> Int
    ) -> Bool {
        guard let source = imageSource(from: content) else {
            repository.deleteOCRText(historyID: historyID)
            return false
        }

        if let existingText = repository.fetchOCRText(sourceHash: source.sourceHash) {
            _ = repository.upsertOCRText(
                historyID: historyID,
                sourceHash: source.sourceHash,
                recognizedText: existingText.recognizedText,
                updatedAt: now()
            )
            return true
        }

        guard let recognizedText = try? recognizer.recognizeText(in: source.data) else {
            repository.deleteOCRText(historyID: historyID)
            return false
        }

        _ = repository.upsertOCRText(
            historyID: historyID,
            sourceHash: source.sourceHash,
            recognizedText: PasteboardHistoryOCRTextLimits.normalized(recognizedText),
            updatedAt: now()
        )
        return true
    }

    private func publish(_ activity: PasteboardHistoryOCRActivity) {
        activityGeneration += 1
        let generation = activityGeneration
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.activityDidChangeNotification,
                object: activity
            )
        }
        guard case .completed = activity else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, generation == activityGeneration else { return }
            NotificationCenter.default.post(name: Self.activityDidChangeNotification, object: PasteboardHistoryOCRActivity.idle)
        }
    }

    private static func isFileSizeWithinSourceLimit(_ url: URL) -> Bool {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return false
        }
        return fileSize <= maxSourceImageBytes
    }

    private static func canCreateImage(from data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    private static func sourceHash(kind: String, data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.utf8))
        hasher.update(data: data)
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct VisionPasteboardImageTextRecognizer: PasteboardImageTextRecognizing {
    func recognizeText(in imageData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
        let recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter { supportedLanguages.contains($0) }
        if !recognitionLanguages.isEmpty {
            request.recognitionLanguages = recognitionLanguages
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }
}

private enum PasteboardHistoryOCRIndexerKey: DependencyKey {
    static var liveValue: any PasteboardHistoryOCRIndexing { PasteboardHistoryOCRIndexer.shared }
    static var testValue: any PasteboardHistoryOCRIndexing { NoopPasteboardHistoryOCRIndexer() }
}

extension DependencyValues {
    var pasteboardHistoryOCRIndexer: PasteboardHistoryOCRIndexing {
        get { self[PasteboardHistoryOCRIndexerKey.self] }
        set { self[PasteboardHistoryOCRIndexerKey.self] = newValue }
    }
}

private struct NoopPasteboardHistoryOCRIndexer: PasteboardHistoryOCRIndexing {
    func enqueueIndexing(historyID _: PasteboardHistory.ID) {}
    func backfillMissingImageOCR(limit _: Int) {}
    func recognizeText(
        historyID _: PasteboardHistory.ID,
        content _: PasteboardContent
    ) async -> Result<String, PasteboardHistoryOCRRecognitionError> {
        .failure(.unsupportedImageSource)
    }
}
