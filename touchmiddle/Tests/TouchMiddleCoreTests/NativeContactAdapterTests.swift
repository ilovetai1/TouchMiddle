import XCTest
@testable import TouchMiddleCore

final class NativeContactAdapterTests: XCTestCase {
    private func contact(_ id: Int, state: Int) -> RawTouchContact {
        RawTouchContact(id: id, state: state, position: TouchPoint(x: 0.5, y: 0.5))
    }

    private func map(_ adapter: inout NativeContactAdapter, time: Double, ids: [Int], state: Int = 4,
                     device: String = "A") -> TouchFrame? {
        adapter.map(deviceID: device, timestamp: time, contacts: ids.map { contact($0, state: state) })
    }

    func testHeldThreeFingersAtStartupCannotCreateTapThenNewTapRecognizes() {
        var adapter = NativeContactAdapter()
        var recognizer = ThreeFingerTapRecognizer()
        XCTAssertFalse(adapter.isArmed(deviceID: "A"))
        XCTAssertNil(map(&adapter, time: 0, ids: [1, 2, 3]))
        XCTAssertNil(map(&adapter, time: 0.04, ids: [1, 2, 3]))
        XCTAssertNil(map(&adapter, time: 0.06, ids: [2, 3]))
        XCTAssertNil(map(&adapter, time: 0.08, ids: [3]))
        XCTAssertFalse(adapter.isArmed(deviceID: "A"))
        XCTAssertNil(map(&adapter, time: 0.10, ids: [1, 2, 3], state: 7))
        XCTAssertTrue(adapter.isArmed(deviceID: "A"))
        let idle = map(&adapter, time: 0.11, ids: [])!
        XCTAssertTrue(recognizer.process(idle).intents.isEmpty)

        let touch = map(&adapter, time: 0.2, ids: [4, 5, 6], state: 3)!
        XCTAssertTrue(recognizer.process(touch).intents.isEmpty)
        let ended = map(&adapter, time: 0.24, ids: [4, 5, 6], state: 7)!
        XCTAssertEqual(recognizer.process(ended).intents, [.middleClick])
    }

    func testNearAndHoverStatesAreExcludedBeforeAndAfterArming() {
        var adapter = NativeContactAdapter()
        let hover = [contact(1, state: 0), contact(2, state: 1), contact(3, state: 2)]
        XCTAssertNil(adapter.map(deviceID: "A", timestamp: 0, contacts: hover))
        XCTAssertTrue(adapter.isArmed(deviceID: "A"))
        let frame = adapter.map(deviceID: "A", timestamp: 0.01, contacts: hover)!
        XCTAssertTrue(frame.contacts.isEmpty)
        let activeAndHover = adapter.map(deviceID: "A", timestamp: 0.02,
                                        contacts: [contact(4, state: 3), contact(5, state: 4)] + hover)!
        XCTAssertEqual(activeAndHover.contacts.map(\.id), [4, 5])
        XCTAssertEqual(activeAndHover.contacts.map(\.phase), [.began, .moved])
    }

    func testLiftOffPhasesFiveSixAndOutOfRangeSevenAreEndedForKnownIDs() {
        var adapter = NativeContactAdapter()
        _ = map(&adapter, time: 0, ids: [])
        _ = map(&adapter, time: 0.01, ids: [1, 2, 3])
        let ended = adapter.map(deviceID: "A", timestamp: 0.05,
                                contacts: [contact(1, state: 5), contact(2, state: 6), contact(3, state: 7)])!
        XCTAssertEqual(ended.contacts.map(\.id), [1, 2, 3])
        XCTAssertEqual(ended.contacts.map(\.phase), [.ended, .ended, .ended])
        let repeated = adapter.map(deviceID: "A", timestamp: 0.06,
                                   contacts: [contact(1, state: 5), contact(2, state: 6), contact(3, state: 7)])!
        XCTAssertTrue(repeated.contacts.isEmpty)
    }

    func testUnknownEndedContactDoesNotRejectValidThreeFingerTap() {
        var adapter = NativeContactAdapter()
        var recognizer = ThreeFingerTapRecognizer()
        _ = map(&adapter, time: 0, ids: [])
        _ = recognizer.process(map(&adapter, time: 0.01, ids: [1, 2, 3])!)
        let still = adapter.map(deviceID: "A", timestamp: 0.04,
                                contacts: [contact(1, state: 4), contact(2, state: 4), contact(3, state: 4), contact(9, state: 7)])!
        XCTAssertEqual(still.contacts.map(\.id), [1, 2, 3])
        XCTAssertTrue(recognizer.process(still).intents.isEmpty)
        XCTAssertEqual(recognizer.process(map(&adapter, time: 0.06, ids: [])!).intents, [.middleClick])
    }

