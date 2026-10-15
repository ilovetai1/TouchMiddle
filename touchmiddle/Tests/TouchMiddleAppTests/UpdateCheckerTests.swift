import XCTest
import TouchMiddleCore
@testable import TouchMiddle

private actor FakeReleaseClient: GitHubReleaseFetching {
    private(set) var calls = 0
    var releases: [GitHubRelease]
    var failure: UpdateCheckError?
    private var pending: CheckedContinuation<Void, Never>?
    private var shouldSuspend = false

    init(_ releases: [GitHubRelease]) { self.releases = releases }
    func setFailure(_ error: UpdateCheckError?) { failure = error }
    func suspendNextRequest() { shouldSuspend = true }
    func resume() { pending?.resume(); pending = nil }
    func fetchReleases() async throws -> [GitHubRelease] {
        calls += 1
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { pending = $0 }
        }
        if let failure { throw failure }
        return releases
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var info: [String: Any] {
        ["CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "5", "TMPrereleaseIdentifier": "beta.1"]
    }
    private let newer = GitHubRelease(tagName: "v0.3.0-beta.2", body: "新增更新檢查", isPrerelease: true)

    private func preferences() -> UserDefaults {
        let name = "TouchMiddle.UpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testAutomaticChecksPersistAcrossRestartAndAllowExact24HourBoundary() async {
        let defaults = preferences(), client = FakeReleaseClient([newer])
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = UpdateChecker(info: info, client: client, defaults: defaults, now: { date })
        await first.check(automatically: true)
        XCTAssertEqual(first.availableUpdate, newer)
        date.addTimeInterval(86_399)
        let restarted = UpdateChecker(info: info, client: client, defaults: defaults, now: { date })
        XCTAssertEqual(restarted.availableUpdate, newer)
        await restarted.check(automatically: true)
        var calls = await client.calls
        XCTAssertEqual(calls, 1)
        date.addTimeInterval(1)
        await restarted.check(automatically: true)
        calls = await client.calls
        XCTAssertEqual(calls, 2)
    }

    func testManualCheckBypassesDailyIntervalAndPresentsNotesAgain() async {
        let client = FakeReleaseClient([newer])
        let checker = UpdateChecker(info: info, client: client, defaults: preferences())
        var presentations = 0
        checker.onUpdateAvailable = { presentations += 1 }
        await checker.check(automatically: true)
        await checker.check(automatically: true)
        await checker.check()
        let calls = await client.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(presentations, 2)
        XCTAssertEqual(checker.availableUpdate?.body, "新增更新檢查")
    }

    func testAutomaticNotificationDoesNotRepeatSameVersionAfterRestart() async {
        let defaults = preferences(), client = FakeReleaseClient([newer])
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let checker = UpdateChecker(info: info, client: client, defaults: defaults, now: { date })
        var presentations = 0
        checker.onUpdateAvailable = { presentations += 1 }
        await checker.check(automatically: true)
        date.addTimeInterval(86_400)
        let restarted = UpdateChecker(info: info, client: client, defaults: defaults, now: { date })
        restarted.onUpdateAvailable = { presentations += 1 }
        await restarted.check(automatically: true)
        XCTAssertEqual(presentations, 1)
        XCTAssertNotNil(restarted.availableUpdate)
    }

    func testFailuresRemainVisibleAcrossRestartAndDoNotTriggerAutomaticRetry() async {
        let defaults = preferences(), client = FakeReleaseClient([newer])
        await client.setFailure(.httpStatus(503))
        let checker = UpdateChecker(info: info, client: client, defaults: defaults)
        await checker.check(automatically: true)
        XCTAssertNotNil(checker.errorMessage)
        XCTAssertFalse(checker.statusMessage.contains("已是最新"))
        XCTAssertNil(checker.lastSuccess)
        let restarted = UpdateChecker(info: info, client: client, defaults: defaults)
        XCTAssertNotNil(restarted.errorMessage)
        await restarted.check(automatically: true)
        let calls = await client.calls
        XCTAssertEqual(calls, 1)
        await client.setFailure(nil)
        await restarted.check()
        XCTAssertNil(restarted.errorMessage)
        XCTAssertNotNil(restarted.lastSuccess)
    }

    func testRateLimitBlocksManualAndAutomaticRequestsUntilServerDeadline() async {
        let client = FakeReleaseClient([newer])
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = date.addingTimeInterval(3600)
        await client.setFailure(.rateLimited(until: deadline))
        let defaults = preferences()
        let checker = UpdateChecker(info: info, client: client, defaults: defaults, now: { date })
        await checker.check()
        let restarted = UpdateChecker(info: info, client: client, defaults: defaults, now: { date })
        await restarted.check()
        var calls = await client.calls
        XCTAssertEqual(calls, 1)
        await client.setFailure(nil)
        date = deadline
        await restarted.check()
        calls = await client.calls
        XCTAssertEqual(calls, 2)
        XCTAssertNil(restarted.errorMessage)
    }

    func testConcurrentManualAndAutomaticChecksUseSingleRequest() async {
        let client = FakeReleaseClient([newer])
        await client.suspendNextRequest()
        let checker = UpdateChecker(info: info, client: client, defaults: preferences())
        let first = Task { await checker.check() }
        while !checker.isChecking { await Task.yield() }
        await checker.check()
        await checker.check(automatically: true)
        await client.resume()
        await first.value
        let calls = await client.calls
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(checker.isChecking)
    }

    func testEqualOrOlderVersionDoesNotOfferDowngrade() async {
        let client = FakeReleaseClient([GitHubRelease(tagName: "v0.3.0-beta.1"), GitHubRelease(tagName: "v0.2.2")])
        let checker = UpdateChecker(info: info, client: client, defaults: preferences())
        await checker.check()
        XCTAssertNil(checker.availableUpdate)
        XCTAssertTrue(checker.statusMessage.contains("已是最新"))
        XCTAssertNil(checker.errorMessage)
    }

    func testMissingVersionAndCorruptHistoryAreObservableFailures() async {
        let client = FakeReleaseClient([newer])
        let missingVersion = UpdateChecker(info: [:], client: client, defaults: preferences())
        await missingVersion.check()
        XCTAssertNotNil(missingVersion.errorMessage)
        let defaults = preferences()
        defaults.set(Data("invalid".utf8), forKey: UpdateChecker.historyKey)
        let corrupt = UpdateChecker(info: info, client: client, defaults: defaults)
        await corrupt.check(automatically: true)
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(corrupt.errorMessage)
        await corrupt.check()
        XCTAssertNil(corrupt.errorMessage)
        XCTAssertNotNil(corrupt.availableUpdate)
    }

    func testEmptyOrUnrecognizedReleaseListDoesNotClaimLatest() async {
        for releases in [[], [GitHubRelease(tagName: "nightly")]] {
            let checker = UpdateChecker(info: info, client: FakeReleaseClient(releases), defaults: preferences())
            await checker.check()
            XCTAssertNotNil(checker.errorMessage)
            XCTAssertFalse(checker.statusMessage.contains("已是最新"))
        }
    }

    func testDownloadButtonOpensReleasePageAndReportsBrowserFailure() async {
        var opened: URL?
        let checker = UpdateChecker(info: info, client: FakeReleaseClient([newer]), defaults: preferences(), openURL: {
            opened = $0
            return false
        })
        await checker.check()
        XCTAssertNil(opened)
        checker.openDownloadPage()
        XCTAssertEqual(opened?.absoluteString, "https://github.com/ilovetai1/TouchMiddle/releases/tag/v0.3.0-beta.2")
        XCTAssertNotNil(checker.errorMessage)
    }

    func testInstalledVersionCombinesPlistVersionAndOptionalPrereleaseIdentifier() throws {
        XCTAssertEqual(try InstalledReleaseVersion(info: info).version, ReleaseVersion("0.3.0-beta.1"))
        var stable = info
        stable.removeValue(forKey: "TMPrereleaseIdentifier")
        XCTAssertEqual(try InstalledReleaseVersion(info: stable).version, ReleaseVersion("0.3.0"))
        for invalid in ["", "beta.01", "beta.1+extra"] {
            var bad = info
            bad["TMPrereleaseIdentifier"] = invalid
            XCTAssertThrowsError(try InstalledReleaseVersion(info: bad))
        }
    }
}
