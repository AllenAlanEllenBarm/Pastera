//
//  PasteraManualUpdateService.swift
//
//  Pastera
//

import CryptoKit
import Foundation

enum PasteraManualUpdateError: Error, Equatable {
    case invalidReleaseMetadata
    case updateAssetNotFound
    case untrustedReleaseAsset
    case sizeMismatch
    case digestMismatch
    case requestFailed
    case invalidResponse
    case downloadsDirectoryUnavailable
    case cannotSaveInstaller
    case cancelled
}

struct PasteraManualUpdateAsset: Equatable, Sendable {
    let fileName: String
    let downloadURL: URL
    let size: Int64
    let sha256: String
}

private struct PasteraGitHubRelease: Decodable {
    let tagName: String
    let assets: [PasteraGitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct PasteraGitHubReleaseAsset: Decodable {
    let name: String
    let contentType: String
    let state: String
    let size: Int64
    let digest: String?
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case state
        case size
        case digest
        case downloadURL = "browser_download_url"
    }
}

enum PasteraManualUpdateAssetResolver {
    static func resolve(
        releaseData: Data,
        expectedVersion: String,
        expectedTag: String
    ) throws -> PasteraManualUpdateAsset {
        let release: PasteraGitHubRelease
        do {
            release = try JSONDecoder().decode(PasteraGitHubRelease.self, from: releaseData)
        } catch {
            throw PasteraManualUpdateError.invalidReleaseMetadata
        }

        guard expectedTag == "v\(expectedVersion)"
                || expectedTag.hasPrefix("v\(expectedVersion)-"),
              release.tagName == expectedTag else {
            throw PasteraManualUpdateError.invalidReleaseMetadata
        }

        let expectedName = "Pastera-\(expectedTag.dropFirst())-macOS.dmg"
        let matchingAssets = release.assets.filter {
            $0.contentType == "application/x-apple-diskimage"
                && $0.state == "uploaded"
                && $0.name == expectedName
        }
        guard matchingAssets.count == 1,
              let asset = matchingAssets.first else {
            throw PasteraManualUpdateError.updateAssetNotFound
        }

        guard asset.size > 0,
              let digest = asset.digest,
              digest.hasPrefix("sha256:") else {
            throw PasteraManualUpdateError.invalidReleaseMetadata
        }
        let sha256 = String(digest.dropFirst("sha256:".count)).lowercased()
        guard sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit }) else {
            throw PasteraManualUpdateError.invalidReleaseMetadata
        }
        guard isTrusted(asset: asset, tagName: release.tagName) else {
            throw PasteraManualUpdateError.untrustedReleaseAsset
        }

        return PasteraManualUpdateAsset(
            fileName: asset.name,
            downloadURL: asset.downloadURL,
            size: asset.size,
            sha256: sha256
        )
    }

    static func releaseAPIURL(for releasePageURL: URL) throws -> URL {
        let tag = try releaseTag(for: releasePageURL)
        return URL(string: "https://api.github.com/repos/pastera-app/Pastera/releases/tags/")!
            .appendingPathComponent(tag)
    }

    static func releaseTag(for releasePageURL: URL) throws -> String {
        let path = releasePageURL.pathComponents.filter { $0 != "/" }
        guard releasePageURL.scheme == "https",
              releasePageURL.host == "github.com",
              releasePageURL.query == nil,
              releasePageURL.fragment == nil,
              path.count == 5,
              path[0] == "pastera-app",
              path[1] == "Pastera",
              path[2] == "releases",
              path[3] == "tag" else {
            throw PasteraManualUpdateError.invalidReleaseMetadata
        }

        return path[4]
    }

    private static func isTrusted(asset: PasteraGitHubReleaseAsset, tagName: String) -> Bool {
        let expectedPath = "/pastera-app/Pastera/releases/download/\(tagName)/\(asset.name)"
        return asset.downloadURL.scheme == "https"
            && asset.downloadURL.host == "github.com"
            && asset.downloadURL.query == nil
            && asset.downloadURL.fragment == nil
            && asset.downloadURL.path == expectedPath
            && asset.downloadURL.lastPathComponent == asset.name
    }
}

