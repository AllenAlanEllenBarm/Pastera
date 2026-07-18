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
import CryptoKit
import Dependencies
import ImageIO
import Vision

protocol PasteboardImageTextRecognizing {
    func recognizeText(in imageData: Data) throws -> String
}

protocol PasteboardHistoryOCRIndexing {
    func enqueueIndexing(historyID: PasteboardHistory.ID, content: PasteboardContent)
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

struct PasteboardHistoryOCRImageSource: Equatable {
    let data: Data
    let sourceHash: String
}

final class PasteboardHistoryOCRIndexer: PasteboardHistoryOCRIndexing {
    typealias Scheduler = (@escaping () -> Void) -> Void

    static let shared = PasteboardHistoryOCRIndexer()
    static let maxSourceImageBytes = 12 * 1024 * 1024

    private static let queue = DispatchQueue(label: "com.pastera-app.Pastera.ocr-indexer", qos: .utility)

    private let repository: any PasteboardHistoryRepositoryProtocol
    private let recognizer: any PasteboardImageTextRecognizing
    private let scheduler: Scheduler
    private let now: () -> Int

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

    func enqueueIndexing(historyID: PasteboardHistory.ID, content: PasteboardContent) {
        scheduler { [repository, recognizer, now] in
            Self.index(historyID: historyID, content: content, repository: repository, recognizer: recognizer, now: now)
        }
    }

    func backfillMissingImageOCR(limit: Int) {
        guard limit > 0 else { return }
        scheduler { [repository, recognizer, now] in
            repository.fetchOCRIndexingCandidates(limit: limit).forEach { candidate in
                Self.index(
                    historyID: candidate.historyID,
                    content: candidate.content,
                    repository: repository,
                    recognizer: recognizer,
                    now: now
                )
            }
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

    private static func index(
        historyID: PasteboardHistory.ID,
        content: PasteboardContent,
        repository: any PasteboardHistoryRepositoryProtocol,
        recognizer: any PasteboardImageTextRecognizing,
        now: () -> Int
    ) {
        guard let source = imageSource(from: content) else {
            repository.deleteOCRText(historyID: historyID)
            return
        }

        if let existingText = repository.fetchOCRText(sourceHash: source.sourceHash) {
            _ = repository.upsertOCRText(
                historyID: historyID,
                sourceHash: source.sourceHash,
                recognizedText: existingText.recognizedText,
                updatedAt: now()
            )
            return
        }

        guard let recognizedText = try? recognizer.recognizeText(in: source.data) else {
            repository.deleteOCRText(historyID: historyID)
            return
        }

        _ = repository.upsertOCRText(
            historyID: historyID,
            sourceHash: source.sourceHash,
            recognizedText: PasteboardHistoryOCRTextLimits.normalized(recognizedText),
            updatedAt: now()
        )
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
    func enqueueIndexing(historyID _: PasteboardHistory.ID, content _: PasteboardContent) {}
    func backfillMissingImageOCR(limit _: Int) {}
    func recognizeText(
        historyID _: PasteboardHistory.ID,
        content _: PasteboardContent
    ) async -> Result<String, PasteboardHistoryOCRRecognitionError> {
        .failure(.unsupportedImageSource)
    }
}
