/// Suppresses trackpad input shortly after a key press, so a hand resting while typing
/// cannot start a gesture. A touch that begins inside the window stays suppressed until release.
public struct TypingGuard: Sendable {
    public static let defaultWindow = 0.4
    public let window: Double
    private var lastKeyDownAt: Double?
    private var blockedUntilRelease = false

    public init(window: Double = TypingGuard.defaultWindow) {
        precondition(window.isFinite && window >= 0, "Typing window must be finite and non-negative")
        self.window = window
    }

    /// Times are monotonic seconds in the same clock domain as `admits(at:activeContactCount:)`.
    public mutating func noteKeyDown(at time: Double) {
        lastKeyDownAt = max(lastKeyDownAt ?? time, time)
    }

    public mutating func reset() {
        lastKeyDownAt = nil
        blockedUntilRelease = false
    }

    public func isTyping(at time: Double) -> Bool {
        guard let lastKeyDownAt else { return false }
        return time < lastKeyDownAt + window
    }

    /// Returns false when this frame must not reach the gesture recognizer.
    public mutating func admits(at time: Double, activeContactCount: Int) -> Bool {
        if isTyping(at: time) {
            if activeContactCount > 0 { blockedUntilRelease = true }
            return false
        }
        if blockedUntilRelease {
            if activeContactCount == 0 { blockedUntilRelease = false }
            return false
        }
        return true
    }
}
