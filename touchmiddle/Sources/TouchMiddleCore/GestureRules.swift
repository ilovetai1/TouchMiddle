import Foundation

public enum GestureKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case threeFingerTap
    case twoFingerDoubleTap
    case threeFingerDoubleTap
    case twoFingerHoldLeftTap
    case twoFingerHoldRightTap
    case oneFingerHoldLeftTap
    case oneFingerHoldRightTap
    case twoFingerHoldSwipeUp
    case twoFingerHoldSwipeDown
    case fourFingerTap
    case threeFingerLongPress
    case topLeftTwoFingerTap
    case topRightTwoFingerTap
    case bottomLeftTwoFingerTap
    case bottomRightTwoFingerTap
    case twoFingerHoldLeftDoubleTap
    case twoFingerHoldRightDoubleTap
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .oneFingerHoldLeftTap: "一指固定左側輕點"
        case .oneFingerHoldRightTap: "一指固定右側輕點"
        case .twoFingerHoldSwipeUp: "兩指固定第三指上滑"
        case .twoFingerHoldSwipeDown: "兩指固定第三指下滑"
        case .fourFingerTap: "四指輕點"
        case .threeFingerLongPress: "三指長按"
        case .topLeftTwoFingerTap: "左上角兩指輕點"
        case .topRightTwoFingerTap: "右上角兩指輕點"
        case .bottomLeftTwoFingerTap: "左下角兩指輕點"
        case .bottomRightTwoFingerTap: "右下角兩指輕點"
        case .twoFingerHoldLeftDoubleTap: "兩指固定左側雙擊"
        case .twoFingerHoldRightDoubleTap: "兩指固定右側雙擊"
        case .threeFingerTap: "三指輕點"
        case .twoFingerDoubleTap: "兩指雙擊"
        case .threeFingerDoubleTap: "三指雙擊"
        case .twoFingerHoldLeftTap: "兩指固定左側點擊"
        case .twoFingerHoldRightTap: "兩指固定右側點擊"
        }
    }
    public var instructions: String {
        switch self {
        case .oneFingerHoldLeftTap: "一指固定至少 150 ms，再用另一指在左側輕點並放開。"
        case .oneFingerHoldRightTap: "一指固定至少 150 ms，再用另一指在右側輕點並放開。"
        case .twoFingerHoldSwipeUp: "兩指固定至少 150 ms，第三指向上短滑至少觸控板高度 6%，再放開第三指。"
        case .twoFingerHoldSwipeDown: "兩指固定至少 150 ms，第三指向下短滑至少觸控板高度 6%，再放開第三指。"
        case .fourFingerTap: "四指一起輕點，然後完全放開。"
        case .threeFingerLongPress: "三指保持固定至少 500 ms，在 2 秒內完全放開時觸發。"
        case .topLeftTwoFingerTap: "兩指都在觸控板左上角 25% 區域輕點，再完全放開。"
        case .topRightTwoFingerTap: "兩指都在觸控板右上角 25% 區域輕點，再完全放開。"
        case .bottomLeftTwoFingerTap: "兩指都在觸控板左下角 25% 區域輕點，再完全放開。"
        case .bottomRightTwoFingerTap: "兩指都在觸控板右下角 25% 區域輕點，再完全放開。"
        case .twoFingerHoldLeftDoubleTap: "兩指保持固定，第三指在左側連續輕點兩次。啟用此手勢時，同側單擊會等待雙擊間隔。"
        case .twoFingerHoldRightDoubleTap: "兩指保持固定，第三指在右側連續輕點兩次。啟用此手勢時，同側單擊會等待雙擊間隔。"
        case .threeFingerTap:
            "三指一起輕點，然後完全放開；不需要壓下觸控板。"
        case .twoFingerDoubleTap:
            "兩指連續輕點兩次，每次完全放開；不需要壓下觸控板。"
        case .threeFingerDoubleTap:
            "三指連續輕點兩次，每次完全放開；不需要壓下觸控板。"
        case .twoFingerHoldLeftTap:
            "兩指保持接觸且固定至少 150 ms，再用第三指在兩指左側外緣輕點。只放開第三指即可觸發；固定兩指時可重複點擊。"
        case .twoFingerHoldRightTap:
            "兩指保持接觸且固定至少 150 ms，再用第三指在兩指右側外緣輕點。只放開第三指即可觸發；固定兩指時可重複點擊。"
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
    public var displayLabel: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        return value
    }
}

