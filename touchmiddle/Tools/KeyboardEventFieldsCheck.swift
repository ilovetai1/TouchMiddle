import ApplicationServices
import Foundation
import TouchMiddleCore

// Compile this tool with the application's KeyboardShortcutOutput.swift.
// It creates events and inspects fields. It never posts input events.
@main
private enum KeyboardEventFieldsCheck {
    static func main() throws {
        let marker: Int64 = KeyboardShortcutOutput.markerPrefix | 42
        var cases = 0
        for modifiers in UInt8(0)...UInt8(15) {
            let shortcut = KeyboardShortcut(keyCode: 17, modifiers: ShortcutModifiers(rawValue: modifiers), keyLabel: "T")
            let (down, up) = try KeyboardShortcutOutput.makeEvents(for: shortcut, marker: marker)
            var expected: CGEventFlags = []
            if modifiers & 1 != 0 { expected.insert(.maskCommand) }
            if modifiers & 2 != 0 { expected.insert(.maskAlternate) }
            if modifiers & 4 != 0 { expected.insert(.maskControl) }
            if modifiers & 8 != 0 { expected.insert(.maskShift) }
            guard down.type == .keyDown, up.type == .keyUp else { throw Failure.wrongType }
            for event in [down, up] {
                guard event.flags == expected,
                      event.getIntegerValueField(.keyboardEventKeycode) == 17,
                      event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                      event.getIntegerValueField(.eventSourceUserData) == marker,
                      event.getIntegerValueField(.eventSourceStateID) == Int64(CGEventSourceStateID.combinedSessionState.rawValue) else {
                    throw Failure.wrongFields(modifiers)
                }
            }
            cases += 1
        }
        for invalid in [KeyboardShortcut(keyCode: 55, modifiers: .command, keyLabel: "⌘"),
                        KeyboardShortcut(keyCode: 128, modifiers: .command, keyLabel: "T"),
                        KeyboardShortcut(keyCode: 17, modifiers: ShortcutModifiers(rawValue: 16), keyLabel: "T")] {
            do {
                _ = try KeyboardShortcutOutput.makeEvents(for: invalid, marker: marker)
                throw Failure.invalidAccepted
            } catch RuleValidationError.invalidShortcut {
                cases += 1
            }
        }
        let result: [String: Any] = ["passed": true, "cases": cases, "eventsPosted": 0,
                                     "markerHex": String(format: "0x%016llx", UInt64(bitPattern: marker))]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum Failure: Error { case wrongType, wrongFields(UInt8), invalidAccepted }
}
