import AppKit
import Foundation

let duration = Double(CommandLine.arguments.dropFirst().first ?? "180") ?? 180
let end = Date().addingTimeInterval(duration)
while Date() < end {
    if let app = NSWorkspace.shared.frontmostApplication {
        let record: [String: Any] = ["wallTime": Date().timeIntervalSince1970,
            "uptime": ProcessInfo.processInfo.systemUptime,
            "pid": app.processIdentifier, "bundleID": app.bundleIdentifier ?? "unknown"]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
    Thread.sleep(forTimeInterval: 0.25)
}
