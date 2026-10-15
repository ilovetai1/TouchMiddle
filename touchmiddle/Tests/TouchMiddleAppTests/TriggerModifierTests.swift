import XCTest
import ApplicationServices
import TouchMiddleCore
@testable import TouchMiddle

final class TriggerModifierTests: XCTestCase {
    func testPhysicalFlagsMapAllSixteenCombinationsAndIgnoreUnrelatedFlags() {
        for raw in UInt8(0)...15 {
            let expected = ShortcutModifiers(rawValue: raw)
            var flags: CGEventFlags = [.maskAlphaShift, .maskNumericPad, .maskSecondaryFn]
            if expected.contains(.command) { flags.insert(.maskCommand) }
            if expected.contains(.option) { flags.insert(.maskAlternate) }
            if expected.contains(.control) { flags.insert(.maskControl) }
            if expected.contains(.shift) { flags.insert(.maskShift) }
            XCTAssertEqual(TouchController.modifiers(from: flags), expected)
        }
    }
}
