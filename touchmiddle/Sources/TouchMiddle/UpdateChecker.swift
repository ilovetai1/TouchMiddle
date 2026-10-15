import AppKit
import Combine
import Foundation
import TouchMiddleCore

struct InstalledReleaseVersion {
    let version: ReleaseVersion
    let build: String

    init(info: [String: Any]?) throws {
        guard let base = info?["CFBundleShortVersionString"] as? String,
              let baseVersion = ReleaseVersion(base), !baseVersion.isPrerelease,
              baseVersion.description == base,
              let build = info?["CFBundleVersion"] as? String,
              build.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil else {
            throw UpdateCheckError.invalidInstalledVersion
        }
        if let identifier = info?["TMPrereleaseIdentifier"] {
            guard let identifier = identifier as? String,
                  let version = ReleaseVersion("\(base)-\(identifier)"),
                  version.description == "\(base)-\(identifier)" else {
                throw UpdateCheckError.invalidInstalledVersion
            }
            self.version = version
        } else {
            version = baseVersion
        }
        self.build = build
    }
}

private struct UpdateCheckHistory: Codable {
    var lastAttempt: Date?
    var lastSuccess: Date?
    var retryAfter: Date?
    var latestRelease: GitHubRelease?
    var lastPresentedVersion: String?
    var lastFailure: String?
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let historyKey = "githubUpdateCheckHistory"
    static let automaticInterval: TimeInterval = 24 * 60 * 60
    let installed: InstalledReleaseVersion?
    @Published private(set) var isChecking = false
    @Published private(set) var availableUpdate: GitHubRelease?
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var statusMessage = "尚未檢查更新。"
    @Published private(set) var errorMessage: String?
    var onUpdateAvailable: (() -> Void)?

    private let client: any GitHubReleaseFetching
    private let defaults: UserDefaults
    private let now: () -> Date
    private let openURL: (URL) -> Bool
    private var history = UpdateCheckHistory()
    private var historyIsValid = true
    private var scheduler: Task<Void, Never>?

    init(info: [String: Any]? = Bundle.main.infoDictionary,
         client: any GitHubReleaseFetching = GitHubReleaseClient(),
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.client = client
        self.defaults = defaults
        self.now = now
        self.openURL = openURL
        do { installed = try InstalledReleaseVersion(info: info) }
        catch { installed = nil; errorMessage = error.localizedDescription }
        if let saved = defaults.object(forKey: Self.historyKey) {
            do {
                guard let data = saved as? Data else { throw UpdateCheckError.invalidHistory }
                history = try JSONDecoder().decode(UpdateCheckHistory.self, from: data)
                lastSuccess = history.lastSuccess
                restoreResult()
                errorMessage = errorMessage ?? history.lastFailure
            } catch {
                historyIsValid = false
                errorMessage = UpdateCheckError.invalidHistory.localizedDescription
            }
        }
    }

    /// Runs only while the app is alive. Persisted attempts cover restarts and
    /// failed requests too; manually checking also resets the 24-hour interval.
    func start() {
        guard scheduler == nil else { return }
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check(automatically: true)
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    func stop() { scheduler?.cancel(); scheduler = nil }

    func check(automatically: Bool = false) async {
        guard !isChecking, let installed else { return }
        let date = now()
        if automatically {
            guard historyIsValid else { return }
            if let lastAttempt = history.lastAttempt,
               date.timeIntervalSince(lastAttempt) < Self.automaticInterval { return }
        }
        if let retryAfter = history.retryAfter, date < retryAfter {
            errorMessage = UpdateCheckError.rateLimited(until: retryAfter).localizedDescription
            return
        }
        isChecking = true
        errorMessage = nil
        statusMessage = "正在檢查正式版與測試版…"
        history.lastAttempt = date
        history.retryAfter = nil
        history.lastFailure = nil
        defer { isChecking = false }
        do {
            try persistHistory()
            let releases = try await client.fetchReleases()
            try Task.checkCancellation()
            guard let latest = GitHubRelease.newest(in: releases), let version = latest.version else {
                throw UpdateCheckError.noComparableReleases
            }
            history.latestRelease = latest
            history.lastSuccess = now()
            lastSuccess = history.lastSuccess
            restoreResult()
            let shouldPresent = version > installed.version &&
                (!automatically || history.lastPresentedVersion != version.description)
            if shouldPresent { history.lastPresentedVersion = version.description }
            try persistHistory()
            if shouldPresent { onUpdateAvailable?() }
        } catch {
            if case UpdateCheckError.rateLimited(let until) = error { history.retryAfter = until }
            history.lastFailure = "檢查更新失敗：\(error.localizedDescription)"
            errorMessage = history.lastFailure
            statusMessage = "本次未能確認是否有新版。"
            do { try persistHistory() }
            catch { errorMessage = "無法儲存更新檢查記錄：\(error.localizedDescription)" }
        }
    }

    func openDownloadPage() {
        guard let url = availableUpdate?.downloadPageURL else { return }
        if !openURL(url) { errorMessage = UpdateCheckError.cannotOpenDownloadPage.localizedDescription }
    }

    private func restoreResult() {
        guard let installed, let release = history.latestRelease, let version = release.version else { return }
        availableUpdate = version > installed.version ? release : nil
        statusMessage = availableUpdate == nil ? "目前已是最新版本（含測試版）。" : "發現新版：\(version.description)"
        if history.lastFailure != nil { statusMessage = "上次未能確認是否有新版。" }
    }

    private func persistHistory() throws {
        defaults.set(try JSONEncoder().encode(history), forKey: Self.historyKey)
        historyIsValid = true
    }
}
