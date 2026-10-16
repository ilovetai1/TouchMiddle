import XCTest
@testable import TouchMiddleCore

final class ExpandedGestureTests: XCTestCase {
    private func contacts(_ count: Int, x: Double = 0.4, y: Double = 0.5) -> [TouchContact] {
        (0..<count).map { TouchContact(id: $0, position: TouchPoint(x: x + Double($0) * 0.03, y: y)) }
    }
    private func frame(_ time: Double, _ contacts: [TouchContact]) -> TouchFrame {
        TouchFrame(deviceID: "A", timestamp: time, contacts: contacts)
    }
    @discardableResult private func send(_ r: inout ConfigurableGestureRecognizer, _ t: Double,
        _ c: [TouchContact], _ g: Set<GestureKind>, context: String = "app:1") -> [GestureKind] {
        r.process(frame(t, c), contextID: context, gestures: g).gestures
    }
    private func hold(_ r: inout ConfigurableGestureRecognizer, _ anchors: [TouchContact], _ g: Set<GestureKind>) {
        for t in [0.0, 0.05, 0.10, 0.15] { XCTAssertEqual(send(&r, t, anchors, g), []) }
    }

    func testFourFingerTapAndUnexpectedFifthCancel() {
        for count in [4, 5] {
            var r = ConfigurableGestureRecognizer()
            send(&r, 0, contacts(count), [.fourFingerTap])
            XCTAssertEqual(send(&r, 0.04, [], [.fourFingerTap]), count == 4 ? [.fourFingerTap] : [])
        }
    }
    func testAllFourCornersRequireBothFingersAndOverrideOrdinaryDoubleTap() {
        let corners: [(Double, Double, GestureKind)] = [(0.1, 0.9, .topLeftTwoFingerTap),
            (0.8, 0.9, .topRightTwoFingerTap), (0.1, 0.1, .bottomLeftTwoFingerTap), (0.8, 0.1, .bottomRightTwoFingerTap)]
        for (x, y, gesture) in corners {
            var r = ConfigurableGestureRecognizer()
            let g: Set<GestureKind> = [gesture, .twoFingerDoubleTap]
            send(&r, 0, contacts(2, x: x, y: y), g)
            XCTAssertEqual(send(&r, 0.04, [], g), [gesture])
            XCTAssertEqual(r.flush(deviceID: "A", timestamp: 1, contextID: "app:1", gestures: g).gestures, [])
        }
        var r = ConfigurableGestureRecognizer()
        send(&r, 0, contacts(2, x: 0.24, y: 0.9), [.topLeftTwoFingerTap])
        XCTAssertEqual(send(&r, 0.04, [], [.topLeftTwoFingerTap]), [])
    }
    func testLongPressReleaseBoundaryDoesNotEmitShortTap() {
        let g: Set<GestureKind> = [.threeFingerTap, .threeFingerLongPress]
        for end in [0.499, 0.5, 1.0, 2.01] {
            var r = ConfigurableGestureRecognizer()
            send(&r, 0, contacts(3), g)
            var t = 0.05
            while t < end { XCTAssertEqual(send(&r, t, contacts(3), g), []); t += 0.05 }
            XCTAssertEqual(send(&r, end, [], g), end >= 0.5 && end <= 2 ? [.threeFingerLongPress] : [])
        }
    }
    func testOneAnchorLeftAndRightReleaseAndReplacement() {
        for (x, gesture) in [(0.2, GestureKind.oneFingerHoldLeftTap), (0.7, .oneFingerHoldRightTap)] {
            let g: Set<GestureKind> = [gesture]
            var r = ConfigurableGestureRecognizer()
            let anchors = contacts(1)
            hold(&r, anchors, g)
            let other = TouchContact(id: 9, position: TouchPoint(x: x, y: 0.5))
            send(&r, 0.20, anchors + [other], g)
            XCTAssertEqual(send(&r, 0.24, anchors, g), [gesture])
            send(&r, 0.3, [], g)
            XCTAssertEqual(send(&r, 0.35, [other], g), [])
        }
    }
    func testVerticalSwipesReleaseAndRejectHorizontalOrShortMotion() {
        for (dx, dy, expected) in [(0.0, 0.08, [GestureKind.twoFingerHoldSwipeUp]),
            (0.0, -0.08, [.twoFingerHoldSwipeDown]), (0.08, 0.08, []), (0.0, 0.04, [])] {
            let g: Set<GestureKind> = [.twoFingerHoldSwipeUp, .twoFingerHoldSwipeDown]
            var r = ConfigurableGestureRecognizer()
            let anchors = contacts(2)
            hold(&r, anchors, g)
            let origin = TouchContact(id: 9, position: TouchPoint(x: 0.7, y: 0.5))
            let moved = TouchContact(id: 9, position: TouchPoint(x: 0.7 + dx, y: 0.5 + dy))
            send(&r, 0.2, anchors + [origin], g)
            XCTAssertEqual(send(&r, 0.24, anchors + [moved], g), [])
            XCTAssertEqual(send(&r, 0.28, anchors, g), expected)
        }
    }
    func testAnchoredDoubleTapAndDeferredSingle() {
        for double in [false, true] {
            let g: Set<GestureKind> = [.twoFingerHoldLeftTap, .twoFingerHoldLeftDoubleTap]
            var r = ConfigurableGestureRecognizer()
            let anchors = contacts(2)
            hold(&r, anchors, g)
            let other = TouchContact(id: 9, position: TouchPoint(x: 0.2, y: 0.5))
            send(&r, 0.2, anchors + [other], g)
            XCTAssertEqual(send(&r, 0.24, anchors, g), [])
            XCTAssertEqual(r.pendingDeadline(deviceID: "A"), 0.59)
            if double {
                send(&r, 0.30, anchors + [other], g)
                XCTAssertEqual(send(&r, 0.34, anchors, g), [.twoFingerHoldLeftDoubleTap])
            } else {
                XCTAssertEqual(r.flush(deviceID: "A", timestamp: 0.59, contextID: "app:1", gestures: g).gestures, [.twoFingerHoldLeftTap])
            }
        }
    }
    func testNewGesturesCancelOnContextChangePalmMovementOrFrameGap() {
        let g: Set<GestureKind> = [.fourFingerTap, .threeFingerLongPress]
        for reason in 0..<4 {
            var r = ConfigurableGestureRecognizer()
            send(&r, 0, contacts(3), g)
            if reason == 0 { send(&r, 0.05, contacts(3), g, context: "app:2") }
            if reason == 1 {
                let palm = TouchContact(id: 0, position: TouchPoint(x: 0.4, y: 0.5), isPalm: true)
                send(&r, 0.05, [palm] + Array(contacts(3).dropFirst()), g)
            }
            if reason == 2 { send(&r, 0.05, contacts(3, x: 0.5), g) }
            if reason == 3 { send(&r, 0.20, contacts(3), g) }
            XCTAssertEqual(send(&r, 0.24, [], g), [])
        }
    }
    func testCenterTouchWithoutSwipeDoesNotEmitAndSwipeCannotReverse() {
        for reverse in [false, true] {
            var r = ConfigurableGestureRecognizer()
            let g: Set<GestureKind> = [.twoFingerHoldSwipeUp, .twoFingerHoldSwipeDown]
            let anchors = contacts(2)
            hold(&r, anchors, g)
            func moving(_ y: Double) -> [TouchContact] {
                anchors + [TouchContact(id: 9, position: TouchPoint(x: 0.415, y: y))]
            }
            send(&r, 0.2, moving(0.5), g)
            if reverse {
                send(&r, 0.24, moving(0.58), g)
                send(&r, 0.28, moving(0.42), g)
            }
            XCTAssertEqual(send(&r, 0.32, anchors, g), [])
        }
    }
    func testRightAnchoredDoubleWithoutSingleAndRapidThirdTap() {
        var r = ConfigurableGestureRecognizer()
        let g: Set<GestureKind> = [.twoFingerHoldRightDoubleTap, .twoFingerHoldRightTap]
        let anchors = contacts(2)
        hold(&r, anchors, g)
        let tapped = anchors + [TouchContact(id: 9, position: TouchPoint(x: 0.7, y: 0.5))]
        for t in [0.2, 0.3, 0.4] {
            send(&r, t, tapped, g)
            XCTAssertEqual(send(&r, t + 0.04, anchors, g), t == 0.3 ? [.twoFingerHoldRightDoubleTap] : [])
        }
        XCTAssertEqual(r.flush(deviceID: "A", timestamp: 1, contextID: "app:1", gestures: g).gestures, [])
    }
    func testDeferredLeftAndRightSinglesAreIndependentAndAnchorReleaseCancels() {
        let g: Set<GestureKind> = [.twoFingerHoldLeftTap, .twoFingerHoldRightTap,
            .twoFingerHoldLeftDoubleTap, .twoFingerHoldRightDoubleTap]
        for release in [false, true] {
            var r = ConfigurableGestureRecognizer()
            let anchors = contacts(2)
            hold(&r, anchors, g)
            send(&r, 0.20, anchors + [TouchContact(id: 9, position: TouchPoint(x: 0.2, y: 0.5))], g)
            send(&r, 0.24, anchors, g)
            send(&r, 0.30, anchors + [TouchContact(id: 10, position: TouchPoint(x: 0.7, y: 0.5))], g)
            send(&r, 0.34, anchors, g)
            if release { send(&r, 0.38, [], g) }
            let result = r.flush(deviceID: "A", timestamp: 0.70, contextID: "app:1", gestures: g).gestures
            XCTAssertEqual(Set(result), release ? [] : [.twoFingerHoldLeftTap, .twoFingerHoldRightTap])
        }
    }
    func testOneAnchorCancellationRequiresHandsOffAndThenRecovers() {
        let g: Set<GestureKind> = [.oneFingerHoldLeftTap]
        for reason in 0..<4 {
            var r = ConfigurableGestureRecognizer()
            let anchors = contacts(1)
            hold(&r, anchors, g)
            let other = TouchContact(id: 9, position: TouchPoint(x: 0.2, y: 0.5))
            send(&r, 0.2, anchors + [other], g)
            if reason == 0 { send(&r, 0.24, [other], g) }
            if reason == 1 { send(&r, 0.24, contacts(1, x: 0.5) + [other], g) }
            if reason == 2 { send(&r, 0.24, anchors + [other], g, context: "app:2") }
            if reason == 3 { send(&r, 0.4, anchors + [other], g) }
            XCTAssertEqual(send(&r, 0.45, anchors, g), [])
            send(&r, 0.5, [], g)
            for t in [0.6, 0.65, 0.7, 0.75] { send(&r, t, anchors, g) }
            send(&r, 0.8, anchors + [other], g)
            XCTAssertEqual(send(&r, 0.84, anchors, g), [.oneFingerHoldLeftTap])
        }
    }
    func testPendingDoubleTimerDoesNotCancelSecondLongPress() {
        var r = ConfigurableGestureRecognizer()
        let g: Set<GestureKind> = [.threeFingerTap, .threeFingerDoubleTap, .threeFingerLongPress]
        send(&r, 0, contacts(3), g)
        send(&r, 0.04, [], g)
        send(&r, 0.1, contacts(3), g)
        for t in [0.2, 0.3, 0.4, 0.5, 0.6] {
            send(&r, t, contacts(3), g)
            XCTAssertEqual(r.flush(deviceID: "A", timestamp: t, contextID: "app:1", gestures: g).gestures, [])
        }
        XCTAssertEqual(send(&r, 0.64, [], g), [.threeFingerLongPress])
    }
    func testAllGesturesTogetherChooseSpecificShapeWithoutDuplicates() {
        let g = Set(GestureKind.allCases)
        var r = ConfigurableGestureRecognizer()
        send(&r, 0, contacts(4), g)
        XCTAssertEqual(send(&r, 0.04, [], g), [.fourFingerTap])
        XCTAssertEqual(r.flush(deviceID: "A", timestamp: 1, contextID: "app:1", gestures: g).gestures, [])
        send(&r, 1.1, contacts(2, x: 0.1, y: 0.9), g)
        XCTAssertEqual(send(&r, 1.14, [], g), [.topLeftTwoFingerTap])
    }

}