enum PasteraManualUpdateVerifier {
    static func verify(
        fileURL: URL,
        expectedSize: Int64,
        expectedSHA256: String,
        cancellationToken: PasteraManualUpdateCancellationToken? = nil
    ) throws {
        try cancellationToken?.checkCancellation()
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == expectedSize else {
            throw PasteraManualUpdateError.sizeMismatch
        }

        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try cancellationToken?.checkCancellation()
            hasher.update(data: data)
        }
        try cancellationToken?.checkCancellation()
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256.lowercased() else {
            throw PasteraManualUpdateError.digestMismatch
        }
    }
}

final class PasteraManualUpdateCancellationToken: @unchecked Sendable {
    private enum State {
        case active
        case cancelled
        case committed
    }

    private let lock = NSLock()
    private var state = State.active

    @discardableResult
    func cancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .active:
            state = .cancelled
            return true
        case .cancelled:
            return true
        case .committed:
            return false
        }
    }

    func checkCancellation() throws {
        lock.lock()
        let cancelled = state == .cancelled
        lock.unlock()
        if cancelled {
            throw PasteraManualUpdateError.cancelled
        }
    }

    func performCommitIfActive<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard state == .active else {
            throw PasteraManualUpdateError.cancelled
        }
        let result = try operation()
        state = .committed
        return result
    }
}

enum PasteraManualUpdateFileFinalizer {
    static func moveVerifiedFile(
        at temporaryURL: URL,
        to downloadsDirectory: URL,
        fileName: String,
        cancellationToken: PasteraManualUpdateCancellationToken
    ) throws -> URL {
        try cancellationToken.checkCancellation()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let destinationURL = PasteraManualUpdateDownloadService.availableDestinationURL(
            directoryURL: downloadsDirectory,
            fileName: fileName
        )
        do {
            try cancellationToken.performCommitIfActive {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch let error as PasteraManualUpdateError {
            throw error
        } catch {
            throw PasteraManualUpdateError.cannotSaveInstaller
        }
        return destinationURL
    }
}

@MainActor
final class PasteraManualUpdateDownloadService: NSObject {
    typealias ProgressHandler = @MainActor (_ completedBytes: Int64, _ totalBytes: Int64) -> Void
    typealias CompletionHandler = @MainActor (Result<URL, Error>) -> Void

    private let session: URLSession
    private let downloadsDirectory: URL?
    private var metadataTask: URLSessionDataTask?
    private var downloadTask: URLSessionDownloadTask?
    private var progressTimer: Timer?
    private var progressHandler: ProgressHandler?
    private var expectedSize: Int64 = 0
    private var operationID: UUID?
    private var cancellationToken: PasteraManualUpdateCancellationToken?

    init(
        session: URLSession = .shared,
        downloadsDirectory: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    ) {
        self.session = session
        self.downloadsDirectory = downloadsDirectory
        super.init()
    }

    deinit {
        metadataTask?.cancel()
        downloadTask?.cancel()
        cancellationToken?.cancel()
        progressTimer?.invalidate()
    }

    func start(
        update: PasteraManualUpdateDescriptor,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        abandon()
        let operationID = UUID()
        let cancellationToken = PasteraManualUpdateCancellationToken()
        self.operationID = operationID
        self.cancellationToken = cancellationToken
        progressHandler = progress

        let apiURL: URL
        let releaseTag: String
        do {
            apiURL = try PasteraManualUpdateAssetResolver.releaseAPIURL(for: update.releasePageURL)
            releaseTag = try PasteraManualUpdateAssetResolver.releaseTag(for: update.releasePageURL)
        } catch {
            finishDownload()
            completion(.failure(error))
            return
        }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pastera-Updater", forHTTPHeaderField: "User-Agent")
        metadataTask = session.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self, self.operationID == operationID else { return }
                self.metadataTask = nil
                guard error == nil else {
                    self.finishDownload()
                    completion(.failure(PasteraManualUpdateError.requestFailed))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data else {
                    self.finishDownload()
                    completion(.failure(PasteraManualUpdateError.invalidResponse))
                    return
                }

                do {
                    let asset = try PasteraManualUpdateAssetResolver.resolve(
                        releaseData: data,
                        expectedVersion: update.displayVersion,
                        expectedTag: releaseTag
                    )
                    try self.startAssetDownload(
                        asset: asset,
                        operationID: operationID,
                        cancellationToken: cancellationToken,
                        progress: progress,
                        completion: completion
                    )
                } catch {
                    self.finishDownload()
                    completion(.failure(error))
                }
            }
        }
        metadataTask?.resume()
    }

    @discardableResult
    func cancel() -> Bool {
        guard cancellationToken?.cancel() != false else { return false }
        clearOperation()
        return true
    }

    func abandon() {
        cancellationToken?.cancel()
        clearOperation()
    }
}

private extension PasteraManualUpdateDownloadService {
    func clearOperation() {
        cancellationToken = nil
        metadataTask?.cancel()
        metadataTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        progressTimer?.invalidate()
        progressTimer = nil
        progressHandler = nil
        expectedSize = 0
        operationID = nil
    }

