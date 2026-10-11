import Foundation

public enum GestureKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case threeFingerTap
    case twoFingerDoubleTap
    case threeFingerDoubleTap
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .threeFingerTap: "三指輕點"
        case .twoFingerDoubleTap: "兩指雙擊"
        case .threeFingerDoubleTap: "三指雙擊"
        }
    }
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let supported: Self = [.command, .option, .control, .shift]
}

public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    public var keyLabel: String
    public init(keyCode: UInt16, modifiers: ShortcutModifiers, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    public var displayLabel: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + keyLabel
    }
    public func validate() throws {
        guard keyCode <= 127, !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              modifiers.rawValue & ~ShortcutModifiers.supported.rawValue == 0 else {
            throw RuleValidationError.invalidShortcut
        }
        // Modifier-only keycodes are never valid as the main shortcut key.
        guard ![54,55,56,57,58,59,60,61,62,63].contains(keyCode) else { throw RuleValidationError.invalidShortcut }
    }
}

public enum RuleAction: Codable, Equatable, Sendable {
    case middleClick
    case shortcut(KeyboardShortcut)
    public var title: String {
        switch self { case .middleClick: "中鍵"; case .shortcut(let value): value.displayLabel }
    }
}

public enum RuleScope: Codable, Hashable, Sendable {
    case global
    case application(bundleIdentifier: String, name: String)
    public var title: String {
        switch self { case .global: "全域（所有 App）"; case .application(_, let name): name }
    }
    public var bundleIdentifier: String? {
        switch self { case .global: nil; case .application(let identifier, _): identifier }
    }
}

public struct GestureRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var gesture: GestureKind
    public var scope: RuleScope
    public var action: RuleAction
    public var isEnabled: Bool
    public init(id: UUID = UUID(), gesture: GestureKind, scope: RuleScope, action: RuleAction, isEnabled: Bool = true) {
        self.id = id; self.gesture = gesture; self.scope = scope; self.action = action; self.isEnabled = isEnabled
    }
}

public enum RuleValidationError: Error, LocalizedError, Equatable {
    case invalidShortcut, invalidApplication, duplicateRule, duplicateIdentifier, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .invalidShortcut: "快捷鍵無效，請重新錄製。"
        case .invalidApplication: "App 必須有有效的 bundle identifier。"
        case .duplicateRule: "同一 App 範圍與手勢只能有一條規則，請編輯既有規則。"
        case .duplicateIdentifier: "規則識別碼重複。"
        case .unsupportedVersion: "規則檔版本不支援。"
        }
    }
}

public struct RuleConfiguration: Codable, Equatable, Sendable {
    public var version: Int
    public var rules: [GestureRule]
    public init(rules: [GestureRule], version: Int = 1) { self.version = version; self.rules = rules }
    public static var initial: Self {
        Self(rules: [GestureRule(gesture: .threeFingerTap, scope: .global, action: .middleClick)])
    }
    public func validate() throws {
        guard version == 1 else { throw RuleValidationError.unsupportedVersion }
        guard Set(rules.map(\.id)).count == rules.count else { throw RuleValidationError.duplicateIdentifier }
        var keys: Set<String> = []
        for rule in rules {
            if let identifier = rule.scope.bundleIdentifier {
                guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RuleValidationError.invalidApplication
                }
            }
            let key = rule.gesture.rawValue + "\u{0}" + (rule.scope.bundleIdentifier ?? "")
            guard keys.insert(key).inserted else { throw RuleValidationError.duplicateRule }
            if case .shortcut(let shortcut) = rule.action { try shortcut.validate() }
        }
    }
    public func resolve(_ gesture: GestureKind, bundleIdentifier: String?) -> GestureRule? {
        let matching = rules.filter { $0.isEnabled && $0.gesture == gesture }
        if let bundleIdentifier, let specific = matching.first(where: { $0.scope.bundleIdentifier == bundleIdentifier }) {
            return specific
        }
        return matching.first { $0.scope == .global }
    }
    public func gestures(bundleIdentifier: String?) -> Set<GestureKind> {
        Set(GestureKind.allCases.filter { resolve($0, bundleIdentifier: bundleIdentifier) != nil })
    }
}
