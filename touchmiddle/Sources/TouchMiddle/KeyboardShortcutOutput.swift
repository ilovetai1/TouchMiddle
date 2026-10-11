import AppKit
import ApplicationServices
import TouchMiddleCore

enum ShortcutOutputError: LocalizedError {
    case invalidTarget, targetChanged, permissionRequired, eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidTarget: "快捷鍵的 App 目標無效，事件尚未送出。"
        case .targetChanged: "原本的 App 已不在前景，快捷鍵尚未送出。"
        case .permissionRequired: "缺少輔助使用權限，快捷鍵尚未送出。"
        case .eventCreationFailed: "無法建立快捷鍵事件。"
        }
    }
}

@MainActor
final class KeyboardShortcutOutput {
    nonisolated static let markerPrefix: Int64 = 0x544B000000000000
    nonisolated static let markerMask = Int64(bitPattern: 0xFFFF000000000000)
    private var serial: Int64 = 0

    func post(_ shortcut: KeyboardShortcut, targetPID: pid_t) throws -> Int64 {
        try shortcut.validate()
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            throw ShortcutOutputError.permissionRequired
        }
        guard targetPID > 0 else { throw ShortcutOutputError.invalidTarget }
        guard let target = NSRunningApplication(processIdentifier: targetPID),
              target.bundleIdentifier != nil, target.isActive,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            throw ShortcutOutputError.targetChanged
        }
        let nextSerial = serial == 0x0000FFFFFFFFFFFF ? 1 : serial + 1
        let marker = Self.markerPrefix | nextSerial
        let (down, up) = try Self.makeEvents(for: shortcut, marker: marker)

        // Build first, then recheck before dispatch. Both events go to the same
        // process even if focus changes during delivery, so its key is released.
        guard target.isActive,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            throw ShortcutOutputError.targetChanged
        }
        serial = nextSerial
        down.postToPid(targetPID)
        up.postToPid(targetPID)
        return marker
    }

    // Creating events is side-effect free. The receiver and event-field checks
    // can verify this seam without granting permissions or posting input.
    nonisolated static func makeEvents(for shortcut: KeyboardShortcut, marker: Int64) throws -> (CGEvent, CGEvent) {
        try shortcut.validate()
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
            throw ShortcutOutputError.eventCreationFailed
        }
        var flags: CGEventFlags = []
        if shortcut.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if shortcut.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.control) { flags.insert(.maskControl) }
        if shortcut.modifiers.contains(.shift) { flags.insert(.maskShift) }
        // Each key event has the recorded flags, independent of keys physically
        // held by the user. No modifier-key down is synthesized or left held.
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.setIntegerValueField(.eventSourceUserData, value: marker)
        }
        return (down, up)
    }
}