    func testFourthPreviouslyActiveContactRemainsKnownUntilEntireGroupReleases() {
        var adapter = NativeContactAdapter()
        _ = map(&adapter, time: 0, ids: [])
        XCTAssertEqual(map(&adapter, time: 0.01, ids: [1, 2, 3, 4])!.contacts.count, 4)
        let lifted = adapter.map(deviceID: "A", timestamp: 0.03,
                                 contacts: [contact(1, state: 4), contact(2, state: 4), contact(3, state: 4), contact(4, state: 7)])!
        XCTAssertEqual(lifted.contacts.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(lifted.contacts.last?.phase, .ended)
        let later = adapter.map(deviceID: "A", timestamp: 0.04,
                                contacts: [contact(1, state: 4), contact(2, state: 4), contact(3, state: 4), contact(4, state: 7)])!
        XCTAssertEqual(later.contacts.map(\.id), [1, 2, 3, 4])
    }

    func testArmingAndKnownIDsAreScopedToEachDevice() {
        var adapter = NativeContactAdapter()
        _ = map(&adapter, time: 0, ids: [], device: "A")
        XCTAssertTrue(adapter.isArmed(deviceID: "A"))
        XCTAssertFalse(adapter.isArmed(deviceID: "B"))
        XCTAssertNil(map(&adapter, time: 0.01, ids: [1, 2, 3], device: "B"))
        _ = map(&adapter, time: 0.02, ids: [1, 2, 3], device: "A")
        XCTAssertNil(map(&adapter, time: 0.03, ids: [], device: "B"))
        let unknownEndedOnB = map(&adapter, time: 0.04, ids: [1, 2, 3], state: 7, device: "B")!
        XCTAssertTrue(unknownEndedOnB.contacts.isEmpty)
        let knownEndedOnA = map(&adapter, time: 0.05, ids: [1, 2, 3], state: 7, device: "A")!
        XCTAssertEqual(knownEndedOnA.contacts.count, 3)
    }

    func testResetRearmsOnlyAfterNextHandsOffAndDropsOldKnownIDs() {
        var adapter = NativeContactAdapter()
        var recognizer = ThreeFingerTapRecognizer()
        _ = map(&adapter, time: 0, ids: [])
        _ = recognizer.process(map(&adapter, time: 0.01, ids: [1, 2, 3])!)
        adapter.reset()
        _ = recognizer.reset()
        XCTAssertFalse(adapter.isArmed(deviceID: "A"))
        XCTAssertNil(map(&adapter, time: 0.03, ids: [1, 2, 3]))
        XCTAssertNil(map(&adapter, time: 0.05, ids: [1, 2, 3], state: 7))
        XCTAssertTrue(adapter.isArmed(deviceID: "A"))
        let afterReset = map(&adapter, time: 0.06, ids: [1, 2, 3], state: 7)!
        XCTAssertTrue(afterReset.contacts.isEmpty)
        XCTAssertTrue(recognizer.process(afterReset).intents.isEmpty)
    }

    func testTimestampAndSequenceArePreservedAndUnknownStateIsExcluded() {
        var adapter = NativeContactAdapter()
        _ = map(&adapter, time: 0, ids: [])
        let frame = adapter.map(deviceID: "A", timestamp: 42.5, sequence: 123,
                                contacts: [contact(1, state: 4), contact(2, state: 99)])!
        XCTAssertEqual(frame.deviceID, "A")
        XCTAssertEqual(frame.timestamp, 42.5)
        XCTAssertEqual(frame.sequence, 123)
        XCTAssertEqual(frame.contacts.map(\.id), [1])
    }
}

final class NativeContactAdapterPalmTests: XCTestCase {
    private func raw(_ id: Int, state: Int, major: Double, x: Double = 0.5) -> RawTouchContact {
        RawTouchContact(id: id, state: state, position: TouchPoint(x: x, y: 0.5), majorAxis: major)
    }

    func testMajorAxisAtOrAboveLimitMarksPalm() {
        var adapter = NativeContactAdapter(palmMajorAxis: 20)
        _ = adapter.map(deviceID: "A", timestamp: 0, contacts: [])
        let frame = adapter.map(deviceID: "A", timestamp: 0.01,
                                contacts: [raw(1, state: 3, major: 14.9), raw(2, state: 4, major: 20), raw(3, state: 4, major: 26)])!
        XCTAssertEqual(frame.contacts.map(\.isPalm), [false, true, true])
    }

    func testMissingAxisDataIsNotPalm() {
        var adapter = NativeContactAdapter()
        _ = adapter.map(deviceID: "A", timestamp: 0, contacts: [])
        let frame = adapter.map(deviceID: "A", timestamp: 0.01,
                                contacts: [RawTouchContact(id: 1, state: 3, position: TouchPoint(x: 0.5, y: 0.5))])!
        XCTAssertEqual(frame.contacts.map(\.isPalm), [false])
    }

    func testPalmBesideFingersRejectsTapUntilAllContactsRelease() {
        var adapter = NativeContactAdapter()
        var recognizer = ConfigurableGestureRecognizer()
        let gestures: Set<GestureKind> = [.threeFingerTap]
        func step(_ time: Double, _ contacts: [RawTouchContact]) -> GestureRecognitionOutcome {
            recognizer.process(adapter.map(deviceID: "A", timestamp: time, contacts: contacts)!,
                               contextID: "app", gestures: gestures)
        }
        _ = adapter.map(deviceID: "A", timestamp: 0, contacts: [])
        let fingers = [raw(1, state: 3, major: 8, x: 0.4), raw(2, state: 3, major: 8, x: 0.5)]
        let palm = step(0.01, fingers + [raw(3, state: 3, major: 24, x: 0.9)])
        XCTAssertEqual(palm.diagnostics, [.gestureRejected(.palmContact(contactID: 3))])
        XCTAssertEqual(palm.phase, .blockedUntilRelease)
        let ended = step(0.08, [raw(1, state: 7, major: 8), raw(2, state: 7, major: 8), raw(3, state: 7, major: 24)])
        XCTAssertTrue(ended.gestures.isEmpty)

        // A clean three-finger tap afterwards is still recognized.
        _ = step(0.5, [])
        let touch = [raw(4, state: 3, major: 8, x: 0.4), raw(5, state: 3, major: 9, x: 0.5), raw(6, state: 3, major: 8, x: 0.6)]
        _ = step(0.6, touch)
        let held = touch.map { raw($0.id, state: 4, major: $0.majorAxis, x: $0.position.x) }
        _ = step(0.63, held)
        let tap = step(0.66, held.map { raw($0.id, state: 7, major: $0.majorAxis, x: $0.position.x) })
        XCTAssertEqual(tap.gestures, [.threeFingerTap])
    }
}
