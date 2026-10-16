import XCTest
@testable import TouchMiddleCore

final class FingerGapTests: XCTestCase {
    private func contact(_ id: Int, _ x: Double, y: Double = 0.5, phase: TouchPhase = .stationary) -> TouchContact {
        TouchContact(id: id, position: TouchPoint(x: x, y: y), phase: phase)
    }
    @discardableResult
    private func send(_ r: inout ConfigurableGestureRecognizer, _ t: Double, _ c: [TouchContact],
                      _ g: Set<GestureKind>) -> GestureRecognitionOutcome {
        r.process(TouchFrame(deviceID: "A", timestamp: t, contacts: c), contextID: "app:1", gestures: g)
    }

    func testLargestHorizontalGapUsesNeighbouringFingers() {
        XCTAssertEqual(TouchPoint.largestHorizontalGap([]), 0)
        XCTAssertEqual(TouchPoint.largestHorizontalGap([TouchPoint(x: 0.3, y: 0.1)]), 0)
        let points = [0.7, 0.2, 0.35].map { TouchPoint(x: $0, y: 0.5) }
        XCTAssertEqual(TouchPoint.largestHorizontalGap(points), 0.35, accuracy: 1e-12)
    }

    func testOneAnchorSideTapWithinGapIsRecognizedAndWideTapIsRejected() {
        let g: Set<GestureKind> = [.oneFingerHoldRightTap]
        for (x, expected) in [(0.75, [GestureKind.oneFingerHoldRightTap]), (0.76, []), (1.0, [])] {
            var r = ConfigurableGestureRecognizer()
            let anchor = [contact(1, 0.4)]
            for t in [0.0, 0.05, 0.10, 0.15] { send(&r, t, anchor, g) }
            let start = send(&r, 0.20, anchor + [contact(2, x)], g)
            if expected.isEmpty {
                XCTAssertEqual(start.diagnostics.last, .gestureRejected(.fingersTooFarApart(gap: x - 0.4)))
                XCTAssertEqual(start.phase, .blockedUntilRelease)
            }
            XCTAssertEqual(send(&r, 0.24, anchor, g).gestures, expected, "x=\(x)")
        }
    }

    func testTwoAnchorSideTapMeasuresFromNearestAnchor() {
        let g: Set<GestureKind> = [.twoFingerHoldLeftTap]
        for (x, expected) in [(0.12, [GestureKind.twoFingerHoldLeftTap]), (0.05, [])] {
            var r = ConfigurableGestureRecognizer()
            let anchors = [contact(1, 0.45), contact(2, 0.60)]
            for t in [0.0, 0.05, 0.10, 0.15] { send(&r, t, anchors, g) }
            send(&r, 0.20, anchors + [contact(3, x)], g)
            XCTAssertEqual(send(&r, 0.24, anchors, g).gestures, expected, "x=\(x)")
        }
    }

    func testWideTwoFingerGroupCannotFormDoubleTap() {
        let g: Set<GestureKind> = [.twoFingerDoubleTap]
        for (gapRight, expected) in [(0.55, [GestureKind.twoFingerDoubleTap]), (0.80, [])] {
            var r = ConfigurableGestureRecognizer()
            for start in [0.0, 0.15] {
                send(&r, start, [contact(1, 0.2), contact(2, gapRight)], g)
                let result = send(&r, start + 0.04, [], g)
                if start > 0 { XCTAssertEqual(result.gestures, expected, "right=\(gapRight)") }
            }
        }
    }

    func testSpreadFourFingerTapWithModestNeighbourGapsIsStillRecognized() {
        let g: Set<GestureKind> = [.fourFingerTap]
        var r = ConfigurableGestureRecognizer()
        // About 0.45 total width, matching wide deliberate four-finger taps in local traces.
        send(&r, 0, [0.25, 0.40, 0.55, 0.70].enumerated().map { contact($0.offset, $0.element) }, g)
        XCTAssertEqual(send(&r, 0.04, [], g).gestures, [.fourFingerTap])
    }

    func testCustomGapIsValidated() {
        XCTAssertThrowsError(try TapConfiguration(maximumMovement: 0.025, maximumFingerGap: 0)) {
            XCTAssertEqual($0 as? TapConfigurationError, .invalidValue(field: "maximumFingerGap"))
        }
        XCTAssertEqual(try TapConfiguration(maximumMovement: 0.025, maximumFingerGap: 0.2).maximumFingerGap, 0.2)
    }
}
