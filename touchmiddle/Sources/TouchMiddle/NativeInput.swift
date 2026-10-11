import Foundation
import Darwin
import CTouchBridge

struct NativeContact: Sendable {
    let id: Int
    let state: Int
    let x, y, major, minor: Double
}
struct NativeFrame: Sendable {
    let device: UInt64
    let timestamp: Double
    let sequence: Int32
    let invalidReason: Int
    let contacts: [NativeContact]
    let receivedUptime: UInt64
    let receivedWallTime: Double
}

final class FrameDelivery: @unchecked Sendable {
    private let handler: @Sendable (NativeFrame) -> Void
    init(handler: @escaping @Sendable (NativeFrame) -> Void) { self.handler = handler }
    func deliver(_ frame: NativeFrame) { handler(frame) }
}

let nativeFrameSink: TMFrameSink = { context, pointer in
    guard let context, let pointer else { return }
    let f = pointer.pointee
    var contacts: [NativeContact] = []
    for i in 0..<max(0, Int(f.count)) {
        if let c = TMFrameContact(pointer, Int32(i))?.pointee {
            contacts.append(NativeContact(id: Int(c.identifier), state: Int(c.state),
                x: Double(c.x), y: Double(c.y), major: Double(c.majorAxis), minor: Double(c.minorAxis)))
        }
    }
    let copy = NativeFrame(device: f.device, timestamp: f.timestamp, sequence: f.sequence,
        invalidReason: Int(f.invalidReason), contacts: contacts,
        receivedUptime: DispatchTime.now().uptimeNanoseconds, receivedWallTime: Date().timeIntervalSince1970)
    Unmanaged<FrameDelivery>.fromOpaque(context).takeUnretainedValue().deliver(copy)
}

@MainActor
final class SessionLog {
    let path: URL
    private let handle: FileHandle
    init() throws {
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--log") {
            guard i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") else {
                throw NSError(domain: "TouchMiddleLog", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "--log 必須指定新的記錄檔路徑"])
            }
            path = URL(fileURLWithPath: arguments[i + 1])
        } else {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TouchMiddle/Diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            path = folder.appendingPathComponent("session-\(UUID().uuidString).jsonl")
        }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Never truncate an existing file, and never follow a log-path symlink.
        // Open and wrap the same descriptor so there is no second path lookup.
        let descriptor = path.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            let code = errno
            let detail = code == EEXIST ? "記錄檔已存在；請使用新的路徑" : String(cString: strerror(code))
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: "無法建立診斷記錄：\(detail)",
                                     NSFilePathErrorKey: path.path])
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: "無法設定診斷記錄權限：\(String(cString: strerror(code)))",
                                     NSFilePathErrorKey: path.path])
        }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    func write(_ record: [String: Any]) throws {
        var values = record
        values["wallTime"] = Date().timeIntervalSince1970
        var data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        data.append(10)
        try handle.write(contentsOf: data)
    }
    func close() throws { try handle.synchronize(); try handle.close() }
}
