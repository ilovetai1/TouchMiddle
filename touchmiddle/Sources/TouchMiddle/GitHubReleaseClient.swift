import Foundation
import TouchMiddleCore

protocol GitHubReleaseFetching: Sendable {
    func fetchReleases() async throws -> [GitHubRelease]
}

enum UpdateCheckError: LocalizedError {
    case invalidInstalledVersion, invalidResponse, noComparableReleases, tooManyPages
    case httpStatus(Int)
    case rateLimited(until: Date)
    case invalidHistory
    case cannotOpenDownloadPage

    var errorDescription: String? {
        switch self {
        case .invalidInstalledVersion: "目前 App 的版本資訊缺失或無效，無法檢查更新。"
        case .invalidResponse: "GitHub 回傳無效的版本資料，無法確認是否有新版。"
        case .noComparableReleases: "GitHub 尚無可辨識的已發布版本，無法確認是否有新版。"
        case .tooManyPages: "GitHub 版本清單超過檢查上限，無法確認最新版本。"
        case .httpStatus(let code): "GitHub 版本查詢失敗（HTTP \(code)），請稍後手動重試。"
        case .rateLimited(let date): "GitHub 暫時限制查詢，請在 \(date.formatted(date: .abbreviated, time: .shortened)) 後重試。"
        case .invalidHistory: "更新檢查記錄無法讀取。請按「檢查更新」重新查詢。"
        case .cannotOpenDownloadPage: "無法開啟下載頁，請確認預設瀏覽器設定後重試。"
        }
    }
}

struct GitHubReleaseClient: GitHubReleaseFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    init(transport: @escaping Transport) { self.transport = transport }

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        transport = { try await session.data(for: $0) }
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        var releases: [GitHubRelease] = []
        // Read every page rather than assuming publication order is version order.
        // A bounded failure must not be reported as "up to date".
        for page in 1...10 {
            let url = URL(string: "https://api.github.com/repos/ilovetai1/TouchMiddle/releases?per_page=100&page=\(page)")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("TouchMiddle-UpdateCheck", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
            if response.statusCode == 429 || (response.statusCode == 403 &&
                (response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" ||
                 response.value(forHTTPHeaderField: "Retry-After") != nil)) {
                let now = Date()
                let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
                    .map { Date(timeIntervalSince1970: $0) }
                let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    .map { now.addingTimeInterval($0) }
                throw UpdateCheckError.rateLimited(until: max(now.addingTimeInterval(60), reset ?? now, retry ?? now))
            }
            guard response.statusCode == 200 else { throw UpdateCheckError.httpStatus(response.statusCode) }
            let entries: [GitHubRelease]
            do { entries = try JSONDecoder().decode([GitHubRelease].self, from: data) }
            catch { throw UpdateCheckError.invalidResponse }
            releases.append(contentsOf: entries)
            if entries.count < 100 { return releases }
        }
        throw UpdateCheckError.tooManyPages
    }
}
