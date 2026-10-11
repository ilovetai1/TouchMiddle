import XCTest
@testable import TouchMiddleCore

final class ThreeFingerTapRecognizerTests: XCTestCase {
    private func contact(_ id: Int, x: Double = 0.5, y: Double = 0.5,
                         phase: TouchPhase = .stationary, palm: Bool = false) -> TouchContact {
        TouchContact(id: id, position: TouchPoint(x: x, y: y), phase: phase, isPalm: palm)
    }

    private func frame(_ time: Double, _ ids: [Int], device: String = "trackpad-A", sequence: UInt64? = nil) -> TouchFrame {
        TouchFrame(deviceID: device, timestamp: time, sequence: sequence, contacts: ids.map { contact($0) })
    }

    func testStaggeredOnsetAndLiftOffEmitsOnlyWhenAllFingersLeave() {
        var recognizer = ThreeFingerTapRecognizer()
        XCTAssertEqual(recognizer.process(frame(0, [1])).snapshot.phase, .collecting)
        XCTAssertTrue(recognizer.process(frame(0.02, [1, 2])).intents.isEmpty)
        XCTAssertEqual(recognizer.process(frame(0.05, [1, 2, 3])).snapshot.phase, .tracking)
        XCTAssertTrue(recognizer.process(frame(0.08, [1, 2, 3])).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.10, [2, 3])).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.12, [3])).intents.isEmpty)
        let result = recognizer.process(frame(0.14, []))
        XCTAssertEqual(result.intents, [.middleClick])
        XCTAssertEqual(result.snapshot.phase, .cooldown)
        XCTAssertTrue(result.diagnostics.contains(.tapRecognized(duration: 0.14)))
        XCTAssertTrue(recognizer.process(frame(0.15, [])).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.16, [])).intents.isEmpty)
    }

    func testExplicitFinalContactsCompleteLiftOffWithoutWaitingForAnotherEmptyFrame() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        _ = recognizer.process(frame(0.04, [1, 2, 3]))
        let ended = TouchFrame(deviceID: "trackpad-A", timestamp: 0.06,
                               contacts: [contact(1, phase: .ended), contact(2, phase: .ended), contact(3, phase: .ended)])
        XCTAssertEqual(recognizer.process(ended).intents, [.middleClick])
        XCTAssertTrue(recognizer.process(frame(0.07, [])).intents.isEmpty)
    }

    func testTwoFingerScrollThenBriefThirdContactDoesNotBecomeTap() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2]))
        let moved = TouchFrame(deviceID: "trackpad-A", timestamp: 0.025,
                               contacts: [contact(1, y: 0.55), contact(2, y: 0.55)])
        let rejection = recognizer.process(moved)
        guard case .gestureRejected(.movementExceeded) = rejection.diagnostics.first else {
            return XCTFail("Scroll movement must cancel the pending group")
        }
        XCTAssertTrue(recognizer.process(frame(0.04, [1, 2, 3])).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.06, [1, 2])).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.08, [])).intents.isEmpty)
    }

    func testExistingTwoFingerHoldCannotRecruitThirdContactOutsideOnsetWindow() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2]))
        XCTAssertEqual(recognizer.process(frame(0.07, [1, 2, 3])).diagnostics,
                       [.gestureRejected(.onsetWindowExceeded)])
        XCTAssertTrue(recognizer.process(frame(0.10, [])).intents.isEmpty)
    }

    func testOneAndTwoFingerTouchesDoNotEmit() {
        for ids in [[1], [1, 2]] {
            var recognizer = ThreeFingerTapRecognizer()
            _ = recognizer.process(frame(0, ids))
            let result = recognizer.process(frame(0.04, []))
            XCTAssertTrue(result.intents.isEmpty)
            XCTAssertEqual(result.diagnostics, [.gestureRejected(.tooFewContacts)])
        }
    }

    func testInsufficientThreeFingerOverlapDoesNotEmit() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2]))
        _ = recognizer.process(frame(0.04, [1, 2, 3]))
        _ = recognizer.process(frame(0.045, [1, 2]))
        let result = recognizer.process(frame(0.06, []))
        XCTAssertEqual(result.diagnostics, [.gestureRejected(.insufficientThreeFingerOverlap)])
        XCTAssertTrue(result.intents.isEmpty)
    }

    func testOneFingerMotionRejectsEvenIfOtherFingersAreStill() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        let moved = TouchFrame(deviceID: "trackpad-A", timestamp: 0.03,
                               contacts: [contact(1), contact(2), contact(3, x: 0.53)])
        let result = recognizer.process(moved)
        XCTAssertEqual(result.snapshot.phase, .blockedUntilRelease)
        guard case .gestureRejected(.movementExceeded(contactID: 3, distance: _)) = result.diagnostics.first else {
            return XCTFail("Per-finger motion must reject the tap")
        }
        XCTAssertTrue(recognizer.process(frame(0.06, [])).intents.isEmpty)
    }

    func testMovementInExplicitLiftOffFrameAlsoRejects() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        let end = TouchFrame(deviceID: "trackpad-A", timestamp: 0.04,
                             contacts: [contact(1, x: 0.7, phase: .ended), contact(2, phase: .ended), contact(3, phase: .ended)])
        XCTAssertTrue(recognizer.process(end).intents.isEmpty)
    }

    func testFourFingerContactAndPalmCancelUntilRelease() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        XCTAssertEqual(recognizer.process(frame(0.02, [1, 2, 3, 4])).diagnostics,
                       [.gestureRejected(.tooManyContacts)])
        XCTAssertTrue(recognizer.process(frame(0.04, [1, 2, 3])).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.05, [])).intents.isEmpty)

        let palm = TouchFrame(deviceID: "trackpad-A", timestamp: 0.10,
                              contacts: [contact(1), contact(2), contact(3, palm: true)])
        XCTAssertEqual(recognizer.process(palm).diagnostics, [.gestureRejected(.palmContact(contactID: 3))])
        XCTAssertTrue(recognizer.process(frame(0.14, [])).intents.isEmpty)
    }

    func testMoreThanThreeDistinctIDsRejectsEvenWhenNoFrameContainsFour() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        let result = recognizer.process(frame(0.04, [1, 2, 4]))
        XCTAssertEqual(result.diagnostics, [.gestureRejected(.tooManyContacts)])
        XCTAssertTrue(recognizer.process(frame(0.08, [])).intents.isEmpty)
    }

    func testPreviouslyUnobservedFourthContactInLiftOffFrameRejects() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        let liftedFourth = TouchFrame(deviceID: "trackpad-A", timestamp: 0.03,
                                     contacts: [contact(1), contact(2), contact(3), contact(4, phase: .ended)])
        XCTAssertEqual(recognizer.process(liftedFourth).diagnostics, [.gestureRejected(.tooManyContacts)])
        XCTAssertTrue(recognizer.process(frame(0.05, [])).intents.isEmpty)
    }

    func testBriefMissingContactCanReturnWithoutBeingCountedTwice() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        _ = recognizer.process(frame(0.03, [1, 2]))
        XCTAssertEqual(recognizer.process(frame(0.05, [1, 2, 3])).snapshot.trackedContactCount, 3)
        XCTAssertEqual(recognizer.process(frame(0.08, [])).intents, [.middleClick])
    }

    func testContactReturningAfterLongGapRejects() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        _ = recognizer.process(frame(0.03, [1, 2]))
        XCTAssertEqual(recognizer.process(frame(0.08, [1, 2, 3])).diagnostics,
                       [.gestureRejected(.contactReturnedAfterGap(contactID: 3))])
        XCTAssertTrue(recognizer.process(frame(0.10, [])).intents.isEmpty)
    }

    func testExplicitEndedContactCannotRestartWithinSameGroup() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        let lifted = TouchFrame(deviceID: "trackpad-A", timestamp: 0.02,
                                contacts: [contact(1), contact(2), contact(3, phase: .ended)])
        _ = recognizer.process(lifted)
        XCTAssertEqual(recognizer.process(frame(0.04, [1, 2, 3])).diagnostics,
                       [.gestureRejected(.contactRestarted(contactID: 3))])
    }

    func testCancelledContactNeverEmitsEvenWhenAllContactsDisappear() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        let cancelled = TouchFrame(deviceID: "trackpad-A", timestamp: 0.04,
                                   contacts: [contact(1, phase: .cancelled)])
        XCTAssertEqual(recognizer.process(cancelled).diagnostics,
                       [.gestureRejected(.contactCancelled(contactID: 1))])
        XCTAssertTrue(recognizer.process(frame(0.05, [])).intents.isEmpty)
    }

    func testDurationAndMissingCallbackGapsReject() {
        var longGesture = ThreeFingerTapRecognizer()
        _ = longGesture.process(frame(0, [1, 2, 3]))
        _ = longGesture.process(frame(0.1, [1, 2, 3]))
        _ = longGesture.process(frame(0.2, [1, 2, 3]))
        XCTAssertEqual(longGesture.process(frame(0.26, [])).diagnostics, [.gestureRejected(.durationExceeded)])

        var callbackGap = ThreeFingerTapRecognizer()
        _ = callbackGap.process(frame(0, [1, 2, 3]))
        XCTAssertEqual(callbackGap.process(frame(0.13, [])).diagnostics, [.gestureRejected(.frameGapExceeded)])
    }

    func testTimestampResetRejectsAndRequiresHandsOffBeforeRecovery() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(10, [1, 2, 3]))
        let reset = recognizer.process(frame(1, [1, 2, 3]))
        XCTAssertEqual(reset.diagnostics, [.frameRejected(.timestampWentBackward(previous: 10, current: 1))])
        XCTAssertEqual(reset.snapshot.phase, .blockedUntilRelease)
        XCTAssertTrue(recognizer.process(frame(1.04, [])).intents.isEmpty)
        _ = recognizer.process(frame(1.1, [1, 2, 3]))
        XCTAssertEqual(recognizer.process(frame(1.14, [])).intents, [.middleClick])
    }

    func testSequenceResetAndDuplicateAreObservable() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3], sequence: 20))
        XCTAssertEqual(recognizer.process(frame(0.02, [], sequence: 20)).diagnostics, [.duplicateFrame])
        let reset = recognizer.process(frame(0.03, [1, 2, 3], sequence: 1))
        XCTAssertEqual(reset.diagnostics, [.frameRejected(.sequenceWentBackward(previous: 20, current: 1))])
        XCTAssertTrue(recognizer.process(frame(0.05, [], sequence: 2)).intents.isEmpty)
    }

    func testInvalidFramesHaveExplicitErrorsAndCannotCompletePendingTap() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        let invalid = TouchFrame(deviceID: "trackpad-A", timestamp: .nan,
                                 contacts: [contact(1, x: .infinity), contact(1)])
        let result = recognizer.process(invalid)
        XCTAssertTrue(result.diagnostics.contains(.frameRejected(.nonFiniteTimestamp)))
        XCTAssertTrue(result.diagnostics.contains(.frameRejected(.invalidPosition(contactID: 1))))
        XCTAssertTrue(result.diagnostics.contains(.frameRejected(.duplicateContactID(1))))
        XCTAssertTrue(result.intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.04, [])).intents.isEmpty)
    }

    func testNegativeTimestampAndEmptyDeviceIDAreRejected() {
        var recognizer = ThreeFingerTapRecognizer()
        let bad = TouchFrame(deviceID: " ", timestamp: -1, contacts: [])
        let result = recognizer.process(bad)
        XCTAssertEqual(result.diagnostics, [.frameRejected(.emptyDeviceID), .frameRejected(.negativeTimestamp)])
        XCTAssertTrue(result.intents.isEmpty)
    }

    func testContactsFromDifferentDevicesAreNeverCombined() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2], device: "A"))
        _ = recognizer.process(frame(0.02, [3], device: "B"))
        XCTAssertTrue(recognizer.process(frame(0.04, [], device: "A")).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.06, [], device: "B")).intents.isEmpty)

        _ = recognizer.process(frame(1, [1, 2, 3], device: "A"))
        _ = recognizer.process(frame(99, [1, 2, 3], device: "B"))
        XCTAssertEqual(recognizer.process(frame(1.04, [], device: "A")).intents, [.middleClick])
        XCTAssertEqual(recognizer.process(frame(99.04, [], device: "B")).intents, [.middleClick])
    }

    func testCooldownDoesNotStartGestureInMiddleOfExistingContact() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        XCTAssertEqual(recognizer.process(frame(0.04, [])).intents, [.middleClick])
        XCTAssertEqual(recognizer.process(frame(0.1, [1, 2, 3])).diagnostics, [.cooldownSuppressed])
        XCTAssertTrue(recognizer.process(frame(0.3, [1, 2, 3])).intents.isEmpty)
        XCTAssertTrue(recognizer.process(frame(0.34, [])).intents.isEmpty)
        _ = recognizer.process(frame(0.4, [1, 2, 3]))
        XCTAssertEqual(recognizer.process(frame(0.44, [])).intents, [.middleClick])
    }

    func testDisableAndResetDiscardPendingGroup() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(frame(0, [1, 2, 3]))
        XCTAssertEqual(recognizer.setEnabled(false), [.disabled])
        XCTAssertEqual(recognizer.process(frame(0.04, [])).snapshot.phase, .disabled)
        _ = recognizer.setEnabled(true)
        XCTAssertTrue(recognizer.process(frame(0.05, [])).intents.isEmpty)
        _ = recognizer.process(frame(0.1, [1, 2, 3]))
        _ = recognizer.reset(deviceID: "trackpad-A")
        XCTAssertTrue(recognizer.process(frame(0.14, [])).intents.isEmpty)
    }

    func testCustomMovementThresholdAndInvalidConfiguration() throws {
        let configuration = try TapConfiguration(maximumMovement: 0.04)
        var recognizer = ThreeFingerTapRecognizer(configuration: configuration)
        _ = recognizer.process(frame(0, [1, 2, 3]))
        _ = recognizer.process(TouchFrame(deviceID: "trackpad-A", timestamp: 0.02,
                                          contacts: [contact(1), contact(2), contact(3, x: 0.53)]))
        XCTAssertEqual(recognizer.process(frame(0.05, [])).intents, [.middleClick])
        XCTAssertThrowsError(try TapConfiguration(maximumMovement: .nan))
        XCTAssertThrowsError(try TapConfiguration(maximumMovement: 0.02, onsetWindow: 0.3))
        XCTAssertThrowsError(try TapConfiguration(maximumMovement: 0.02, cooldown: -0.1))
    }
}
