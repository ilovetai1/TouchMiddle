import AppKit
import ApplicationServices

enum ClickOutputError: LocalizedError {
    case permissionRequired, eventCreationFailed
    var errorDescription: String? {
        switch self {
        case .permissionRequired: "缺少輔助使用權限，中鍵事件尚未送出。"
        case .eventCreationFailed: "無法建立中鍵事件。"
        }
    }
}

@MainActor
final class MiddleClickOutput {
    nonisolated static let markerPrefix: Int64 = 0x544D000000000000
    nonisolated static let markerMask = Int64(bitPattern: 0xFFFF000000000000)
    private var serial: Int64 = 0

    func post() throws -> Int64 {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw ClickOutputError.permissionRequired }
        guard let pointer = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(mouseEventSource: source, mouseType: .otherMouseDown, mouseCursorPosition: pointer, mouseButton: .center),
              let up = CGEvent(mouseEventSource: source, mouseType: .otherMouseUp, mouseCursorPosition: pointer, mouseButton: .center) else {
            throw ClickOutputError.eventCreationFailed
        }
        serial += 1
        let marker = Self.markerPrefix | serial
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return marker
    }
}
