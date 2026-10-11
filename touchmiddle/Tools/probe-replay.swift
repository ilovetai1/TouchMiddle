import Foundation

private struct RawContact: Decodable { let id: Int; let state: Int; let x, y: Double }
private struct RawFrame: Decodable { let device: UInt64; let timestamp: Double; let sequence: Int32; let invalidReason: Int; let contacts: [RawContact] }

@main
struct ProbeReplay {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw NSError(domain: "ProbeReplay", code: 2) }
        let data = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        var recognizer = ThreeFingerTapRecognizer()
        var known = Set<Int>()
        var accepted: [Double] = []
        var diagnostics: [String: Int] = [:]
        for line in data.split(separator: "\n") {
            let f = try JSONDecoder().decode(RawFrame.self, from: Data(line.utf8))
            guard f.invalidReason == 0 else { throw NSError(domain: "NativeABI", code: f.invalidReason) }
            let active = f.contacts.filter { $0.state == 3 || $0.state == 4 }
            known.formUnion(active.map(\.id))
            let contacts = f.contacts.compactMap { c -> TouchContact? in
                guard c.state >= 3, c.state <= 7, known.contains(c.id) else { return nil }
                return TouchContact(id: c.id, position: TouchPoint(x: c.x, y: c.y), phase: c.state == 3 ? .began : c.state == 4 ? .moved : .ended)
            }
            let outcome = recognizer.process(TouchFrame(deviceID: String(f.device), timestamp: f.timestamp, sequence: UInt64(UInt32(bitPattern: f.sequence)), contacts: contacts))
            for d in outcome.diagnostics { diagnostics[String(describing: d), default: 0] += 1 }
            if outcome.intents.contains(.middleClick) { accepted.append(f.timestamp) }
            if active.isEmpty { known.removeAll() }
        }
        let result: [String: Any] = ["acceptedCount": accepted.count, "acceptedTimestamps": accepted, "diagnostics": diagnostics]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(json); FileHandle.standardOutput.write(Data([10]))
    }
}