    func finishDownload() {
        progressTimer?.invalidate()
        progressTimer = nil
        downloadTask = nil
        progressHandler = nil
        expectedSize = 0
        operationID = nil
        cancellationToken = nil
    }
}

extension PasteraManualUpdateDownloadService {
    nonisolated static func availableDestinationURL(directoryURL: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        let preferredURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: preferredURL.path) else { return preferredURL }

        let sourceURL = URL(fileURLWithPath: fileName)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var suffix = 2
        while true {
            let candidateName = pathExtension.isEmpty
                ? "\(baseName)-\(suffix)"
                : "\(baseName)-\(suffix).\(pathExtension)"
            let candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }
}

private extension PasteraManualUpdateDownloadService {
    func startAssetDownload(
        asset: PasteraManualUpdateAsset,
        operationID: UUID,
        cancellationToken: PasteraManualUpdateCancellationToken,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) throws {
        guard let downloadsDirectory else {
            throw PasteraManualUpdateError.downloadsDirectoryUnavailable
        }
        expectedSize = asset.size
        progressHandler = progress

        let task = session.downloadTask(with: asset.downloadURL) { temporaryURL, response, error in
            let result: Result<URL, Error> = Result {
                guard error == nil else {
                    throw PasteraManualUpdateError.requestFailed
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let temporaryURL else {
                    throw PasteraManualUpdateError.invalidResponse
                }

                try PasteraManualUpdateVerifier.verify(
                    fileURL: temporaryURL,
                    expectedSize: asset.size,
                    expectedSHA256: asset.sha256,
                    cancellationToken: cancellationToken
                )
                return try PasteraManualUpdateFileFinalizer.moveVerifiedFile(
                    at: temporaryURL,
                    to: downloadsDirectory,
                    fileName: asset.fileName,
                    cancellationToken: cancellationToken
                )
            }

            Task { @MainActor [weak self] in
                guard let self, self.operationID == operationID else { return }
                self.finishDownload()
                completion(result)
            }
        }
        downloadTask = task
        task.resume()
        progressTimer = Timer.scheduledTimer(
            timeInterval: 0.15,
            target: self,
            selector: #selector(reportProgress),
            userInfo: nil,
            repeats: true
        )
    }

    @objc func reportProgress() {
        guard let task = downloadTask else { return }
        progressHandler?(task.countOfBytesReceived, expectedSize)
    }

}
