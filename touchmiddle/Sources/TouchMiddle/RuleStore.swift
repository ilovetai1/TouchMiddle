import Foundation
import Darwin
import TouchMiddleCore

@MainActor
final class RuleStore {
    let path: URL
    init() throws {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true).appendingPathComponent("TouchMiddle", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        path = folder.appendingPathComponent("rules.json")
    }
    func load() throws -> RuleConfiguration {
        if !FileManager.default.fileExists(atPath: path.path) {
            // A dangling symlink is not an absent configuration.
            if (try? FileManager.default.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                throw fileError("規則檔不可使用符號連結。")
            }
            let initial = RuleConfiguration.initial
            try save(initial)
            return initial
        }
        try requireRegularFile()
        let configuration = try JSONDecoder().decode(RuleConfiguration.self, from: Data(contentsOf: path))
        try configuration.validate()
        return configuration
    }
    func save(_ configuration: RuleConfiguration) throws {
        try configuration.validate()
        if FileManager.default.fileExists(atPath: path.path) { try requireRegularFile() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        let temporary = path.deletingLastPathComponent().appendingPathComponent(".rules-\(UUID().uuidString).tmp")
        let descriptor = temporary.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600)) }
        guard descriptor >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var closed = false
        defer {
            if !closed { try? handle.close() }
            _ = temporary.path.withCString { Darwin.unlink($0) }
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw posixError() }
        try handle.write(contentsOf: data); try handle.synchronize(); try handle.close(); closed = true
        let status = temporary.path.withCString { from in path.path.withCString { to in Darwin.rename(from, to) } }
        guard status == 0 else { throw posixError() }
    }
    private func requireRegularFile() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw fileError("規則檔必須是一般檔案，不能使用資料夾或符號連結。")
        }
    }
    private func fileError(_ text: String) -> NSError {
        NSError(domain: "TouchMiddleRules", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
