import XCTest
@testable import TouchMiddleCore

final class ReleaseVersionTests: XCTestCase {
    func testSemanticVersionPrecedenceIncludingBetaNumbersAndStableRelease() throws {
        let ordered = ["0.3.0-alpha", "0.3.0-alpha.1", "0.3.0-alpha.beta", "0.3.0-beta.2",
                       "0.3.0-beta.10", "0.3.0-rc.1", "0.3.0", "0.3.1-beta.1", "0.10.0", "1.0.0"]
        let versions = try ordered.map { try XCTUnwrap(ReleaseVersion($0)) }
        XCTAssertEqual(versions.reversed().sorted(), versions)
        XCTAssertEqual(ReleaseVersion("v0.3.0-beta.1+build.9"), ReleaseVersion("0.3.0-beta.1"))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("1.0.0-beta.999999999999999999999")),
                          try XCTUnwrap(ReleaseVersion("1.0.0-beta.1000000000000000000000")))
    }

    func testMalformedVersionsCannotBeUsedAsUpdateTargets() {
        for text in ["", "v", "0.3", "0.3.0.1", "01.3.0", "0.3.0-", "0.3.0-beta.01", "0.3.0-beta..1",
                     "0.3.0+", "0.3.0+a+b", "0.3.0-beta/1", "0.3.0\n", "０.3.0", "0.3.0-測試"] {
            XCTAssertNil(ReleaseVersion(text), text)
        }
    }

    func testNewestIncludesPrereleasesSkipsDraftsAndDoesNotDependOnListOrder() {
        let releases = [
            GitHubRelease(tagName: "v0.3.0"),
            GitHubRelease(tagName: "v0.4.0-beta.10", body: "New features", isPrerelease: true),
            GitHubRelease(tagName: "v2.0.0", isDraft: true),
            GitHubRelease(tagName: "v0.4.0-beta.2", isPrerelease: true),
            GitHubRelease(tagName: "nightly")
        ]
        XCTAssertEqual(GitHubRelease.newest(in: releases)?.tagName, "v0.4.0-beta.10")
        XCTAssertEqual(GitHubRelease.newest(in: releases.reversed())?.body, "New features")
        XCTAssertNil(GitHubRelease.newest(in: [GitHubRelease(tagName: "nightly")]))
        XCTAssertNil(GitHubRelease.newest(in: []))
    }

    func testStableReleaseSupersedesBetaAndDownloadURLIsPinnedToProject() {
        let beta = GitHubRelease(tagName: "v0.4.0-beta.2", isPrerelease: true)
        let stable = GitHubRelease(tagName: "v0.4.0")
        XCTAssertEqual(GitHubRelease.newest(in: [stable, beta]), stable)
        XCTAssertEqual(beta.downloadPageURL?.absoluteString,
                       "https://github.com/ilovetai1/TouchMiddle/releases/tag/v0.4.0-beta.2")
        XCTAssertNil(GitHubRelease(tagName: "https://example.com/update").downloadPageURL)
    }

    func testGitHubNullReleaseNotesAndNamesAreAccepted() throws {
        let data = Data(#"[{"tag_name":"v0.4.0-beta.1","name":null,"body":null,"draft":false,"prerelease":true}]"#.utf8)
        let release = try XCTUnwrap(JSONDecoder().decode([GitHubRelease].self, from: data).first)
        XCTAssertEqual(release.tagName, "v0.4.0-beta.1")
        XCTAssertTrue(release.isPrerelease)
        XCTAssertNil(release.body)
    }
}
