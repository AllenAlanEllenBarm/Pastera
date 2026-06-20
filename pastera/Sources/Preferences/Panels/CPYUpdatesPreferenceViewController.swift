//
//  CPYUpdatesPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Combine
import Sparkle

class CPYUpdatesPreferenceViewController: NSViewController {

    // MARK: - Properties
    @IBOutlet private weak var lastUpdateCheckDateTextField: NSTextField!
    @IBOutlet private weak var versionTextField: NSTextField!

    private var updaterController: SPUStandardUpdaterController? {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return nil }
        return appDelegate.updaterController
    }
    private let releaseUpdateChecker = PasteraGitHubReleaseUpdateChecker()
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Initialize
    override func loadView() {
        super.loadView()
        updaterController?.updater.publisher(for: \.lastUpdateCheckDate)
            .compactMap { $0 }
            .assign(to: \.objectValue, on: lastUpdateCheckDateTextField)
            .store(in: &cancellables)
        versionTextField.stringValue = "v\(Bundle.main.appVersion ?? "")"
    }

    @IBAction private func checkForUpdates(_ sender: Any) {
        let currentVersion = Bundle.main.appVersion ?? ""
        releaseUpdateChecker.fetchLatestRelease { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(.some(let release)) where self.releaseUpdateChecker.isUpdateAvailable(
                    currentVersion: currentVersion,
                    releaseVersion: release.version
                ):
                    self.presentGitHubUpdate(release)
                case .success(.some(let release)):
                    self.presentNoGitHubUpdate(latestVersion: release.version)
                case .success(nil):
                    self.presentNoGitHubUpdate(latestVersion: currentVersion)
                case .failure:
                    self.checkForSparkleUpdates(sender)
                }
            }
        }
    }

    private func checkForSparkleUpdates(_ sender: Any) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.updaterController?.checkForUpdates(sender)
    }

    private func presentGitHubUpdate(_ update: PasteraAvailableUpdate) {
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "Pastera %@ is available."), update.version)
        alert.informativeText = String(localized: "Open the GitHub release page to download this version.")
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(update.releasePageURL)
    }

    private func presentNoGitHubUpdate(latestVersion: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "You're up to date!")
        alert.informativeText = String(
            format: String(localized: "Pastera %@ is the latest published version."),
            latestVersion
        )
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}

struct PasteraAvailableUpdate: Equatable {
    let version: String
    let releasePageURL: URL
    let assetURL: URL?
}

final class PasteraGitHubReleaseUpdateChecker {
    private let releasesURL = URL(string: "https://api.github.com/repos/pastera-app/Pastera/releases?per_page=10")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestRelease(completion: @escaping (Result<PasteraAvailableUpdate?, Error>) -> Void) {
        let task = session.dataTask(with: releasesURL) { [weak self] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            guard let self, let data else {
                completion(.success(nil))
                return
            }

            do {
                completion(.success(try self.latestRelease(from: data)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    func availableUpdate(currentVersion: String, from data: Data) throws -> PasteraAvailableUpdate? {
        guard let release = try latestRelease(from: data),
              isUpdateAvailable(currentVersion: currentVersion, releaseVersion: release.version) else {
            return nil
        }
        return release
    }

    func latestRelease(from data: Data) throws -> PasteraAvailableUpdate? {
        let releases = try JSONDecoder().decode([PasteraGitHubRelease].self, from: data)
        let latest = releases
            .filter { !$0.draft }
            .compactMap { release -> (release: PasteraGitHubRelease, version: PasteraReleaseVersion)? in
                let version = PasteraReleaseVersion(release.tagName)
                return (release, version)
            }
            .max { $0.version < $1.version }

        guard let latest else { return nil }
        let asset = latest.release.assets.first { $0.name.hasSuffix(".dmg") } ?? latest.release.assets.first
        return PasteraAvailableUpdate(
            version: latest.version.displayString,
            releasePageURL: latest.release.htmlURL,
            assetURL: asset?.browserDownloadURL
        )
    }

    func isUpdateAvailable(currentVersion: String, releaseVersion: String) -> Bool {
        PasteraReleaseVersion(releaseVersion) > PasteraReleaseVersion(currentVersion)
    }
}

private struct PasteraGitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let assets: [PasteraGitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case assets
    }
}

private struct PasteraGitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct PasteraReleaseVersion: Comparable {
    let displayString: String
    private let components: [Int]
    private let prereleaseRank: Int

    init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let normalized = withoutPrefix.lowercased()
        displayString = withoutPrefix
        components = normalized
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
        prereleaseRank = normalized.contains("beta") ? 0 : 1
    }

    static func < (lhs: PasteraReleaseVersion, rhs: PasteraReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        if lhs.prereleaseRank != rhs.prereleaseRank {
            return lhs.prereleaseRank < rhs.prereleaseRank
        }
        return false
    }
}
