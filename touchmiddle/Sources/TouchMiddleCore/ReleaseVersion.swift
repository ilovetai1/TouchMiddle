import Foundation

/// SemVer precedence, including numeric prerelease identifiers (beta.10 > beta.2).
/// Build metadata does not affect precedence. Numeric components need not fit in Int.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let description: String
    private let components: [String]
    private let prerelease: [String]

    public init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let metadata = text.split(separator: "+", omittingEmptySubsequences: false)
        guard metadata.count <= 2 else { return nil }
        if metadata.count == 2, !Self.validIdentifiers(String(metadata[1]), numericLeadingZeros: true) { return nil }
        let version = String(metadata[0]).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = version[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard numbers.count == 3, numbers.allSatisfy(Self.validNumber) else { return nil }
        let identifiers: [String]
        if version.count == 2 {
            guard Self.validIdentifiers(String(version[1]), numericLeadingZeros: false) else { return nil }
            identifiers = version[1].split(separator: ".").map(String.init)
        } else {
            identifiers = []
        }
        components = numbers
        prerelease = identifiers
        description = String(metadata[0])
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) where left != right {
            return numberIsLess(left, right)
        }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = isNumeric(left), rightNumeric = isNumeric(right)
            if leftNumeric && rightNumeric { return numberIsLess(left, right) }
            if leftNumeric != rightNumeric { return leftNumeric }
            return left.utf8.lexicographicallyPrecedes(right.utf8)
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validNumber(_ value: String) -> Bool {
        isNumeric(value) && (value.count == 1 || value.first != "0")
    }

    private static func numberIsLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }

    private static func validIdentifiers(_ text: String, numericLeadingZeros: Bool) -> Bool {
        text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            } && (numericLeadingZeros || !isNumeric(String(part)) || validNumber(String(part)))
        }
    }
}