public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    public var keyLabel: String
    public init(keyCode: UInt16, modifiers: ShortcutModifiers, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    public var displayLabel: String { modifiers.displayLabel + keyLabel }
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
    public var requiredModifiers: ShortcutModifiers
    public init(id: UUID = UUID(), gesture: GestureKind, scope: RuleScope, action: RuleAction, isEnabled: Bool = true, requiredModifiers: ShortcutModifiers = []) {
        self.id = id; self.gesture = gesture; self.scope = scope; self.action = action; self.isEnabled = isEnabled; self.requiredModifiers = requiredModifiers
    }
    private enum CodingKeys: String, CodingKey { case id, gesture, scope, action, isEnabled, requiredModifiers }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        gesture = try values.decode(GestureKind.self, forKey: .gesture)
        scope = try values.decode(RuleScope.self, forKey: .scope)
        action = try values.decode(RuleAction.self, forKey: .action)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        requiredModifiers = values.contains(.requiredModifiers) ? try values.decode(ShortcutModifiers.self, forKey: .requiredModifiers) : []
    }
    public var triggerTitle: String {
        requiredModifiers.isEmpty ? gesture.title : requiredModifiers.displayLabel + "＋" + gesture.title
    }
}

public enum RuleValidationError: Error, LocalizedError, Equatable {
    case invalidShortcut, invalidApplication, duplicateRule, duplicateIdentifier, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .invalidShortcut: "快捷鍵無效，請重新錄製。"
        case .invalidApplication: "App 必須有有效的 bundle identifier。"
        case .duplicateRule: "同一 App 範圍、組合鍵與手勢只能有一條規則，請編輯既有規則。"
        case .duplicateIdentifier: "規則識別碼重複。"
        case .unsupportedVersion: "規則檔版本不支援。"
        }
    }
}

public struct RuleConfiguration: Codable, Equatable, Sendable {
    public var version: Int
    public var rules: [GestureRule]
    public init(rules: [GestureRule], version: Int = 2) { self.version = version; self.rules = rules }
    public static var initial: Self {
        Self(rules: [GestureRule(gesture: .threeFingerTap, scope: .global, action: .middleClick)])
    }
    public func validate() throws {
        guard version == 1 || version == 2 else { throw RuleValidationError.unsupportedVersion }
        guard Set(rules.map(\.id)).count == rules.count else { throw RuleValidationError.duplicateIdentifier }
        var keys: Set<String> = []
        for rule in rules {
            if let identifier = rule.scope.bundleIdentifier {
                guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RuleValidationError.invalidApplication
                }
            }
            guard rule.requiredModifiers.rawValue & ~ShortcutModifiers.supported.rawValue == 0 else {
                throw RuleValidationError.invalidShortcut
            }
            let key = String(rule.requiredModifiers.rawValue) + ":" + rule.gesture.rawValue + "\u{0}" + (rule.scope.bundleIdentifier ?? "")
            guard keys.insert(key).inserted else { throw RuleValidationError.duplicateRule }
            if case .shortcut(let shortcut) = rule.action { try shortcut.validate() }
        }
    }
    public func resolve(_ gesture: GestureKind, bundleIdentifier: String?, modifiers: ShortcutModifiers = []) -> GestureRule? {
        let matching = rules.filter { $0.isEnabled && $0.gesture == gesture && $0.requiredModifiers == modifiers }
        if let bundleIdentifier, let specific = matching.first(where: { $0.scope.bundleIdentifier == bundleIdentifier }) {
            return specific
        }
        return matching.first { $0.scope == .global }
    }
    public func gestures(bundleIdentifier: String?, modifiers: ShortcutModifiers = []) -> Set<GestureKind> {
        Set(GestureKind.allCases.filter { resolve($0, bundleIdentifier: bundleIdentifier, modifiers: modifiers) != nil })
    }
}
