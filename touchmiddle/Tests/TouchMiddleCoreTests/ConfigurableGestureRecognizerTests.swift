import XCTest
@testable import TouchMiddleCore

final class ConfigurableGestureRecognizerTests: XCTestCase {
    private let all: Set<GestureKind> = [.threeFingerTap, .twoFingerDoubleTap, .threeFingerDoubleTap]
    private let context = "com.example.Safari:123"

    private func frame(
        _ time: Double, _ count: Int, device: String = "built-in", baseID: Int = 0,
        x: Double = 0.5, phase: TouchPhase = .stationary, sequence: UInt64? = nil
    ) -> TouchFrame {
        TouchFrame(deviceID: device, timestamp: time, sequence: sequence, contacts: (0..<count).map {
            TouchContact(id: baseID + $0, position: TouchPoint(x: x, y: 0.5), phase: phase)
        })
    }

    @discardableResult
    private func tap(
        _ recognizer: inout ConfigurableGestureRecognizer, at time: Double, count: Int,
        gestures: Set<GestureKind>, contextID: String? = nil, device: String = "built-in", x: Double = 0.5
    ) -> GestureRecognitionOutcome {
        let id = contextID ?? context
        XCTAssertTrue(recognizer.process(frame(time, count, device: device, x: x), contextID: id, gestures: gestures).gestures.isEmpty)
        return recognizer.process(frame(time + 0.04, 0, device: device), contextID: id, gestures: gestures)
    }

