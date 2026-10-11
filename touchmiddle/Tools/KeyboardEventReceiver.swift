import AppKit
import CoreGraphics
import Darwin
import Foundation

// An independent recipient for keyboard-output verification. It observes only
// events delivered to its own app, records only TouchMiddle's marked events,
// and does not create or post input. No typed characters are recorded.
// Build: xcrun swiftc -parse-as-library -swift-version 6 -framework AppKit \
//        -framework CoreGraphics Tools/KeyboardEventReceiver.swift -o /tmp/KeyboardEventReceiver
// Package in an app with a bundle identifier before testing PID-targeted output.
// Run: KeyboardEventReceiver --log-path /absolute/path/receiver.jsonl

private enum ReceiverError: Error {
    case usage, regularFileRequired, system(String, Int32)
}

private func fail(_ error: Error) -> Never {
    FileHandle.standardError.write(Data("KeyboardEventReceiver: \(error)\n".utf8))
    exit(2)
}

@MainActor
private final class JSONLWriter {
    private let descriptor: Int32
    init(path: String) throws {
        guard path.hasPrefix("/") else { throw ReceiverError.usage }
        let descriptor = path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw ReceiverError.system("open log", errno) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let code = errno; Darwin.close(descriptor)
            throw ReceiverError.system("inspect log", code)
        }
        guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            Darwin.close(descriptor); throw ReceiverError.regularFileRequired
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno; Darwin.close(descriptor)
            throw ReceiverError.system("set log mode 0600", code)
        }
        self.descriptor = descriptor
    }
    deinit { Darwin.close(descriptor) }
    func append(_ record: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        data.append(10)
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw ReceiverError.system("write log", errno)
                }
                guard count > 0 else { throw ReceiverError.system("write log", EIO) }
                offset += count
            }
        }
    }
}

@MainActor
private final class ReceiverView: NSView {
    var receiverName = "TouchMiddle 獨立快捷鍵接收端"
    var downCount = 0
    var upCount = 0
    var lastKey = "尚未收到快捷鍵"
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 21), .foregroundColor: NSColor.labelColor]
        (receiverName as NSString).draw(at: NSPoint(x: 28, y: bounds.height - 60), withAttributes: attributes)
        ("鍵盤按下：\(downCount)　放開：\(upCount)" as NSString).draw(at: NSPoint(x: 28, y: 80), withAttributes: attributes)
        (lastKey as NSString).draw(at: NSPoint(x: 28, y: 40), withAttributes: attributes)
        let detail = "此視窗只計算 TouchMiddle 的事件。\n沒有快捷鍵動作，也不記錄輸入的文字。"
        (detail as NSString).draw(in: NSRect(x: 28, y: 145, width: bounds.width - 56, height: 70),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.secondaryLabelColor])
    }
}

@MainActor
private final class ReceiverDelegate: NSObject, NSApplicationDelegate {
    private let writer: JSONLWriter
    private var window: NSWindow?
    private var monitor: Any?
    init(writer: JSONLWriter) { self.writer = writer }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = ReceiverView(frame: NSRect(x: 0, y: 0, width: 650, height: 360))
        view.receiverName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? view.receiverName
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = view.receiverName
        window.isReleasedWhenClosed = false; window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self, weak view] event in
            MainActor.assumeIsolated {
                guard let self, let view, let cgEvent = event.cgEvent else { return }
                let marker = cgEvent.getIntegerValueField(.eventSourceUserData)
                guard marker & Int64(bitPattern: 0xFFFF000000000000) == 0x544B000000000000 else { return }
                if event.type == .keyDown { view.downCount += 1 } else { view.upCount += 1 }
                view.lastKey = "鍵碼 \(event.keyCode)，修飾鍵 \(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)"
                view.needsDisplay = true
                do {
                    try self.writer.append([
                        "type": event.type == .keyDown ? "keyDown" : "keyUp",
                        "pid": ProcessInfo.processInfo.processIdentifier,
                        "keyCode": event.keyCode,
                        "modifiers": event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue,
                        "isRepeat": event.isARepeat,
                        "time": event.timestamp,
                        "wallTime": Date().timeIntervalSince1970,
                        "windowNumber": event.windowNumber,
                        "marker": marker,
                        "markerHex": String(format: "0x%016llx", UInt64(bitPattern: marker)),
                        "eventSourceUnixProcessID": cgEvent.getIntegerValueField(.eventSourceUnixProcessID)
                    ])
                } catch { fail(error) }
            }
            return event
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        do {
            try writer.append(["type": "ready", "pid": ProcessInfo.processInfo.processIdentifier,
                               "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "wallTime": Date().timeIntervalSince1970])
        } catch { fail(error) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
@MainActor
private enum KeyboardEventReceiver {
    static func main() {
        do {
            guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--log-path" else { throw ReceiverError.usage }
            let delegate = ReceiverDelegate(writer: try JSONLWriter(path: CommandLine.arguments[2]))
            let app = NSApplication.shared
            app.setActivationPolicy(.regular); app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch { fail(error) }
    }
}
