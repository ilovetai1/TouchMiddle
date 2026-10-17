import AppKit
import Carbon

enum LaunchContext {
    /// macOS identifies login launches in the open-application Apple event.
    static func isLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
