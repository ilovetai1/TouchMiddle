import AppKit
import Carbon
import SwiftUI
import TouchMiddleCore

/// Captures keys only while this editor has focus. It never posts input events.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: TouchMiddleCore.KeyboardShortcut?
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.onCapture = { value in
            shortcut = value
            isRecording = false
        }
        view.onStop = { isRecording = false }
        view.configure(shortcut: shortcut, recording: isRecording)
    }

    static func dismantleNSView(_ view: ShortcutCaptureView, coordinator: ()) {
        view.stopMonitoring()
    }
}

@MainActor
final class ShortcutCaptureView: NSView {
    var onCapture: ((TouchMiddleCore.KeyboardShortcut) -> Void)?
    var onStop: (() -> Void)?
    private var recording = false
    private var shortcut: TouchMiddleCore.KeyboardShortcut?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 48) }
    override var isFlipped: Bool { true }

    func configure(shortcut: TouchMiddleCore.KeyboardShortcut?, recording: Bool) {
        self.shortcut = shortcut
        self.recording = recording
        needsDisplay = true
        if recording { window?.makeFirstResponder(self) }
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel("快捷鍵錄製區")
        setAccessibilityValue(recording ? "錄製中，請按下快捷鍵，Escape 停止" : shortcut?.displayLabel ?? "尚未設定快捷鍵")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.recording, event.window === self.window,
                      self.window?.firstResponder === self else { return false }
                self.capture(event)
                return true
            }
            return consumed ? nil : event
        }
        if recording { window?.makeFirstResponder(self) }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    override func keyDown(with event: NSEvent) {
        if recording { capture(event) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if recording { window?.makeFirstResponder(self) }
    }

    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 {
            recording = false
            onStop?()
            needsDisplay = true
            return
        }
        var modifiers: ShortcutModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        let value = TouchMiddleCore.KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers,
                                     keyLabel: Self.label(for: event))
        do {
            try value.validate()
            recording = false
            onCapture?(value)
            needsDisplay = true
        } catch {
            NSSound.beep()
        }
    }

    private static func label(for event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 76: "⌤", 71: "Clear",
            115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20"
        ]
        if let label = special[event.keyCode] { return label }
        // Translate the physical key using the current layout with no modifiers,
        // so an Option chord keeps a readable base key rather than an accent.
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            if let bytes = CFDataGetBytePtr(data) {
                let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, event.keyCode, UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                    characters.count, &length, &characters)
                if status == noErr, length > 0 {
                    return String(utf16CodeUnits: characters, count: Int(length)).uppercased()
                }
            }
        }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }
        return "Key \(event.keyCode)"
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = recording ? NSColor.controlAccentColor.withAlphaComponent(0.1) : NSColor.controlBackgroundColor
        let border = recording ? NSColor.controlAccentColor : NSColor.separatorColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        fill.setFill(); path.fill()
        border.setStroke(); path.lineWidth = recording ? 2 : 1; path.stroke()
        let value = recording ? "請按下快捷鍵（Escape 停止）" : shortcut?.displayLabel ?? "尚未設定快捷鍵"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: recording ? 14 : 20, weight: .medium),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let text = NSAttributedString(string: value, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: max(12, (bounds.width - size.width) / 2), y: (bounds.height - size.height) / 2))
    }
}
