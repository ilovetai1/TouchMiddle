import XCTest
@testable import TouchMiddleCore

final class AnchoredTapRecognizerTests: XCTestCase {
    private let context = "com.example.Safari:123"
    private let anchored: Set<GestureKind> = [.twoFingerHoldLeftTap, .twoFingerHoldRightTap]
    // Legacy combinations intentionally exclude newly opt-in gestures.
    private let all: Set<GestureKind> = [.threeFingerTap, .twoFingerDoubleTap, .threeFingerDoubleTap, .twoFingerHoldLeftTap, .twoFingerHoldRightTap]

    private func contact(
        _ id: Int, _ x: Double, y: Double = 0.5,
        phase: TouchPhase = .stationary, isPalm: Bool = false
    ) -> TouchContact {
        TouchContact(id: id, position: TouchPoint(x: x, y: y), phase: phase, isPalm: isPalm)
    }

    private var anchors: [TouchContact] { [contact(1, 0.45), contact(2, 0.60)] }

    @discardableResult
    private func process(
        _ recognizer: inout ConfigurableGestureRecognizer, _ time: Double,
        _ contacts: [TouchContact], device: String = "A", sequence: UInt64? = nil,
        contextID: String? = nil, gestures: Set<GestureKind>? = nil
    ) -> GestureRecognitionOutcome {
        recognizer.process(TouchFrame(deviceID: device, timestamp: time, sequence: sequence, contacts: contacts),
                           contextID: contextID ?? context, gestures: gestures ?? anchored)
    }

    private func hold(
        _ recognizer: inout ConfigurableGestureRecognizer, from time: Double = 0,
        device: String = "A", contextID: String? = nil, gestures: Set<GestureKind>? = nil
    ) {
        for offset in [0.0, 0.05, 0.10, 0.15] {
            XCTAssertTrue(process(&recognizer, time + offset, anchors, device: device,
                                  contextID: contextID, gestures: gestures).gestures.isEmpty)
        }
    }

    @discardableResult
    private func thirdTap(
        _ recognizer: inout ConfigurableGestureRecognizer, at time: Double,
        x: Double, id: Int = 3, duration: Double = 0.04, device: String = "A",
        gestures: Set<GestureKind>? = nil
    ) -> GestureRecognitionOutcome {
        XCTAssertTrue(process(&recognizer, time, anchors + [contact(id, x)],
                              device: device, gestures: gestures).gestures.isEmpty)
        var next = time + 0.10
        while next < time + duration - 0.000_000_001 {
            XCTAssertTrue(process(&recognizer, next, anchors + [contact(id, x)],
                                  device: device, gestures: gestures).gestures.isEmpty)
            next += 0.10
        }
        return process(&recognizer, time + duration, anchors + [contact(id, x, phase: .ended)],
                       device: device, gestures: gestures)
    }

