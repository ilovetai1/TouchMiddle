import Foundation

public struct GitHubRelease: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let isDraft: Bool
    public let isPrerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body
        case isDraft = "draft", isPrerelease = "prerelease"
    }

    public init(tagName: String, name: String? = nil, body: String? = nil,
                isDraft: Bool = false, isPrerelease: Bool = false) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
    }

    public var version: ReleaseVersion? { ReleaseVersion(tagName) }

    public static func newest(in releases: [Self]) -> Self? {
        releases.filter { !$0.isDraft && $0.version != nil }.max { $0.version! < $1.version! }
    }

    /// Only valid tags from the configured repository can become download links.
    public var downloadPageURL: URL? {
        guard version != nil else { return nil }
        return URL(string: "https://github.com/ilovetai1/TouchMiddle/releases/tag/")?.appendingPathComponent(tagName)
    }
}
