import XCTest
import TouchMiddleCore
@testable import TouchMiddle

private actor ReleaseTransport {
    struct Reply: Sendable {
        let status: Int
        let data: Data
        var headers: [String: String] = [:]
    }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        return (reply.data, HTTPURLResponse(url: request.url!, statusCode: reply.status,
                    httpVersion: "HTTP/1.1", headerFields: reply.headers)!)
    }
}

final class GitHubReleaseClientTests: XCTestCase {
    func testRequestsPublicListIncludingBetasAndPreservesNotes() async throws {
        let releases = [GitHubRelease(tagName: "v0.4.0-beta.2", body: "## 更新\n- 保留規則", isPrerelease: true)]
        let transport = ReleaseTransport([.init(status: 200, data: try JSONEncoder().encode(releases))])
        let client = GitHubReleaseClient { try await transport.send($0) }
        let result = try await client.fetchReleases()
        XCTAssertEqual(result, releases)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.github.com/repos/ilovetai1/TouchMiddle/releases?per_page=100&page=1")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testPaginatesRatherThanMissingNewerVersionOnSecondPage() async throws {
        let first = Array(repeating: GitHubRelease(tagName: "v0.3.0"), count: 100)
        let second = [GitHubRelease(tagName: "v0.4.0-beta.2", isPrerelease: true)]
        let transport = ReleaseTransport([
            .init(status: 200, data: try JSONEncoder().encode(first)),
            .init(status: 200, data: try JSONEncoder().encode(second))
        ])
        let releases = try await GitHubReleaseClient { try await transport.send($0) }.fetchReleases()
        XCTAssertEqual(GitHubRelease.newest(in: releases)?.tagName, "v0.4.0-beta.2")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].url!.absoluteString.hasSuffix("page=2"))
    }

    func testHTTPAndMalformedDataFailInsteadOfReportingLatest() async {
        for (status, data) in [(500, Data()), (403, Data()), (200, Data("{}".utf8))] {
            let transport = ReleaseTransport([.init(status: status, data: data)])
            do {
                _ = try await GitHubReleaseClient { try await transport.send($0) }.fetchReleases()
                XCTFail("Expected an observable failure for \(status)")
            } catch {
                XCTAssertTrue(error is UpdateCheckError)
            }
        }
    }

    func testRateLimitHonorsServerResetAndRetryAfter() async {
        let reset = Date().addingTimeInterval(3600).timeIntervalSince1970
        for status in [403, 429] {
            let transport = ReleaseTransport([.init(status: status, data: Data(), headers: [
                "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(reset), "Retry-After": "120"
            ])])
            do {
                _ = try await GitHubReleaseClient { try await transport.send($0) }.fetchReleases()
                XCTFail("Expected rate limit")
            } catch UpdateCheckError.rateLimited(let until) {
                XCTAssertGreaterThanOrEqual(until.timeIntervalSince1970, reset)
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testPaginationLimitFailsWithoutReturningPartialResults() async throws {
        let page = try JSONEncoder().encode(Array(repeating: GitHubRelease(tagName: "v0.3.0"), count: 100))
        let transport = ReleaseTransport(Array(repeating: .init(status: 200, data: page), count: 10))
        do {
            _ = try await GitHubReleaseClient { try await transport.send($0) }.fetchReleases()
            XCTFail("Expected incomplete-list failure")
        } catch UpdateCheckError.tooManyPages { }
    }
}