    func testLeftAndRightTapEmitOnlyWhenThirdFingerReleases() {
        for (x, expected) in [(0.20, GestureKind.twoFingerHoldLeftTap), (0.85, .twoFingerHoldRightTap)] {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer)
            XCTAssertTrue(process(&recognizer, 0.20, Array(anchors.reversed()) + [contact(3, x)]).gestures.isEmpty)
            XCTAssertEqual(process(&recognizer, 0.24, anchors + [contact(3, x, phase: .ended)]).gestures, [expected])
            XCTAssertTrue(process(&recognizer, 0.29, anchors).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, 0.34, []).gestures.isEmpty)
            XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
            XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                           gestures: anchored).gestures.isEmpty)
        }
    }

    func testThirdFingerMustArriveAfter150MillisecondsOfStableAnchors() {
        for (arrival, expected) in [(0.149, [GestureKind]()), (0.150, [.twoFingerHoldLeftTap])] {
            var recognizer = ConfigurableGestureRecognizer()
            for time in [0.0, 0.05, 0.10] { _ = process(&recognizer, time, anchors) }
            XCTAssertEqual(thirdTap(&recognizer, at: arrival, x: 0.20).gestures, expected)
            XCTAssertTrue(process(&recognizer, arrival + 0.06, []).gestures.isEmpty)
        }
    }

    func testThirdFingerMustBeBeyondBothAnchorsAndStrictlyBeyondMovementMargin() {
        for x in [0.425, 0.426, 0.50, 0.599, 0.624, 0.625] {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer)
            XCTAssertTrue(thirdTap(&recognizer, at: 0.20, x: x).gestures.isEmpty, "Unexpected side tap at x=\(x)")
            XCTAssertTrue(process(&recognizer, 0.30, []).gestures.isEmpty)
            XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                           gestures: all).gestures.isEmpty)
        }
        for (x, expected) in [(0.4249, GestureKind.twoFingerHoldLeftTap), (0.6251, .twoFingerHoldRightTap)] {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer)
            XCTAssertEqual(thirdTap(&recognizer, at: 0.20, x: x).gestures, [expected])
        }
    }

    func testDisabledSideCannotFireOppositeSideRule() {
        let leftOnly: Set<GestureKind> = [.twoFingerHoldLeftTap]
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, gestures: leftOnly)
        XCTAssertTrue(thirdTap(&recognizer, at: 0.20, x: 0.85, gestures: leftOnly).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.30, [], gestures: leftOnly).gestures.isEmpty)
        hold(&recognizer, from: 0.40, gestures: leftOnly)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.60, x: 0.20, gestures: leftOnly).gestures, [.twoFingerHoldLeftTap])
    }

    func testAnchorsCanRemainHeldLongerThanOrdinaryTapMaximumDuration() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer)
        for step in 2...20 {
            XCTAssertTrue(process(&recognizer, Double(step) * 0.10, anchors).gestures.isEmpty)
        }
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 2.01, contextID: context,
                                       gestures: anchored).diagnostics.isEmpty)
        XCTAssertEqual(thirdTap(&recognizer, at: 2.05, x: 0.20).gestures, [.twoFingerHoldLeftTap])
    }

    func testStationaryFirstAnchorCanWaitBeforeSecondAnchorIsPlaced() {
        var recognizer = ConfigurableGestureRecognizer()
        for time in [0.0, 0.10, 0.20, 0.30, 0.40, 0.50] {
            XCTAssertTrue(process(&recognizer, time, [contact(1, 0.45)], gestures: all).gestures.isEmpty)
        }
        for time in [0.55, 0.60, 0.65, 0.70] {
            XCTAssertTrue(process(&recognizer, time, anchors, gestures: all).gestures.isEmpty)
        }
        XCTAssertEqual(thirdTap(&recognizer, at: 0.75, x: 0.20, gestures: all).gestures, [.twoFingerHoldLeftTap])
    }

    func testMovingFirstAnchorCancelsSequentialPlacementUntilFullRelease() {
        var recognizer = ConfigurableGestureRecognizer()
        for time in [0.0, 0.10, 0.20] {
            _ = process(&recognizer, time, [contact(1, 0.45)], gestures: all)
        }
        let moved = process(&recognizer, 0.30, [contact(1, 0.4751)], gestures: all)
        XCTAssertTrue(moved.gestures.isEmpty)
        XCTAssertEqual(moved.phase, .blockedUntilRelease)
        for time in [0.35, 0.40, 0.45, 0.50] {
            XCTAssertTrue(process(&recognizer, time, anchors, gestures: all).gestures.isEmpty)
        }
        XCTAssertTrue(thirdTap(&recognizer, at: 0.55, x: 0.20, gestures: all).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.60, [], gestures: all).gestures.isEmpty)
        hold(&recognizer, from: 0.65, gestures: all)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.85, x: 0.20, id: 4, gestures: all).gestures,
                       [.twoFingerHoldLeftTap])
    }

    func testLateSecondAnchorAndEarlyThirdCannotBecomeOrdinaryThreeFingerTap() {
        for secondArrival in [0.08, 0.10] {
            var recognizer = ConfigurableGestureRecognizer()
            _ = process(&recognizer, 0, [contact(1, 0.45)], gestures: all)
            _ = process(&recognizer, 0.05, [contact(1, 0.45)], gestures: all)
            _ = process(&recognizer, secondArrival, anchors, gestures: all)
            _ = process(&recognizer, secondArrival + 0.05, anchors, gestures: all)
            let tooEarly = process(&recognizer, secondArrival + 0.10, anchors + [contact(3, 0.20)], gestures: all)
            XCTAssertTrue(tooEarly.gestures.isEmpty)
            XCTAssertEqual(tooEarly.phase, .blockedUntilRelease)
            XCTAssertTrue(process(&recognizer, secondArrival + 0.14, anchors, gestures: all).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, secondArrival + 0.16, [], gestures: all).gestures.isEmpty)
            XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
            XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                           gestures: all).gestures.isEmpty)
        }
    }

    func testPartialReleaseAfterLongPairHoldRequiresFullReleaseBeforeReplacementAnchor() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, gestures: all)
        for time in [0.20, 0.25, 0.30] { _ = process(&recognizer, time, anchors, gestures: all) }
        let partialRelease = process(&recognizer, 0.31, [contact(2, 0.60)], gestures: all)
        XCTAssertTrue(partialRelease.gestures.isEmpty)
        XCTAssertEqual(partialRelease.phase, .blockedUntilRelease)
        let replacements = [contact(5, 0.45), contact(2, 0.60)]
        for time in [0.32, 0.37, 0.42, 0.47] {
            XCTAssertTrue(process(&recognizer, time, replacements, gestures: all).gestures.isEmpty)
        }
        XCTAssertTrue(process(&recognizer, 0.48, replacements + [contact(6, 0.20)], gestures: all).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.52, replacements, gestures: all).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.55, [], gestures: all).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        hold(&recognizer, from: 0.60, gestures: all)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.80, x: 0.20, id: 7, gestures: all).gestures,
                       [.twoFingerHoldLeftTap])
    }

    func testRepeatedThirdTapsRespectCooldownWithoutReleasingAnchors() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.20, x: 0.20).gestures, [.twoFingerHoldLeftTap])
        _ = process(&recognizer, 0.29, anchors)
        XCTAssertTrue(thirdTap(&recognizer, at: 0.34, x: 0.85, id: 4).gestures.isEmpty)
        _ = process(&recognizer, 0.43, anchors)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.49, x: 0.85, id: 5).gestures, [.twoFingerHoldRightTap])
        XCTAssertTrue(process(&recognizer, 0.58, anchors).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.63, []).gestures.isEmpty)
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                       gestures: anchored).gestures.isEmpty)
    }

    func testReleasingAndReanchoringCannotBypassPreviousActionCooldown() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, gestures: all)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.16, x: 0.20, gestures: all).gestures, [.twoFingerHoldLeftTap])
        XCTAssertTrue(process(&recognizer, 0.21, [], gestures: all).gestures.isEmpty)
        XCTAssertEqual(process(&recognizer, 0.22, anchors, gestures: all).phase, .blockedUntilRelease)
        for time in [0.27, 0.32, 0.37] {
            XCTAssertTrue(process(&recognizer, time, anchors, gestures: all).gestures.isEmpty)
        }
        XCTAssertTrue(thirdTap(&recognizer, at: 0.38, x: 0.85, gestures: all).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.44, [], gestures: all).gestures.isEmpty)
        hold(&recognizer, from: 0.50, gestures: all)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.70, x: 0.85, gestures: all).gestures, [.twoFingerHoldRightTap])
    }

    func testAnchoredActionCooldownAlsoSuppressesFreshOrdinaryThreeFingerTap() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, gestures: all)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.16, x: 0.20, gestures: all).gestures, [.twoFingerHoldLeftTap])
        _ = process(&recognizer, 0.21, [], gestures: all)
        XCTAssertTrue(process(&recognizer, 0.22, anchors + [contact(4, 0.50)], gestures: all).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.26, [], gestures: all).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 0.70, contextID: context,
                                       gestures: all).gestures.isEmpty)
    }

    func testThirdTapDurationUsesInclusiveConfiguredBounds() {
        for (duration, shouldRecognize) in [(0.0149, false), (0.015, true), (0.25, true), (0.2501, false)] {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer)
            let result = thirdTap(&recognizer, at: 0.20, x: 0.20, duration: duration)
            XCTAssertEqual(result.gestures, shouldRecognize ? [.twoFingerHoldLeftTap] : [], "duration=\(duration)")
        }
    }

    func testMovementLimitAppliesToEachAnchorAndThirdFingerInclusively() {
        for movingID in [1, 2, 3] {
            for (movement, shouldRecognize) in [(0.025, true), (0.0251, false)] {
                var recognizer = ConfigurableGestureRecognizer()
                hold(&recognizer)
                _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)])
                let shifted = [contact(1, 0.45 + (movingID == 1 ? movement : 0)),
                               contact(2, 0.60 + (movingID == 2 ? movement : 0)),
                               contact(3, 0.20 + (movingID == 3 ? movement : 0))]
                let movementResult = process(&recognizer, 0.22, shifted)
                XCTAssertTrue(movementResult.gestures.isEmpty)
                let release = process(&recognizer, 0.24, Array(shifted.prefix(2)) + [
                    contact(3, shifted[2].position.x, phase: .ended),
                ])
                XCTAssertEqual(release.gestures, shouldRecognize ? [.twoFingerHoldLeftTap] : [],
                               "contact=\(movingID), movement=\(movement)")
                if !shouldRecognize { XCTAssertEqual(movementResult.phase, .blockedUntilRelease) }
            }
        }
    }

    func testCustomMovementAndDurationThresholdsControlAnchoredTap() throws {
        let configuration = try TapConfiguration(maximumMovement: 0.04, maximumDuration: 0.40,
                                                 minimumThreeFingerOverlap: 0.04, cooldown: 0.10)
        for (x, duration, expected) in [(0.405, 0.04, true), (0.415, 0.04, false),
                                      (0.20, 0.039, false), (0.20, 0.40, true)] {
            var recognizer = ConfigurableGestureRecognizer(configuration: configuration)
            hold(&recognizer)
            XCTAssertEqual(thirdTap(&recognizer, at: 0.20, x: x, duration: duration).gestures,
                           expected ? [.twoFingerHoldLeftTap] : [])
        }
    }

    func testShortestTapDurationDoesNotLimitSequentialAnchorPreparation() throws {
        let configuration = try TapConfiguration(maximumMovement: 0.025, maximumDuration: 0.15)
        var recognizer = ConfigurableGestureRecognizer(configuration: configuration)
        _ = process(&recognizer, 0, [contact(1, 0.45)], gestures: all)
        for time in [0.05, 0.10, 0.16, 0.20] {
            XCTAssertTrue(process(&recognizer, time, anchors, gestures: all).gestures.isEmpty)
        }
        XCTAssertEqual(thirdTap(&recognizer, at: 0.21, x: 0.20, gestures: all).gestures, [.twoFingerHoldLeftTap])
    }

    func testKnownEndedThirdContactsCanPersistThroughSubsequentTaps() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.20, x: 0.20).gestures, [.twoFingerHoldLeftTap])
        let oldEnded = contact(3, 0.20, phase: .ended)
        for time in [0.29, 0.34, 0.39, 0.44, 0.49] {
            XCTAssertTrue(process(&recognizer, time, anchors + [oldEnded]).gestures.isEmpty)
        }
        XCTAssertTrue(process(&recognizer, 0.54, anchors + [oldEnded, contact(4, 0.85)]).gestures.isEmpty)
        XCTAssertEqual(process(&recognizer, 0.58, anchors + [oldEnded, contact(4, 0.85, phase: .ended)]).gestures,
                       [.twoFingerHoldRightTap])
        XCTAssertTrue(process(&recognizer, 0.63, anchors + [oldEnded, contact(4, 0.85, phase: .ended)]).gestures.isEmpty)
    }

    func testThirdIDCanBeReusedForAnotherTapAfterRelease() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.20, x: 0.20).gestures, [.twoFingerHoldLeftTap])
        for time in [0.29, 0.34, 0.39, 0.44, 0.49] { _ = process(&recognizer, time, anchors) }
        XCTAssertEqual(thirdTap(&recognizer, at: 0.54, x: 0.85).gestures, [.twoFingerHoldRightTap])
    }

    func testAnchorLossOrReplacementCancelsUntilEntireGroupReleases() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer)
        _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)])
        XCTAssertEqual(process(&recognizer, 0.22, [contact(2, 0.60), contact(3, 0.20)]).phase, .blockedUntilRelease)
        XCTAssertTrue(process(&recognizer, 0.24, [contact(5, 0.45), contact(2, 0.60)]).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.29, anchors + [contact(6, 0.85)]).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.33, anchors).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.36, []).gestures.isEmpty)
        hold(&recognizer, from: 0.40)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.60, x: 0.20, id: 7).gestures, [.twoFingerHoldLeftTap])
    }

    func testSimultaneousAnchorAndThirdReleaseCannotBecomeAnchoredOrOrdinaryTap() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, gestures: all)
        _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)], gestures: all)
        XCTAssertTrue(process(&recognizer, 0.24, [], gestures: all).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                       gestures: all).gestures.isEmpty)
    }

    func testInvalidPhysicalGroupsCancelWithoutDelayedOrdinaryTapAndRecoverAfterRelease() {
        let badFrames = [
            anchors + [contact(3, 0.20), contact(4, 0.85)],
            anchors + [contact(3, 0.20), contact(4, 0.85, phase: .ended)],
            anchors + [contact(3, 0.20, phase: .cancelled)],
            anchors + [contact(3, 0.20, isPalm: true)],
            anchors + [contact(3, .infinity)],
            anchors + [contact(3, 0.20), contact(3, 0.20)],
        ]
        for contacts in badFrames {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer, gestures: all)
            _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)], gestures: all)
            let rejected = process(&recognizer, 0.22, contacts, gestures: all)
            XCTAssertTrue(rejected.gestures.isEmpty)
            XCTAssertFalse(rejected.diagnostics.isEmpty)
            XCTAssertEqual(rejected.phase, .blockedUntilRelease)
            XCTAssertTrue(process(&recognizer, 0.24, anchors, gestures: all).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, 0.29, anchors + [contact(5, 0.85)], gestures: all).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, 0.33, [], gestures: all).gestures.isEmpty)
            XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 0.36, contextID: context,
                                           gestures: all).gestures.isEmpty)
            hold(&recognizer, from: 0.40, gestures: all)
            XCTAssertEqual(thirdTap(&recognizer, at: 0.60, x: 0.20, id: 6, gestures: all).gestures,
                           [.twoFingerHoldLeftTap])
        }
    }

    func testFrameGapWhileHoldingOrTappingCancelsSession() {
        for thirdAlreadyDown in [false, true] {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer)
            if thirdAlreadyDown { _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)]) }
            let gapTime = thirdAlreadyDown ? 0.33 : 0.28
            let result = process(&recognizer, gapTime, anchors)
            XCTAssertEqual(result.diagnostics, [.gestureRejected(.frameGapExceeded)])
            XCTAssertEqual(result.phase, .blockedUntilRelease)
            XCTAssertTrue(thirdTap(&recognizer, at: gapTime + 0.05, x: 0.20, id: 4).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, gapTime + 0.10, []).gestures.isEmpty)
        }
    }

    func testThirdTapTimeoutCanBeCancelledByTimerWithoutManufacturingRelease() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, gestures: all)
        _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)], gestures: all)
        XCTAssertEqual(recognizer.pendingDeadline(deviceID: "A")!, 0.45, accuracy: 0.000_001)
        let expired = recognizer.flush(deviceID: "A", timestamp: 0.4501, contextID: context, gestures: all)
        XCTAssertTrue(expired.gestures.isEmpty)
        XCTAssertEqual(expired.phase, .blockedUntilRelease)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        XCTAssertTrue(process(&recognizer, 0.46, anchors, gestures: all).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.50, [], gestures: all).gestures.isEmpty)
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                       gestures: all).gestures.isEmpty)
    }

    func testBackwardTimestampOrSequenceCancelsHeldSession() {
        for backwardClock in [true, false] {
            var recognizer = ConfigurableGestureRecognizer()
            for (index, time) in [0.0, 0.05, 0.10, 0.15, 0.20].enumerated() {
                _ = process(&recognizer, time, anchors, sequence: UInt64(index + 1))
            }
            let bad = process(&recognizer, backwardClock ? 0.19 : 0.22, anchors + [contact(3, 0.20)],
                              sequence: backwardClock ? 6 : 4)
            XCTAssertTrue(bad.gestures.isEmpty)
            XCTAssertEqual(bad.phase, .blockedUntilRelease)
            XCTAssertFalse(bad.diagnostics.isEmpty)
            XCTAssertTrue(process(&recognizer, 0.24, anchors, sequence: 7).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, 0.29, [], sequence: 8).gestures.isEmpty)
            hold(&recognizer, from: 0.40)
            XCTAssertEqual(thirdTap(&recognizer, at: 0.60, x: 0.20).gestures, [.twoFingerHoldLeftTap])
        }
    }

    func testDuplicateReleaseFrameCannotRepeatRecognizedTap() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer)
        _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)], sequence: 5)
        let released = anchors + [contact(3, 0.20, phase: .ended)]
        XCTAssertEqual(process(&recognizer, 0.24, released, sequence: 6).gestures, [.twoFingerHoldLeftTap])
        let duplicate = process(&recognizer, 0.25, released, sequence: 6)
        XCTAssertTrue(duplicate.gestures.isEmpty)
        XCTAssertEqual(duplicate.diagnostics, [.duplicateFrame])
    }

    func testAppPIDAndEnabledGestureChangesCancelHeldSessionAcrossDevices() {
        for changeContext in [true, false] {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer, gestures: all)
            _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)], gestures: all)
            let nextContext = changeContext ? "com.example.Safari:124" : context
            let nextGestures = changeContext ? all : anchored
            _ = process(&recognizer, 0.22, [], device: "B", contextID: nextContext, gestures: nextGestures)
            let release = process(&recognizer, 0.24, anchors, contextID: nextContext, gestures: nextGestures)
            XCTAssertTrue(release.gestures.isEmpty)
            XCTAssertEqual(release.phase, .blockedUntilRelease)
            XCTAssertTrue(process(&recognizer, 0.29, [], contextID: nextContext, gestures: nextGestures).gestures.isEmpty)
            XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: nextContext,
                                           gestures: nextGestures).gestures.isEmpty)
        }
    }

    func testResetAndConfigurationUpdateCancelInProgressThirdTap() {
        for updateConfiguration in [false, true] {
            var recognizer = ConfigurableGestureRecognizer()
            hold(&recognizer)
            _ = process(&recognizer, 0.20, anchors + [contact(3, 0.20)])
            XCTAssertNotNil(recognizer.pendingDeadline(deviceID: "A"))
            if updateConfiguration { recognizer.updateConfiguration(TapConfiguration()) }
            else { recognizer.reset() }
            XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
            XCTAssertTrue(process(&recognizer, 0.24, anchors).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, 0.29, []).gestures.isEmpty)
            XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                           gestures: anchored).gestures.isEmpty)
        }
    }

    func testDevicesHaveIndependentAnchorsReadinessAndCooldown() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, device: "A")
        _ = process(&recognizer, 0.15, anchors, device: "B")
        XCTAssertEqual(thirdTap(&recognizer, at: 0.20, x: 0.20, device: "A").gestures, [.twoFingerHoldLeftTap])
        _ = process(&recognizer, 0.20, anchors, device: "B")
        _ = process(&recognizer, 0.25, anchors, device: "B")
        _ = process(&recognizer, 0.30, anchors, device: "B")
        XCTAssertEqual(thirdTap(&recognizer, at: 0.31, x: 0.85, device: "B").gestures, [.twoFingerHoldRightTap])
        XCTAssertTrue(process(&recognizer, 0.29, anchors, device: "A").gestures.isEmpty)
    }

    func testOrdinaryTwoFingerAndThreeFingerTapsStillWorkWithAllKindsEnabled() {
        for (count, expected) in [(2, GestureKind.twoFingerDoubleTap), (3, .threeFingerDoubleTap)] {
            var recognizer = ConfigurableGestureRecognizer()
            let fingers = Array((anchors + [contact(3, 0.50)]).prefix(count))
            for time in [0.0, 0.15] {
                XCTAssertTrue(process(&recognizer, time, fingers, gestures: all).gestures.isEmpty)
                XCTAssertEqual(process(&recognizer, time + 0.04, [], gestures: all).gestures,
                               time == 0 ? [] : [expected])
            }
            XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                           gestures: all).gestures.isEmpty)
        }
        var recognizer = ConfigurableGestureRecognizer()
        _ = process(&recognizer, 0, anchors + [contact(3, 0.50)], gestures: all)
        XCTAssertTrue(process(&recognizer, 0.04, [], gestures: all).gestures.isEmpty)
        XCTAssertEqual(recognizer.flush(deviceID: "A", timestamp: 0.39, contextID: context,
                                        gestures: all).gestures, [.threeFingerTap])
    }

    func testTwoFingerDoubleTapHeld200MillisecondsStillWorksWithAnchoredKindsEnabled() {
        var recognizer = ConfigurableGestureRecognizer()
        for time in [0.0, 0.35] {
            XCTAssertTrue(process(&recognizer, time, anchors, gestures: all).gestures.isEmpty)
            XCTAssertTrue(process(&recognizer, time + 0.10, anchors, gestures: all).gestures.isEmpty)
            XCTAssertEqual(process(&recognizer, time + 0.20, [], gestures: all).gestures,
                           time == 0 ? [] : [.twoFingerDoubleTap])
        }
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                       gestures: all).gestures.isEmpty)
    }

    func testAnchorReleaseAfterSuccessfulTapCannotProduceOrdinaryTapOrPendingSingle() {
        var recognizer = ConfigurableGestureRecognizer()
        hold(&recognizer, gestures: all)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.20, x: 0.20, gestures: all).gestures, [.twoFingerHoldLeftTap])
        XCTAssertTrue(process(&recognizer, 0.29, [contact(2, 0.60)], gestures: all).gestures.isEmpty)
        XCTAssertTrue(process(&recognizer, 0.34, [], gestures: all).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                       gestures: all).gestures.isEmpty)
    }

    func testAnchoredTapCancelsEarlierDeferredOrdinarySingle() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = process(&recognizer, 0, anchors + [contact(3, 0.50)], gestures: all)
        XCTAssertTrue(process(&recognizer, 0.04, [], gestures: all).gestures.isEmpty)
        XCTAssertNotNil(recognizer.pendingDeadline(deviceID: "A"))
        hold(&recognizer, from: 0.10, gestures: all)
        XCTAssertEqual(thirdTap(&recognizer, at: 0.26, x: 0.20, id: 4, gestures: all).gestures,
                       [.twoFingerHoldLeftTap])
        XCTAssertTrue(process(&recognizer, 0.35, [], gestures: all).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                       gestures: all).gestures.isEmpty)
    }

    func testWaitingSingleAnchorCancelsOldPendingSingleWithoutTimerCancellingSetup() {
        var recognizer = ConfigurableGestureRecognizer()
        _ = process(&recognizer, 0, anchors + [contact(3, 0.50)], gestures: all)
        _ = process(&recognizer, 0.04, [], gestures: all)
        XCTAssertNotNil(recognizer.pendingDeadline(deviceID: "A"))
        for time in [0.10, 0.20, 0.30, 0.40] {
            XCTAssertTrue(process(&recognizer, time, [contact(1, 0.45)], gestures: all).gestures.isEmpty)
        }
        let timer = recognizer.flush(deviceID: "A", timestamp: 0.42, contextID: context, gestures: all)
        XCTAssertTrue(timer.gestures.isEmpty)
        XCTAssertTrue(timer.diagnostics.isEmpty)
        XCTAssertNotEqual(timer.phase, .blockedUntilRelease)
        for time in [0.45, 0.50, 0.55, 0.60] {
            XCTAssertTrue(process(&recognizer, time, anchors, gestures: all).gestures.isEmpty)
        }
        XCTAssertEqual(thirdTap(&recognizer, at: 0.65, x: 0.20, id: 4, gestures: all).gestures,
                       [.twoFingerHoldLeftTap])
        XCTAssertTrue(process(&recognizer, 0.74, [], gestures: all).gestures.isEmpty)
        XCTAssertNil(recognizer.pendingDeadline(deviceID: "A"))
        XCTAssertTrue(recognizer.flush(deviceID: "A", timestamp: 1, contextID: context,
                                       gestures: all).gestures.isEmpty)
    }

    func testNativeAdapterRequiresFullReleaseBeforeHeldGestureCanArm() {
        var adapter = NativeContactAdapter()
        var recognizer = ConfigurableGestureRecognizer()
        func raw(_ contacts: [TouchContact]) -> [RawTouchContact] {
            contacts.map { RawTouchContact(id: $0.id, state: $0.phase.isActive ? 4 : 7, position: $0.position) }
        }
        for (time, contacts) in [(0.0, anchors), (0.10, anchors + [contact(3, 0.20)]), (0.15, anchors)] {
            XCTAssertNil(adapter.map(deviceID: "A", timestamp: time, contacts: raw(contacts)))
        }
        XCTAssertFalse(adapter.isArmed(deviceID: "A"))
        XCTAssertNil(adapter.map(deviceID: "A", timestamp: 0.20, contacts: []))
        XCTAssertTrue(adapter.isArmed(deviceID: "A"))
        for time in [0.30, 0.35, 0.40, 0.45] {
            let frame = adapter.map(deviceID: "A", timestamp: time, contacts: raw(anchors))!
            XCTAssertTrue(recognizer.process(frame, contextID: context, gestures: anchored).gestures.isEmpty)
        }
        let down = adapter.map(deviceID: "A", timestamp: 0.50, contacts: raw(anchors + [contact(3, 0.20)]))!
        XCTAssertTrue(recognizer.process(down, contextID: context, gestures: anchored).gestures.isEmpty)
        let releaseContacts = anchors + [contact(3, 0.20, phase: .ended)]
        let release = adapter.map(deviceID: "A", timestamp: 0.54, contacts: raw(releaseContacts))!
        XCTAssertEqual(recognizer.process(release, contextID: context, gestures: anchored).gestures, [.twoFingerHoldLeftTap])
        let repeated = adapter.map(deviceID: "A", timestamp: 0.59, contacts: raw(releaseContacts))!
        XCTAssertTrue(recognizer.process(repeated, contextID: context, gestures: anchored).gestures.isEmpty)
    }
}
