import AppKit
import CoreGraphics
import Darwin
import Foundation

// This is a separate, harmless recipient for end-to-end middle-click tests.
// It neither observes keyboard input nor creates or posts any input event.
// Build: xcrun swiftc -parse-as-library -swift-version 6 -framework AppKit \
//        -framework CoreGraphics Tools/MiddleEventReceiver.swift -o /tmp/MiddleEventReceiver
// Run:   /tmp/MiddleEventReceiver --log-path /absolute/path/receiver.jsonl

private enum ReceiverError: Error, CustomStringConvertible {
    case usage
    case system(String, Int32)
    case regularFileRequired

    var description: String {
        switch self {
        case .usage:
            return "Usage: MiddleEventReceiver --log-path /absolute/path/receiver.jsonl"
        case .system(let operation, let code):
            return "\(operation): \(String(cString: strerror(code)))"
        case .regularFileRequired:
            return "The log path must identify a regular file."
        }
    }
}

private func fail(_ error: Error) -> Never {
    let message = "MiddleEventReceiver: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
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
        var fileStatus = stat()
        guard fstat(descriptor, &fileStatus) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw ReceiverError.system("inspect log", code)
        }
        guard fileStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            Darwin.close(descriptor)
            throw ReceiverError.regularFileRequired
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw ReceiverError.system("set log mode 0600", code)
        }
        self.descriptor = descriptor
    }

    deinit {
        Darwin.close(descriptor)
    }

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
    private let writer: JSONLWriter
    private var middleDownCount = 0
    private var middleUpCount = 0

    init(writer: JSONLWriter) {
        self.writer = writer
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    }

    required init?(coder: NSCoder) {
        fatalError("ReceiverView is created programmatically.")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func otherMouseDown(with event: NSEvent) {
        receive(event, type: "otherMouseDown")
    }

    override func otherMouseUp(with event: NSEvent) {
        receive(event, type: "otherMouseUp")
    }

    private func receive(_ event: NSEvent, type: String) {
        if event.buttonNumber == 2 {
            if type == "otherMouseDown" { middleDownCount += 1 }
            if type == "otherMouseUp" { middleUpCount += 1 }
        }
        var record: [String: Any] = [
            "type": type,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "buttonNumber": event.buttonNumber,
            "time": event.timestamp,
            "wallTime": Date().timeIntervalSince1970,
            "windowNumber": event.windowNumber,
            "eventNumber": event.eventNumber,
            "locationInWindow": ["x": event.locationInWindow.x, "y": event.locationInWindow.y]
        ]
        if let cgEvent = event.cgEvent {
            let marker = cgEvent.getIntegerValueField(.eventSourceUserData)
            record["eventSourceUserData"] = marker
            record["eventSourceUserDataHex"] = String(format: "0x%016llx", UInt64(bitPattern: marker))
            record["eventSourceUnixProcessID"] = cgEvent.getIntegerValueField(.eventSourceUnixProcessID)
        } else {
            record["eventSourceUserData"] = NSNull()
            record["eventSourceUserDataHex"] = NSNull()
            record["cgEventAvailable"] = false
        }
        do { try writer.append(record) } catch { fail(error) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
        bounds.fill()
        let title = "TouchMiddle 中鍵測試區"
        let details = "請把游標移到灰色區域，再做三指點按。\n此視窗只接收事件，沒有連結或其他動作。"
        let count = "中鍵按下：\(middleDownCount)　中鍵放開：\(middleUpCount)"
        let color = NSColor(calibratedWhite: 0.12, alpha: 1)
        (title as NSString).draw(in: NSRect(x: 32, y: bounds.height - 78, width: bounds.width - 64, height: 42),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                                                  .foregroundColor: color])
        (details as NSString).draw(in: NSRect(x: 32, y: bounds.height - 164, width: bounds.width - 64, height: 70),
                                   withAttributes: [.font: NSFont.systemFont(ofSize: 17),
                                                    .foregroundColor: color])
        (count as NSString).draw(in: NSRect(x: 32, y: 34, width: bounds.width - 64, height: 38),
                                 withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium),
                                                  .foregroundColor: color])
    }
}

@MainActor
private final class ReceiverDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let writer: JSONLWriter
    private var window: NSWindow?

    init(writer: JSONLWriter) {
        self.writer = writer
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "TouchMiddle — 獨立中鍵接收端"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = ReceiverView(writer: writer)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        let frame = window.frame
        do {
            try writer.append([
                "type": "ready",
                "pid": ProcessInfo.processInfo.processIdentifier,
                "time": ProcessInfo.processInfo.systemUptime,
                "wallTime": Date().timeIntervalSince1970,
                "windowNumber": window.windowNumber,
                "windowFrameScreen": ["x": frame.origin.x, "y": frame.origin.y,
                                      "width": frame.size.width, "height": frame.size.height]
            ])
        } catch { fail(error) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
@MainActor
private enum MiddleEventReceiver {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 3, arguments[1] == "--log-path" else { throw ReceiverError.usage }
            let writer = try JSONLWriter(path: arguments[2])
            let delegate = ReceiverDelegate(writer: writer)
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch { fail(error) }
    }
}
