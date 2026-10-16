import XCTest
@testable import TouchMiddleCore

final class TypingGuardTests: XCTestCase {
    func testAdmitsFramesWhenNoKeyWasPressed() {
        var guardState = TypingGuard()
        XCTAssertTrue(guardState.admits(at: 10, activeContactCount: 3))
    }

    func testSuppressesInsideWindowAndAdmitsAtBoundary() {
        var guardState = TypingGuard(window: 0.4)
        guardState.noteKeyDown(at: 10)
        XCTAssertFalse(guardState.admits(at: 10.399, activeContactCount: 0))
        XCTAssertTrue(guardState.isTyping(at: 10.399))
        XCTAssertFalse(guardState.isTyping(at: 10.4))
        XCTAssertTrue(guardState.admits(at: 10.4, activeContactCount: 0))
        XCTAssertTrue(guardState.admits(at: 10.5, activeContactCount: 2))
    }

    func testTouchStartedWhileTypingStaysSuppressedUntilRelease() {
        var guardState = TypingGuard(window: 0.4)
        guardState.noteKeyDown(at: 10)
        XCTAssertFalse(guardState.admits(at: 10.2, activeContactCount: 2))
        XCTAssertFalse(guardState.admits(at: 10.6, activeContactCount: 2))
        // The release frame itself is consumed so the recognizer never sees a partial touch.
        XCTAssertFalse(guardState.admits(at: 10.7, activeContactCount: 0))
        XCTAssertTrue(guardState.admits(at: 10.8, activeContactCount: 3))
    }

    func testLaterKeyPressExtendsWindowAndEarlierTimestampDoesNotShortenIt() {
        var guardState = TypingGuard(window: 0.4)
        guardState.noteKeyDown(at: 10)
        guardState.noteKeyDown(at: 10.3)
        guardState.noteKeyDown(at: 10.1)
        XCTAssertFalse(guardState.admits(at: 10.6, activeContactCount: 0))
        XCTAssertTrue(guardState.admits(at: 10.71, activeContactCount: 0))
    }

    func testResetClearsWindowAndBlock() {
        var guardState = TypingGuard(window: 0.4)
        guardState.noteKeyDown(at: 10)
        XCTAssertFalse(guardState.admits(at: 10.1, activeContactCount: 1))
        guardState.reset()
        XCTAssertTrue(guardState.admits(at: 10.2, activeContactCount: 1))
    }

    func testZeroWindowNeverSuppresses() {
        var guardState = TypingGuard(window: 0)
        guardState.noteKeyDown(at: 10)
        XCTAssertTrue(guardState.admits(at: 10, activeContactCount: 2))
    }
}