    func testTwoFingerDoubleTapNeedsTwoCompleteReleasedGroups() {
        var recognizer = ConfigurableGestureRecognizer()
        let gestures: Set<GestureKind> = [.twoFingerDoubleTap]
        XCTAssertTrue(tap(&recognizer, at: 1, count: 2, gestures: gestures).gestures.isEmpty)
        XCTAssertEqual(recognizer.pendingDeadline(deviceID: "built-in")!, 1.39, accuracy: 0.00001)
        XCTAssertTrue(recognizer.process(frame(1.15, 2), contextID: context, gestures: gestures).gestures.isEmpty)
        XCTAssertTrue(recognizer.process(frame(1.18, 1), contextID: context, gestures: gestures).gestures.isEmpty)
        XCTAssertEqual(recognizer.process(frame(1.2, 0), contextID: context, gestures: gestures).gestures, [.twoFingerDoubleTap])
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "built-in"))
        XCTAssertTrue(recognizer.process(frame(1.22, 0), contextID: context, gestures: gestures).gestures.isEmpty)
    }

    func testThreeFingerDoubleTapEmitsOnceWithoutSingleInBetween() {
        var recognizer = ConfigurableGestureRecognizer()
        XCTAssertTrue(tap(&recognizer, at: 0, count: 3, gestures: all).gestures.isEmpty)
        XCTAssertEqual(tap(&recognizer, at: 0.14, count: 3, gestures: all).gestures, [.threeFingerDoubleTap])
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 0.8, contextID: context, gestures: all).gestures.isEmpty)
    }

    func testStandaloneSingleTapKeepsImmediateLegacyBehavior() {
        var recognizer = ConfigurableGestureRecognizer()
        let single: Set<GestureKind> = [.threeFingerTap]
        XCTAssertEqual(tap(&recognizer, at: 0, count: 3, gestures: single).gestures, [.threeFingerTap])
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "built-in"))
        XCTAssertTrue(tap(&recognizer, at: 0.15, count: 3, gestures: single).gestures.isEmpty)
        XCTAssertEqual(tap(&recognizer, at: 0.4, count: 3, gestures: single).gestures, [.threeFingerTap])
    }

    func testSingleDefersUntilDeadlineAndCanFlushWithoutSensorFrames() {
        var recognizer = ConfigurableGestureRecognizer()
        XCTAssertTrue(tap(&recognizer, at: 0, count: 3, gestures: all).gestures.isEmpty)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 0.38, contextID: context, gestures: all).gestures.isEmpty)
        let release = recognizer.flush(deviceID: "built-in", timestamp: 0.39, contextID: context, gestures: all)
        XCTAssertEqual(release.gestures, [.threeFingerTap])
        XCTAssertEqual(release.phase, .cooldown)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 0.6, contextID: context, gestures: all).gestures.isEmpty)
    }

    func testSingleCanExpireFromNextEmptySnapshot() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        XCTAssertEqual(recognizer.process(frame(0.40, 0), contextID: context, gestures: all).gestures, [.threeFingerTap])
        XCTAssertTrue(recognizer.process(frame(0.41, 0), contextID: context, gestures: all).gestures.isEmpty)
    }

    func testSecondTapMayFinishAfterIntervalIfItStartsBeforeDeadline() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        _ = recognizer.process(frame(0.38, 3), contextID: context, gestures: all)
        XCTAssertEqual(recognizer.pendingDeadline(deviceID: "built-in")!, 0.63, accuracy: 0.00001)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 0.40, contextID: context, gestures: all).gestures.isEmpty)
        XCTAssertEqual(recognizer.process(frame(0.42, 0), contextID: context, gestures: all).gestures, [.threeFingerDoubleTap])
    }

    func testHeldSecondTapCannotLaterFlushFirstSingle() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        _ = recognizer.process(frame(0.2, 3), contextID: context, gestures: all)
        XCTAssertEqual(recognizer.flush(deviceID: "built-in", timestamp: 0.46, contextID: context, gestures: all).diagnostics,
                       [.gestureRejected(.durationExceeded)])
        XCTAssertTrue(recognizer.process(frame(0.47, 0), contextID: context, gestures: all).gestures.isEmpty)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 1, contextID: context, gestures: all).gestures.isEmpty)
    }

    func testFastTripleDoesNotAddTrailingSingleEvenWithZeroCooldown() throws {
        let config = try TapConfiguration(maximumMovement: 0.025, cooldown: 0)
        var recognizer = ConfigurableGestureRecognizer(configuration: config)
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        XCTAssertEqual(tap(&recognizer, at: 0.12, count: 3, gestures: all).gestures, [.threeFingerDoubleTap])
        XCTAssertTrue(tap(&recognizer, at: 0.24, count: 3, gestures: all).gestures.isEmpty)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 1, contextID: context, gestures: all).gestures.isEmpty)
    }

    func testThreeFingerGroupNeverFiresTwoFingerDoubleTap() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        XCTAssertTrue(tap(&recognizer, at: 0.15, count: 2, gestures: all).gestures.isEmpty)
        XCTAssertEqual(tap(&recognizer, at: 0.3, count: 2, gestures: all).gestures, [.twoFingerDoubleTap])
    }

    func testStaggeredThirdFingerPromotesGroupToThreeInsteadOfTwo() {
        var recognizer = ConfigurableGestureRecognizer()
        for start in [0.0, 0.2] {
            _ = recognizer.process(frame(start, 2), contextID: context, gestures: all)
            _ = recognizer.process(frame(start + 0.025, 3), contextID: context, gestures: all)
            let result = recognizer.process(frame(start + 0.055, 0), contextID: context, gestures: all)
            XCTAssertEqual(result.gestures, start == 0 ? [] : [.threeFingerDoubleTap])
        }
    }

    func testTwoFingerOnlyRejectsThreeAndUnseenFourthLiftOff() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        XCTAssertEqual(recognizer.process(frame(0, 3), contextID: context, gestures: two).diagnostics,
                       [.gestureRejected(.tooManyContacts)])
        _ = recognizer.process(frame(0.04, 0), contextID: context, gestures: two)
        _ = tap(&recognizer, at: 0.1, count: 2, gestures: two)
        _ = recognizer.process(frame(0.2, 2), contextID: context, gestures: two)
        let unobserved = TouchContact(id: 5, position: TouchPoint(x: 0.5, y: 0.5), phase: .ended)
        let lifted = TouchFrame(deviceID: "built-in", timestamp: 0.23,
                                contacts: frame(0.23, 2).contacts + [unobserved])
        XCTAssertEqual(recognizer.process(lifted, contextID: context, gestures: two).diagnostics,
                       [.gestureRejected(.tooManyContacts)])
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "built-in"))
    }

    func testScrollingSecondGroupCancelsPendingTap() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        _ = tap(&recognizer, at: 0, count: 2, gestures: two)
        _ = recognizer.process(frame(0.1, 2), contextID: context, gestures: two)
        let result = recognizer.process(frame(0.13, 2, x: 0.55), contextID: context, gestures: two)
        guard case .gestureRejected(.movementExceeded) = result.diagnostics.first else { return XCTFail("Scroll must reject") }
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "built-in"))
        XCTAssertTrue(recognizer.process(frame(0.16, 0), contextID: context, gestures: two).gestures.isEmpty)
        XCTAssertTrue(tap(&recognizer, at: 0.25, count: 2, gestures: two).gestures.isEmpty)
    }

    func testUnobservedThirdLiftOffCannotBecomeTwoFingerDoubleEvenWhenThreeIsEnabled() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 2, gestures: all)
        _ = recognizer.process(frame(0.1, 2), contextID: context, gestures: all)
        let third = TouchContact(id: 9, position: TouchPoint(x: 0.5, y: 0.5), phase: .ended)
        let result = recognizer.process(TouchFrame(deviceID: "built-in", timestamp: 0.13,
                                                   contacts: frame(0.13, 2).contacts + [third]),
                                        contextID: context, gestures: all)
        XCTAssertEqual(result.diagnostics, [.gestureRejected(.tooManyContacts)])
        XCTAssertTrue(recognizer.process(frame(0.15, 0), contextID: context, gestures: all).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "built-in"))
    }

    func testFourFingerGroupCancelsDeferredSingle() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        XCTAssertEqual(recognizer.process(frame(0.12, 4), contextID: context, gestures: all).diagnostics,
                       [.gestureRejected(.tooManyContacts)])
        _ = recognizer.process(frame(0.15, 0), contextID: context, gestures: all)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 1, contextID: context, gestures: all).gestures.isEmpty)
    }

    func testDistantSecondTapCannotPairWithFirst() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        _ = tap(&recognizer, at: 0, count: 2, gestures: two, x: 0.2)
        XCTAssertTrue(tap(&recognizer, at: 0.15, count: 2, gestures: two, x: 0.7).gestures.isEmpty)
        XCTAssertEqual(tap(&recognizer, at: 0.3, count: 2, gestures: two, x: 0.7).gestures, [.twoFingerDoubleTap])
    }

    func testDifferentDevicesDoNotPair() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        _ = tap(&recognizer, at: 0, count: 2, gestures: two, device: "A")
        XCTAssertTrue(tap(&recognizer, at: 0.15, count: 2, gestures: two, device: "B").gestures.isEmpty)
        XCTAssertEqual(tap(&recognizer, at: 0.3, count: 2, gestures: two, device: "A").gestures, [.twoFingerDoubleTap])
    }

    func testApplicationSwitchCancelsPendingAcrossDevices() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all, device: "A")
        _ = recognizer.process(frame(0.1, 0, device: "B"), contextID: "com.example.Finder:456", gestures: all)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: "com.example.Finder:456", gestures: all).gestures.isEmpty)
    }

    func testSameBundleDifferentPIDCannotPairButFreshTouchNeedsNoCalibration() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        _ = tap(&recognizer, at: 0, count: 2, gestures: two)
        XCTAssertEqual(recognizer.process(frame(0.1, 2), contextID: "com.example.Safari:124", gestures: two).phase,
                       .tracking)
        XCTAssertTrue(recognizer.process(frame(0.14, 0), contextID: "com.example.Safari:124", gestures: two).gestures.isEmpty)
        XCTAssertEqual(tap(&recognizer, at: 0.2, count: 2, gestures: two, contextID: "com.example.Safari:124").gestures,
                       [.twoFingerDoubleTap])
    }

    func testHeldContactGroupAcrossContextChangeRequiresFullRelease() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        _ = recognizer.process(frame(0, 2), contextID: context, gestures: two)
        XCTAssertEqual(recognizer.process(frame(0.03, 2), contextID: "other:124", gestures: two).phase, .blockedUntilRelease)
        XCTAssertTrue(recognizer.process(frame(0.05, 0), contextID: "other:124", gestures: two).gestures.isEmpty)
        XCTAssertTrue(tap(&recognizer, at: 0.1, count: 2, gestures: two, contextID: "other:124").gestures.isEmpty)
        XCTAssertEqual(tap(&recognizer, at: 0.25, count: 2, gestures: two, contextID: "other:124").gestures, [.twoFingerDoubleTap])
    }

    func testEligibleGestureChangeAndPauseCancelPending() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 1, contextID: context,
                                       gestures: [.threeFingerTap]).gestures.isEmpty)
        _ = recognizer.process(frame(1.1, 0), contextID: context, gestures: all)
        _ = tap(&recognizer, at: 1.2, count: 3, gestures: all)
        XCTAssertNotNil(recognizer.pendingDeadline(deviceID: "built-in"))
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 2, contextID: context, gestures: []).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "built-in"))
    }

    func testResetAndConfigurationUpdateCancelPending() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        recognizer.reset()
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 1, contextID: context, gestures: all).gestures.isEmpty)
        _ = tap(&recognizer, at: 2, count: 3, gestures: all)
        recognizer.updateConfiguration(TapConfiguration(), doubleTapInterval: 0.4)
        XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 3, contextID: context, gestures: all).gestures.isEmpty)
        XCTAssertEqual(recognizer.doubleTapInterval, 0.4)
    }

    func testInvalidFrameAndCancelledPalmCannotCompleteOrFlushPending() {
        for badContact in [
            TouchContact(id: 1, position: TouchPoint(x: .infinity, y: 0.5)),
            TouchContact(id: 1, position: TouchPoint(x: 0.5, y: 0.5), phase: .cancelled),
            TouchContact(id: 1, position: TouchPoint(x: 0.5, y: 0.5), isPalm: true),
        ] {
            var recognizer = ConfigurableGestureRecognizer()
            _ = tap(&recognizer, at: 0, count: 3, gestures: all)
            let bad = TouchFrame(deviceID: "built-in", timestamp: 0.1, contacts: [badContact])
            XCTAssertFalse(recognizer.process(bad, contextID: context, gestures: all).diagnostics.isEmpty)
            _ = recognizer.process(frame(0.15, 0), contextID: context, gestures: all)
            XCTAssertTrue(recognizer.flush(deviceID: "built-in", timestamp: 1, contextID: context, gestures: all).gestures.isEmpty)
        }
    }

    func testDuplicateReleaseCannotManufactureSecondTapAndClockResetCancels() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        _ = recognizer.process(frame(0, 2, sequence: 1), contextID: context, gestures: two)
        _ = recognizer.process(frame(0.04, 0, sequence: 2), contextID: context, gestures: two)
        XCTAssertEqual(recognizer.process(frame(0.05, 0, sequence: 2), contextID: context, gestures: two).diagnostics,
                       [.duplicateFrame])
        XCTAssertEqual(recognizer.process(frame(0.01, 2, sequence: 3), contextID: context, gestures: two).diagnostics,
                       [.frameRejected(.timestampWentBackward(previous: 0.04, current: 0.01))])
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "built-in"))
        _ = recognizer.process(frame(0.05, 0, sequence: 4), contextID: context, gestures: two)
        XCTAssertTrue(tap(&recognizer, at: 0.1, count: 2, gestures: two).gestures.isEmpty)
    }

    func testTimerDoesNotAdvanceSensorTimestampValidation() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = tap(&recognizer, at: 0, count: 3, gestures: all)
        _ = recognizer.flush(deviceID: "built-in", timestamp: 0.10, contextID: context, gestures: all)
        // A callback queued before the timer is valid because hardware time still increases.
        XCTAssertTrue(recognizer.process(frame(0.09, 0), contextID: context, gestures: all).diagnostics.isEmpty)
        XCTAssertEqual(recognizer.flush(deviceID: "built-in", timestamp: 0.4, contextID: context, gestures: all).gestures,
                       [.threeFingerTap])
    }

    func testMissingContactAndFrameGapRejectSecondGroup() {
        var recognizer = ConfigurableGestureRecognizer()
        let two: Set<GestureKind> = [.twoFingerDoubleTap]
        _ = tap(&recognizer, at: 0, count: 2, gestures: two)
        _ = recognizer.process(frame(0.1, 2), contextID: context, gestures: two)
        _ = recognizer.process(frame(0.13, 1), contextID: context, gestures: two)
        XCTAssertEqual(recognizer.process(frame(0.18, 2), contextID: context, gestures: two).diagnostics,
                       [.gestureRejected(.contactReturnedAfterGap(contactID: 1))])
        _ = recognizer.process(frame(0.2, 0), contextID: context, gestures: two)
        _ = tap(&recognizer, at: 0.3, count: 2, gestures: two)
        _ = recognizer.process(frame(0.4, 2), contextID: context, gestures: two)
        XCTAssertEqual(recognizer.process(frame(0.53, 0), contextID: context, gestures: two).diagnostics,
                       [.gestureRejected(.frameGapExceeded)])
    }
}
